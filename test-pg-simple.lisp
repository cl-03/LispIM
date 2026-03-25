;;;; test-pg-simple.lisp - Simple PostgreSQL connection test

;; Set locale before loading
(setf sb-impl::*default-external-format* :utf-8)

(ql:quickload '(:postmodern))

(in-package :postmodern)

(format t "~%PostgreSQL Connection Test~%")
(format t "========================~%~%")

;; Try connecting with explicit encoding
(handler-case
    (progn
      (format t "Connecting to PostgreSQL (127.0.0.1:5432)...~%")
      (format t "Database: lispim, User: lispim~%~%")

      ;; Try with IP address 127.0.0.1 instead of localhost
      (connect "lispim" "lispim" "Clsper03" "127.0.0.1" :port 5432 :use-ssl :no)

      (format t "SUCCESS: Connected!~%")

      ;; Try query
      (format t "Running query: SELECT 1~%")
      (let ((result (query "SELECT 1")))
        (format t "Result: ~A~%" result)))

  (error (e)
    (format t "ERROR: ~A~%" e)
    (format t "Type: ~A~%" (type-of e))))

(uiop:quit 0)
