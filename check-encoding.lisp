;;;; check-encoding.lisp - Check PostgreSQL encoding

(ql:quickload '(:postmodern))

(in-package :postmodern)

(format t "~%========================================~%")
(format t "  PostgreSQL Encoding Check~%")
(format t "========================================~%~%")

;; First, try to connect and query encoding
(format t "Attempting to connect and query encoding...~%~%")

(handler-case
    (progn
      ;; Connect
      (connect "lispim" "lispim" "Clsper03" "127.0.0.1" :port 5432 :use-ssl :no)
      (format t "Connection successful!~%~%")

      ;; Query database encoding
      (let ((encoding (query "SELECT pg_encoding_to_char(encoding) FROM pg_database WHERE datname = current_database()")))
        (format t "Database Encoding: ~A~%" encoding))

      ;; Query server encoding
      (let ((server-encoding (query "SHOW server_encoding")))
        (format t "Server Encoding: ~A~%" server-encoding))

      ;; Query client encoding
      (let ((client-encoding (query "SHOW client_encoding")))
        (format t "Client Encoding: ~A~%" client-encoding))

      ;; Query locale settings
      (let ((lc-collate (query "SHOW lc_collate")))
        (format t "LC_COLLATE: ~A~%" lc-collate))

      (let ((lc-ctype (query "SHOW lc_ctype")))
        (format t "LC_CTYPE: ~A~%" lc-ctype))

      (disconnect *connection*))

  (error (e)
    (format t "ERROR during connection/query: ~A~%" e)
    (format t "Type: ~A~%" (type-of e))
    (format t "~%~%This indicates a server encoding configuration issue.~%")
    (format t "The PostgreSQL server encoding is likely not UTF8.~%")))

(uiop:quit 0)
