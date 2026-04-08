;;;; auth-manager.lisp - Authentication Manager for LispIM Client

(in-package :lispim-client)

;; ============================================================================
;; Auth Manager class
;; ============================================================================

(defclass auth-manager ()
  ((api-client :accessor auth-manager-api-client
               :initarg :api-client
               :documentation "API client for making auth calls")
   (current-user :accessor auth-manager-current-user
                 :initform nil
                 :documentation "Current authenticated user info")
   (token :accessor auth-manager-token
          :initform nil
          :documentation "Current auth token")
   (token-expires-at :accessor auth-manager-token-expires-at
                     :initform nil
                     :documentation "Token expiration time"))
  (:documentation "Authentication manager for handling login/logout"))

(defun make-auth-manager (&key (api-client))
  "Create a new auth manager instance"
  (make-instance 'auth-manager
                 :api-client api-client))

;; ============================================================================
;; Authentication functions
;; ============================================================================

(defun auth-manager-login (auth-manager username password)
  "Login with username and password"
  (multiple-value-bind (success response)
      (api-client-login (auth-manager-api-client auth-manager) username password)
    (if success
        (let* ((response-data (json-to-plist response))
               (token (getf response-data :token))
               (user (getf response-data :user)))
          (when token
            (setf (auth-manager-token auth-manager) token
                  (auth-manager-api-client (auth-manager-api-client auth-manager)) token)
            (when user
              (setf (auth-manager-current-user auth-manager) user)))
          (values t response-data))
        (values nil response))))

(defun auth-manager-logout (auth-manager)
  "Logout current user"
  (multiple-value-bind (success response)
      (api-client-logout (auth-manager-api-client auth-manager))
    (when success
      (setf (auth-manager-token auth-manager) nil
            (auth-manager-current-user auth-manager) nil
            (auth-manager-api-client (auth-manager-api-client auth-manager)) nil))
    (values success response)))

(defun auth-manager-is-authenticated-p (auth-manager)
  "Check if currently authenticated"
  (and (auth-manager-token auth-manager)
       (auth-manager-current-user auth-manager)))

(defun auth-manager-get-token (auth-manager)
  "Get current auth token"
  (auth-manager-token auth-manager))

(defun auth-manager-get-current-user (auth-manager)
  "Get current user info"
  (auth-manager-current-user auth-manager))

(defun auth-manager-refresh-token-if-needed (auth-manager)
  "Refresh token if expired - placeholder for future token refresh logic"
  ;; For now, tokens don't expire in this implementation
  ;; Future: check expiration and call refresh endpoint
  (declare (ignore auth-manager))
  nil)
