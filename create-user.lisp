;;;; create-user.lisp - Update test user password

(ql:quickload :postmodern)
(ql:quickload :ironclad)
(ql:quickload :babel)

(postmodern:connect-toplevel "lispim" "lispim" "Clsper03" "127.0.0.1" :port 5432 :use-ssl :no)

(format t "Connected~%")

;; Generate password hash using PBKDF2+SHA256 (same as auth.lisp)
(defun hash-password (password salt)
  (let* ((password-bytes (babel:string-to-octets password :encoding :utf-8))
         (salt-bytes (babel:string-to-octets salt :encoding :utf-8))
         (key (ironclad:pbkdf2-hash-password password-bytes
                                             :salt salt-bytes
                                             :iterations 10000
                                             :digest :sha256)))
    ;; Convert hash to hex string
    (with-output-to-string (s)
      (loop for b across key do (format s "~2,'0x" b)))))

;; Update existing admin user
(let* ((salt "testsalt123")
       (hash (hash-password "admin123" salt)))
  (postmodern:execute "UPDATE users SET password_hash = $1, password_salt = $2 WHERE username = 'admin'"
                      hash salt)
  (format t "User 'admin' password updated with salt '~a'~%" salt))

(quit)
