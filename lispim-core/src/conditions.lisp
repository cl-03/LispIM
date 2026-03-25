;;;; conditions.lisp - LispIM 条件系统定义
;;;;
;;;; 定义完整的错误层次结构，支持 restart 恢复机制
;;;;
;;;; 参考：Common Lisp Cookbook - Conditions, Restarts, Restarter

(in-package :lispim-core/conditions)

;;;; 基础条件类型 - 支持 restart 恢复

(define-condition lispim-error (error)
  ((message :initarg :message :reader condition-message :type string)
   (context :initarg :context :initform nil :reader condition-context)
   (data :initarg :data :initform nil :reader condition-data))
  (:report (lambda (condition stream)
             (format stream "LispIM Error: ~a~@[ (Context: ~a)~]~@[ Data: ~a~]"
                     (condition-message condition)
                     (condition-context condition)
                     (condition-data condition))))
  (:documentation "LispIM 基础错误类型"))

(define-condition lispim-warning (warning)
  ((message :initarg :message :reader condition-message :type string)
   (data :initarg :data :initform nil :reader condition-data))
  (:report (lambda (condition stream)
             (format stream "LispIM Warning: ~a~@[ Data: ~a~]"
                     (condition-message condition)
                     (condition-data condition))))
  (:documentation "LispIM 基础警告类型"))

(define-condition lispim-serious-condition (serious-condition)
  ((message :initarg :message :reader condition-message :type string))
  (:report (lambda (condition stream)
             (format stream "LispIM Serious Condition: ~a"
                     (condition-message condition))))
  (:documentation "LispIM 严重条件类型"))

;;;; 连接错误 - 带恢复 restart

(define-condition connection-error (lispim-error)
  ((connection-id :initarg :connection-id :reader condition-connection-id))
  (:documentation "连接错误基类"))

(define-condition connection-timeout (connection-error)
  ((timeout-duration :initarg :timeout-duration :initform 30
                     :reader condition-timeout-duration))
  (:report (lambda (condition stream)
             (format stream "Connection ~a timeout after ~a seconds"
                     (condition-connection-id condition)
                     (condition-timeout-duration condition))))
  (:documentation "连接超时"))

(define-condition connection-closed (connection-error)
  ((reason :initarg :reason :initform nil :reader condition-reason))
  (:report (lambda (condition stream)
             (format stream "Connection ~a closed~@[ reason: ~a~]"
                     (condition-connection-id condition)
                     (condition-reason condition))))
  (:documentation "连接已关闭"))

(define-condition connection-not-found (connection-error)
  ()
  (:report (lambda (condition stream)
             (format stream "Connection ~a not found"
                     (condition-connection-id condition))))
  (:documentation "连接未找到"))

(define-condition connection-lost (connection-error)
  ((attempted-reconnect :initarg :attempted-reconnect :initform nil
                        :reader condition-attempted-reconnect))
  (:report (lambda (condition stream)
             (format stream "Connection ~a lost~@[, attempted reconnect: ~a~]"
                     (condition-connection-id condition)
                     (condition-attempted-reconnect condition))))
  (:documentation "连接丢失"))

;;;; 认证错误 - 带恢复 restart

(define-condition auth-error (lispim-error)
  ((user-id :initarg :user-id :reader condition-user-id)
   (ip-address :initarg :ip-address :initform nil :reader condition-ip-address))
  (:documentation "认证错误基类"))

(define-condition auth-token-expired (auth-error)
  ((expired-at :initarg :expired-at :reader condition-expired-at))
  (:report (lambda (condition stream)
             (format stream "Auth token expired for user ~a at ~a"
                     (condition-user-id condition)
                     (condition-expired-at condition))))
  (:documentation "Token 过期"))

(define-condition auth-invalid-credentials (auth-error)
  ((attempted-username :initarg :attempted-username :reader condition-attempted-username))
  (:report (lambda (condition stream)
             (format stream "Invalid credentials for user ~a from IP ~a"
                     (condition-attempted-username condition)
                     (condition-ip-address condition))))
  (:documentation "凭证无效"))

(define-condition auth-account-locked (auth-error)
  ((locked-until :initarg :locked-until :reader condition-locked-until)
   (failed-attempts :initarg :failed-attempts :reader condition-failed-attempts))
  (:report (lambda (condition stream)
             (format stream "Account ~a locked until ~a after ~a failed attempts"
                     (condition-user-id condition)
                     (condition-locked-until condition)
                     (condition-failed-attempts condition))))
  (:documentation "账户被锁定"))

(define-condition auth-token-invalid (auth-error)
  ()
  (:report (lambda (condition stream)
             (format stream "Invalid auth token for user ~a"
                     (condition-user-id condition))))
  (:documentation "Token 无效"))

;;;; 消息错误 - 带恢复 restart

