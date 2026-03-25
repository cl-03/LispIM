;;;; test-postmodern2.lisp - Test postmodern connection with correct API

(ql:quickload '(:postmodern))

(in-package :postmodern)

(format t "~%Testing postmodern:connect with correct API...~%")

;; postmodern:connect database user password host &key port socket-dsn unix-socket-name use-ssl
;; According to postmodern documentation

(handler-case
    (progn
      (format t "~%Connecting to PostgreSQL...~%")
      (connect "lispim" "lispim" "Clsper03" "localhost" :port 5432 :use-ssl :no)
      (format t "Connection successful!~%")

      ;; Test a simple query
      (let ((result (query "SELECT 1 AS test")))
        (format t "Query result: ~a~%" result))

      (disconnect *connection*))
  (error (e)
    (format t "Error: ~a~%" e)))

(uiop:quit 0)
