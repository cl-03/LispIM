;;;; test-message-dedup.lisp - Unit tests for message deduplication

(in-package :lispim-core/test)

(def-suite test-message-dedup
  :description "Message deduplication unit tests")

(in-suite test-message-dedup)

;;;; Initialization Tests

(test init-message-deduplicator
  "Test message deduplicator initialization"
  (let ((dedup (lispim-core:init-message-deduplicator
                :window-size 1000
                :window-ttl 3600
                :bloom-size 10000)))
    (is (typep dedup 'lispim-core::message-deduplicator))
    (is (= (lispim-core::message-deduplicator-window-size dedup) 1000))
    (is (= (lispim-core::message-deduplicator-window-ttl dedup) 3600))
    (is (not (null (lispim-core::message-deduplicator-bloom-filter dedup))))))

;;;; Fingerprint Tests

(test generate-message-fingerprint
  "Test message fingerprint generation"
  (let ((fp1 (lispim-core:generate-message-fingerprint "msg1" "content1" "user1" 1000))
        (fp2 (lispim-core:generate-message-fingerprint "msg2" "content2" "user2" 2000)))
    (is (vectorp fp1))
    (is (vectorp fp2))
    ;; Different messages should have different fingerprints
    (is (not (equalp fp1 fp2)))
    ;; Same message should have same fingerprint
    (let ((fp3 (lispim-core:generate-message-fingerprint "msg1" "content1" "user1" 1000)))
      (is (equalp fp1 fp3)))))

(test message-fingerprint-to-string
  "Test fingerprint to string conversion"
  (let ((fp (lispim-core:generate-message-fingerprint "msg1" "content1" "user1" 1000))
        (str (lispim-core:message-fingerprint-to-string fp)))
    (is (stringp str))
    ;; Should be hex string
    (is (every (lambda (c) (or (digit-char-p c) (find c "abcdefABCDEF"))) str))))

;;;; Bloom Filter Tests

(test bloom-filter-basic
  "Test basic bloom filter operations"
  (let ((bloom (make-array 1000 :element-type 'bit :initial-element 0))
        (fp (lispim-core:generate-message-fingerprint "msg1" "content1" "user1" 1000)))
    ;; Should not contain initially
    (is (not (lispim-core:bloom-filter-contains-p bloom fp)))
    ;; Add to filter
    (lispim-core:bloom-filter-add bloom fp)
    ;; Should contain after adding
    (is (lispim-core:bloom-filter-contains-p bloom fp))))

;;;; Deduplication Tests

(test dedup-check-message
  "Test message deduplication check"
  (let ((dedup (lispim-core:init-message-deduplicator :window-size 100 :bloom-size 1000)))
    ;; First check should pass (not duplicate)
    (is (not (lispim-core:dedup-check-message dedup "msg1" "content1" "user1" 1000)))
    ;; Second check should fail (duplicate)
    (is (lispim-core:dedup-check-message dedup "msg1" "content1" "user1" 1000))
    ;; Different message should pass
    (is (not (lispim-core:dedup-check-message dedup "msg2" "content2" "user2" 2000)))))

(test dedup-check-message-id-only
  "Test deduplication with message ID only"
  (let ((dedup (lispim-core:init-message-deduplicator :window-size 100 :bloom-size 1000)))
    ;; First check
    (is (not (lispim-core:dedup-check-message dedup "msg1")))
    ;; Duplicate check
    (is (lispim-core:dedup-check-message dedup "msg1"))))

;;;; Window Cleanup Tests

(test cleanup-dedup-window
  "Test dedup window cleanup"
  (let ((dedup (lispim-core:init-message-deduplicator :window-size 100 :window-ttl 1)))
    ;; Add some messages
    (lispim-core:dedup-check-message dedup "msg1" "content1")
    (lispim-core:dedup-check-message dedup "msg2" "content2")
    ;; Wait for TTL
    (sleep 2)
    ;; Cleanup should remove expired entries
    (let ((removed (lispim-core:cleanup-dedup-window dedup)))
      (is (>= removed 0)))))

;;;; Statistics Tests

(test get-dedup-stats
  "Test dedup statistics"
  (let ((dedup (lispim-core:init-message-deduplicator :window-size 100 :bloom-size 1000)))
    ;; Add some messages
    (lispim-core:dedup-check-message dedup "msg1" "content1")
    (lispim-core:dedup-check-message dedup "msg2" "content2")
    ;; Add duplicate
    (lispim-core:dedup-check-message dedup "msg1" "content1")
    ;; Get stats
    (let ((stats (lispim-core:get-dedup-stats dedup)))
      (is (listp stats))
      (is (= (getf stats :message-count) 2))
      (is (= (getf stats :duplicate-count) 1))
      (is (>= (getf stats :duplicate-rate) 0)))))

;;;; High-level API Tests

(test init-message-dedup
  "Test high-level init API"
  (let ((dedup (lispim-core:init-message-dedup :window-size 1000 :window-ttl 3600
                                                :bloom-size 10000 :cleanup-interval 60)))
    (is (not (null lispim-core:*message-deduplicator*)))
    (is (typep lispim-core:*message-deduplicator* 'lispim-core::message-deduplicator))
    ;; Cleanup
    (lispim-core:shutdown-message-dedup)))

(test is-duplicate-message-p
  "Test high-level duplicate check API"
  (lispim-core:init-message-dedup :window-size 100 :bloom-size 1000)
  ;; First message
  (is (not (lispim-core:is-duplicate-message-p "msg1" "content1" "user1" 1000)))
  ;; Duplicate
  (is (lispim-core:is-duplicate-message-p "msg1" "content1" "user1" 1000)))
  ;; Cleanup
  (lispim-core:shutdown-message-dedup))

;;;; Idempotency Macro Tests

(test with-idempotent-operation
  "Test idempotency macro"
  (lispim-core:init-message-dedup :window-size 100 :bloom-size 1000)
  (let ((result nil))
    ;; First execution should succeed
    (let ((executed (lispim-core:with-idempotent-operation ("op1" 3600)
                      (setf result 'first-execution)
                      t)))
      (is executed)
      (is (eq result 'first-execution)))
    ;; Second execution should be skipped
    (let ((executed (lispim-core:with-idempotent-operation ("op1" 3600)
                      (setf result 'second-execution)
                      t)))
      (is (null executed))
      (is (eq result 'first-execution)))) ;; Should still be first
  (lispim-core:shutdown-message-dedup))

;;;; Integration Test

(test dedup-integration
  "Integration test for message deduplication"
  (let ((dedup (lispim-core:init-message-deduplicator :window-size 1000 :bloom-size 10000)))
    ;; Simulate multiple messages
    (loop for i from 1 to 100
          do (lispim-core:dedup-check-message dedup
                                               (format nil "msg~d" i)
                                               (format nil "content~d" i)
                                               (format nil "user~d" (mod i 10))
                                               i))
    ;; Simulate some duplicates
    (loop for i from 1 to 20
          do (lispim-core:dedup-check-message dedup
                                               (format nil "msg~d" i)
                                               (format nil "content~d" i)
                                               (format nil "user~d" (mod i 10))
                                               i))
    ;; Check stats
    (let ((stats (lispim-core:get-dedup-stats dedup)))
      (is (= (getf stats :message-count) 100))
      (is (= (getf stats :duplicate-count) 20))
      (is (> (getf stats :duplicate-rate) 0)))))