(define-condition message-error (lispim-error)
  ((message-id :initarg :message-id :reader condition-message-id)
   (conversation-id :initarg :conversation-id :initform nil
                    :reader condition-conversation-id))
  (:documentation "消息错误基类"))

(define-condition message-not-found (message-error)
  ()
  (:report (lambda (condition stream)
             (format stream "Message ~a not found~@[ in conversation ~a~]"
                     (condition-message-id condition)
                     (condition-conversation-id condition))))
  (:documentation "消息未找到"))

(define-condition message-send-failed (message-error)
  ((reason :initarg :reason :reader condition-reason))
  (:report (lambda (condition stream)
             (format stream "Failed to send message ~a~@[ in conversation ~a~]: ~a"
                     (condition-message-id condition)
                     (condition-conversation-id condition)
                     (condition-reason condition))))
  (:documentation "消息发送失败"))

(define-condition message-recall-timeout (message-error)
  ((elapsed :initarg :elapsed :reader condition-elapsed)
   (max-elapsed :initarg :max-elapsed :initform (* 2 60 60)
                :reader condition-max-elapsed))
  (:report (lambda (condition stream)
             (format stream "Message recall timeout (~a seconds elapsed, max ~a)"
                     (condition-elapsed condition)
                     (condition-max-elapsed condition))))
  (:documentation "消息撤回超时"))

(define-condition message-too-long (message-error)
  ((length :initarg :length :reader condition-length)
   (max-length :initarg :max-length :reader condition-max-length))
  (:report (lambda (condition stream)
             (format stream "Message too long: ~a characters (max ~a)"
                     (condition-length condition)
                     (condition-max-length condition))))
  (:documentation "消息过长"))

(define-condition message-rate-limited (message-error)
  ((retry-after :initarg :retry-after :reader condition-retry-after))
  (:report (lambda (condition stream)
             (format stream "Message rate limited, retry after ~a seconds"
                     (condition-retry-after condition))))
  (:documentation "消息频率限制"))

;;;; 会话错误

(define-condition conversation-error (lispim-error)
  ((conversation-id :initarg :conversation-id :reader condition-conversation-id))
  (:documentation "会话错误基类"))

(define-condition conversation-not-found (conversation-error)
  ()
  (:report (lambda (condition stream)
             (format stream "Conversation ~a not found"
                     (condition-conversation-id condition))))
  (:documentation "会话未找到"))

(define-condition conversation-access-denied (conversation-error)
  ((user-id :initarg :user-id :reader condition-user-id))
  (:report (lambda (condition stream)
             (format stream "User ~a access denied to conversation ~a"
                     (condition-user-id condition)
                     (condition-conversation-id condition))))
  (:documentation "会话访问拒绝"))

(define-condition conversation-full (conversation-error)
  ((current-members :initarg :current-members :reader condition-current-members)
   (max-members :initarg :max-members :reader condition-max-members))
  (:report (lambda (condition stream)
             (format stream "Conversation full: ~a/~a members"
                     (condition-current-members condition)
                     (condition-max-members condition))))
  (:documentation "会话成员已满"))

;;;; 存储错误 - 带恢复 restart

(define-condition storage-error (lispim-error)
  ((key :initarg :key :reader condition-key)
   (storage-type :initarg :storage-type :initform nil :reader condition-storage-type))
  (:documentation "存储错误基类"))

(define-condition storage-not-found (storage-error)
  ()
  (:report (lambda (condition stream)
             (format stream "Storage key ~a not found~@[ in ~a~]"
                     (condition-key condition)
                     (condition-storage-type condition))))
  (:documentation "存储键未找到"))

(define-condition storage-write-failed (storage-error)
  ((reason :initarg :reason :reader condition-reason))
  (:report (lambda (condition stream)
             (format stream "Failed to write storage ~a~@[ in ~a~]: ~a"
                     (condition-key condition)
                     (condition-storage-type condition)
                     (condition-reason condition))))
  (:documentation "存储写入失败"))

(define-condition storage-quota-exceeded (storage-error)
  ((used :initarg :used :reader condition-used)
   (quota :initarg :quota :reader condition-quota))
  (:report (lambda (condition stream)
             (format stream "Storage quota exceeded: ~a/~a bytes"
                     (condition-used condition)
                     (condition-quota condition))))
  (:documentation "存储配额超出"))

;;;; E2EE 错误

(define-condition e2ee-error (lispim-error)
  ((session-id :initarg :session-id :reader condition-session-id))
  (:documentation "E2EE 错误基类"))

(define-condition e2ee-decrypt-failed (e2ee-error)
  ((reason :initarg :reason :reader condition-reason)
   (message-id :initarg :message-id :initform nil :reader condition-message-id))
  (:report (lambda (condition stream)
             (format stream "Failed to decrypt message~@[ ~a~]~@[ in session ~a~]: ~a"
                     (condition-message-id condition)
                     (condition-session-id condition)
                     (condition-reason condition))))
  (:documentation "E2EE 解密失败"))

