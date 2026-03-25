;;;; test-pg-md5.lisp - Test PostgreSQL with MD5 password encryption

(ql:quickload '(:postmodern))

(in-package :postmodern)

(format t "~%=== PostgreSQL Connection Test (MD5) ===~%~%")

(handler-case
    (progn
      (format t "Connecting with :password-encryption :md5...~%")

      ;; Try with explicit password encryption method
      (connect "lispim" "lispim" "Clsper03" "127.0.0.1"
               :port 5432
               :use-ssl :no
               :password-encryption :md5)

      (format t "SUCCESS!~%"))

  (error (e)
    (format t "ERROR: ~A~%" e)))

(handler-case
    (progn
      (format t "~%Connecting with :password-encryption :scram-sha-256...~%")

      ;; Try with SCRAM-SHA-256
      (connect "lispim" "lispim" "Clsper03" "127.0.0.1"
               :port 5432
               :use-ssl :no
               :password-encryption :scram-sha-256)

      (format t "SUCCESS!~%"))

  (error (e)
    (format t "ERROR: ~A~%" e)))

(uiop:quit 0)
