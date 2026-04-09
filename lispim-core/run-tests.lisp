;;; Run LispIM Core Test Suite
;;; Usage: sbcl --non-interactive --load run-tests.lisp
;;;
;;; This script runs all available tests and reports results.

;; First load ASDF
(require 'asdf)

;; Load system definition
(let* ((base-path (or *load-pathname* *default-pathname-defaults*))
       (base-dir (pathname (directory-namestring base-path))))
  (pushnew base-dir asdf:*central-registry* :test #'equal))

;; Set external format for consistent encoding
#+sbcl (setf sb-impl::*default-external-format* :utf-8)

;; Load dependencies
(format t "~%~%; Loading Quicklisp...~%")
(ql:quickload :quicklisp)
(quicklisp:setup)

(format t "~%~%; Loading test dependencies...~%")
(ql:quickload '(:fiveam
                :hunchentoot
                :cl-json
                :postmodern
                :cl-redis
                :bordeaux-threads
                :uuid
                :babel
                :salza2
                :local-time
                :log4cl
                :ironclad
                :trivia
                :alexandria
                :serapeum
                :flexi-streams
                :str
                :drakma
                :cl-ppcre))

;; Load the system
(format t "~%~%; Loading LispIM Core system...~%")
(handler-case
    (asdf:load-system :lispim-core)
  (error (c)
    (format t "~%ERROR: Failed to load system: ~a~%" c)
    (sb-ext:quit :unix-status 1)))

;; Load test system
(format t "~%~%; Loading test suite...~%")
(handler-case
    (asdf:load-system :lispim-core/test)
  (error (c)
    (format t "~%ERROR: Failed to load test suite: ~a~%" c)
    (sb-ext:quit :unix-status 1)))

;; Run tests
(format t "~%~%========================================~%")
(format t "  Running LispIM Core Test Suite~%")
(format t "========================================~%")

(defvar *test-passed* t)
(defvar *test-results* nil)

;; Run all FiveAM tests
(dolist (test-suite '(:test-snowflake
                      :test-gateway
                      :test-module
                      :test-chat
                      :test-e2ee
                      :test-message-status
                      :test-message-encoding
                      :test-multi-level-cache
                      :test-offline-queue
                      :test-sync
                      :test-message-queue
                      :test-cluster
                      :test-double-ratchet
                      :test-cdn-storage
                      :test-db-replica
                      :test-message-dedup
                      :test-rate-limiter
                      :test-fulltext-search
                      :test-message-reply
                      :test-new-features
                      :test-privacy))
  (format t "~%Running test: ~a... " test-suite)
  (handler-case
      (let ((result (fiveam:run! test-suite)))
        (if result
            (format t "PASSED")
            (progn
              (format t "FAILED")
              (setf *test-passed* nil)))
        (push (list test-suite result) *test-results*))
    (error (c)
      (format t "ERROR: ~a" c)
      (setf *test-passed* nil)
      (push (list test-suite :error (princ-to-string c)) *test-results*))))

;; Report results
(format t "~%~%========================================~%")
(format t "  Test Report~%")
(format t "========================================~%~%")

(format t "Results:~%")
(dolist (result (reverse *test-results*))
  (let ((name (first result))
        (status (second result)))
    (format t "  ~a: ~a~%" name
            (cond
              ((eq status t) "PASSED")
              ((eq status :error) "ERROR")
              (t "FAILED")))))

(format t "~%~%========================================~%")

(if *test-passed*
    (progn
      (format t "~%All tests PASSED!~%~%")
      (sb-ext:quit :unix-status 0))
    (progn
      (format t "~%Some tests FAILED!~%~%")
      (sb-ext:quit :unix-status 1)))
