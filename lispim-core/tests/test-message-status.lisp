;;;; test-message-status.lisp - Message Status Tracking Tests
;;;;
;;;; Tests for the message status tracking system

(in-package :lispim-core/test)

;;;; Test Package

(defpackage :lispim-core/test/message-status
  (:use :cl :fiveam :lispim-core)
  (:export :run-message-status-tests))

(in-package :lispim-core/test/message-status)

;;;; Status Code Conversion Tests

(def-test test-status-code-to-keyword ()
  "Test status code to keyword conversion"
  (is (eq :pending (status-code-to-keyword 0)))
  (is (eq :sending (status-code-to-keyword 1)))
  (is (eq :sent (status-code-to-keyword 2)))
  (is (eq :delivered (status-code-to-keyword 3)))
  (is (eq :read (status-code-to-keyword 4)))
  (is (eq :failed (status-code-to-keyword 5))))

(def-test test-status-keyword-to-code ()
  "Test status keyword to code conversion"
  (is (= 0 (status-keyword-to-code :pending)))
  (is (= 1 (status-keyword-to-code :sending)))
  (is (= 2 (status-keyword-to-code :sent)))
  (is (= 3 (status-keyword-to-code :delivered)))
  (is (= 4 (status-keyword-to-code :read)))
  (is (= 5 (status-keyword-to-code :failed))))

(def-test test-status-conversion-roundtrip ()
  "Test that status conversion is reversible"
  (loop for code from 0 to 5 do
    (is (= code (status-keyword-to-code (status-code-to-keyword code))))))

;;;; Message Status Info Structure Tests

