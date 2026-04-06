;;;; oauth.lisp - OAuth 2.0 和开放平台 API
;;;;
;;;; 实现 OAuth 2.0 授权流程，支持第三方应用集成
;;;; 提供 WebSocket API 和事件订阅系统

(in-package :lispim-core)

;;;; 依赖声明

(eval-when (:compile-toplevel :load-toplevel :execute)
  (ql:quickload '( :bordeaux-threads :cl-json :uuid :drakma :ironclad :babel)))

;;;; OAuth 2.0 数据结构

(defstruct oauth-app
  "OAuth 应用"
  (id nil :type string)                 ; 应用 ID
  (name nil :type string)               ; 应用名称
  (description nil :type (or null string)) ; 应用描述
  (client-id nil :type string)          ; Client ID
  (client-secret nil :type string)      ; Client Secret
  (redirect-uris nil :type list)        ; 允许的回调 URL 列表
  (scopes nil :type list)               ; 申请的权限范围
  (owner-id nil :type string)           ; 所有者用户 ID
  (created-at nil :type integer)        ; 创建时间
  (active t :type boolean))             ; 是否激活

(defstruct oauth-code
  "授权码"
  (code nil :type string)               ; 授权码
  (client-id nil :type string)          ; Client ID
  (user-id nil :type string)            ; 用户 ID
  (redirect-uri nil :type string)       ; 回调 URL
  (scopes nil :type list)               ; 授权范围
  (expires-at nil :type integer)        ; 过期时间（10 分钟）
  (used nil :type boolean))             ; 是否已使用

(defstruct oauth-token
  "访问令牌"
  (access-token nil :type string)       ; Access Token
  (refresh-token nil :type string)      ; Refresh Token
  (client-id nil :type string)          ; Client ID
  (user-id nil :type string)            ; 用户 ID
  (scopes nil :type list)               ; 授权范围
  (created-at nil :type integer)        ; 创建时间
  (expires-at nil :type integer)        ; 过期时间（2 小时）
  (revoked nil :type boolean))          ; 是否已撤销

(defstruct oauth-event-subscription
  "事件订阅"
  (id nil :type string)                 ; 订阅 ID
  (app-id nil :type string)             ; 应用 ID
  (events nil :type list)               ; 订阅的事件列表
  (webhook-url nil :type (or null string)) ; Webhook URL
  (secret nil :type string)             ; 签名密钥
  (active t :type boolean)              ; 是否激活
  (created-at nil :type integer))       ; 创建时间

;;;; 权限范围定义

(defparameter +oauth-scopes+
  '(:user-read          "读取用户信息")
  "OAuth 权限范围列表")

(defparameter +oauth-scope-user-read+        :user-read         "读取用户基本信息")
(defparameter +oauth-scope-user-email+       :user-email        "读取用户邮箱")
(defparameter +oauth-scope-friends-read+     :friends-read      "读取好友列表")
(defparameter +oauth-scope-groups-read+      :groups-read       "读取群组信息")
(defparameter +oauth-scope-messages-read+    :messages-read     "读取消息历史")
(defparameter +oauth-scope-messages-write+   :messages-write    "发送消息")
(defparameter +oauth-scope-webhook+          :webhook           "管理 Webhook")
(defparameter +oauth-scope-admin+            :admin             "管理员权限")

;;;; 数据库初始化

(defun ensure-oauth-tables-exist ()
  "确保 OAuth 数据表存在"
  (handler-case
      (progn
        ;; OAuth 应用表
        (postmodern:execute
         "CREATE TABLE IF NOT EXISTS lispim_oauth_apps (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            description TEXT,
            client_id TEXT UNIQUE NOT NULL,
            client_secret TEXT NOT NULL,
            redirect_uris JSONB,
            scopes JSONB,
            owner_id TEXT NOT NULL,
            created_at BIGINT,
            active BOOLEAN DEFAULT true
          )")

        ;; 授权码表
        (postmodern:execute
         "CREATE TABLE IF NOT EXISTS lispim_oauth_codes (
            code TEXT PRIMARY KEY,
            client_id TEXT NOT NULL,
            user_id TEXT NOT NULL,
            redirect_uri TEXT,
            scopes JSONB,
            expires_at BIGINT,
            used BOOLEAN DEFAULT false,
            created_at BIGINT DEFAULT (EXTRACT(EPOCH FROM NOW()) * 1000)::BIGINT
          )")

        ;; 访问令牌表
        (postmodern:execute
         "CREATE TABLE IF NOT EXISTS lispim_oauth_tokens (
            access_token TEXT PRIMARY KEY,
            refresh_token TEXT UNIQUE NOT NULL,
            client_id TEXT NOT NULL,
            user_id TEXT NOT NULL,
            scopes JSONB,
            created_at BIGINT,
            expires_at BIGINT,
            revoked BOOLEAN DEFAULT false
          )")

        ;; 事件订阅表
        (postmodern:execute
         "CREATE TABLE IF NOT EXISTS lispim_event_subscriptions (
            id TEXT PRIMARY KEY,
            app_id TEXT NOT NULL,
            events JSONB NOT NULL,
            webhook_url TEXT,
            secret TEXT NOT NULL,
            active BOOLEAN DEFAULT true,
            created_at BIGINT,
            FOREIGN KEY (app_id) REFERENCES lispim_oauth_apps(id) ON DELETE CASCADE
          )")

        ;; 创建索引
        (postmodern:execute
         "CREATE INDEX IF NOT EXISTS idx_oauth_codes_client ON lispim_oauth_codes(client_id)")
        (postmodern:execute
         "CREATE INDEX IF NOT EXISTS idx_oauth_codes_user ON lispim_oauth_codes(user_id)")
        (postmodern:execute
         "CREATE INDEX IF NOT EXISTS idx_oauth_codes_expires ON lispim_oauth_codes(expires_at)")
        (postmodern:execute
         "CREATE INDEX IF NOT EXISTS idx_oauth_tokens_client ON lispim_oauth_tokens(client_id)")
        (postmodern:execute
         "CREATE INDEX IF NOT EXISTS idx_oauth_tokens_user ON lispim_oauth_tokens(user_id)")
        (postmodern:execute
         "CREATE INDEX IF NOT EXISTS idx_oauth_tokens_expires ON lispim_oauth_tokens(expires_at)")
        (postmodern:execute
         "CREATE INDEX IF NOT EXISTS idx_event_subscriptions_app ON lispim_event_subscriptions(app_id)")

        (log-info "OAuth tables initialized"))
    (error (c)
      (log-error "Failed to initialize OAuth tables: ~a" c))))

;;;; OAuth 应用管理

(defun create-oauth-app (name owner-id &key (description nil) (redirect-uris nil) (scopes nil))
  "创建 OAuth 应用"
  (declare (type string name owner-id))

  (let* ((app-id (generate-snowflake-id))
         (client-id (generate-client-id))
         (client-secret (generate-client-secret))
         (app (make-oauth-app
               :id app-id
               :name name
               :description description
               :client-id client-id
               :client-secret client-secret
               :redirect-uris (or redirect-uris '())
               :scopes (or scopes (list :user-read))
               :owner-id owner-id
               :created-at (get-universal-time)
               :active t)))

    ;; 保存到数据库
    (postmodern:execute
     "INSERT INTO lispim_oauth_apps (id, name, description, client_id, client_secret, redirect_uris, scopes, owner_id, created_at)
      VALUES ($1, $2, $3, $4, $5, $6::jsonb, $7::jsonb, $8, $9)"
     app-id name description client-id client-secret
     (cl-json:encode-json-to-string (mapcar #'string redirect-uris))
     (cl-json:encode-json-to-string (mapcar #'string scopes))
     owner-id
     (lispim-universal-to-unix-ms (get-universal-time)))

    (log-info "OAuth app created: ~a (~a)" name app-id)
    app))

(defun get-oauth-app (client-id)
  "获取 OAuth 应用"
  (let ((result (postmodern:query
                 "SELECT id, name, description, client_id, client_secret, redirect_uris, scopes, owner_id, created_at, active
                  FROM lispim_oauth_apps WHERE client_id = $1"
                 client-id :alist)))
    (when result
      (row-to-oauth-app (first result)))))

(defun get-oauth-app-by-id (app-id)
  "通过应用 ID 获取 OAuth 应用"
  (let ((result (postmodern:query
                 "SELECT id, name, description, client_id, client_secret, redirect_uris, scopes, owner_id, created_at, active
                  FROM lispim_oauth_apps WHERE id = $1"
                 app-id :alist)))
    (when result
      (row-to-oauth-app (first result)))))

(defun list-oauth-apps (owner-id)
  "列出用户的所有 OAuth 应用"
  (let ((results (postmodern:query
                  "SELECT id, name, description, client_id, client_secret, redirect_uris, scopes, owner_id, created_at, active
                   FROM lispim_oauth_apps WHERE owner_id = $1 ORDER BY created_at DESC"
                  owner-id :alist)))
    (mapcar #'row-to-oauth-app results)))

(defun update-oauth-app (client-id &key (name nil) (description nil) (redirect-uris nil) (active nil))
  "更新 OAuth 应用"
  (let ((app (get-oauth-app client-id)))
    (unless app
      (error 'oauth-app-not-found :client-id client-id))

    (when name
      (setf (oauth-app-name app) name))
    (when description
      (setf (oauth-app-description app) description))
    (when redirect-uris
      (setf (oauth-app-redirect-uris app) redirect-uris))
    (when (booleanp active)
      (setf (oauth-app-active app) active))

    ;; 保存到数据库
    (postmodern:execute
     "UPDATE lispim_oauth_apps SET name = $2, description = $3, redirect_uris = $4::jsonb, active = $5
      WHERE client_id = $1"
     client-id (oauth-app-name app) (oauth-app-description app)
     (cl-json:encode-json-to-string (mapcar #'string (oauth-app-redirect-uris app)))
     (oauth-app-active app))

    app))

(defun delete-oauth-app (client-id)
  "删除 OAuth 应用"
  (let ((app (get-oauth-app client-id)))
    (unless app
      (error 'oauth-app-not-found :client-id client-id))

    ;; 删除应用（级联删除相关订阅）
    (postmodern:execute "DELETE FROM lispim_oauth_apps WHERE client_id = $1" client-id)

    (log-info "OAuth app deleted: ~a" client-id)
    t))

;;;; 授权码流程

(defun generate-client-id ()
  "生成 Client ID"
  (format nil "client_~a" (generate-snowflake-id)))

(defun generate-client-secret ()
  "生成 Client Secret (32 字节随机十六进制字符串)"
  (format nil "secret_~{~2,'0x~}"
          (loop for i from 1 to 32
                collect (random 256))))

(defun create-authorization-code (client-id user-id redirect-uri scopes)
  "创建授权码"
  (declare (type string client-id user-id redirect-uri)
           (type list scopes))

  (let* ((code (format nil "auth_~a" (uuid:make-v4-uuid)))
         (expires-at (+ (get-universal-time) (* 10 60))) ; 10 分钟后过期
         (auth-code (make-oauth-code
                     :code code
                     :client-id client-id
                     :user-id user-id
                     :redirect-uri redirect-uri
                     :scopes scopes
                     :expires-at expires-at
                     :used nil)))

    ;; 保存到数据库
    (postmodern:execute
     "INSERT INTO lispim_oauth_codes (code, client_id, user_id, redirect_uri, scopes, expires_at)
      VALUES ($1, $2, $3, $4, $5, $6)"
     code client-id user-id redirect-uri
     (cl-json:encode-json-to-string (mapcar #'string scopes))
     (lispim-universal-to-unix-ms expires-at))

    (log-debug "Authorization code created: ~a" code)
    code))

(defun get-authorization-code (code)
  "获取授权码"
  (let ((result (postmodern:query
                 "SELECT code, client_id, user_id, redirect_uri, scopes, expires_at, used
                  FROM lispim_oauth_codes WHERE code = $1"
                 code :alist)))
    (when result
      (row-to-oauth-code (first result)))))

(defun validate-authorization-code (code client-id redirect-uri)
  "验证授权码"
  (let ((auth-code (get-authorization-code code)))
    (unless auth-code
      (return-from validate-authorization-code (values nil "Invalid authorization code")))

    (when (oauth-code-used auth-code)
      (return-from validate-authorization-code (values nil "Authorization code already used")))

    (unless (string= (oauth-code-client-id auth-code) client-id)
      (return-from validate-authorization-code (values nil "Invalid client_id")))

    (unless (string= (oauth-code-redirect-uri auth-code) redirect-uri)
      (return-from validate-authorization-code (values nil "Invalid redirect_uri")))

    (when (> (get-universal-time) (oauth-code-expires-at auth-code))
      ;; 删除过期的授权码
      (postmodern:execute "DELETE FROM lispim_oauth_codes WHERE code = $1" code)
      (return-from validate-authorization-code (values nil "Authorization code expired")))

    ;; 标记为已使用
    (postmodern:execute "UPDATE lispim_oauth_codes SET used = true WHERE code = $1" code)

    (values auth-code nil)))

;;;; 令牌管理

(defun create-oauth-token (client-id user-id scopes)
  "创建访问令牌"
  (declare (type string client-id user-id)
           (type list scopes))

  (let* ((access-token (format nil "access_~{~2,'0x~}" (loop for i from 1 to 32 collect (random 256))))
         (refresh-token (format nil "refresh_~a" (uuid:make-v4-uuid)))
         (now (get-universal-time))
         (expires-at (+ now (* 2 60 60))) ; 2 小时后过期
         (token (make-oauth-token
                 :access-token access-token
                 :refresh-token refresh-token
                 :client-id client-id
                 :user-id user-id
                 :scopes scopes
                 :created-at now
                 :expires-at expires-at
                 :revoked nil)))

    ;; 保存到数据库
    (postmodern:execute
     "INSERT INTO lispim_oauth_tokens (access_token, refresh_token, client_id, user_id, scopes, created_at, expires_at)
      VALUES ($1, $2, $3, $4, $5, $6, $7)"
     access-token refresh-token client-id user-id
     (cl-json:encode-json-to-string (mapcar #'string scopes))
     (lispim-universal-to-unix-ms now)
     (lispim-universal-to-unix-ms expires-at))

    (log-info "OAuth token created for user ~a" user-id)
    token))

(defun get-oauth-token (access-token)
  "获取访问令牌"
  (let ((result (postmodern:query
                 "SELECT access_token, refresh_token, client_id, user_id, scopes, created_at, expires_at, revoked
                  FROM lispim_oauth_tokens WHERE access_token = $1"
                 access-token :alist)))
    (when result
      (row-to-oauth-token (first result)))))

(defun validate-oauth-token (access-token &optional required-scopes)
  "验证访问令牌"
  (let ((token (get-oauth-token access-token)))
    (unless token
      (return-from validate-oauth-token (values nil "Invalid access token")))

    (when (oauth-token-revoked token)
      (return-from validate-oauth-token (values nil "Token has been revoked")))

    (when (> (get-universal-time) (oauth-token-expires-at token))
      (return-from validate-oauth-token (values nil "Token expired")))

    ;; 验证权限范围
    (when required-scopes
      (let ((token-scopes (oauth-token-scopes token)))
        (dolist (scope required-scopes)
          (unless (member scope token-scopes :test #'equalp)
            (unless (member :admin token-scopes :test #'equalp)
              (return-from validate-oauth-token
                (values nil (format nil "Missing required scope: ~a" scope))))))))

    (values token nil)))

(defun refresh-oauth-token (refresh-token client-id)
  "刷新访问令牌"
  (let ((result (postmodern:query
                 "SELECT access_token, refresh_token, client_id, user_id, scopes, created_at, expires_at, revoked
                  FROM lispim_oauth_tokens WHERE refresh_token = $1"
                 refresh-token :alist)))
    (unless result
      (return-from refresh-oauth-token (values nil "Invalid refresh token")))

    (let ((token (row-to-oauth-token (first result))))
      (when (oauth-token-revoked token)
        (return-from refresh-oauth-token (values nil "Token has been revoked")))

      (unless (string= (oauth-token-client-id token) client-id)
        (return-from refresh-oauth-token (values nil "Invalid client_id")))

      ;; 撤销旧令牌
      (postmodern:execute
       "UPDATE lispim_oauth_tokens SET revoked = true WHERE refresh_token = $1"
       refresh-token)

      ;; 创建新令牌
      (create-oauth-token
       (oauth-token-client-id token)
       (oauth-token-user-id token)
       (oauth-token-scopes token)))))

(defun revoke-oauth-token (access-token)
  "撤销访问令牌"
  (postmodern:execute
   "UPDATE lispim_oauth_tokens SET revoked = true WHERE access_token = $1"
   access-token)
  (log-info "Token revoked: ~a" access-token)
  t)

;;;; 事件订阅系统

(defun create-event-subscription (app-id events &key (webhook-url nil))
  "创建事件订阅"
  (declare (type string app-id)
           (type list events))

  (let* ((sub-id (generate-snowflake-id))
         (secret (generate-client-secret))
         (sub (make-oauth-event-subscription
               :id sub-id
               :app-id app-id
               :events events
               :webhook-url webhook-url
               :secret secret
               :active t
               :created-at (get-universal-time))))

    ;; 保存到数据库
    (postmodern:execute
     "INSERT INTO lispim_event_subscriptions (id, app_id, events, webhook_url, secret, created_at)
      VALUES ($1, $2, $3, $4, $5, $6)"
     sub-id app-id
     (cl-json:encode-json-to-string (mapcar #'string events))
     webhook-url secret
     (lispim-universal-to-unix-ms (get-universal-time)))

    (log-info "Event subscription created: ~a" sub-id)
    sub))

(defun get-event-subscription (sub-id)
  "获取事件订阅"
  (let ((result (postmodern:query
                 "SELECT id, app_id, events, webhook_url, secret, active, created_at
                  FROM lispim_event_subscriptions WHERE id = $1"
                 sub-id :alist)))
    (when result
      (row-to-event-subscription (first result)))))

(defun get-app-subscriptions (app-id)
  "获取应用的所有事件订阅"
  (let ((results (postmodern:query
                  "SELECT id, app_id, events, webhook_url, secret, active, created_at
                   FROM lispim_event_subscriptions WHERE app_id = $1"
                  app-id :alist)))
    (mapcar #'row-to-event-subscription results)))

(defun delete-event-subscription (sub-id)
  "删除事件订阅"
  (postmodern:execute
   "DELETE FROM lispim_event_subscriptions WHERE id = $1"
   sub-id)
  (log-info "Event subscription deleted: ~a" sub-id)
  t)

;;;; 事件分发

(defparameter *event-queue* nil
  "事件队列（Redis Streams）")

(defun emit-event (event-type payload)
  "分发事件"
  (declare (type keyword event-type))

  ;; 查询订阅了该事件的所有订阅
  (let ((subscriptions (get-active-subscriptions-for-event event-type)))
    (when (null subscriptions)
      (return-from emit-event nil))

    ;; 将事件加入队列异步处理
    (dolist (sub subscriptions)
      (when (and (oauth-event-subscription-webhook-url sub)
                 (oauth-event-subscription-active sub))
        (enqueue-webhook-event sub event-type payload)))))

(defun get-active-subscriptions-for-event (event-type)
  "获取订阅了指定事件的所有活跃订阅"
  (let* ((event-name (string-downcase (symbol-name event-type)))
         (results (postmodern:query
                   "SELECT id, app_id, events, webhook_url, secret, active, created_at
                    FROM lispim_event_subscriptions
                    WHERE active = true AND events::jsonb @> $1::jsonb"
                   (format nil "[\"~a\"]" event-name)
                   :alist)))
    (mapcar #'row-to-event-subscription results)))

(defun enqueue-webhook-event (subscription event-type payload)
  "将 Webhook 事件加入队列 (简化版：直接发送)"
  ;; 简化实现：直接发送 webhook，不使用 Redis Streams
  (let ((event-data (list :type event-type
                          :payload payload
                          :timestamp (get-universal-time)
                          :subscription-id (oauth-event-subscription-id subscription))))
    (handler-case
        (let ((webhook-url (oauth-event-subscription-webhook-url subscription)))
          (when webhook-url
            (send-webhook-request webhook-url event-data (oauth-event-subscription-id subscription)))
          (log-debug "Webhook event sent: ~a" event-type))
      (error (c)
        (log-error "Failed to send webhook event: ~a" c)))))

(defun process-webhook-queue ()
  "处理 Webhook 队列 (简化版：无操作)"
  ;; 简化实现：不需要队列处理
  nil)

(defun send-webhook-request (url event-data subscription-id)
  "发送 Webhook 请求"
  (let ((subscription (get-event-subscription subscription-id)))
    (unless subscription
      (return-from send-webhook-request nil))

    (let* ((body (cl-json:encode-json-to-string event-data))
           (timestamp (get-universal-time))
           (signature (generate-webhook-signature body (oauth-event-subscription-secret subscription) timestamp))
           (headers (list (list "Content-Type" "application/json")
                          (list "X-LispIM-Signature" signature)
                          (list "X-LispIM-Timestamp" (write-to-string timestamp))
                          (list "X-LispIM-Event" (string (getf event-data :type))))))
      (handler-case
          (let ((response (drakma:http-request url
                                               :method :post
                                               :content body
                                               :content-type "application/json"
                                               :additional-headers headers)))
            (log-debug "Webhook sent successfully: ~a" url)
            response)
        (error (c)
          (log-error "Webhook delivery failed to ~a: ~a" url c)
          ;; 可以实现重试逻辑
          nil)))))

(defun generate-webhook-signature (payload secret timestamp)
  "生成 Webhook 签名"
  (let* ((timestamp-str (write-to-string timestamp))
         (signed-string (format nil "~a.~a" timestamp-str payload))
         (key (babel:string-to-octets secret :encoding :utf-8))
         (data (babel:string-to-octets signed-string :encoding :utf-8))
         (hmac (ironclad:make-hmac key :sha256)))
    (format nil "sha256=~a" (ironclad:byte-array-to-hex-string (ironclad:hmac-digest hmac :data data)))))

;;;; WebSocket API 支持

(defvar *websocket-api-handlers* (make-hash-table :test 'equal)
  "WebSocket API 处理器注册表")

(defun register-websocket-api (endpoint handler)
  "注册 WebSocket API 处理器"
  (declare (type string endpoint)
           (type function handler))
  (setf (gethash endpoint *websocket-api-handlers*) handler)
  (log-debug "WebSocket API registered: ~a" endpoint))

(defun handle-websocket-api-message (conn message)
  "处理 WebSocket API 消息"
  (let ((type (getf message :type))
        (payload (getf message :payload)))
    (when (and type (starts-with-string-p "API:" type))
      (let* ((endpoint (subseq type 4)) ; 移除 "API:" 前缀
             (handler (gethash endpoint *websocket-api-handlers*)))
        (if handler
            (funcall handler conn payload)
            (send-to-connection conn (encode-ws-message
                                      `(:type "ERROR"
                                        :payload (:message ,(format nil "Unknown API endpoint: ~a" endpoint))))))))))

;;;; 用户信息 API

(defun api-get-current-user (conn payload)
  "获取当前用户信息 API"
  (declare (ignore payload))
  (let ((user (get-user-by-id (connection-user-id conn))))
    (if user
        (send-to-connection conn (encode-ws-message
                                  `(:type "API:USER"
                                    :payload (:user ,(user-to-plist user)))))
        (send-to-connection conn (encode-ws-message
                                  `(:type "ERROR"
                                    :payload (:message "User not found")))))))

;;;; 消息发送 API

(defun api-send-message (conn payload)
  "发送消息 API"
  (let* ((target-id (getf payload :targetId))
         (content (getf payload :content))
         (type (or (getf payload :type) :text)))
    (unless (and target-id content)
      (return-from api-send-message
        (send-to-connection conn (encode-ws-message
                                  `(:type "ERROR"
                                    :payload (:message "Missing targetId or content"))))))

    (handler-case
        (let* ((sender-id (connection-user-id conn))
               (msg (create-message sender-id target-id content :type type)))
          (send-to-connection conn (encode-ws-message
                                    `(:type "API:MESSAGE_SENT"
                                      :payload (:messageId ,(message-id msg))))))
      (error (c)
        (send-to-connection conn (encode-ws-message
                                  `(:type "ERROR"
                                    :payload (:message ,(princ-to-string c)))))))))

;;;; 辅助函数

(defun starts-with-string-p (prefix string)
  "检查字符串是否以指定前缀开头"
  (and (<= (length prefix) (length string))
       (string= prefix (subseq string 0 (length prefix)) :end2 (length prefix))))

(defun row-to-oauth-app (row)
  "将数据库行转换为 OAuth 应用结构"
  (make-oauth-app
   :id (getf row :id)
   :name (getf row :name)
   :description (getf row :description)
   :client-id (getf row :client-id)
   :client-secret (getf row :client-secret)
   :redirect-uris (mapcar #'intern (cl-json:decode-json-from-string (getf row :redirect_uris)))
   :scopes (mapcar #'intern (cl-json:decode-json-from-string (getf row :scopes)))
   :owner-id (getf row :owner-id)
   :created-at (unix-ms-to-lispim-universal (getf row :created_at))
   :active (getf row :active)))

(defun row-to-oauth-code (row)
  "将数据库行转换为授权码结构"
  (make-oauth-code
   :code (getf row :code)
   :client-id (getf row :client-id)
   :user-id (getf row :user-id)
   :redirect-uri (getf row :redirect-uri)
   :scopes (mapcar #'intern (cl-json:decode-json-from-string (getf row :scopes)))
   :expires-at (unix-ms-to-lispim-universal (getf row :expires_at))
   :used (getf row :used)))

(defun row-to-oauth-token (row)
  "将数据库行转换为令牌结构"
  (make-oauth-token
   :access-token (getf row :access-token)
   :refresh-token (getf row :refresh-token)
   :client-id (getf row :client-id)
   :user-id (getf row :user-id)
   :scopes (mapcar #'intern (cl-json:decode-json-from-string (getf row :scopes)))
   :created-at (unix-ms-to-lispim-universal (getf row :created_at))
   :expires-at (unix-ms-to-lispim-universal (getf row :expires_at))
   :revoked (getf row :revoked)))

(defun row-to-event-subscription (row)
  "将数据库行转换为事件订阅结构"
  (make-oauth-event-subscription
   :id (getf row :id)
   :app-id (getf row :app_id)
   :events (mapcar #'intern (cl-json:decode-json-from-string (getf row :events)))
   :webhook-url (getf row :webhook_url)
   :secret (getf row :secret)
   :active (getf row :active)
   :created-at (unix-ms-to-lispim-universal (getf row :created_at))))

;;;; 条件系统

(define-condition oauth-error (condition)
  ()
  (:report (lambda (c s)
             (format s "OAuth error"))))

(define-condition oauth-app-not-found (oauth-error)
  ((client-id :initarg :client-id :reader oauth-error-client-id))
  (:report (lambda (c s)
             (format s "OAuth app not found: ~a" (oauth-error-client-id c)))))

(define-condition oauth-invalid-grant (oauth-error)
  ((reason :initarg :reason :reader oauth-error-reason))
  (:report (lambda (c s)
             (format s "Invalid grant: ~a" (oauth-error-reason c)))))

(define-condition oauth-token-expired (oauth-error)
  ((token :initarg :token :reader oauth-error-token))
  (:report (lambda (c s)
             (format s "Token expired: ~a" (oauth-error-token c)))))

;;;; 初始化

(defun init-oauth-system ()
  "初始化 OAuth 系统"
  (log-info "Initializing OAuth system...")

  ;; 确保数据表存在
  (ensure-oauth-tables-exist)

  ;; 注册 WebSocket API
  (register-websocket-api "USER" #'api-get-current-user)
  (register-websocket-api "SEND_MESSAGE" #'api-send-message)

  ;; 启动 Webhook 队列处理器
  (bt:make-thread #'process-webhook-queue
                  :name "lispim-webhook-processor")

  (log-info "OAuth system initialized"))

;;;; 导出 - Removed: exports are in package.lisp