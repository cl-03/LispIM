;;;; message-queue.lisp - Redis Message Queue (List-based)
;;;;
;;;; Implements async message delivery using Redis lists
;;;; Note: Redis Streams support requires a library with X* command support
;;;;
;;;; Architecture:
;;;; - Redis lists for message queue
;;;; - Simple push/pop semantics
;;;; - Dead letter queue for failed messages

(in-package :lispim-core)

;;;; Dependencies

(eval-when (:compile-toplevel :load-toplevel :execute)
  (ql:quickload '(:cl-redis :bordeaux-threads :cl-json)))

;;;; Queue Configuration

(defparameter *message-queue-config*
  '((:queue-name . "lispim:messages")
    (:dlq-name . "lispim:messages:dlq")
    (:max-retry-count . 3)
    (:retry-delay . 5)
    (:batch-size . 100)
    (:block-timeout . 5))
  "Message queue configuration")

;;;; Queue State

(defvar *message-queue* nil
  "Global message queue instance")
(defvar *message-queue-consumer* nil
  "Message queue consumer thread")
(defvar *message-queue-running* nil
  "Queue consumer running flag")

(defstruct message-queue
  "Redis-based message queue"
  (redis-connected nil :type boolean)
  (queue-name "" :type string)
  (dlq-name "" :type string)
  (lock (bordeaux-threads:make-lock "message-queue-lock"))
  (enqueue-count 0 :type integer)
  (dequeue-count 0 :type integer)
  (ack-count 0 :type integer)
  (nack-count 0 :type integer)
  (dlq-count 0 :type integer))

;;;; Initialization

(defun init-message-queue (&key
                           (redis-host "localhost")
                           (redis-port 6379)
                           (queue-name "lispim:messages")
                           (dlq-name "lispim:messages:dlq"))
  "Initialize Redis message queue"
  (declare (type string redis-host queue-name dlq-name)
           (type integer redis-port))
  (let ((connected nil))
    (handler-case
        (progn
          (redis:connect :host redis-host :port redis-port)
          (setf connected t)
          (log-info "Redis connected for message queue: ~a:~a" redis-host redis-port))
      (error (c)
        (log-warn "Redis connection failed for message queue: ~a" c)))
    (let ((queue (make-message-queue
                  :redis-connected connected
                  :queue-name queue-name
                  :dlq-name dlq-name)))
      (setf *message-queue* queue)
      (if connected
          (log-info "Message queue initialized: queue=~a" queue-name)
          (log-warn "Message queue initialized: Redis not available"))
      queue)))

;;;; Enqueue Operations

(defun enqueue-message (message-data &key (priority :normal))
  "Add message to queue (right push)"
  (declare (type list message-data)
           (type keyword priority))
  (let ((queue *message-queue*))
    (unless queue
      (log-error "Message queue not initialized")
      (return-from enqueue-message nil))
    (unless (message-queue-redis-connected queue)
      (log-error "Redis not connected for message queue")
      (return-from enqueue-message nil))
    (bordeaux-threads:with-lock-held ((message-queue-lock queue))
      (let* ((queue-name (message-queue-queue-name queue))
             (message-id (generate-message-id))
             (entry (list :message-id message-id
                          :data message-data
                          :priority priority
                          :created-at (get-universal-time)
                          :status "pending"
                          :retry-count 0)))
        (handler-case
            (let ((entry-json (cl-json:encode-json-to-string entry)))
              (redis:red-rpush queue-name entry-json)
              (incf (message-queue-enqueue-count queue))
              (log-debug "Enqueued message ~a to ~a" message-id queue-name)
              message-id)
          (error (c)
            (log-error "Failed to enqueue message: ~a" c)
            nil))))))

(defun enqueue-message-batch (messages &key (priority :normal))
  "Add batch of messages to queue"
  (declare (type list messages)
           (type keyword priority))
  (let ((queue *message-queue*))
    (unless queue
      (return-from enqueue-message-batch nil))
    (unless (message-queue-redis-connected queue)
      (return-from enqueue-message-batch nil))
    (bordeaux-threads:with-lock-held ((message-queue-lock queue))
      (let ((queue-name (message-queue-queue-name queue))
            (ids nil))
        (handler-case
            (dolist (msg messages)
              (let* ((message-id (generate-message-id))
                     (entry (list :message-id message-id
                                  :data msg
                                  :priority priority
                                  :created-at (get-universal-time)
                                  :status "pending"
                                  :retry-count 0))
                     (entry-json (cl-json:encode-json-to-string entry)))
                (redis:red-rpush queue-name entry-json)
                (push message-id ids)
                (incf (message-queue-enqueue-count queue))))
          (error (c)
            (log-error "Failed to enqueue batch: ~a" c)
            nil))
        (when ids
          (log-info "Enqueued batch of ~a messages" (length ids)))
        (nreverse ids)))))

;;;; Dequeue Operations

(defun dequeue-message (&key (block t) (timeout 5))
  "Get single message from queue (left pop)"
  (declare (type boolean block)
           (type integer timeout))
  (let ((queue *message-queue*))
    (unless queue
      (return-from dequeue-message nil))
    (let ((redis-connected (message-queue-redis-connected queue))
          (queue-name (message-queue-queue-name queue)))
      (unless redis-connected
        (return-from dequeue-message nil))
      (handler-case
          (let ((result
                 (if block
                     (redis:red-brpop queue-name timeout)
                     (redis:red-lpop queue-name))))
            (when result
              (incf (message-queue-dequeue-count queue))
              (let ((entry (cl-json:decode-json-from-string result)))
                (list :message-id (cdr (assoc :message-id entry))
                      :data (cdr (assoc :data entry))
                      :raw entry))))
        (error (c)
          (log-debug "Dequeue error: ~a" c)
          nil)))))

(defun dequeue-messages (&key (batch-size 100) (block t) (timeout 5))
  "Get batch of messages from queue"
  (declare (type integer batch-size)
           (type boolean block)
           (type integer timeout))
  (let ((queue *message-queue*))
    (unless queue
      (return-from dequeue-messages nil))
    (let ((redis-connected (message-queue-redis-connected queue))
          (queue-name (message-queue-queue-name queue)))
      (unless redis-connected
        (return-from dequeue-messages nil))
      (handler-case
          (let ((messages nil)
                (count 0))
            (loop while (< count batch-size)
                  for result = (redis:red-lpop queue-name)
                  while result
                  do (let ((entry (cl-json:decode-json-from-string result)))
                       (push (list :message-id (cdr (assoc :message-id entry))
                                   :data (cdr (assoc :data entry))
                                   :raw entry)
                             messages)
                       (incf count))
                  when (and (not block) (>= count 1)) return nil)
            (when (> (length messages) 0)
              (incf (message-queue-dequeue-count queue) (length messages))
              (nreverse messages)))
        (error (c)
          (log-debug "Dequeue batch error: ~a" c)
          nil)))))

;;;; Acknowledgment

(defun ack-message (message-id)
  "Acknowledge message processing (success)"
  (declare (type integer message-id))
  (let ((queue *message-queue*))
    (unless queue
      (return-from ack-message nil))
    (let ((redis-connected (message-queue-redis-connected queue)))
      (unless redis-connected
        (return-from ack-message nil))
      (handler-case
          (progn
            (incf (message-queue-ack-count queue))
            (log-debug "Acked message ~a" message-id)
            t)
        (error (c)
          (log-error "Failed to ack message: ~a" c)
          nil)))))

(defun nack-message (message-id &key requeue-p)
  "Negative acknowledge message (failure)"
  (declare (type integer message-id)
           (type boolean requeue-p))
  (let ((queue *message-queue*))
    (unless queue
      (return-from nack-message nil))
    (let ((redis-connected (message-queue-redis-connected queue))
          (dlq-name (message-queue-dlq-name queue)))
      (unless redis-connected
        (return-from nack-message nil))
      (handler-case
          (progn
            (if requeue-p
                (move-to-dlq queue message-id)
                (incf (message-queue-ack-count queue)))
            (incf (message-queue-nack-count queue))
            (log-debug "Nacked message ~a (requeue: ~a)" message-id requeue-p)
            t)
        (error (c)
          (log-error "Failed to nack message: ~a" c)
          nil)))))

;;;; Dead Letter Queue

(defun move-to-dlq (queue message-id)
  "Move message to dead letter queue"
  (declare (type message-queue queue)
           (type integer message-id))
  (when (message-queue-redis-connected queue)
    (let ((dlq-name (message-queue-dlq-name queue)))
      (handler-case
          (progn
            (let ((entry (list :original-id message-id
                               :original-stream (message-queue-queue-name queue)
                               :failed-at (get-universal-time))))
              (redis:red-rpush dlq-name (cl-json:encode-json-to-string entry)))
            (incf (message-queue-dlq-count queue))
            (log-warn "Message ~a moved to DLQ" message-id)
            t)
        (error (c)
          (log-error "Failed to move message to DLQ: ~a" c)
          nil)))))

;;;; Pending Messages

(defun get-pending-messages (&optional (count 100))
  "Get pending messages (simplified - returns queue length)"
  (declare (type integer count))
  (let ((queue *message-queue*))
    (unless queue
      (return-from get-pending-messages nil))
    (let ((redis-connected (message-queue-redis-connected queue))
          (queue-name (message-queue-queue-name queue)))
      (unless redis-connected
        (return-from get-pending-messages nil))
      (handler-case
          (let ((len (redis:red-llen queue-name)))
            (list :pending len))
        (error (c)
          (log-debug "Get pending error: ~a" c)
          nil)))))

;;;; Consumer

(defun start-message-consumer (&optional message-handler)
  "Start background message consumer"
  (let ((queue *message-queue*))
    (unless queue
      (log-error "Cannot start consumer: queue not initialized")
      (return-from start-message-consumer nil))
    (when *message-queue-consumer*
      (log-warn "Message consumer already running")
      (return-from start-message-consumer nil))
    (setf *message-queue-running* t)
    (setf *message-queue-consumer*
          (bordeaux-threads:make-thread
           (lambda ()
             (log-info "Message consumer started")
             (let ((timeout (cdr (assoc :block-timeout *message-queue-config*)))
                   (retry-delay (cdr (assoc :retry-delay *message-queue-config*))))
               (loop while *message-queue-running*
                     do (handler-case
                            (let ((msg (dequeue-message :block t :timeout timeout)))
                              (when msg
                                (let ((msg-id (getf msg :message-id))
                                      (data (getf msg :data)))
                                  (handler-case
                                      (progn
                                        (if message-handler
                                            (funcall message-handler data)
                                            (process-queued-message data))
                                        (ack-message msg-id))
                                    (error (c)
                                      (log-error "Message processing error: ~a" c)
                                      (nack-message msg-id :requeue-p t))))))
                          (error (c)
                            (log-error "Consumer error: ~a" c)
                            (sleep retry-delay)))
                     (sleep 0.1))))))
    (log-info "Message consumer started")))

(defun stop-message-consumer ()
  "Stop message consumer"
  (setf *message-queue-running* nil)
  (when *message-queue-consumer*
    (bordeaux-threads:destroy-thread *message-queue-consumer*)
    (setf *message-queue-consumer* nil)
    (log-info "Message consumer stopped")))

;;;; Message Processing

(defun process-queued-message (message-data)
  "Process a queued message"
  (declare (type list message-data))
  (let* ((type (getf message-data :type))
         (recipient (getf message-data :recipient-id))
         (content (getf message-data :content))
         (msg-id (getf message-data :message-id)))
    (case type
      (:chat
       (let ((connections (get-user-connections recipient)))
         (if (and connections (> (length connections) 0))
             (dolist (conn connections)
               (send-message-to-connection conn msg-id content :type type))
             (enqueue-offline-message msg-id
                                      (getf message-data :sender-id)
                                      recipient
                                      (getf message-data :conversation-id)
                                      content :type type))))
      (:notification
       (let ((connections (get-user-connections recipient)))
         (when connections
           (dolist (conn connections)
             (send-notification-to-connection conn message-data)))))
      (t
       (log-debug "Unknown message type: ~a" type)))))

;;;; Statistics

(defun get-message-queue-stats ()
  "Get message queue statistics"
  (let ((queue *message-queue*))
    (unless queue
      (return-from get-message-queue-stats nil))
    (list :enqueue-count (message-queue-enqueue-count queue)
          :dequeue-count (message-queue-dequeue-count queue)
          :ack-count (message-queue-ack-count queue)
          :nack-count (message-queue-nack-count queue)
          :dlq-count (message-queue-dlq-count queue)
          :consumer-running (if *message-queue-consumer* t nil))))

(defun print-message-queue-stats ()
  "Print message queue statistics"
  (let ((stats (get-message-queue-stats)))
    (when stats
      (format t "~%Message Queue Statistics:~%")
      (format t "  Enqueued: ~a~%" (getf stats :enqueue-count))
      (format t "  Dequeued: ~a~%" (getf stats :dequeue-count))
      (format t "  Acked: ~a~%" (getf stats :ack-count))
      (format t "  Nacked: ~a~%" (getf stats :nack-count))
      (format t "  DLQ: ~a~%" (getf stats :dlq-count))
      (format t "  Consumer: ~a~%" (if (getf stats :consumer-running) "Running" "Stopped")))))

;;;; Exports

(export '(;; Queue management
          init-message-queue
          *message-queue*
          message-queue
          make-message-queue
          ;; Enqueue operations
          enqueue-message
          enqueue-message-batch
          ;; Dequeue operations
          dequeue-message
          dequeue-messages
          ;; Acknowledgment
          ack-message
          nack-message
          ;; Dead letter queue
          move-to-dlq
          ;; Pending messages
          get-pending-messages
          ;; Consumer
          start-message-consumer
          stop-message-consumer
          *message-queue-consumer*
          *message-queue-running*
          ;; Statistics
          get-message-queue-stats
          print-message-queue-stats
          ;; Configuration
          *message-queue-config*)
        :lispim-core)
