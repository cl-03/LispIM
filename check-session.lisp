;;;; check-session.lisp - Check session in database

(ql:quickload :postmodern)

(postmodern:connect-toplevel "lispim" "lispim" "Clsper03" "127.0.0.1" :port 5432 :use-ssl :no)

(format t "Connected~%")

;; Check sessions
(let ((sessions (postmodern:query "SELECT session_id, user_id, username, expires_at FROM user_sessions ORDER BY created_at DESC LIMIT 5")))
  (format t "Recent sessions:~%")
  (dolist (session sessions)
    (format t "  ~a~%" session)))

(quit)