(define-condition e2ee-key-not-found (e2ee-error)
  ((user-id :initarg :user-id :reader condition-user-id)
   (key-type :initarg :key-type :initform :identity :reader condition-key-type))
  (:report (lambda (condition stream)
             (format stream "E2EE ~a key not found for user ~a"
                     (condition-key-type condition)
                     (condition-user-id condition))))
  (:documentation "E2EE 密钥未找到"))

(define-condition e2ee-session-expired (e2ee-error)
  ((expired-at :initarg :expired-at :reader condition-expired-at))
  (:report (lambda (condition stream)
             (format stream "E2EE session ~a expired at ~a"
                     (condition-session-id condition)
                     (condition-expired-at condition))))
  (:documentation "E2EE 会话过期"))

;;;; 模块错误

(define-condition module-error (lispim-error)
  ((module-name :initarg :module-name :reader condition-module-name))
  (:documentation "模块错误基类"))

(define-condition module-load-failed (module-error)
  ((reason :initarg :reason :reader condition-reason)
   (dependencies :initarg :dependencies :initform nil :reader condition-dependencies))
  (:report (lambda (condition stream)
             (format stream "Failed to load module ~a~@[ dependencies: ~a~]: ~a"
                     (condition-module-name condition)
                     (condition-dependencies condition)
                     (condition-reason condition))))
  (:documentation "模块加载失败"))

(define-condition module-health-check-failed (module-error)
  ((check-name :initarg :check-name :initform nil :reader condition-check-name))
  (:report (lambda (condition stream)
             (format stream "Health check failed for module ~a~@[ check: ~a~]"
                     (condition-module-name condition)
                     (condition-check-name condition))))
  (:documentation "模块健康检查失败"))

(define-condition module-not-found (module-error)
  ()
  (:report (lambda (condition stream)
             (format stream "Module ~a not found"
                     (condition-module-name condition))))
  (:documentation "模块未找到"))

;;;; 网络错误

(define-condition network-error (lispim-error)
  ((host :initarg :host :reader condition-host)
   (port :initarg :port :initform nil :reader condition-port))
  (:documentation "网络错误基类"))

(define-condition network-timeout (network-error)
  ((operation :initarg :operation :reader condition-operation)
   (timeout-duration :initarg :timeout-duration :reader condition-timeout-duration))
  (:report (lambda (condition stream)
             (format stream "Network timeout during ~a on ~a:~a after ~a seconds"
                     (condition-operation condition)
                     (condition-host condition)
                     (condition-port condition)
                     (condition-timeout-duration condition))))
  (:documentation "网络超时"))

(define-condition network-unreachable (network-error)
  ()
  (:report (lambda (condition stream)
             (format stream "Network unreachable: ~a:~a"
                     (condition-host condition)
                     (condition-port condition))))
  (:documentation "网络不可达"))

;;;; WebSocket 错误

(define-condition websocket-error (lispim-error)
  ((url :initarg :url :reader condition-url))
  (:documentation "WebSocket 错误基类"))

(define-condition websocket-connection-failed (websocket-error)
  ((reason :initarg :reason :reader condition-reason)
   (status-code :initarg :status-code :initform nil :reader condition-status-code))
  (:report (lambda (condition stream)
             (format stream "WebSocket connection failed to ~a~@[ status: ~a~]: ~a"
                     (condition-url condition)
                     (condition-status-code condition)
                     (condition-reason condition))))
  (:documentation "WebSocket 连接失败"))

(define-condition websocket-message-error (websocket-error)
  ((message :initarg :ws-message :reader condition-ws-message))
  (:report (lambda (condition stream)
             (format stream "WebSocket message error on ~a: ~a"
                     (condition-url condition)
                     (condition-message condition))))
  (:documentation "WebSocket 消息错误"))

;;;; Restarts - 恢复机制宏

;; 使用 restart-case 定义常用 restart 包装器

