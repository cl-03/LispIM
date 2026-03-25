;;; Run LispIM Core Snowflake Tests - Simple version
;;; Usage: sbcl --load run-tests-simple.lisp

(require 'asdf)

;; Load system definition
(let* ((base-path (or *load-pathname* *default-pathname-defaults*))
       (base-dir (pathname (directory-namestring base-path))))
  (pushnew base-dir asdf:*central-registry* :test #'equal))

(format t "~%Loading FiveAM...~%")
(ql:quickload :fiveam :silent t)

(format t "Loading LispIM Core...~%")
(asdf:load-system :lispim-core :verbose nil)

(format t "~%========================================~%")
(format t "Running Snowflake Tests~%")
(format t "========================================~%~%")

;; Load test file directly in lispim-core package
(in-package :lispim-core)
(load "tests/test-snowflake.lisp")

(defparameter *result* (fiveam:run! :test-snowflake))

(format t "~%========================================~%")
(format t "Tests result: ~a~%" *result*)
(format t "========================================~%")

;; Check if all tests passed
(if (and (listp *result*)
         (every #'fiveam::test-passed-p *result*))
    (progn
      (format t "~%All tests PASSED!~%")
      (sb-ext:quit))
    (progn
      (format t "~%Some tests FAILED!~%")
      (sb-ext:quit :unix-status 1)))
