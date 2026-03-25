;;;; test-postmodern.lisp - Test postmodern connection

(ql:quickload '(:postmodern))

(in-package :postmodern)

(format t "~%Testing postmodern:connect API...~%")

;; Try different connection methods
(handler-case
    (progn
      ;; Method 1: Using connection string
      (format t "~%Method 1: Connection string~%")
      (connect "postgresql://lispim:Clsper03@localhost:5432/lispim")
      (format t "Success with connection string~%")
      (disconnect))
  (error (e)
    (format t "Method 1 failed: ~a~%" e)))

(handler-case
    (progn
      ;; Method 2: Using separate parameters
      (format t "~%Method 2: Separate parameters~%")
      (connect "lispim" "lispim" "Clsper03" "localhost" :port 5432)
      (format t "Success with separate parameters~%")
      (disconnect))
  (error (e)
    (format t "Method 2 failed: ~a~%" e)))

(uiop:quit 0)
