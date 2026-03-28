;;;; test-phase7.lisp - Phase 7 Integration Test
;;;;
;;;; Test fulltext search and message reply APIs

(in-package :lispim-core)

;;;; Test Fulltext Search

(defun test-fulltext-search ()
  "Test fulltext search functionality"
  (format t "~%=== Testing Fulltext Search ===~%")

  ;; Test tokenize-text
  (let* ((text "Hello World 测试中文")
         (tokens (tokenize-text text)))
    (format t "Tokenize '~A': ~A~%" text tokens)
    (assert (member "hello" tokens :test 'string=))
    (assert (member "world" tokens :test 'string=)))

  ;; Test build-inverted-index
  (let* ((text "Lisp programming is awesome")
         (index (build-inverted-index text)))
    (format t "Inverted index for '~A': ~A~%" text index)
    (assert (gethash "lisp" index))
    (assert (gethash "programming" index)))

  ;; Test search-messages (requires database)
  (format t "Search API test skipped (requires database)~%")

  (format t "Fulltext search tests passed!~%")
  t)

;;;; Test Message Reply

(defun test-message-reply-struct ()
  "Test message reply struct creation"
  (format t "~%=== Testing Message Reply Struct ===~%")

  (let ((reply (make-message-reply
                :id "reply-1"
                :message-id "msg-1"
                :reply-to-id "msg-0"
                :conversation-id "conv-1"
                :sender-id "user-1"
                :reply-to-sender-id "user-0"
                :quote-content "Original message"
                :quote-type "text"
                :depth 1
                :created-at (get-universal-time))))
    (format t "Created reply: ~A~%" reply)
    (assert (string= (message-reply-id reply) "reply-1"))
    (assert (string= (message-reply-message-id reply) "msg-1"))
    (assert (= (message-reply-depth reply) 1)))

  (format t "Message reply struct tests passed!~%")
  t)

(defun test-reply-thread-struct ()
  "Test reply thread struct creation"
  (format t "~%=== Testing Reply Thread Struct ===~%")

  (let ((thread (make-reply-thread
                 :root-message-id "msg-0"
                 :reply-count 5
                 :latest-reply-id "msg-5"
                 :latest-reply-at (get-universal-time)
                 :participants '("user-1" "user-2" "user-3"))))
    (format t "Created thread: ~A~%" thread)
    (assert (string= (reply-thread-root-message-id thread) "msg-0"))
    (assert (= (reply-thread-reply-count thread) 5))
    (assert (= (length (reply-thread-participants thread)) 3)))

  (format t "Reply thread struct tests passed!~%")
  t)

;;;; Run All Tests

(defun run-phase7-tests ()
  "Run all Phase 7 tests"
  (format t "~%========================================~%")
  (format t "  Phase 7 Integration Tests~%")
  (format t "========================================~%")

  (let ((passed 0)
        (failed 0))

    ;; Test fulltext search
    (handler-case
        (progn
          (test-fulltext-search)
          (incf passed))
      (error (c)
        (format t "Fulltext search test FAILED: ~A~%" c)
        (incf failed)))

    ;; Test message reply struct
    (handler-case
        (progn
          (test-message-reply-struct)
          (incf passed))
      (error (c)
        (format t "Message reply struct test FAILED: ~A~%" c)
        (incf failed)))

    ;; Test reply thread struct
    (handler-case
        (progn
          (test-reply-thread-struct)
          (incf passed))
      (error (c)
        (format t "Reply thread struct test FAILED: ~A~%" c)
        (incf failed)))

    (format t "~%========================================~%")
    (format t "  Results: ~A passed, ~A failed~%" passed failed)
    (format t "========================================~%")

    (zerop failed)))

;; Run tests when loaded
;; (run-phase7-tests)