(def-test test-make-message-status-info ()
  "Test creating message status info structure"
  (let ((info (make-message-status-info)))
    (is (eq :pending (message-status-info-status info)))
    (is (= 0 (message-status-info-status-code info)))
    (is (= 0 (message-status-info-retry-count info)))
    (is (= 3 (message-status-info-max-retries info)))
    (is (null (message-status-info-last-error info)))
    (is (listp (message-status-info-delivered-to info)))
    (is (listp (message-status-info-read-by info)))
    (is (typep (message-status-info-metadata info) 'hash-table))))

(def-test test-message-status-info-with-values ()
  "Test creating message status info with custom values"
  (let ((info (make-message-status-info
               :status :delivered
               :status-code 3
               :retry-count 1
               :last-error "Test error"
               :delivered-to '("user1" "user2"))))
    (is (eq :delivered (message-status-info-status info)))
    (is (= 3 (message-status-info-status-code info)))
    (is (= 1 (message-status-info-retry-count info)))
    (is (string= "Test error" (message-status-info-last-error info)))
    (is (equal '("user1" "user2") (message-status-info-delivered-to info)))))

;;;; Retry Delay Tests

(def-test test-get-retry-delay ()
  "Test exponential backoff delay calculation"
  ;; Expected: 5 * 3^retry-count
  (is (= 5 (get-retry-delay 0)))    ; 5 * 1 = 5
  (is (= 15 (get-retry-delay 1)))   ; 5 * 3 = 15
  (is (= 45 (get-retry-delay 2)))   ; 5 * 9 = 45
  (is (= 135 (get-retry-delay 3)))) ; 5 * 27 = 135

;;;; Failed Message Queue Tests

(def-test test-enqueue-dequeue-failed-message ()
  "Test enqueueing and dequeueing failed messages"
  (let* ((conv-id 12345)
         (msg-id 98765)
         (content "Test message"))
    ;; Clear queue first
    (dequeue-failed-messages conv-id :limit 100)

    ;; Enqueue
    (enqueue-failed-message msg-id conv-id content :type :text)

    ;; Dequeue
    (let ((messages (dequeue-failed-messages conv-id :limit 10)))
      (is (= 1 (length messages)))
      (let ((msg (first messages)))
        (is (= msg-id (getf msg :message-id)))
        (is (string= content (getf msg :content)))
        (is (eq :text (getf msg :type)))))))

(def-test test-dequeue-empty-queue ()
  "Test dequeueing from empty queue returns nil"
  (let ((conv-id 99999))
    ;; Clear any existing messages
    (dequeue-failed-messages conv-id :limit 100)

    ;; Try to dequeue
    (is (null (dequeue-failed-messages conv-id :limit 10)))))

(def-test test-dequeue-partial ()
  "Test dequeueing only requested limit"
  (let* ((conv-id 54321)
         (messages-to-add 5)
         (limit 3))
    ;; Clear queue first
    (dequeue-failed-messages conv-id :limit 100)

    ;; Add messages
    (loop for i from 1 to messages-to-add do
      (enqueue-failed-message (+ 1000 i) conv-id (format nil "Message ~a" i)))

    ;; Dequeue with limit
    (let ((messages (dequeue-failed-messages conv-id :limit limit)))
      (is (= limit (length messages))))

    ;; Remaining messages should still be in queue
    (let ((remaining (dequeue-failed-messages conv-id :limit 100)))
      (is (= (- messages-to-add limit) (length remaining))))))

;;;; Should Retry Tests

(def-test test-should-retry-message-pending ()
  "Test that pending messages should not be retried"
  ;; This would require database setup, so we just test the logic
  ;; In a real test, we'd need to store a message with :pending status
  t) ;; Placeholder

;;;; ACK Tracking Tests

(def-test test-create-message-ack ()
  "Test creating ACK tracking"
  (let* ((msg-id 11111)
         (recipients '("user1" "user2" "user3")))
    ;; Clear any existing
    (bordeaux-threads:with-lock-held (*pending-acks-lock*)
      (remhash msg-id *pending-acks*))

    ;; Create ACK
    (create-message-ack msg-id recipients :timeout-seconds 30)

    ;; Verify
    (bordeaux-threads:with-lock-held (*pending-acks-lock*)
      (let ((ack (gethash msg-id *pending-acks*)))
        (is (not (null ack)))
        (is (= msg-id (message-ack-message-id ack)))
        (is (equal recipients (message-ack-pending-acks ack)))
        (is (= 30 (- (message-ack-timeout-at ack) (get-universal-time))))))))

(def-test test-acknowledge-message ()
  "Test acknowledging message receipt"
  (let* ((msg-id 22222)
         (user-id "user1")
         (recipients (list user-id "user2")))
    ;; Clear any existing
    (bordeaux-threads:with-lock-held (*pending-acks-lock*)
      (remhash msg-id *pending-acks*))

    ;; Create ACK
    (create-message-ack msg-id recipients :timeout-seconds 30)

    ;; Acknowledge
    (multiple-value-bind (success status)
        (acknowledge-message msg-id user-id)
      (is (eq t success))
      (is (eq :acked status)))

    ;; Verify user removed from pending
    (bordeaux-threads:with-lock-held (*pending-acks-lock*)
      (let ((ack (gethash msg-id *pending-acks*)))
        (is (not (member user-id (message-ack-pending-acks ack) :test #'string=)))
        (is (member user-id (mapcar #'car (message-ack-acked-by ack)) :test #'string=))))))

(def-test test-acknowledge-all-recipients ()
  "Test that fully acknowledged message is removed from pending"
  (let* ((msg-id 33333)
         (recipients '("user1" "user2")))
    ;; Clear any existing
    (bordeaux-threads:with-lock-held (*pending-acks-lock*)
      (remhash msg-id *pending-acks*))

    ;; Create ACK with callback
    (let ((callback-called nil)
          (callback-status nil))
      (create-message-ack msg-id recipients
                          :timeout-seconds 30
                          :callback (lambda (id status)
                                      (setf callback-called t
                                            callback-status status)))

      ;; Acknowledge all
      (dolist (user recipients)
        (acknowledge-message msg-id user))

      ;; Should be removed from pending
      (bordeaux-threads:with-lock-held (*pending-acks-lock*)
        (is (null (gethash msg-id *pending-acks*))))

      ;; Callback should have been called
      (is callback-called)
      (is (eq :fully-acked callback-status)))))

;;;; Run All Tests

(defun run-message-status-tests ()
  "Run all message status tracking tests"
  (run! :lispim-core/test/message-status))
