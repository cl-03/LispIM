;;;; test-pg-encoding.lisp - Test PostgreSQL connection with encoding

(ql:quickload '(:postmodern :cl-postgres))

(in-package :postmodern)

(format t "~%Testing PostgreSQL with encoding parameter...~%")

;; Check cl-postgres parameters
(format t "Available connect parameters:~%")
(format t "database user password host &key port socket-dsn unix-socket-name use-ssl~%~%")

(handler-case
    (progn
      ;; Try connecting with different options
      (format t "Attempting connection...~%")

      ;; Use :utf8 encoding explicitly
      (let* ((dsn "lispim")
             (user "lispim")
             (password "Clsper03")
             (host "127.0.0.1")
             (port 5432))

        ;; First try basic connection
        (format t "Basic connect...~%")
        (connect dsn user password host :port port :use-ssl :no)

        (format t "Connected!~%")

        ;; Query server encoding
        (let ((result (query "SELECT pg_encoding_to_char(encoding) FROM pg_database WHERE datname = current_database()")))
          (format t "Server encoding: ~A~%" result))))

  (error (e)
    (format t "ERROR: ~A~%" e)
    (format t "Type: ~A~%" (type-of e))))

(uiop:quit 0)
