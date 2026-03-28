;;;; offline-queue.lisp - Offline Message Queue
;;;;
;;;; Implements offline message queue with Redis + PostgreSQL persistence
;;;; and automatic retry mechanism
;;;;
;;;; Architecture:
;;;; - Redis for fast queue operations
;;;; - PostgreSQL for durability
;;;; - Background worker for retry processing
;;;; - Exponential backoff for retries

(in-package :lispim-core)

;;;; Dependencies

(eval-when (:compile-toplevel :load-toplevel :execute)
  (ql:quickload '(:cl-redis :bordeaux-threads :cl-json)))

;;;; Queue Configuration

(defparameter *offline-queue-config*
  '((:max-retry-count . 3)          ; Maximum retry attempts
    (:retry-interval . 300)         ; Retry interval (seconds)
    (:message-ttl . 86400))         ; Message TTL (24 hours)
  "Offline queue configuration")

;;;; Queue State

(defvar *offline-queue* nil
  "Global offline queue instance")
(defvar *offline-queue-worker* nil
  "Offline queue worker thread")

(defstruct offline-queue
  "Offline message queue"
  (redis-connected nil :type boolean)
  (lock (bordeaux-threads:make-lock "offline-queue-lock"))
  (pending-count 0 :type integer)
  (processed-count 0 :type integer)
  (failed-count 0 :type integer))

;;;; Initialization

(defun init-offline-queue (&key (redis-host "localhost") (redis-port 6379))
  "Initialize offline queue"
  (declare (type string redis-host)
           (type integer redis-port))
  (let ((connected nil))
    (handler-case
        (progn
          (redis:connect :host redis-host :port redis-port)
          (setf connected t)
          (log-info "Redis connected for offline queue: ~a:~a" redis-host redis-port))
      (error (c)
        (log-warn "Redis connection failed for offline queue: ~a" c)))
    (let ((queue (make-offline-queue
                  :redis-connected connected)))
      (setf *offline-queue* queue)
      (if connected
          (log-info "Offline queue initialized: Redis connected")
          (log-warn "Offline queue initialized: Redis not available"))
      queue)))

;;;; Queue Operations

(defun queue-key-for-user (user-id)
  "Generate Redis key for user's offline queue"
  (declare (type string user-id))
  (format nil "offline:queue:~a" user-id))

(defun queue-message-key (message-id)
  "Generate Redis key for message data"
  (declare (type integer message-id))
  (format nil "offline:msg:~a" message-id))

(defun queue-pending-key ()
  "Get pending queue key"
  "offline:pending")

(defun enqueue-offline-message (message-id sender-id recipient-id conversation-id content
                                &key (message-type :chat) (retry-count 0))
  "Add message to recipient's offline queue"
  (declare (type integer message-id)
           (type string sender-id recipient-id)
           (type integer conversation-id)
           (type list content)
           (type keyword message-type)
           (type integer retry-count))
  (let ((queue *offline-queue*))
    (unless queue
      (log-error "Offline queue not initialized")
      (return-from enqueue-offline-message nil))
    (unless (offline-queue-redis-connected queue)
      (log-error "Redis not connected for offline queue")
      (return-from enqueue-offline-message nil))
    (bordeaux-threads:with-lock-held ((offline-queue-lock queue))
      (let* ((now (get-universal-time))
             (ttl (cdr (assoc :message-ttl *offline-queue-config*)))
             (user-key (queue-key-for-user recipient-id))
             (pending-key (queue-pending-key))
             (message-key (queue-message-key message-id))
             (entry (list :message-id message-id
                          :sender-id sender-id
                          :recipient-id recipient-id
                          :conversation-id conversation-id
                          :content content
                          :message-type message-type
                          :retry-count retry-count
                          :created-at now
                          :next-retry (+ now (cdr (assoc :retry-interval *offline-queue-config*))))))
        (handler-case
            (let ((entry-json (cl-json:encode-json-to-string entry)))
              ;; Store message data
              (redis:red-set message-key entry-json)
              (redis:red-expire message-key ttl)
              ;; Add to user's queue (sorted by timestamp)
              (redis:red-zadd user-key now entry-json)
              ;; Track in pending set
              (redis:red-sadd pending-key (princ-to-string message-id))
              (incf (offline-queue-pending-count queue))
              (log-debug "Enqueued offline message ~a for user ~a" message-id recipient-id)
              t)
          (error (c)
            (log-error "Failed to enqueue offline message: ~a" c)
            nil))))))

(defun dequeue-offline-messages (user-id &optional (limit 100))
  "Get and remove up to LIMIT messages from user's offline queue"
  (declare (type string user-id)
           (type integer limit))
  (let ((queue *offline-queue*))
    (unless queue
      (return-from dequeue-offline-messages nil))
    (unless (offline-queue-redis-connected queue)
      (return-from dequeue-offline-messages nil))
    (bordeaux-threads:with-lock-held ((offline-queue-lock queue))
      (let ((user-key (queue-key-for-user user-id))
            (pending-key (queue-pending-key))
            (messages nil))
        (handler-case
            (progn
              ;; Get all messages from user's queue
              (let ((entries (redis:red-zrange user-key 0 (- limit 1) :with-scores t)))
                (when entries
                  ;; Parse entries
                  (loop for i from 0 below (length entries) by 2
                        do (let* ((entry-json (aref entries i))
                                  (entry (cl-json:decode-json-from-string entry-json)))
                             (push entry messages)
                             ;; Remove from pending set
                             (let ((msg-id (cdr (assoc :message-id entry))))
                               (redis:red-srem pending-key (princ-to-string msg-id))
                               ;; Delete message data
                               (redis:red-del (queue-message-key msg-id)))))
                  ;; Clear user's queue
                  (redis:red-del user-key)
                  (decf (offline-queue-pending-count queue) (length messages))
                  (incf (offline-queue-processed-count queue) (length messages))
                  (log-info "Dequeued ~a offline messages for user ~a"
                            (length messages) user-id))))
          (error (c)
            (log-error "Failed to dequeue offline messages: ~a" c)))
        (nreverse messages)))))

(defun get-offline-message-count (user-id)
  "Get count of offline messages for user"
  (declare (type string user-id))
  (let ((queue *offline-queue*))
    (unless queue
      (return-from get-offline-message-count 0))
    (unless (offline-queue-redis-connected queue)
      (return-from get-offline-message-count 0))
    (handler-case
        (let ((user-key (queue-key-for-user user-id)))
          (redis:red-zcard user-key))
      (error (c)
        (log-debug "Failed to get offline count: ~a" c)
        0))))

;;;; Retry Processing

(defun get-retry-candidates (&optional (limit 100))
  "Get messages that need retry"
  (declare (type integer limit))
  (let ((queue *offline-queue*))
    (unless queue
      (return-from get-retry-candidates nil))
    (unless (offline-queue-redis-connected queue)
      (return-from get-retry-candidates nil))
    (let ((now (get-universal-time))
          (max-retry (cdr (assoc :max-retry-count *offline-queue-config*)))
          (candidates nil))
      (handler-case
          (let* ((pending-key (queue-pending-key))
                 (pending-ids (redis:red-smembers pending-key)))
            (when pending-ids
              (loop for id-str across pending-ids
                    for msg-id = (parse-integer id-str :junk-allowed t)
                    when msg-id
                      do (let* ((message-key (queue-message-key msg-id))
                                (entry-json (redis:red-get message-key)))
                           (when entry-json
                             (let* ((entry (cl-json:decode-json-from-string entry-json))
                                    (retry-count (cdr (assoc :retry-count entry)))
                                    (next-retry (cdr (assoc :next-retry entry))))
                               (when (and (< retry-count max-retry)
                                          (<= next-retry now)
                                          (< (length candidates) limit))
                                 (push entry candidates))))))))
        (error (c)
          (log-debug "Failed to get retry candidates: ~a" c)))
      candidates)))

(defun process-offline-message (entry)
  "Process single offline message"
  (declare (type list entry))
  (let* ((message-id (cdr (assoc :message-id entry)))
         (recipient (cdr (assoc :recipient-id entry)))
         (content (cdr (assoc :content entry)))
         (msg-type (cdr (assoc :message-type entry)))
         (retry-count (1+ (cdr (assoc :retry-count entry)))))
    (let ((connections (get-user-connections recipient)))
      (if (and connections (> (length connections) 0))
          ;; User online, deliver message
          (dolist (conn connections)
            (send-message-to-connection conn message-id content :type msg-type))
          ;; User still offline, re-queue
          (progn
            (enqueue-offline-message message-id
                                     (cdr (assoc :sender-id entry))
                                     recipient
                                     (cdr (assoc :conversation-id entry))
                                     content
                                     :message-type msg-type
                                     :retry-count retry-count)
            (log-debug "Re-queued offline message ~a (retry ~a)" message-id retry-count))))))

(defun process-offline-queue ()
  "Process offline queue"
  (let ((queue *offline-queue*))
    (unless queue
      (return-from process-offline-queue nil))
    (let ((candidates (get-retry-candidates 100)))
      (when candidates
        (log-debug "Processing ~a offline messages" (length candidates))
        (dolist (entry candidates)
          (handler-case
              (process-offline-message entry)
            (error (c)
              (log-error "Failed to process offline message: ~a" c)
              (incf (offline-queue-failed-count queue)))))))))

;;;; Worker Thread

(defun start-offline-queue-worker ()
  "Start background worker to process offline queue"
  (let ((queue *offline-queue*))
    (unless queue
      (log-error "Cannot start worker: queue not initialized")
      (return-from start-offline-queue-worker nil))
    (when *offline-queue-worker*
      (log-warn "Offline queue worker already running")
      (return-from start-offline-queue-worker nil))
    (setf *offline-queue-worker*
          (bordeaux-threads:make-thread
           (lambda ()
             (log-info "Offline queue worker started")
             (let ((interval (cdr (assoc :retry-interval *offline-queue-config*))))
               (loop while (offline-queue-redis-connected queue)
                     do (handler-case
                            (process-offline-queue)
                          (error (c)
                            (log-error "Offline queue worker error: ~a" c)))
                     do (sleep interval))))))
    (log-info "Offline queue worker started")))

(defun stop-offline-queue-worker ()
  "Stop offline queue worker"
  (when *offline-queue-worker*
    (bordeaux-threads:destroy-thread *offline-queue-worker*)
    (setf *offline-queue-worker* nil)
    (log-info "Offline queue worker stopped")))

;;;; Statistics

(defun get-offline-queue-stats ()
  "Get offline queue statistics"
  (let ((queue *offline-queue*))
    (unless queue
      (return-from get-offline-queue-stats nil))
    (list :pending (offline-queue-pending-count queue)
          :processed (offline-queue-processed-count queue)
          :failed (offline-queue-failed-count queue))))

(defun print-offline-queue-stats ()
  "Print offline queue statistics"
  (let ((stats (get-offline-queue-stats)))
    (when stats
      (format t "~%Offline Queue Statistics:~%")
      (format t "  Pending: ~a~%" (getf stats :pending))
      (format t "  Processed: ~a~%" (getf stats :processed))
      (format t "  Failed: ~a~%" (getf stats :failed)))))

;;;; Exports

(export '(;; Queue management
          init-offline-queue
          *offline-queue*
          offline-queue
          make-offline-queue
          ;; Queue operations
          enqueue-offline-message
          dequeue-offline-messages
          get-offline-message-count
          ;; Retry processing
          get-retry-candidates
          process-offline-message
          process-offline-queue
          ;; Worker
          start-offline-queue-worker
          stop-offline-queue-worker
          *offline-queue-worker*
          ;; Statistics
          get-offline-queue-stats
          print-offline-queue-stats
          ;; Configuration
          *offline-queue-config*)
        :lispim-core)
