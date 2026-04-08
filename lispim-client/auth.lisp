;;;; auth.lisp - Client Authentication

(in-package :lispim-client)

;;;; Authentication

(defun login (client username password)
  "Login to server"
  (declare (type client client)
           (type string username password))

  (unless (client-connected client)
    (error 'client-error :message "Not connected"))

  (log-info "Logging in as ~a..." username)

  ;; Send authentication message
  (send-message client
                (make-message :type "AUTH"
                              :username username
                              :password password))

  ;; Wait for response (simplified - would need proper async in production)
  (sleep 0.5)

  ;; Check if we got a token (this would be set by message callback)
  ;; In practice, you'd handle this in the message callback
  t)

(defun register (client username password &key email phone)
  "Register a new account"
  (declare (type client client)
           (type string username password)
           (type (or null string) email)
           (type (or null string) phone))

  (unless (client-connected client)
    (error 'client-error :message "Not connected"))

  (log-info "Registering user ~a..." username)

  (let ((msg (make-message :type "REGISTER"
                           :username username
                           :password password)))
    (when email (setf (getf msg :email) email))
    (when phone (setf (getf msg :phone) phone))
    (send-message client msg))

  t)

(defun logout (client)
  "Logout from server"
  (declare (type client client))

  (when (client-connected client)
    (send-message client (make-message :type "LOGOUT"))
    (log-info "Logged out"))

  t)

(defun authenticate-token (client token)
  "Authenticate with token"
  (declare (type client client)
           (type string token))

  (unless (client-connected client)
    (error 'client-error :message "Not connected"))

  (setf (client-token client) token)

  (send-message client (make-message :type "AUTH_TOKEN"
                                     :token token))

  t)
