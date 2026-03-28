;;;; message-status.lisp - Message Status Tracking
;;;;
;;;; Implements complete message lifecycle tracking with 5-state machine:
;;;; PENDING → SENDING → SENT → DELIVERED → READ
;;;;                               ↓
;;;;                            FAILED (with auto-retry)
;;;;
;;;; Reference: WhatsApp Message State Machine, Signal Protocol

(in-package :lispim-core)

;;;; Dependencies

(eval-when (:compile-toplevel :load-toplevel :execute)
  (ql:quickload '(:bordeaux-threads :postmodern :cl-redis)))

;;;; Message Status Constants

(defparameter *message-status-codes*
  '((:pending . 0)
    (:sending . 1)
    (:sent . 2)
    (:delivered . 3)
    (:read . 4)
    (:failed . 5))
  "Message status codes mapping")

(defparameter *message-status-names*
  '(0 :pending
    1 :sending
    2 :sent
    3 :delivered
    4 :read
    5 :failed)
  "Message status codes to keywords mapping")

(deftype message-status ()
  "Message status type"
  '(member :pending :sending :sent :delivered :read :failed))

;;;; Message Status Structure

(defstruct message-status-info
  "Message status information"
  (status :pending :type message-status)
  (status-code 0 :type (integer 0 5))
  (updated-at 0 :type integer)
  (retry-count 0 :type (integer 0 *))
  (max-retries 3 :type (integer 0 *))
  (last-error nil :type (or null string))
  (delivered-to nil :type list)  ;; List of user-ids
  (read-by nil :type list)       ;; List of (user-id . timestamp)
  (metadata (make-hash-table :test 'equal) :type hash-table))

;;;; Status Update Functions

(defun status-code-to-keyword (code)
  "Convert status code to keyword"
  (declare (type (integer 0 5) code))
  (getf *message-status-names* code :pending))

(defun status-keyword-to-code (keyword)
  "Convert status keyword to code"
  (declare (type keyword keyword))
  (or (cdr (assoc keyword *message-status-codes*)) 0))

(defun update-message-status (message-id new-status &key (error-message nil) (delivered-to nil))
  "Update message status in database
   Returns: (values success? old-status new-status)"
  (declare (type integer message-id)
           (type message-status new-status))
  (ensure-pg-connected)

  (let* ((old-status nil)
         (new-code (status-keyword-to-code new-status))
         (now (get-universal-time)))

    ;; Get old status
    (let ((row (postmodern:query
                "SELECT status FROM messages WHERE id = $1"
                message-id)))
      (when row
        (setf old-status (status-code-to-keyword (parse-integer (caar row))))))

    ;; Update status
    (bordeaux-threads:with-lock-held (*storage-lock*)
      (cond
        ((eq new-status :failed)
         ;; Failed status: increment retry count
         (postmodern:query
          "UPDATE messages
           SET status = $1,
               last_error = $2,
               retry_count = COALESCE(retry_count, 0) + 1,
               updated_at = NOW()
           WHERE id = $3"
          new-code (or error-message "") message-id))

        ((eq new-status :delivered)
         ;; Delivered status: update delivered_to array
         (postmodern:query
          "UPDATE messages
           SET status = $1,
               delivered_to = array_cat(COALESCE(delivered_to, '{}'), $2::text[]),
               updated_at = NOW()
           WHERE id = $3"
          new-code (or delivered-to (vector)) message-id))

        (t
         ;; Other status updates
         (postmodern:query
          "UPDATE messages
           SET status = $1,
               updated_at = NOW()
           WHERE id = $2"
          new-code message-id))))

    ;; Cache status in Redis
    (when *redis-connected*
      (redis-set "message-status"
                 (write-to-string message-id)
                 (cl-json:encode-json-to-string
                  (list :status new-status
                        :status-code new-code
                        :updated-at now))))

    (log-info "Message ~a status updated: ~a → ~a"
              message-id old-status new-status)

    (values t old-status new-status)))

(defun get-message-status (message-id)
  "Get message status from database or cache
   Returns: message-status-info or nil"
  (declare (type integer message-id))

  ;; Try Redis cache first
  (when (and *redis-connected*)
    (let ((cached (redis-get "message-status" (write-to-string message-id))))
      (when cached
        (let ((data (cl-json:decode-json-from-string cached)))
          (return-from get-message-status
            (make-message-status-info
             :status (getf data :status)
             :status-code (getf data :status-code)
             :updated-at (getf data :updated-at)))))))

  ;; Fallback to PostgreSQL
  (ensure-pg-connected)
  (let ((row (postmodern:query
              "SELECT status, retry_count, last_error, delivered_to, created_at
               FROM messages WHERE id = $1"
              message-id)))
    (when row
      (let ((status-code (parse-integer (elt row 0)))
            (retry-count (or (elt row 1) 0))
            (last-error (elt row 2))
            (delivered-to (elt row 3))
            (created-at (elt row 4)))
        (make-message-status-info
         :status (status-code-to-keyword status-code)
         :status-code status-code
         :updated-at created-at
         :retry-count retry-count
         :last-error last-error
         :delivered-to (when delivered-to (coerce delivered-to 'list)))))))

(defun store-message-with-status (message &key (status :pending))
  "Store message with initial status to database
   Returns: (values success? message-id)"
  (declare (type message message)
           (type message-status status))
  (ensure-pg-connected)

  (let* ((msg-id (message-id message))
         (conv-id (message-conversation-id message))
         (sender-id (message-sender-id message))
         (sequence (message-sequence message))
         (type (message-message-type message))
         (content (message-content message))
         (attachments (message-attachments message))
         (status-code (status-keyword-to-code status)))

    (bordeaux-threads:with-lock-held (*storage-lock*)
      (postmodern:query
       "INSERT INTO messages
        (id, conversation_id, sender_id, sequence, type, content, attachments, status, retry_count, created_at)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, 0, NOW())"
       msg-id conv-id sender-id sequence (string-downcase (string type)) content
       (cl-json:encode-json-to-string (or attachments '()))
       status-code))

    ;; Cache in Redis
    (when *redis-connected*
      (let ((key (format nil "messages:~a" conv-id)))
        (redis-lpush key (cl-json:encode-json-to-string
                          (list :id msg-id
                                :sequence sequence
                                :type type
                                :content content
                                :status status)))
        (redis-ltrim key 0 99)))

    (log-info "Stored message ~a with status ~a" msg-id status)
    (values t msg-id)))

;;;; Retry Mechanism

(defparameter *failed-messages-queue*
  (make-hash-table :test 'eql)
  "Failed messages queue for retry")

(defparameter *failed-messages-lock*
  (bordeaux-threads:make-lock "failed-messages-lock")
  "Lock for failed messages queue")

(defun enqueue-failed-message (message-id conversation-id content &key (type :text))
  "Add failed message to retry queue"
  (declare (type integer message-id conversation-id)
           (type string content))
  (bordeaux-threads:with-lock-held (*failed-messages-lock*)
    (let ((entry (gethash conversation-id *failed-messages-queue*)))
      (if entry
          (push (list :message-id message-id
                      :content content
                      :type type
                      :enqueued-at (get-universal-time))
                entry)
          (setf (gethash conversation-id *failed-messages-queue*)
                (list (list :message-id message-id
                            :content content
                            :type type
                            :enqueued-at (get-universal-time))))))
    (log-info "Enqueued failed message ~a for retry" message-id)))

(defun dequeue-failed-messages (conversation-id &key (limit 10))
  "Get failed messages from retry queue"
  (declare (type integer conversation-id))
  (bordeaux-threads:with-lock-held (*failed-messages-lock*)
    (let ((queue (gethash conversation-id *failed-messages-queue*)))
      (when queue
        (let ((messages (subseq queue 0 (min limit (length queue)))))
          (setf (gethash conversation-id *failed-messages-queue*)
                (subseq queue (length messages)))
          messages)))))

(defun should-retry-message-p (message-id)
  "Check if message should be retried"
  (declare (type integer message-id))
  (let ((status-info (get-message-status message-id)))
    (when status-info
      (and (eq (message-status-info-status status-info) :failed)
           (< (message-status-info-retry-count status-info)
              (message-status-info-max-retries status-info))))))

(defun get-retry-delay (retry-count)
  "Calculate exponential backoff delay for retry
   Returns: delay in seconds"
  (declare (type (integer 0 *) retry-count))
  ;; Exponential backoff: 5s, 15s, 45s, 135s, ...
  (* 5 (expt 3 retry-count)))

;;;; Message Status Table Migration

(defun ensure-message-status-column ()
  "Ensure messages table has status column"
  (ensure-pg-connected)
  (handler-case
      (progn
        ;; Check if status column exists
        (let ((result (postmodern:query
                       "SELECT column_name FROM information_schema.columns
                        WHERE table_name = 'messages' AND column_name = 'status'")))
          (unless result
            ;; Add status column with default value
            (postmodern:query
             "ALTER TABLE messages ADD COLUMN status INTEGER DEFAULT 1")
            (log-info "Added status column to messages table")))

        ;; Check for retry_count column
        (let ((result (postmodern:query
                       "SELECT column_name FROM information_schema.columns
                        WHERE table_name = 'messages' AND column_name = 'retry_count'")))
          (unless result
            (postmodern:query
             "ALTER TABLE messages ADD COLUMN retry_count INTEGER DEFAULT 0")
            (log-info "Added retry_count column to messages table")))

        ;; Check for last_error column
        (let ((result (postmodern:query
                       "SELECT column_name FROM information_schema.columns
                        WHERE table_name = 'messages' AND column_name = 'last_error'")))
          (unless result
            (postmodern:query
             "ALTER TABLE messages ADD COLUMN last_error TEXT")
            (log-info "Added last_error column to messages table")))

        ;; Check for delivered_to column
        (let ((result (postmodern:query
                       "SELECT column_name FROM information_schema.columns
                        WHERE table_name = 'messages' AND column_name = 'delivered_to'")))
          (unless result
            (postmodern:query
             "ALTER TABLE messages ADD COLUMN delivered_to TEXT[]")
            (log-info "Added delivered_to column to messages table"))))
    (error (c)
      (log-error "Failed to ensure message status columns: ~a" c))))

;;;; Background Retry Worker

(defparameter *retry-worker-thread* nil
  "Background retry worker thread")

(defparameter *retry-worker-running* nil
  "Retry worker running flag")

(defun start-retry-worker ()
  "Start background retry worker thread"
  (unless *retry-worker-running*
    (setf *retry-worker-running* t)
    (setf *retry-worker-thread*
          (bordeaux-threads:make-thread
           (lambda ()
             (log-info "Retry worker started")
             (loop while *retry-worker-running*
                   do (handler-case
                          (process-retry-queue)
                        (error (c)
                          (log-error "Retry worker error: ~a" c)))
                   do (sleep 5)))))
    (log-info "Retry worker thread created")))

(defun stop-retry-worker ()
  "Stop background retry worker thread"
  (setf *retry-worker-running* nil)
  (when *retry-worker-thread*
    (bordeaux-threads:destroy-thread *retry-worker-thread*)
    (setf *retry-worker-thread* nil))
  (log-info "Retry worker stopped"))

(defun process-retry-queue ()
  "Process failed messages retry queue"
  (loop for conv-id being the hash-keys of *failed-messages-queue*
        do (let ((messages (dequeue-failed-messages conv-id :limit 5)))
             (dolist (msg-data messages)
               (let* ((msg-id (getf msg-data :message-id))
                      (content (getf msg-data :content))
                      (type (getf msg-data :type))
                      (status-info (get-message-status msg-id)))
                 (when (and status-info
                            (should-retry-message-p msg-id))
                   (let ((retry-count (message-status-info-retry-count status-info)))
                     ;; Wait for backoff delay
                     (let ((delay (get-retry-delay retry-count)))
                       (log-info "Retrying message ~a (attempt ~a, delay ~as)"
                                 msg-id (1+ retry-count) delay)
                       (sleep delay))

                     ;; Attempt to resend
                     (handler-case
                         (progn
                           (update-message-status msg-id :sending)
                           ;; Re-push to online users
                           (push-to-online-users conv-id
                                                 (make-message
                                                  :id msg-id
                                                  :conversation-id conv-id
                                                  :sender-id ""
                                                  :message-type type
                                                  :content content))
                           (update-message-status msg-id :sent))
                       (error (c)
                         (log-error "Retry failed for message ~a: ~a" msg-id c)
                         (update-message-status msg-id :failed
                                                :error-message (format nil "~a" c))
                         ;; Re-enqueue if still have retries
                         (when (< retry-count 2)
                           (enqueue-failed-message msg-id conv-id content :type type)))))))))))

;;;; Message ACK Tracking

(defstruct message-ack
  "Message acknowledgment tracking"
  (message-id 0 :type integer)
  (pending-acks nil :type list)  ;; List of user-ids waiting for ACK
  (acked-by nil :type list)      ;; List of (user-id . timestamp)
  (timeout-at 0 :type integer)
  (callback nil :type (or null function)))

(defparameter *pending-acks*
  (make-hash-table :test 'eql)
  "Pending acknowledgments")

(defparameter *pending-acks-lock*
  (bordeaux-threads:make-lock "pending-acks-lock")
  "Lock for pending acks")

(defun create-message-ack (message-id recipient-ids &key (timeout-seconds 30) (callback nil))
  "Create ACK tracking for sent message"
  (declare (type integer message-id)
           (type list recipient-ids))
  (bordeaux-threads:with-lock-held (*pending-acks-lock*)
    (setf (gethash message-id *pending-acks*)
          (make-message-ack
           :message-id message-id
           :pending-acks recipient-ids
           :acked-by nil
           :timeout-at (+ (get-universal-time) timeout-seconds)
           :callback callback)))
  (log-info "Created ACK tracking for message ~a, waiting for ~a"
            message-id recipient-ids))

(defun acknowledge-message (message-id user-id)
  "Acknowledge message receipt by user"
  (declare (type integer message-id)
           (type string user-id))
  (bordeaux-threads:with-lock-held (*pending-acks-lock*)
    (let ((ack (gethash message-id *pending-acks*)))
      (when ack
        ;; Remove from pending
        (setf (message-ack-pending-acks ack)
              (remove user-id (message-ack-pending-acks ack) :test #'string=))
        ;; Add to acked
        (push (cons user-id (get-universal-time)) (message-ack-acked-by ack))

        ;; Update message status to delivered
        (update-message-status message-id :delivered
                               :delivered-to (vector user-id))

        ;; Check if all acked
        (when (null (message-ack-pending-acks ack))
          (log-info "Message ~a fully acknowledged" message-id)
          (when (message-ack-callback ack)
            (funcall (message-ack-callback ack) message-id :fully-acked))
          (remhash message-id *pending-acks*)))
      (values t :acked))))

(defun check-ack-timeouts ()
  "Check for ACK timeouts and trigger callbacks"
  (let ((now (get-universal-time)))
    (bordeaux-threads:with-lock-held (*pending-acks-lock*)
      (loop for msg-id being the hash-keys of *pending-acks*
            using (hash-value ack)
            when (> now (message-ack-timeout-at ack))
            do (progn
                 (log-warn "Message ~a ACK timeout" msg-id)
                 (update-message-status msg-id :failed
                                        :error-message "ACK timeout")
                 (when (message-ack-callback ack)
                   (funcall (message-ack-callback ack) msg-id :timeout))
                 (remhash msg-id *pending-acks*))))))

;;;; Exports

(export '(;; Types
          message-status
          message-status-info

          ;; Constants
          *message-status-codes*
          *message-status-names*

          ;; Status functions
          update-message-status
          get-message-status
          store-message-with-status
          status-code-to-keyword
          status-keyword-to-code

          ;; Retry mechanism
          enqueue-failed-message
          dequeue-failed-messages
          should-retry-message-p
          get-retry-delay
          start-retry-worker
          stop-retry-worker
          process-retry-queue

          ;; ACK tracking
          create-message-ack
          acknowledge-message
          check-ack-timeouts

          ;; Migration
          ensure-message-status-column)
        :lispim-core)
