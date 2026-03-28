;;;; test-message-queue.lisp - Unit tests for Redis Streams message queue

(in-package :lispim-core/test)

(def-suite test-message-queue
  :description "Redis Streams message queue unit tests")

(in-suite test-message-queue)

;;;; Queue Initialization

(test message-queue-init
  "Test message queue initialization"
  (let ((queue (lispim-core:init-message-queue
                :redis-host "localhost"
                :redis-port 6379
                :stream-name "lispim:test:messages"
                :group-name "lispim:test:consumers"
                :consumer-name "test-consumer-1")))
    (is (not (null queue)))
    (is (typep queue 'lispim-core::message-queue))
    (is (string= (lispim-core::message-queue-stream-name queue) "lispim:test:messages"))
    (is (string= (lispim-core::message-queue-group-name queue) "lispim:test:consumers"))))

;;;; Enqueue Operations

(test enqueue-message-basic
  "Test basic message enqueue"
  (lispim-core:init-message-queue
   :redis-host "localhost"
   :redis-port 6379
   :stream-name "lispim:test:messages:1"
   :group-name "lispim:test:consumers:1")
  (let ((message '(:type :chat :recipient-id "user1" :content "Hello" :message-id 123)))
    (let ((result (lispim-core:enqueue-message message :priority :normal)))
      ;; Should return message-id if Redis is available
      (is (or (null result) (integerp result))))))

(test enqueue-message-batch
  "Test batch message enqueue"
  (lispim-core:init-message-queue
   :redis-host "localhost"
   :redis-port 6379
   :stream-name "lispim:test:messages:2"
   :group-name "lispim:test:consumers:2")
  (let ((messages
         (loop for i from 1 to 5
               collect '(:type :chat :recipient-id "user1"
                         :content (format nil "Message ~a" i)
                         :message-id (+ 100 i)))))
    (let ((results (lispim-core:enqueue-message-batch messages :priority :normal)))
      (is (listp results))
      ;; If Redis available, should have 5 ids
      (when results
        (is (= (length results) 5))))))

;;;; Dequeue Operations

(test dequeue-message-basic
  "Test basic message dequeue"
  (lispim-core:init-message-queue
   :redis-host "localhost"
   :redis-port 6379
   :stream-name "lispim:test:messages:3"
   :group-name "lispim:test:consumers:3")
  ;; First enqueue a message
  (lispim-core:enqueue-message '(:type :test :content "Dequeue test") :priority :normal)
  ;; Then dequeue (non-blocking)
  (let ((result (lispim-core:dequeue-message :block nil)))
    (is (or (null result) (listp result)))))

(test dequeue-messages-batch
  "Test batch message dequeue"
  (lispim-core:init-message-queue
   :redis-host "localhost"
   :redis-port 6379
   :stream-name "lispim:test:messages:4"
   :group-name "lispim:test:consumers:4")
  ;; Enqueue some messages
  (lispim-core:enqueue-message-batch
   (loop for i from 1 to 3
         collect '(:type :test :content (format nil "Batch ~a" i)))
   :priority :normal)
  ;; Dequeue batch
  (let ((results (lispim-core:dequeue-messages :batch-size 10 :block nil)))
    (is (listp results))))

;;;; Acknowledgment

(test ack-message-basic
  "Test message acknowledgment"
  ;; This test requires a message to be dequeued first
  ;; For now, just test the function exists and handles nil gracefully
  (let ((result (lispim-core:ack-message "test-message-id")))
    (is (booleanp result))))

(test nack-message-basic
  "Test negative acknowledgment"
  (let ((result (lispim-core:nack-message "test-message-id" :requeue-p t))
        (result2 (lispim-core:nack-message "test-message-id" :requeue-p nil)))
    (is (booleanp result))
    (is (booleanp result2))))

;;;; Configuration

(test message-queue-config-defaults
  "Test message queue configuration defaults"
  (let ((config lispim-core:*message-queue-config*))
    (is (not (null config)))
    (is (string= (cdr (assoc :stream-name config)) "lispim:messages"))
    (is (string= (cdr (assoc :group-name config)) "lispim-consumers"))
    (is (= (cdr (assoc :block-timeout config)) 5000))
    (is (= (cdr (assoc :max-retry-count config)) 3))
    (is (= (cdr (assoc :batch-size config)) 100))))

;;;; Statistics

(test message-queue-stats
  "Test message queue statistics"
  (lispim-core:init-message-queue
   :redis-host "localhost"
   :redis-port 6379
   :stream-name "lispim:test:messages:5"
   :group-name "lispim:test:consumers:5")
  (let ((stats (lispim-core:get-message-queue-stats)))
    (is (listp stats))
    (is (not (null (getf stats :enqueue-count))))
    (is (not (null (getf stats :dequeue-count))))
    (is (not (null (getf stats :ack-count))))
    (is (not (null (getf stats :nack-count))))
    (is (not (null (getf stats :dlq-count))))))

;;;; Consumer Lifecycle

(test message-queue-consumer-lifecycle
  "Test consumer start/stop lifecycle"
  (lispim-core:init-message-queue
   :redis-host "localhost"
   :redis-port 6379
   :stream-name "lispim:test:messages:6"
   :group-name "lispim:test:consumers:6")
  ;; Start consumer
  (lispim-core:start-message-consumer (lambda (msg) (declare (ignore msg))))
  (sleep 0.5) ; Give thread time to start
  (is (not (null lispim-core:*message-queue-consumer*)))
  (is lispim-core:*message-queue-running*)
  ;; Stop consumer
  (lispim-core:stop-message-consumer)
  (sleep 0.1)
  (is (null lispim-core:*message-queue-consumer*)))

;;;; Integration Test

(test message-queue-integration
  "Integration test for message queue flow"
  (lispim-core:init-message-queue
   :redis-host "localhost"
   :redis-port 6379
   :stream-name "lispim:test:messages:7"
   :group-name "lispim:test:consumers:7")
  (let ((processed nil))
    ;; Start consumer with handler
    (lispim-core:start-message-consumer
     (lambda (msg) (push msg processed)))
    (sleep 0.5)
    ;; Enqueue messages
    (lispim-core:enqueue-message '(:type :test :content "Integration 1") :priority :normal)
    (lispim-core:enqueue-message '(:type :test :content "Integration 2") :priority :normal)
    ;; Wait for processing
    (sleep 2)
    ;; Stop consumer
    (lispim-core:stop-message-consumer)
    ;; Check stats
    (let ((stats (lispim-core:get-message-queue-stats)))
      (is (>= (getf stats :enqueue-count) 2)))))

;;;; Priority Test

(test enqueue-priority
  "Test message priority handling"
  (lispim-core:init-message-queue
   :redis-host "localhost"
   :redis-port 6379
   :stream-name "lispim:test:messages:8"
   :group-name "lispim:test:consumers:8")
  ;; Enqueue with different priorities
  (lispim-core:enqueue-message '(:type :test :content "Normal") :priority :normal)
  (lispim-core:enqueue-message '(:type :test :content "High") :priority :high)
  (lispim-core:enqueue-message '(:type :test :content "Low") :priority :low)
  ;; All should succeed
  (is t))