(defmacro with-retry-restart (&body body)
  "包装代码块添加 retry restart"
  `(restart-case
       (progn ,@body)
     (retry ()
       :report "Retry the operation"
       :interactive (lambda () nil)
       (invoke-restart 'retry))))

(defmacro with-retry-with-delay-restart (delay &body body)
  "包装代码块添加 retry-with-delay restart"
  `(restart-case
       (progn ,@body)
     (retry-with-delay (delay)
       :report (lambda (stream)
                 (format stream "Retry after ~a seconds" delay))
       :interactive (lambda ()
                      (format *query-io* "Enter delay in seconds: ")
                      (list (parse-integer (read-line *query-io*))))
       (invoke-restart 'retry-with-delay delay))))

(defmacro with-use-value-restart (default-value &body body)
  "包装代码块添加 use-value restart"
  `(restart-case
       (progn ,@body)
     (use-value (value)
       :report (lambda (stream)
                 (format stream "Use value: ~a" value))
       :interactive (lambda ()
                      (format *query-io* "Enter replacement value: ")
                      (list (read-line *query-io*)))
       (invoke-restart 'use-value value))))

(defmacro with-skip-restart (&body body)
  "包装代码块添加 skip restart"
  `(restart-case
       (progn ,@body)
     (skip ()
       :report "Skip this operation"
       :interactive (lambda () nil)
       (values))))

(defmacro with-abort-connection-restart (&body body)
  "包装代码块添加 abort-connection restart"
  `(restart-case
       (progn ,@body)
     (abort-connection ()
       :report "Abort connection attempt"
       :interactive (lambda () nil)
       nil)))

(defmacro with-reconnect-restart (&body body)
  "包装代码块添加 reconnect restart"
  `(restart-case
       (progn ,@body)
     (reconnect ()
       :report "Attempt to reconnect"
       :interactive (lambda () nil)
       (invoke-restart 'reconnect))))

(defmacro with-enter-debugger-restart (&body body)
  "包装代码块添加 enter-debugger restart"
  `(restart-case
       (progn ,@body)
     (enter-debugger ()
       :report "Enter the debugger"
       :interactive (lambda () nil)
       (invoke-debugger))))

;;;; Handler 宏 - 简化错误处理

(defmacro with-condition-handler ((condition-type handler) &body body)
  "包装代码块添加条件处理器"
  `(handler-case
       (progn ,@body)
     (,condition-type (c)
       (funcall ,handler c))))

(defmacro with-auth-error-handler (handler &body body)
  "包装代码块添加认证错误处理器"
  `(handler-case
       (progn ,@body)
     (auth-error (c)
       (funcall ,handler c))))

(defmacro with-connection-error-handler (handler &body body)
  "包装代码块添加连接错误处理器"
  `(handler-case
       (progn ,@body)
     (connection-error (c)
       (funcall ,handler c))))

(defmacro with-storage-error-handler (handler &body body)
  "包装代码块添加存储错误处理器"
  `(handler-case
       (progn ,@body)
     (storage-error (c)
       (funcall ,handler c))))

(defmacro with-abort-restart (&body body)
  "包装代码块添加 abort restart"
  `(restart-case
       (progn ,@body)
     (abort ()
       :report "Abort the operation"
       :interactive (lambda () nil)
       nil)))

;;;; 辅助函数 - 通用条件消息访问

;; 为任何没有 condition-message 方法的条件提供默认实现
(defmethod condition-message ((condition t))
  "Default condition-message method for any condition type"
  (princ-to-string condition))

(export '(;; Conditions
          lispim-error
          lispim-warning
          lispim-serious-condition

          ;; Connection errors
          connection-error
          connection-timeout
          connection-closed
          connection-not-found
          connection-lost

          ;; Auth errors
          auth-error
          auth-token-expired
          auth-invalid-credentials
          auth-account-locked
          auth-token-invalid

          ;; Message errors
          message-error
          message-not-found
          message-send-failed
          message-recall-timeout
          message-too-long
          message-rate-limited

          ;; Conversation errors
          conversation-error
          conversation-not-found
          conversation-access-denied
          conversation-full

          ;; Storage errors
          storage-error
          storage-not-found
          storage-write-failed
          storage-quota-exceeded

          ;; E2EE errors
          e2ee-error
          e2ee-decrypt-failed
          e2ee-key-not-found
          e2ee-session-expired

          ;; Module errors
          module-error
          module-load-failed
          module-health-check-failed
          module-not-found

          ;; Network errors
          network-error
          network-timeout
          network-unreachable

          ;; WebSocket errors
          websocket-error
          websocket-connection-failed
          websocket-message-error

          ;; Handler macros
          with-condition-handler
          with-retry-restart
          with-skip-restart
          with-abort-restart

          ;; Accessors
          condition-message
          condition-context
          condition-data
          condition-connection-id
          condition-user-id
          condition-message-id
          condition-conversation-id
          condition-session-id
          condition-module-name
          condition-key
          condition-url
          condition-host
          condition-port
          condition-reason
          condition-timeout-duration
          condition-ip-address
          condition-expired-at
          condition-attempted-username
          condition-locked-until
          condition-failed-attempts
          condition-length
          condition-max-length
          condition-retry-after
          condition-check-name
          condition-dependencies
          condition-storage-type
          condition-used
          condition-quota
          condition-operation
          condition-ws-message
          condition-status-code
          condition-attempted-reconnect
          condition-current-members
          condition-max-members
          condition-elapsed
          condition-max-elapsed
          condition-key-type)
        :lispim-core/conditions)
