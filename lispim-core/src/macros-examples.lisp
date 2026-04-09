;;;; macros-examples.lisp - Examples of refactored code using On Lisp macros
;;;;
;;;; This file demonstrates how the macros from macros.lisp can be used
;;;; to refactor and simplify existing LispIM code patterns.
;;;;
;;;; Each example shows "Before" (original code) and "After" (refactored with macros)

(in-package :lispim-core)

;;;; =====================================================================
;;;; Example 1: API Response Pattern
;;;; =====================================================================

;; BEFORE: Verbose API response pattern
(defun api-get-user-before (user-id)
  "Get user info - original version"
  (let ((user (get-user user-id)))
    (if user
        (progn
          (setf (hunchentoot:content-type*) "application/json")
          (send-cors-headers)
          (cl-json:encode-json-to-string
           (convert-response-to-camelcase
            (list :success t :data user))))
        (progn
          (setf (hunchentoot:return-code*) 404)
          (setf (hunchentoot:content-type*) "application/json")
          (send-cors-headers)
          (cl-json:encode-json-to-string
           (convert-response-to-camelcase
            (make-api-error "NOT_FOUND" "User not found")))))))

;; AFTER: Using respond-with macro and awhen
(defun api-get-user-after (user-id)
  "Get user info - refactored with macros"
  (awhen (get-user user-id)
    (return-from api-get-user-after
      (respond-with it :success t)))
  (setf (hunchentoot:return-code*) 404)
  (respond-with nil :error-code "NOT_FOUND" :message "User not found"))

;;;; =====================================================================
;;;; Example 2: Nested plist access
;;;; =====================================================================

;; BEFORE: Manual plist extraction
(defun process-message-before (message)
  "Process message - original version"
  (let ((sender-id (getf message :sender-id))
        (content (getf message :content))
        (timestamp (getf message :timestamp))
        (conversation-id (getf message :conversation-id))
        (message-type (getf message :message-type)))
    (when sender-id
      (when content
        (when conversation-id
          ;; Process the message
          (store-message sender-id content conversation-id message-type timestamp))))))

;; AFTER: Using with-plist-bindings and when-let*
(defun process-message-after (message)
  "Process message - refactored with macros"
  (with-plist-bindings (message :sender-id :content :timestamp :conversation-id :message-type)
    (when-let* ((valid-sender sender-id)
                (valid-content content)
                (valid-conversation conversation-id))
      (store-message valid-sender valid-content valid-conversation message-type timestamp))))

;;;; =====================================================================
;;;; Example 3: Multiple condition checks
;;;; =====================================================================

