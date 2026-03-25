;;;; oc-adapter.lisp - OpenClaw 适配器
;;;;
;;;; 负责与 OpenClaw AI 系统的深度集成

(in-package :lispim-core)

;;;; 依赖声明

(eval-when (:compile-toplevel :load-toplevel :execute)
  (ql:quickload '(:cl-json :bordeaux-threads :drakma)))

;;;; OpenClaw 连接状态

(defvar *oc-connected* nil
  "OpenClaw 连接状态")

(defvar *oc-endpoint* ""
  "OpenClaw 端点 URL")

(defvar *oc-api-key* ""
  "OpenClaw API 密钥")

;;;; 能力发现

(defstruct oc-capabilities
  "OpenClaw 能力描述"
  (streaming-p nil :type boolean)
  (context-summarization-p nil :type boolean)
  (skill-callback-p nil :type boolean)
  (max-context-size 8192 :type integer)
  (supported-models nil :type list)
  (rate-limit 60 :type integer))  ; requests per minute

(defvar *oc-capabilities* nil
  "OpenClaw 能力缓存")

;;;; 速率限制器

(defstruct rate-limiter
  "令牌桶速率限制器"
  (capacity 60 :type integer)
  (tokens 60.0 :type float)
  (last-refill (get-universal-time) :type integer)
  (lock (bordeaux-threads:make-lock "rate-limiter-lock") :type bordeaux-threads:lock))

(defvar *oc-rate-limiter* (make-rate-limiter)
  "OpenClaw 速率限制器")

(defun rate-limit-allow-p (limiter)
  "检查是否允许请求（令牌桶算法）"
  (declare (type rate-limiter limiter)
           (optimize (speed 3) (safety 1)))
  (bordeaux-threads:with-lock-held ((rate-limiter-lock limiter))
    (let* ((now (get-universal-time))
           (elapsed (- now (rate-limiter-last-refill limiter)))
           (refill-rate 1.0))  ; 每秒补充 1 个令牌
      ;; 补充令牌
      (setf (rate-limiter-tokens limiter)
            (min (coerce (rate-limiter-capacity limiter) 'float)
                 (+ (rate-limiter-tokens limiter)
                    (* elapsed refill-rate))))
      (setf (rate-limiter-last-refill limiter) now)
      ;; 消耗令牌
      (if (>= (rate-limiter-tokens limiter) 1.0)
          (progn
            (decf (rate-limiter-tokens limiter))
            t)
          nil))))

;;;; OpenClaw 连接管理

(defun oc-connect (endpoint api-key)
  "连接到 OpenClaw"
  (declare (type string endpoint)
           (type string api-key))
  (setf *oc-endpoint* endpoint
        *oc-api-key* api-key)

  (log-info "Connecting to OpenClaw: ~a" endpoint)

  ;; 获取能力
  (discover-capabilities)

  (setf *oc-connected* t)
  (log-info "OpenClaw connected"))

(defun oc-disconnect ()
  "断开 OpenClaw 连接"
  (setf *oc-connected* nil)
  (log-info "OpenClaw disconnected"))

;;;; 能力发现

(defun discover-capabilities ()
  "发现 OpenClaw 能力"
  (handler-case
      (let ((response (drakma:http-request (format nil "~a/capabilities" *oc-endpoint*)
                                           :method :get
                                           :additional-headers
                                           `(("Authorization" . ,(format nil "Bearer ~a" *oc-api-key*))))))
        (let ((data (cl-json:decode-json-from-string response)))
          (setf *oc-capabilities*
                (make-oc-capabilities
                 :streaming-p (getf data :streaming)
                 :context-summarization-p (getf data :context-summarization)
                 :skill-callback-p (getf data :skill-callback)
                 :max-context-size (or (getf data :max-context-size) 8192)
                 :supported-models (or (getf data :supported-models) nil)
                 :rate-limit (or (getf data :rate-limit) 60)))
          (log-info "OpenClaw capabilities: ~a" *oc-capabilities*)))
    (error (c)
      (log-error "Failed to discover OpenClaw capabilities: ~a" c)
      (setf *oc-capabilities* (make-oc-capabilities)))))

;;;; 消息发送

(defun oc-send-message (conversation-id message &key stream-p callback)
  "发送消息到 OpenClaw"
  (declare (type integer conversation-id)
           (type string message))

  ;; 速率限制检查
  (unless (rate-limit-allow-p *oc-rate-limiter*)
    (error "OpenClaw rate limit exceeded"))

  ;; 本地上下文摘要
  (let ((context (summarize-context conversation-id
                                    (oc-capabilities-max-context-size *oc-capabilities*))))

    (handler-case
        (let ((request `((:conversation-id . ,conversation-id)
                         (:message . ,message)
                         (:context . ,context)
                         (:stream . ,stream-p))))
          (log-info "Sending to OpenClaw: ~a" message)

          (drakma:http-request (format nil "~a/chat" *oc-endpoint*)
                               :method :post
                               :content-type "application/json"
                               :content (cl-json:encode-json-to-string request)
                               :additional-headers
                               `(("Authorization" . ,(format nil "Bearer ~a" *oc-api-key*))))

          ;; 记录 token 成本
          (record-token-cost conversation-id))

      (error (c)
        (log-error "OpenClaw send failed: ~a" c)
        ;; Fallback 逻辑
        (oc-fallback conversation-id message)))))

;;;; 本地上下文摘要

(defun summarize-context (conversation-id max-length)
  "使用向量相似度提取关键消息，减少 Token 消耗"
  (declare (type integer conversation-id)
           (type integer max-length))
  (let* ((messages (get-history conversation-id :limit max-length))
         (key-messages (extract-key-messages messages)))
    (format nil "~{~a~^~%~%~}"
            (mapcar (lambda (m) (message-content m)) key-messages))))

(defun extract-key-messages (messages)
  "基于规则提取关键消息"
  (declare (type list messages))
  (remove-if-not (lambda (msg)
                   (or (lispim-string-contains-p (message-content msg) "?")
                       (lispim-string-contains-p (message-content msg) "!")
                       (not (null (message-mentions msg)))
                       (eq (message-message-type msg) :system)))
                 messages))

;; lispim-string-contains-p is defined in utils.lisp

;;;; Token 成本记录

(defun record-token-cost (conversation-id)
  "记录 Token 消耗成本"
  (declare (type integer conversation-id))
  ;; 简化实现，实际应记录详细成本
  (log-debug "Recorded token cost for conversation ~a" conversation-id)
  ;; 更新指标
  (incf *oc-token-cost-counter*))

(defvar *oc-token-cost-counter* 0
  "OpenClaw Token 成本计数器")

;;;; Fallback 逻辑

(defun oc-fallback (conversation-id message)
  "OpenClaw 失败时的 fallback 逻辑"
  (declare (type integer conversation-id)
           (type string message))
  (log-warn "OpenClaw fallback for: ~a" message)
  ;; 可以返回预设回复或本地处理
  (let ((response "AI 服务暂时不可用，请稍后重试。"))
    (send-message conversation-id response :type :notification)))

;;;; 多 Agent 路由

(defstruct agent-router
  "多 Agent 路由器"
  (rules (make-hash-table :test 'equal) :type hash-table)
  (default-agent "general" :type string))

(defvar *agent-router* (make-agent-router)
  "全局 Agent 路由器")

(defun add-routing-rule (pattern agent-id)
  "添加路由规则"
  (declare (type string pattern)
           (type string agent-id))
  (setf (gethash pattern (agent-router-rules *agent-router*))
        agent-id))

(defun route-to-agent (conversation-id message)
  "路由消息到指定 Agent"
  (declare (type integer conversation-id)
           (type string message))
  (let ((agent-id (find-matching-agent message)))
    (oc-send-message conversation-id message)
    (log-info "Routed to agent: ~a" agent-id)))

(defun find-matching-agent (message)
  "查找匹配的 Agent"
  (declare (type string message))
  (let ((result (agent-router-default-agent *agent-router*)))
    (maphash (lambda (pattern agent)
               (when (search pattern message)
                 (setf result agent)))
             (agent-router-rules *agent-router*))
    result))

;;;; 技能回调

(defun register-skill (name callback)
  "注册技能回调"
  (declare (type string name)
           (type function callback))
  (setf (gethash name *oc-skills*) callback))

(defvar *oc-skills* (make-hash-table :test 'equal)
  "OpenClaw 技能注册表")

(defun invoke-skill (skill-name args)
  "调用技能"
  (declare (type string skill-name))
  (let ((skill (gethash skill-name *oc-skills*)))
    (if skill
        (funcall skill args)
        (error "Skill not found: ~a" skill-name))))

;;;; 成本监控

(defun get-token-cost (&optional (conversation-id nil))
  "获取 Token 成本"
  (declare (type (or null integer) conversation-id))
  (if conversation-id
      (gethash conversation-id *oc-token-costs* 0)
      *oc-token-cost-counter*))

(defvar *oc-token-costs* (make-hash-table :test 'eql)
  "会话 Token 成本表")

;;;; 流式响应处理

(defun handle-stream-response (conversation-id response-handler)
  "处理流式响应"
  (declare (type integer conversation-id)
           (type function response-handler))
  ;; 实现流式响应处理
  (log-info "Handling stream response for conversation ~a" conversation-id))

;;;; 初始化

(defun init-oc-adapter (&key endpoint api-key)
  "初始化 OpenClaw 适配器"
  (declare (type string endpoint)
           (type string api-key))
  (oc-connect endpoint api-key)

  ;; 注册默认技能
  (register-skill "summarize" #'skill-summarize)
  (register-skill "translate" #'skill-translate)
  (register-skill "extract" #'skill-extract)

  (log-info "OpenClaw adapter initialized"))

;;;; 默认技能

(defun skill-summarize (args)
  "摘要技能"
  (declare (ignore args))
  "摘要结果")

(defun skill-translate (args)
  "翻译技能"
  (declare (ignore args))
  "翻译结果")

(defun skill-extract (args)
  "提取技能"
  (declare (ignore args))
  "提取结果")

;;;; 清理

(defun shutdown-oc-adapter ()
  "关闭 OpenClaw 适配器"
  (oc-disconnect)
  (log-info "OpenClaw adapter shutdown"))
