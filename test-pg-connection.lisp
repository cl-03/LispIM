;;;; test-pg-connection.lisp - Test PostgreSQL connection after setup

(ql:quickload '(:postmodern))

(format t "~%=== PostgreSQL Connection Test ===~%~%")

;; Use dynamic variables for connection
(defparameter *db* nil)

(handler-case
    (progn
      (format t "Connecting to PostgreSQL...~%")
      (format t "  Database: lispim~%")
      (format t "  User: lispim~%")
      (format t "  Host: 127.0.0.1:5432~%~%")

      ;; Connect and store connection
      (setf *db* (postmodern:connect-toplevel "lispim" "lispim" "Clsper03" "127.0.0.1" :port 5432 :use-ssl :no))
      (format t "SUCCESS! Connected to PostgreSQL~%~%")

      ;; Test query
      (format t "Testing query...~%")
      (let ((result (postmodern:query "SELECT 1 AS test")))
        (format t "Result: ~A~%~%" result))

      ;; Query database encoding
      (format t "Database Encoding: ~A~%" (postmodern:query "SELECT pg_encoding_to_char(encoding) FROM pg_database WHERE datname = current_database()"))
      (format t "Server Encoding: ~A~%" (postmodern:query "SHOW server_encoding"))
      (format t "Client Encoding: ~A~%" (postmodern:query "SHOW client_encoding"))

      (format t "~%All tests passed!~%")

      ;; Disconnect
      (postmodern:disconnect *db*)
      (format t "Disconnected.~%"))

  (error (e)
    (format t "ERROR: ~A~%" e)
    (format t "Type: ~A~%" (type-of e))
    (when *db*
      (postmodern:disconnect *db*))))

(uiop:quit 0)
