;;;; test-pg-v2.lisp - PostgreSQL connection test v2

(ql:quickload '(:postmodern))

(in-package :postmodern)

(format t "~%=== PostgreSQL Connection Test ===~%~%")

(handler-case
    (progn
      (format t "Connecting to PostgreSQL...~%")
      (format t "  Database: lispim~%")
      (format t "  User: lispim~%")
      (format t "  Host: 127.0.0.1:5432~%~%")

      ;; Connect with minimal parameters
      (connect "lispim" "lispim" "Clsper03" "127.0.0.1" :port 5432 :use-ssl :no)

      (format t "SUCCESS! Connected to PostgreSQL~%~%")

      ;; Test query
      (format t "Testing query...~%")
      (let ((result (query "SELECT 1 AS test")))
        (format t "Result: ~A~%" result)))

  (error (e)
    (format t "ERROR: ~A~%" e)
    (format t "Type: ~A~%" (type-of e))
    (format t "~%This might be a PostgreSQL server encoding configuration issue.~%")
    (format t "Try checking PostgreSQL server configuration:~%")
    (format t "  - Check server_encoding in postgresql.conf~%")
    (format t "  - Should be UTF8~%")))

(uiop:quit 0)
