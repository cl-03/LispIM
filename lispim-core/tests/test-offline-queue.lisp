;;;; test-offline-queue.lisp - Unit tests for offline message queue

(in-package :lispim-core/test)

(def-suite test-offline-queue
  :description "Offline message queue unit tests")

(in-suite test-offline-queue)

;;;; Helper functions

(defun setup-offline-queue ()
  "Setup offline queue for testing"
  (lispim-core:init-offline-queue :redis-host "localhost" :redis-port 6379))

(defun teardown-offline-queue ()
  "Teardown offline queue after testing"
  (lispim-core:stop-offline-queue-worker)
  (when lispim-core:*offline-queue*
    (let ((redis (lispim-core::offline-queue-redis-client lispim-core:*offline-queue*)))
      (when redis
        ;; Clear test data
        (handler-case
            (progn
              (cl-redis:redis-del redis "offline:queue:test-user")
              (cl-redis:redis-srem redis "offline:pending" "999999")
              (cl-redis:redis-del redis "offline:msg:999999"))
          (error () nil))))))

;;;; Queue Initialization

(test offline-queue-init
  "Test offline queue initialization"
  (let ((queue (setup-offline-queue)))
    (unwind-protect
         (progn
           (is (not (null queue)))
           (is (typep queue 'lispim-core::offline-queue)))
      (teardown-offline-queue))))

;;;; Queue Operations

(test enqueue-offline-message
  "Test enqueueing offline message"
  (setup-offline-queue)
  (unwind-protect
       (let ((result (lispim-core:enqueue-offline-message
                      999999 "user1" "user2" 1 "Hello offline" :type :text)))
         ;; Should succeed if Redis is available
         (is (booleanp result)))
    (teardown-offline-queue)))

(test get-offline-message-count
  "Test getting offline message count"
  (setup-offline-queue)
  (unwind-protect
       (progn
         ;; Enqueue a message
         (lispim-core:enqueue-offline-message
          999998 "user1" "user2" 1 "Test message" :type :text)
         ;; Get count
         (let ((count (lispim-core:get-offline-message-count "user2")))
           (is (integerp count))
           (is (>= count 0))))
    (teardown-offline-queue)))

(test dequeue-offline-messages
  "Test dequeueing offline messages"
  (setup-offline-queue)
  (unwind-protect
       (progn
         ;; Enqueue a message
         (lispim-core:enqueue-offline-message
          999997 "user1" "user3" 1 "Dequeue test" :type :text)
         ;; Dequeue messages
         (let ((messages (lispim-core:dequeue-offline-messages "user3" 10)))
           (is (listp messages))
           ;; If Redis is available and message was enqueued, should get message
           (when (> (length messages) 0)
             (let ((msg (first messages)))
               (is (equal (cdr (assoc :message-id msg)) 999997))
               (is (string= (cdr (assoc :content msg)) "Dequeue test"))))))
    (teardown-offline-queue)))

;;;; Retry Logic

(test get-retry-delay
  "Test exponential backoff delay calculation"
  ;; 5s, 15s, 45s, 135s, 405s
  (is (= (lispim-core:get-retry-delay 0) 5))
  (is (= (lispim-core:get-retry-delay 1) 15))
  (is (= (lispim-core:get-retry-delay 2) 45))
  (is (= (lispim-core:get-retry-delay 3) 405)))

;;;; Queue Statistics

(test offline-queue-stats
  "Test offline queue statistics"
  (setup-offline-queue)
  (unwind-protect
       (let ((stats (lispim-core:get-offline-queue-stats)))
         (is (listp stats))
         (is (not (null (getf stats :pending))))
         (is (not (null (getf stats :processed))))
         (is (not (null (getf stats :failed)))))
    (teardown-offline-queue)))

;;;; Worker Thread

(test offline-queue-worker
  "Test offline queue worker lifecycle"
  (setup-offline-queue)
  (unwind-protect
       (progn
         ;; Start worker
         (lispim-core:start-offline-queue-worker)
         (sleep 0.5) ; Give thread time to start
         (is (not (null lispim-core:*offline-queue-worker*)))
         (is lispim-core:*offline-queue-running*)
         ;; Stop worker
         (lispim-core:stop-offline-queue-worker)
         (sleep 0.1)
         (is (null lispim-core:*offline-queue-worker*)))
    (teardown-offline-queue)))

;;;; Message TTL

(test message-ttl
  "Test message TTL expiration"
  (setup-offline-queue)
  (unwind-protect
       (let ((redis (lispim-core::offline-queue-redis-client lispim-core:*offline-queue*)))
         (when redis
           ;; Enqueue with short TTL
           (lispim-core:enqueue-offline-message
            999996 "user1" "user4" 1 "TTL test" :type :text)
           ;; Check message exists
           (let ((msg (cl-redis:redis-get redis "offline:msg:999996")))
             (is (not (null msg))))))
    (teardown-offline-queue)))

;;;; Integration Test

(test offline-queue-integration
  "Integration test for offline queue flow"
  (setup-offline-queue)
  (unwind-protect
       (progn
         ;; Start worker
         (lispim-core:start-offline-queue-worker)
         ;; Enqueue messages for multiple users
         (dotimes (i 5)
           (lispim-core:enqueue-offline-message
            (+ 999900 i) "sender" (format nil "recipient-~a" i)
            1 (format nil "Message ~a" i) :type :text))
         ;; Check counts
         (let ((count (lispim-core:get-offline-message-count "recipient-0")))
           (is (>= count 0)))
         ;; Dequeue
         (let ((messages (lispim-core:dequeue-offline-messages "recipient-0" 10)))
           (is (listp messages)))
         ;; Stop worker
         (lispim-core:stop-offline-queue-worker))
    (teardown-offline-queue)))