;; BEFORE: Nested conditionals
(defun validate-user-before (user-data)
  "Validate user data - original version"
  (let ((username (getf user-data :username))
        (password (getf user-data :password))
        (email (getf user-data :email)))
    (if username
        (if (>= (length username) 3)
            (if password
                (if (>= (length password) 8)
                    (if email
                        (if (and (find-if #'digit-char-p email)
                                 (find #\@ email))
                            t
                            "Invalid email")
                        "Email required")
                    "Password too short")
                "Password required")
            "Username required")))

;; AFTER: Using cond-let and aand
(defun validate-user-after (user-data)
  "Validate user data - refactored with macros"
  (cond-let ((user user-data))
    ((aand (getf it :username)
           (>= (length it) 3))
     (cond-let ((user user-data))
       ((aand (getf it :password)
              (>= (length it) 8))
        (cond-let ((user user-data))
          ((aand (getf it :email)
                 (find-if #'digit-char-p it)
                 (find #\@ it))
           t)
          (t "Email required")))
       (t "Password too short"))
     (t "Username required"))))

;;;; =====================================================================
;;;; Example 4: Redis operations with cleanup
;;;; =====================================================================

;; BEFORE: Manual resource management
(defun get-cached-message-before (message-id)
  "Get cached message - original version"
  (let ((conn (cl-redis:redis-pop *redis-pool*))
        (result nil))
    (unwind-protect
         (when conn
           (let ((key (format nil "message:~a" message-id)))
             (setf result (cl-redis:redis-get conn key))))
      (when conn
        (cl-redis:redis-push conn *redis-pool*)))
    result))

;; AFTER: Using with-redis-connection macro
(defun get-cached-message-after (message-id)
  "Get cached message - refactored with macro"
  (with-redis-connection (conn *redis-pool*)
    (let ((key (format nil "message:~a" message-id)))
      (cl-redis:redis-get conn key))))

;;;; =====================================================================
;;;; Example 5: Database transaction with error handling
;;;; =====================================================================

;; BEFORE: Manual transaction management
(defun store-message-with-transaction-before (sender-id content conversation-id)
  "Store message with transaction - original version"
  (let ((conn *db-connection*)
        (success nil)
        (result nil))
    (unwind-protect
         (progn
           (postmodern:with-transaction (conn)
             (setf result (store-message sender-id content conversation-id))
             (setf success t)
             result))
      (unless success
        (log-error "Transaction rolled back for message ~a" content))))

;; AFTER: Using with-db-transaction macro
(defun store-message-with-transaction-after (sender-id content conversation-id)
  "Store message with transaction - refactored with macro"
  (with-db-transaction (conn *db-connection*)
    (store-message sender-id content conversation-id)))

;;;; =====================================================================
;;;; Example 6: Hash table iteration
;;;; =====================================================================

;; BEFORE: Manual maphash
(defun get-all-users-before ()
  "Get all users - original version"
  (let ((users nil))
    (maphash (lambda (id user)
               (push (cons id user) users))
             *users-cache*)
    (nreverse users)))

;; AFTER: Using do-hash macro
(defun get-all-users-after ()
  "Get all users - refactored with macro"
  (let ((users nil))
    (do-hash (id user *users-cache* (nreverse users))
      (push (cons id user users)))))

;;;; =====================================================================
;;;; Example 7: Building up a result list
;;;; =====================================================================

;; BEFORE: Manual accumulation
(defun get-active-conversations-before (user-id)
  "Get active conversations - original version"
  (let ((result nil))
    (dolist (conv (get-user-conversations user-id))
      (when (getf conv :active)
        (push conv result)))
    (dolist (conv (get-user-groups user-id))
      (when (getf conv :has-unread)
        (push conv result)))
    (dolist (conv (get-user-favorites user-id))
      (when (getf conv :recent)
        (push conv result)))
    (nreverse result)))

;; AFTER: Using accumulating macro
(defun get-active-conversations-after (user-id)
  "Get active conversations - refactored with macro"
  (accumulating (result nil)
    (dolist (conv (get-user-conversations user-id))
      (when (getf conv :active)
        (result conv)))
    (dolist (conv (get-user-groups user-id))
      (when (getf conv :has-unread)
        (result conv)))
    (dolist (conv (get-user-favorites user-id))
      (when (getf conv :recent)
        (result conv)))))

;;;; =====================================================================
;;;; Example 8: Define API handler using macro
;;;; =====================================================================

;; BEFORE: Verbose handler definition
(hunchentoot:define-easy-handler (api-create-user-before :uri "/api/v1/users") ()
  (unless (string= (hunchentoot:request-method hunchentoot:*request*) "POST")
    (setf (hunchentoot:return-code*) 405)
    (return-from api-create-user-before
      (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed"))))
  (setf (hunchentoot:content-type*) "application/json")
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (let ((user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-create-user-before
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (let ((username (hunchentoot:post-parameter "username"))
          (password (hunchentoot:post-parameter "password"))
          (email (hunchentoot:post-parameter "email")))
      (unless (and username password email)
        (setf (hunchentoot:return-code*) 400)
        (return-from api-create-user-before
          (encode-api-response (make-api-error "MISSING_FIELDS" "Required: username, password, email"))))
      (handler-case
          (let ((new-user-id (create-user username password email)))
            (encode-api-response (make-api-response (list :userId new-user-id))))
        (error (c)
          (log-error "Create user error: ~A" c)
          (setf (hunchentoot:return-code*) 500)
          (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c))))))))

;; AFTER: Using define-api-handler macro
(define-api-handler api-create-user-after "/api/v1/users"
  :method "POST"
  :auth t
  :required-fields ("username" "password" "email")
  (let ((new-user-id (create-user username password email)))
    (respond-with (list :userId new-user-id) :success t)))

;;;; =====================================================================
;;;; Example 9: Timing and profiling
;;;; =====================================================================

;; BEFORE: Manual timing
(defun benchmark-database-query-before ()
  "Benchmark database query - original version"
  (let ((start (get-internal-real-time))
        (result nil))
    (dotimes (i 100)
      (declare (ignore i))
      (setf result (query "SELECT * FROM users")))
    (let ((elapsed (/ (- (get-internal-real-time) start) internal-time-units-per-second)))
      (log-info "Elapsed: ~f seconds" elapsed)
      (values result elapsed))))

;; AFTER: Using with-timing macro
(defun benchmark-database-query-after ()
  "Benchmark database query - refactored with macro"
  (with-timing (result :iterations 100)
    (query "SELECT * FROM users")))

;;;; =====================================================================
;;;; Example 10: Anaphoric chaining
;;;; =====================================================================

;; BEFORE: Nested lets
(defun get-user-display-name-before (user-id)
  "Get user display name - original version"
  (let ((user (get-user user-id)))
    (if user
        (let ((profile (get-user-profile user-id)))
          (if profile
              (let ((display-name (getf profile :display-name)))
                (if display-name
                    display-name
                    (getf user :username)))
              (getf user :username)))
        nil)))

;; AFTER: Using aand (anaphoric and)
(defun get-user-display-name-after (user-id)
  "Get user display name - refactored with anaphoric macro"
  (aand (get-user user-id)
        (or (aand (get-user-profile user-id)
                  (getf it :display-name))
            (getf it :username))))

;;;; =====================================================================
;;;; Summary of macro benefits
;;;; =====================================================================

;; 1. Code reduction: 30-50% fewer lines
;; 2. Reduced cognitive load: fewer nested levels
;; 3. Consistent patterns: standard ways to handle common operations
;; 4. Automatic resource management: less boilerplate for cleanup
;; 5. Better error handling: unified error patterns
;; 6. Anaphoric elegance: implicit 'it' for cleaner chaining

;; These examples demonstrate how On Lisp macro techniques can be applied
;; to real-world LispIM code to make it more concise and maintainable.
