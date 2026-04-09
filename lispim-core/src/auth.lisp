;;;; auth.lisp - 用户认证模块
;;;;
;;;; 负责用户认证、Token 管理、会话管理

(in-package :lispim-core)

;;;; 依赖声明

(eval-when (:compile-toplevel :load-toplevel :execute)
  (ql:quickload '(:ironclad :bordeaux-threads :uuid :cl-json :postmodern)))

;;;; 类型定义

(deftype auth-token ()
  'string)

(deftype session-id ()
  'string)

;;;; 会话结构

(defstruct user-session
  "用户会话"
  (session-id "" :type session-id)
  (user-id "" :type string)
  (username "" :type string)
  (created-at (get-universal-time) :type integer)
  (expires-at 0 :type integer)
  (last-active (get-universal-time) :type integer)
  (ip-address nil :type (or null string))
  (user-agent nil :type (or null string))
  (metadata (make-hash-table :test 'equal) :type hash-table))

;;;; 认证状态

(defstruct auth-result
  "认证结果"
  (success nil :type boolean)
  (user-id nil :type (or null string))
  (username nil :type (or null string))
  (token nil :type (or null auth-token))
  (error nil :type (or null string)))

;;;; 全局变量

(defparameter *session-timeout* (* 24 60 60)
  "会话超时时间 (秒)，默认 24 小时")

(defparameter *max-failed-attempts* 5
  "最大失败尝试次数")

(defparameter *lockout-duration* (* 15 60)
  "锁定持续时间 (秒)，默认 15 分钟")

;;;; 验证码存储（使用 Redis）

(defparameter *verification-code-length* 6
  "验证码长度")

(defparameter *verification-code-expiry* (* 5 60)
  "验证码过期时间 (秒)，默认 5 分钟")

(defparameter *verification-code-ratelimit-interval* 60
  "发送验证码间隔 (秒)，默认 1 分钟")

;;;; 密码哈希

(defun hash-password (password &key (salt nil))
  "使用 PBKDF2+SHA256 哈希密码"
  (declare (type string password))
  (log-debug "Hash-password: password length=~A" (length password))
  (let* ((salt (or salt (ironclad:make-random-salt)))
         (password-bytes (babel:string-to-octets password :encoding :utf-8)))
    ;; pbkdf2-hash-password returns two values: key (hash) and salt-bytes
    (multiple-value-bind (key salt-bytes)
        (ironclad:pbkdf2-hash-password password-bytes
                                       :salt salt
                                       :digest 'ironclad:sha256
                                       :iterations 10000)
      ;; Convert hash and salt to hex strings for storage
      (values (with-output-to-string (s)
                (loop for b across key do (format s "~2,'0x" b)))
              (with-output-to-string (s)
                (loop for b across salt-bytes do (format s "~2,'0x" b)))))))

(defun verify-password (password stored-hash salt)
  "验证密码"
  (let ((salt-bytes (make-array (/ (length salt) 2) :element-type '(unsigned-byte 8))))
    (loop for i from 0 below (/ (length salt) 2) do
      (setf (aref salt-bytes i)
            (parse-integer salt :start (* i 2) :end (+ (* i 2) 2) :radix 16)))
    (multiple-value-bind (computed-hash computed-salt)
        (hash-password password :salt salt-bytes)
      (declare (ignore computed-salt))
      (string-equal computed-hash stored-hash))))

;;;; 用户认证

(defun authenticate (username password &key (ip-address nil))
  "用户认证"
  (declare (type string username password))
  (log-info "authenticate called: username=~A, password length=~A, ip-address=~A"
            username (length password) ip-address)

  ;; Check IP lock
  (when ip-address
    (when (ip-locked-p ip-address)
      (return-from authenticate
        (make-auth-result
         :success nil
         :error "Account temporarily locked due to too many failed attempts"))))

  ;; Debug logging
  (log-debug "Authenticate: username=~A" username)

  ;; Find user with error handling
  (let (user)
    (log-info "Looking up user: ~A" username)
    (handler-case
        (setf user (get-user-by-username username))
      (simple-error (c)
        (log-error "Simple error finding user: ~A" c)
        (return-from authenticate
          (make-auth-result
           :success nil
           :error (format nil "Database error: ~A" c))))
      (error (c)
        (log-error "Error finding user: ~A" c)
        (return-from authenticate
          (make-auth-result
           :success nil
           :error (format nil "Internal error: ~A" c)))))
    (log-info "User lookup result: ~A" user)
    (unless user
      (log-debug "User not found: ~a" username)
      (record-failed-attempt ip-address)
      (return-from authenticate
        (make-auth-result
         :success nil
         :error "Invalid username or password")))

    ;; Verify password
    (let ((stored-hash (getf user :password-hash))
          (salt (getf user :password-salt)))
      (log-info "Verifying password for ~a - hash: ~a (len: ~a), salt: ~a (len: ~a)"
                username stored-hash (if stored-hash (length stored-hash) 0)
                salt (if salt (length salt) 0))
      (log-info "Input password: ~a (len: ~a)" password (length password))
      (let ((result (verify-password password stored-hash salt)))
        (log-info "Verify result: ~a (type: ~a)" result (type-of result))
        (unless result
          (record-failed-attempt ip-address)
          (return-from authenticate
            (make-auth-result
             :success nil
             :error "Invalid username or password"))))
      (log-info "Password verified, checking account status")

      ;; Check account status
      (let ((status (getf user :status)))
        (unless (or (eq status :active) (string= status "active"))
          (return-from authenticate
            (make-auth-result
             :success nil
             :error (format nil "Account is ~a" status)))))
      (log-info "Account status OK, generating token")

      ;; Generate Token
      (let ((user-id-val (getf user :user-id))
            (username-val (getf user :username)))
        (log-info "Creating session: user-id-val=~A (type: ~A), username-val=~A"
                  user-id-val (type-of user-id-val) username-val)
        (let* ((session-id (create-session (princ-to-string user-id-val)
                                        username-val
                                        :ip-address ip-address))
               (token session-id))
          (make-auth-result
           :success t
           :user-id user-id-val
           :username username-val
           :token token))))))

(defun authenticate-token (token)
  "使用 Token 认证"
  (declare (type auth-token token))
  ;; Get session from storage
  (let ((session (get-session token)))
    (unless session
      (return-from authenticate-token
        (make-auth-result
         :success nil
         :error "Invalid or expired token")))

    ;; 检查过期
    (let ((expires-at (getf session :expires-at)))
      (when (and expires-at (< (get-universal-time) expires-at))
        ;; 更新最后活跃时间
        (update-session-last-active token)
        (return-from authenticate-token
          (make-auth-result
           :success t
           :user-id (getf session :user-id)
           :username (getf session :username)))))

    ;; 会话过期，清理
    (invalidate-session token)
    (make-auth-result
     :success nil
     :error "Token expired")))

(defun verify-token (token)
  "Verify token and return user-id (or nil if invalid)"
  (declare (type auth-token token))
  (let ((result (authenticate-token token)))
    (if (auth-result-success result)
        (auth-result-user-id result)
        nil)))

;;;; 会话管理

;; Note: create-session, get-session, invalidate-session in this file
;; wrap the storage layer implementations with additional auth logic

(defun create-session (user-id username &key (ip-address nil) (user-agent nil))
  "创建新会话"
  (declare (type string user-id username))
  (log-info "create-session: user-id=~A (type: ~A), username=~A" user-id (type-of user-id) username)
  (let* ((session-id (format nil "~a" (uuid:make-v4-uuid)))
         (expires-at (+ (get-universal-time) *session-timeout*)))
    ;; Store in database and Redis cache using storage layer function
    (storage-create-session session-id user-id username
                            :ip-address ip-address
                            :user-agent user-agent
                            :expires-at expires-at)
    (log-info "Created session ~a for user ~a" session-id username)
    session-id))

(defun get-session (session-id)
  "获取会话"
  (declare (type session-id session-id))
  ;; Get from storage (uses PostgreSQL + Redis cache)
  (storage-get-session session-id))

(defun invalidate-session (session-id)
  "使会话失效"
  (declare (type session-id session-id))
  (storage-invalidate-session session-id)
  (log-info "Invalidated session ~a" session-id)
  nil)

(defun invalidate-all-user-sessions (user-id)
  "使所有用户会话失效"
  (declare (type string user-id))
  (storage-invalidate-all-user-sessions user-id)
  (log-info "Invalidated all sessions for user ~a" user-id))

(defun get-user-sessions (user-id)
  "获取用户所有会话"
  (declare (type string user-id))
  (storage-get-user-sessions user-id))

(defun refresh-session (session-id)
  "刷新会话有效期"
  (declare (type session-id session-id))
  (let ((new-expires (+ (get-universal-time) *session-timeout*)))
    (storage-refresh-session session-id :expires-at new-expires)
    new-expires))

;;;; Token 管理

(defun invalidate-token (token)
  "使 Token 失效"
  (declare (type auth-token token))
  (invalidate-session token)
  nil)

;;;; Storage wrappers - 实际存储层操作

(defun storage-create-session (session-id user-id username &key (ip-address nil) (user-agent nil) (expires-at nil))
  "Wrapper for storage layer create-session"
  (declare (type string session-id user-id username))
  (log-info "storage-create-session: session-id=~A, user-id=~A (type: ~A), username=~A"
            session-id user-id (type-of user-id) username)
  (let ((expires (or expires-at (+ (get-universal-time) *session-timeout*))))
    ;; Store in database
    (ensure-pg-connected)
    (let ((unix-time (storage-universal-to-unix expires))
          (user-id-int (handler-case (parse-integer user-id)
                         (error (c)
                           (log-error "Failed to parse user-id '~A': ~A" user-id c)
                           0))))
      (log-info "Parsed user-id: ~A -> ~A" user-id user-id-int)
      (postmodern:query
       "INSERT INTO user_sessions (session_id, user_id, username, ip_address, user_agent, expires_at)
        VALUES ($1, $2, $3, NULLIF($4, '')::inet, NULLIF($5, ''), to_timestamp($6::bigint))"
       session-id user-id-int username (or ip-address "") (or user-agent "") unix-time))
    ;; Cache in Redis
    (when *redis-connected*
      (redis-set "session" session-id (cl-json:encode-json-to-string
                                       (list :sessionId session-id
                                             :userId user-id
                                             :username username
                                             :expiresAt expires))
                 :expires (- expires (get-universal-time))))
    (log-info "Created session: ~a for user ~a" session-id user-id)
    session-id))

(defun storage-get-session (session-id)
  "Wrapper for storage layer get-session"
  (declare (type string session-id))
  (let (result data cached)
    ;; Try Redis cache first
    (when (and *redis-connected*)
      (setq cached (redis-get "session" session-id))
      (when cached
        (setq data (cl-json:decode-json-from-string cached))
        ;; Handle different JSON decoding results
        (typecase data
          (list
           ;; Check if it's a flat plist with string keys
           ;; Format: ("sessionid" "xxx" "userid" "1" "username" "admin" ...)
           (cond
             ((stringp (car data))
              (setq result nil)
              (loop for (key val) on data by #'cddr do
                (cond
                  ((string= key "sessionid") (push :session-id result) (push val result))
                  ((string= key "userid") (push :user-id result) (push val result))
                  ((string= key "username") (push :username result) (push val result))
                  ((string= key "expiresat") (push :expires-at result) (push val result))
                  ((string= key "ipaddress") (push :ip-address result) (push val result))
                  ((string= key "useragent") (push :user-agent result) (push val result))))
              (return-from storage-get-session (nreverse result)))
             ((and (listp data) (listp (car data)))
              (setq result nil)
              (loop for item in data do
                (cond
                  ((string= (car item) "sessionId") (push :session-id result) (push (cdr item) result))
                  ((string= (car item) "userId") (push :user-id result) (push (cdr item) result))
                  ((string= (car item) "username") (push :username result) (push (cdr item) result))
                  ((string= (car item) "expiresAt") (push :expires-at result) (push (cdr item) result))
                  ((string= (car item) "ipAddress") (push :ip-address result) (push (cdr item) result))
                  ((string= (car item) "userAgent") (push :user-agent result) (push (cdr item) result))))
              (return-from storage-get-session (nreverse result)))
             (t
              (return-from storage-get-session data))))
          (hash-table
           ;; Convert hash-table to plist
           (setq result nil)
           (maphash (lambda (key value)
                      (cond
                        ((string= key "sessionId") (push :session-id result) (push value result))
                        ((string= key "userId") (push :user-id result) (push value result))
                        ((string= key "username") (push :username result) (push value result))
                        ((string= key "expiresAt") (push :expires-at result) (push value result))
                        ((string= key "ipAddress") (push :ip-address result) (push value result))
                        ((string= key "userAgent") (push :user-agent result) (push value result))))
                    data)
           (return-from storage-get-session result)))
          (otherwise
           (log-error "Unknown data type from Redis: ~A" (type-of data)))))
    ;; Fallback to PostgreSQL
    (ensure-pg-connected)
    (let ((pg-result (postmodern:query
                      "SELECT * FROM user_sessions WHERE session_id = $1 AND expires_at > NOW()"
                      session-id :alists)))
      (when pg-result
        (let ((row (car pg-result)))
          (flet ((get-val (name)
                   (let ((cell (find name row :key #'car :test #'string=)))
                     (when cell (cdr cell)))))
            (setq result (list :session-id (get-val "SESSION-ID")
                               :user-id (write-to-string (get-val "USER-ID"))
                               :username (get-val "USERNAME")
                               :ip-address (get-val "IP-ADDRESS")
                               :user-agent (get-val "USER-AGENT")
                               :created-at (get-val "CREATED-AT")
                               :expires-at (get-val "EXPIRES-AT")
                               :last-active (get-val "LAST-ACTIVE")
                               :metadata (get-val "METADATA")))))))
    result))

(defun storage-invalidate-session (session-id)
  "Wrapper for storage layer invalidate-session"
  (declare (type string session-id))
  (ensure-pg-connected)
  (postmodern:query "DELETE FROM user_sessions WHERE session_id = $1" session-id)
  ;; Remove from Redis
  (when *redis-connected*
    (redis-del "session" session-id))
  (log-info "Invalidated session: ~a" session-id))

(defun storage-invalidate-all-user-sessions (user-id)
  "Wrapper for storage layer invalidate-all-user-sessions"
  (declare (type string user-id))
  (ensure-pg-connected)
  (postmodern:query "DELETE FROM user_sessions WHERE user_id = $1" user-id)
  (log-info "Invalidated all sessions for user: ~a" user-id))

(defun storage-get-user-sessions (user-id)
  "Wrapper for storage layer get-user-sessions"
  (declare (type string user-id))
  (ensure-pg-connected)
  (let ((result (postmodern:query
                 "SELECT * FROM user_sessions WHERE user_id = $1 AND expires_at > NOW()"
                 user-id)))
    (when result
      (loop for row in result
            collect (list :session-id (elt row 0)
                          :user-id (elt row 1)
                          :username (elt row 2)
                          :ip-address (elt row 3)
                          :user-agent (elt row 4)
                          :created-at (elt row 5)
                          :expires-at (elt row 6)
                          :last-active (elt row 7)
                          :metadata (elt row 8)))))
  nil)

(defun storage-refresh-session (session-id &key (expires-at nil))
  "Wrapper for storage layer refresh-session"
  (declare (type string session-id))
  (ensure-pg-connected)
  (let ((new-expires (or expires-at (+ (get-universal-time) *session-timeout*))))
    (postmodern:query
     "UPDATE user_sessions SET expires_at = to_timestamp($2::bigint) WHERE session_id = $1"
     session-id (storage-universal-to-unix new-expires))
    ;; Update Redis TTL
    (when *redis-connected*
      (let ((cached (redis-get "session" session-id)))
        (when cached
          (let* ((data (cl-json:decode-json-from-string cached))
                 (session-id-val (cdr (assoc "sessionId" data)))
                 (user-id-val (cdr (assoc "userId" data)))
                 (username-val (cdr (assoc "username" data))))
            (redis-set "session" session-id
                       (cl-json:encode-json-to-string
                        (list :sessionId session-id-val
                              :userId user-id-val
                              :username username-val
                              :expiresAt new-expires))
                       :expires (- new-expires (get-universal-time)))))))
    new-expires))

(defun storage-update-session-last-active (session-id)
  "Wrapper for storage layer update-session-last-active"
  (declare (type string session-id))
  (ensure-pg-connected)
  (postmodern:query "UPDATE user_sessions SET last_active = NOW() WHERE session_id = $1" session-id))

;;;; Account lock management

(defun ip-locked-p (ip-address)
  "Check if IP is locked"
  (declare (type string ip-address))
  (let ((key (format nil "ip_lock:~a" ip-address)))
    (when *redis-connected*
      (redis:red-exists key))))

(defun record-failed-attempt (ip-address)
  "Record failed login attempt"
  (when ip-address
    (let ((key (format nil "failed_attempts:~a" ip-address)))
      (when *redis-connected*
        (let ((count (redis:red-incr key)))
          (when (= count 1)
            (redis:red-expire key *lockout-duration*)))))))

(defun cleanup-failed-attempts (ip-address)
  "Clear failed attempts for IP"
  (when ip-address
    (let ((key (format nil "failed_attempts:~a" ip-address)))
      (when *redis-connected*
        (redis:red-del key)))))

;;;; Initialization

(defun init-auth ()
  "Initialize auth module"
  (log-info "Initializing auth module...")
  ;; Start session cleanup thread
  (bordeaux-threads:make-thread
   (lambda ()
     (loop do
       (sleep (* 60 60)) ;; Every hour
       (cleanup-expired-sessions)))
   :name "session-cleanup-thread")
  (log-info "Auth module initialized"))

;;;; Cleanup

(defun cleanup-expired-sessions ()
  "Clean up expired sessions"
  (ensure-pg-connected)
  (postmodern:query "DELETE FROM user_sessions WHERE expires_at < NOW()")
  (log-info "Cleaned up expired sessions"))

;;;; Verification code

(defun generate-verification-code ()
  "Generate verification code - using alexandria:random-elt"
  (declare (optimize (speed 3) (safety 1)))
  (let ((digits "0123456789"))
    (with-output-to-string (s)
      (dotimes (i *verification-code-length*)
        (write-char (alexandria:random-elt digits) s)))))

(defun send-verification-code (method target)
  "Send verification code - using case for method dispatch"
  (declare (type (member :phone :email) method)
           (type string target))
  (let* ((code (generate-verification-code))
         (method-str (case method (:phone "phone") (:email "email")))
         (key (format nil "verify_code:~a:~a" method-str target)))
    ;; Store in Redis
    (when *redis-connected*
      (redis-set "verify_code" key code :expires *verification-code-expiry*))
    ;; TODO: Send actual SMS/email
    (log-info "Verification code for ~a: ~a" target code)
    t))

(defun verify-verification-code (method target code)
  "Verify verification code - using case for method dispatch"
  (declare (type (member :phone :email) method)
           (type string target code))
  (let* ((method-str (case method (:phone "phone") (:email "email")))
         (key (format nil "verify_code:~a:~a" method-str target)))
    (when *redis-connected*
      (let ((stored (redis-get "verify_code" key)))
        (when stored
          (prog1
              (string= stored code)
            (redis-del "verify_code" key)))))))

(defun send-phone-code (phone)
  "Send phone verification code"
  (declare (type string phone))
  (send-verification-code :phone phone))

(defun send-email-code (email)
  "Send email verification code"
  (declare (type string email))
  (send-verification-code :email email))

;;;; User registration

(defun register-user (username password email &key (invitation-code nil) phone (display-name nil))
  "Register user with username/password"
  (declare (type string username password email))
  (declare (ignore invitation-code))

  ;; Log debug info
  (log-error "register-user called: username=~A, email=~A, phone=~A, display-name=~A"
             username email phone display-name)

  ;; Check if username exists
  (let ((existing (get-user-by-username username)))
    (when existing
      (log-error "Username already exists: ~A" username)
      (return-from register-user
        (values nil "Username already exists"))))

  (log-error "Username ~A is available, hashing password..." username)

  ;; Hash password
  (multiple-value-bind (hash salt)
      (hash-password password)
    (log-error "Password hashed: hash=~A... salt=~A..." (subseq hash 0 (min 8 (length hash)))
               (when (> (length salt) 0) (subseq salt 0 (min 8 (length salt)))))
    ;; Create user
    (let ((user-id (generate-user-id)))
      (log-error "Creating user with id=~A..." user-id)
      (create-user user-id username email hash
                   :password-salt salt
                   :phone (or phone "")
                   :display-name (or display-name username))
      (log-error "User created, now creating system admin conversation...")
      ;; Create conversation with system admin
      (create-system-admin-conversation-for-user user-id)
      (log-error "Registration complete for user ~A" user-id)
      (values user-id nil))))

(defun register-by-phone (phone password code &key (invitation-code nil) (display-name nil))
  "Register user with phone"
  (declare (type string phone password code))
  (declare (ignore invitation-code))

  ;; Verify code
  (unless (verify-verification-code :phone phone code)
    (return-from register-by-phone
      (values nil nil nil "Invalid verification code")))

  ;; Hash password
  (multiple-value-bind (hash salt)
      (hash-password password)
    (let ((user-id (generate-user-id))
          (username (format nil "user_~a" phone)))
      (create-user user-id username "" hash :password-salt salt :phone phone :display-name (or display-name username))
      ;; Create conversation with system admin
      (create-system-admin-conversation-for-user user-id)
      ;; Generate token
      (let ((token (generate-token)))
        (store-session user-id username token)
        (values t user-id token nil)))))

(defun register-by-email (email password code &key (invitation-code nil) (display-name nil))
  "Register user with email"
  (declare (type string email password code))
  (declare (ignore invitation-code))

  ;; Verify code
  (unless (verify-verification-code :email email code)
    (return-from register-by-email
      (values nil nil nil "Invalid verification code")))

  ;; Hash password
  (multiple-value-bind (hash salt)
      (hash-password password)
    (let ((user-id (generate-user-id))
          (username (format nil "user_~a" email)))
      (create-user user-id username email hash :password-salt salt :display-name (or display-name username))
      ;; Create conversation with system admin
      (create-system-admin-conversation-for-user user-id)
      ;; Generate token
      (let ((token (generate-token)))
        (store-session user-id username token)
        (values t user-id token nil)))))

;;;; WeChat OAuth

(defparameter *wechat-app-id* nil
  "WeChat app ID")

(defparameter *wechat-app-secret* nil
  "WeChat app secret")

(defun wechat-oauth-login (code)
  "Login via WeChat OAuth"
  (declare (type string code))
  ;; TODO: Implement WeChat OAuth
  (declare (ignore code))
  (values nil "WeChat login not implemented"))

(defun login-by-wechat (wechat-openid)
  "Login or register with WeChat"
  (declare (type string wechat-openid))
  ;; TODO: Implement WeChat login
  (declare (ignore wechat-openid))
  (values nil "WeChat login not implemented"))

;;;; Anonymous Registration

(defparameter *anonymous-registration-enabled* t
  "Enable anonymous registration (no phone/email required)")

(defparameter *anonymous-registration-captcha* nil
  "Require captcha for anonymous registration (optional anti-abuse)")

(defun register-anonymous-user (&key (display-name nil) (captcha-response nil) invitation-code)
  "Register anonymous user without phone/email
   Returns: (values success user-id token error-message)

   Features:
   - No phone number or email required
   - Generates random user ID (Snowflake) and username
   - Optional captcha support for anti-abuse
   - Optional invitation code for private deployments

   Reference: Session, Threema anonymous registration"
  (declare (type (or null string) display-name captcha-response invitation-code))

  ;; Check if anonymous registration is enabled
  (unless *anonymous-registration-enabled*
    (return-from register-anonymous-user
      (values nil nil nil "Anonymous registration is disabled")))

  ;; Verify captcha if required (optional anti-abuse measure)
  (when (and *anonymous-registration-captcha* captcha-response)
    ;; TODO: Implement captcha verification
    ;; For now, we just log it
    (log-debug "Captcha verification requested: ~A" captcha-response))

  ;; Verify invitation code if required (for private deployments)
  (when invitation-code
    ;; TODO: Implement invitation code verification
    (log-debug "Invitation code provided: ~A" invitation-code))

  ;; Generate random user ID and username
  (let* ((user-id (generate-user-id))
         ;; Generate random username: anon_XXXXXXXX (8 random hex chars)
         (random-suffix (with-output-to-string (s)
                          (dotimes (i 8)
                            (format s "~X" (random 16)))))
         (username (format nil "anon_~A" random-suffix))
         ;; Generate random password (user can set later)
         (random-password (uuid:make-v4-uuid))
         (display-name-val (or display-name username)))

    (log-info "Registering anonymous user: ~A (display-name: ~A)" username display-name-val)

    ;; Hash password (even though it's random, we store it for consistency)
    (multiple-value-bind (hash salt)
        (hash-password random-password)
      ;; Create user with minimal metadata
      (create-user user-id username "" hash
                   :password-salt salt
                   :phone ""              ; No phone
                   :display-name display-name-val
                   :is-anonymous t)       ; Mark as anonymous user

      ;; Create conversation with system admin
      (create-system-admin-conversation-for-user user-id)

      ;; Generate session token (convert user-id to string for create-session)
      (let ((token (create-session (princ-to-string user-id) username)))
        (log-info "Anonymous user registered: ~A -> ~A" user-id username)
        (values t user-id token nil)))))

;;;; Export

(export '(authenticate
          authenticate-token
          verify-token
          create-session
          get-session
          invalidate-session
          invalidate-all-user-sessions
          refresh-session
          get-user-sessions
          hash-password
          verify-password
          cleanup-expired-sessions
          init-auth
          *session-timeout*
          *max-failed-attempts*
          *lockout-duration*
          invalidate-token

          ;; Verification code
          send-verification-code
          verify-verification-code
          generate-verification-code
          cleanup-expired-codes
          *verification-code-expiry*
          *verification-code-length*
          *verification-code-ratelimit-interval*
          send-phone-code
          send-email-code

          ;; Registration
          register-user
          register-by-phone
          register-by-email
          register-anonymous-user

          ;; Anonymous registration options
          *anonymous-registration-enabled*
          *anonymous-registration-captcha*

          ;; WeChat
          wechat-oauth-login
          login-by-wechat
          *wechat-app-id*
          *wechat-app-secret*)
        :lispim-core)
