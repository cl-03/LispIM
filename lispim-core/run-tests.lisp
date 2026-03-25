;;; Run LispIM Core Snowflake Tests
;;; Usage: sbcl --load run-tests.lisp

;; First load ASDF
(require 'asdf)

;; Load system definition
(let* ((base-path (or *load-pathname* *default-pathname-defaults*))
       (base-dir (pathname (directory-namestring base-path))))
  (pushnew base-dir asdf:*central-registry* :test #'equal))

;; Load dependencies
(ql:quickload :fiveam)

;; Load the system
(asdf:load-system :lispim-core)
(asdf:load-system :lispim-core/test)

(format t "~%========================================~%")
(format t "Running Snowflake Tests~%")
(format t "========================================~%~%")

(defparameter *result* (fiveam:run! :test-snowflake))

(format t "~%========================================~%")
(format t "Tests result: ~a~%" *result*)
(format t "========================================~%")

;; Simple check - if result is T or non-nil, tests passed
(if *result*
    (progn
      (format t "~%All tests PASSED!~%")
      (sb-ext:quit :unix-status 0))
    (progn
      (format t "~%Some tests FAILED!~%")
      (sb-ext:quit :unix-status 1)))
