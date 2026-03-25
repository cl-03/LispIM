;;;; test-db.lisp - Test database operations

(ql:quickload :postmodern)

(postmodern:connect-toplevel "lispim" "lispim" "Clsper03" "127.0.0.1" :port 5432 :use-ssl :no)

(format t "Connected~%")

;; Check table schema
(let ((result (postmodern:query "SELECT column_name FROM information_schema.columns WHERE table_name = 'users' ORDER BY ordinal_position")))
  (format t "Users table columns:~%")
  (dolist (col result)
    (format t "  - ~a~%" (car col))))

;; Check if any users exist
(let ((result (postmodern:query "SELECT * FROM users LIMIT 1")))
  (format t "First user: ~a~%" result))

(quit)
