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

;;;; 速率限制器 (OpenClaw 专用)

(defstruct oc-rate-limiter
  "OpenClaw 令牌桶速率限制器"
  (capacity 60 :type integer)
  (tokens 60.0 :type float)
  (last-refill (get-universal-time) :type integer)
  (lock (bordeaux-threads:make-lock "oc-rate-limiter-lock") :type bordeaux-threads:lock))

(defvar *oc-rate-limiter* (make-oc-rate-limiter)
  "OpenClaw 速率限制器")

(defun oc-rate-limit-allow-p (limiter)
  "检查是否允许请求（令牌桶算法）"
  (declare (type oc-rate-limiter limiter)
           (optimize (speed 3) (safety 1)))
  (bordeaux-threads:with-lock-held ((oc-rate-limiter-lock limiter))
    (let* ((now (get-universal-time))
           (elapsed (- now (oc-rate-limiter-last-refill limiter)))
           (refill-rate 1.0))  ; 每秒补充 1 个令牌
      ;; 补充令牌
      (setf (oc-rate-limiter-tokens limiter)
            (min (coerce (oc-rate-limiter-capacity limiter) 'float)
                 (+ (oc-rate-limiter-tokens limiter)
                    (* elapsed refill-rate))))
      (setf (oc-rate-limiter-last-refill limiter) now)
      ;; 消耗令牌
      (if (>= (oc-rate-limiter-tokens limiter) 1.0)
          (progn
            (decf (oc-rate-limiter-tokens limiter))
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

(defun oc-send-message (conversation-id message &key stream-p callback connection)
  "发送消息到 OpenClaw"
  (declare (type integer conversation-id)
           (type string message))

  ;; 速率限制检查
  (unless (oc-rate-limit-allow-p *oc-rate-limiter*)
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

          (if stream-p
              ;; 流式响应
              (handle-stream-response conversation-id
                                      (lambda (content complete-p)
                                        (when connection
                                          (handle-ai-stream-chunk connection
                                                                  (list :content content
                                                                        :complete-p complete-p))))
                                      :stream-id nil)
              ;; 普通响应
              (progn
                (drakma:http-request (format nil "~a/chat" *oc-endpoint*)
                                     :method :post
                                     :content-type "application/json"
                                     :content (cl-json:encode-json-to-string request)
                                     :additional-headers
                                     `(("Authorization" . ,(format nil "Bearer ~a" *oc-api-key*))))

                ;; 记录 token 成本
                (record-token-cost conversation-id))))

      (error (c)
        (log-error "OpenClaw send failed: ~a" c)
        ;; Fallback 逻辑
        (oc-fallback conversation-id message)))))

;;;; Phase 5: 智能重试

(defun oc-send-with-retry (conversation-id message &key (max-retries 3) (backoff 2) stream-p connection)
  "带智能重试的消息发送（指数退避）"
  (declare (type integer conversation-id)
           (type string message)
           (type integer max-retries)
           (type number backoff))
  (let ((attempt 0)
        (last-error nil))
    (loop
      (incf attempt)
      (handler-case
          (progn
            (log-info "Sending to OpenClaw (attempt ~a/~a): ~a" attempt max-retries message)
            ;; 调用原始发送函数
            (oc-send-message conversation-id message
                             :stream-p stream-p
                             :connection connection)
            ;; 成功，退出循环
            (return t))
        (error (c)
          (setf last-error c)
          (log-error "OpenClaw send attempt ~a failed: ~a" attempt c)
          (if (>= attempt max-retries)
              ;; 达到最大重试次数
              (progn
                (log-error "Max retries reached, falling back")
                (oc-fallback conversation-id message)
                (return nil))
              ;; 等待后重试
              (let ((delay (* (expt backoff (1- attempt)) 0.1))) ; 指数退避
                (log-info "Retrying in ~a seconds..." delay)
                (sleep delay))))))))

;;;; Phase 5: 多后端 fallback

(defvar *ai-backend-priority* '("openclaw" "openai" "claude" "local")
  "AI 后端优先级列表")

(defvar *ai-backend-status* (make-hash-table :test 'equal)
  "AI 后端状态表：backend-name -> (:status :healthy/:unhealthy :last-check timestamp)")

(defun get-available-backend (&optional (excluded-backend nil))
  "获取可用的 AI 后端"
  (let ((now (get-universal-time)))
    (loop for backend in *ai-backend-priority*
          when (and (not (equal backend excluded-backend))
                    (backend-healthy-p backend now))
          return backend)
    ;; 如果没有健康后端，返回优先级最高的
    (car *ai-backend-priority*)))

(defun backend-healthy-p (backend-name now)
  "检查后端是否健康"
  (let ((status (gethash backend-name *ai-backend-status*)))
    (if status
        (let ((status-keyword (getf status :status))
              (last-check (getf status :last-check)))
          ;; 如果最近检查过且健康，认为是健康的
          (and (eq status-keyword :healthy)
               (< (- now last-check) 300))) ; 5 分钟内
        ;; 没有状态记录，默认健康
        t)))

(defun mark-backend-status (backend-name status)
  "标记后端状态"
  (setf (gethash backend-name *ai-backend-status*)
        (list :status status
              :last-check (get-universal-time))))

(defun send-with-fallback (conversation-id message &key (backends nil) stream-p connection)
  "多后端 fallback 发送"
  (declare (type integer conversation-id)
           (type string message))
  (let ((backend-list (or backends *ai-backend-priority*)))
    (loop with success = nil
          with last-error = nil
          for backend in backend-list
          while (not success)
          do (handler-case
                 (progn
                   (log-info "Trying backend: ~a" backend)
                   ;; 切换后端并发送
                   (switch-to-backend backend)
                   (oc-send-message conversation-id message
                                    :stream-p stream-p
                                    :connection connection)
                   ;; 成功
                   (mark-backend-status backend :healthy)
                   (setf success t)
                   (log-info "Backend ~a succeeded" backend))
               (error (c)
                 (setf last-error c)
                 (log-error "Backend ~a failed: ~a" backend c)
                 (mark-backend-status backend :unhealthy)))
          finally (return success))))

(defun switch-to-backend (backend-name)
  "切换到指定后端"
  (declare (type string backend-name))
  (cond
    ((string= backend-name "openclaw")
     ;; 已经是当前后端，不需要切换
     (log-info "Using OpenClaw backend"))
    ((string= backend-name "openai")
     ;; 切换到 OpenAI
     (switch-to-openai-backend))
    ((string= backend-name "claude")
     ;; 切换到 Claude
     (switch-to-claude-backend))
    ((string= backend-name "local")
     ;; 切换到本地模型
     (switch-to-local-backend))
    (t
     (error "Unknown backend: ~a" backend-name))))

(defun switch-to-openai-backend ()
  "切换到 OpenAI 后端"
  (let ((endpoint (uiop:getenv "OPENAI_ENDPOINT"))
        (api-key (uiop:getenv "OPENAI_API_KEY")))
    (when (and endpoint api-key)
      (setf *oc-endpoint* endpoint
            *oc-api-key* api-key)
      (log-info "Switched to OpenAI backend"))))

(defun switch-to-claude-backend ()
  "切换到 Claude 后端"
  (let ((endpoint (uiop:getenv "ANTHROPIC_ENDPOINT"))
        (api-key (uiop:getenv "ANTHROPIC_API_KEY")))
    (when (and endpoint api-key)
      (setf *oc-endpoint* endpoint
            *oc-api-key* api-key)
      (log-info "Switched to Claude backend"))))

(defun switch-to-local-backend ()
  "切换到本地模型后端"
  (let ((endpoint (or (uiop:getenv "LOCAL_MODEL_ENDPOINT")
                      "http://localhost:8080")))
    (setf *oc-endpoint* endpoint
          *oc-api-key* "local-key")
    (log-info "Switched to local backend")))

;;;; 本地上下文摘要

(defun summarize-context (conversation-id max-length)
  "使用向量相似度提取关键消息，减少 Token 消耗"
  (declare (type integer conversation-id)
           (type integer max-length))
  (let* ((messages (get-history conversation-id :limit max-length))
         (key-messages (extract-key-messages messages)))
    (format nil "~{~a~^~%~%~}"
            (mapcar (lambda (m) (message-content m)) key-messages))))

(defun summarize-context-v2 (conversation-id max-length &key use-vectors-p)
  "使用向量相似度提取关键消息（增强版）"
  (declare (type integer conversation-id)
           (type integer max-length))
  (let* ((messages (get-history conversation-id :limit max-length))
         (key-messages (if use-vectors-p
                           (extract-key-messages-vector messages)
                           (extract-key-messages messages))))
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

(defun extract-key-messages-vector (messages)
  "基于向量相似度提取关键消息（简化实现）"
  (declare (type list messages))
  ;; 简化版本：使用 TF-IDF 风格的词频分析
  ;; 完整版本需要集成向量嵌入模型
  (let* ((message-words (mapcar (lambda (m)
                                  (tokenize-message (message-content m)))
                                messages))
         (word-freqs (calculate-word-frequencies message-words))
         (scored-messages (score-messages-by-importance messages word-freqs)))
    ;; 返回得分最高的消息（最多 50%）
    (let ((threshold (nth-value 1 (find-threshold scored-messages))))
      (remove-if (lambda (msg-score)
                   (< (cdr msg-score) threshold))
                 scored-messages))))

(defun tokenize-message (content)
  "将消息分词"
  (declare (type string content))
  (let ((words (remove-if-not (lambda (w)
                                (and (> (length w) 2)
                                     (not (member w +stop-words+ :test #'string=))))
                              (split-string content))))
    (mapcar #'string-downcase words)))

(defun split-string (string)
  "分割字符串为单词列表"
  (declare (type string string))
  (let ((words nil))
    (with-input-from-string (s string)
      (loop for word = (read-word s nil nil)
            while word
            do (push (princ-to-string word) words)))
    (nreverse words)))

(defun read-word (stream &optional eof-error-p eof-value)
  "从流中读取一个单词"
  (let ((word-chars nil))
    (loop for ch = (read-char stream eof-error-p eof-value)
          while (and ch (alpha-char-p ch))
          do (push ch word-chars))
    (when word-chars
      (coerce (nreverse word-chars) 'string))))

(defun calculate-word-frequencies (message-words)
  "计算词频（TF-IDF 简化版）"
  (declare (type list message-words))
  (let ((freqs (make-hash-table :test 'equal))
        (doc-count (length message-words)))
    ;; 计算每个词在多少个消息中出现
    (dolist (words message-words)
      (let ((seen-words (make-hash-table :test 'equal)))
        (dolist (word words)
          (unless (gethash word seen-words)
            (setf (gethash word seen-words) t)
            (incf (gethash word freqs 0))))))
    ;; 计算 IDF
    (maphash (lambda (word freq)
               (setf (gethash word freqs)
                     (log (/ doc-count freq))))
             freqs)
    freqs))

(defun score-messages-by-importance (messages word-freqs)
  "根据词频给消息打分"
  (declare (type list messages)
           (type hash-table word-freqs))
  (mapcar (lambda (msg)
            (let* ((words (tokenize-message (message-content msg)))
                   (score (reduce #'+ words
                                  :key (lambda (w) (gethash w word-freqs 0.1)))))
              (cons msg score)))
          messages))

(defun find-threshold (scored-messages)
  "找到合适的阈值，返回（阈值消息，阈值分数）"
  (declare (type list scored-messages))
  (let* ((sorted (sort (copy-list scored-messages) #'> :key #'cdr))
         (count (length sorted))
         (top-n (max 1 (floor count 2))))
    (if (<= count top-n)
        (values nil 0)
        (let ((top-msg (nth (1- top-n) sorted)))
          (values (car top-msg) (cdr top-msg))))))

;; 常见停用词
(defparameter +stop-words+
  '("the" "a" "an" "is" "are" "was" "were" "be" "been" "being"
    "have" "has" "had" "do" "does" "did" "will" "would" "could" "should"
    "我" "的" "了" "是" "在" "和" "有" "这" "那" "个" "你" "我" "他" "她"
    "it" "to" "for" "with" "on" "at" "from" "by" "about" "as" "into"
    "through" "during" "before" "after" "above" "below" "between"
    "and" "but" "or" "nor" "so" "yet" "both" "either" "neither"
    "not" "only" "own" "same" "than" "too" "very" "just" "also")
  "英文和中文停用词列表")

;;;; 对话历史优化

(defun optimize-conversation-history (conversation-id)
  "优化对话历史，保留关键信息"
  (declare (type integer conversation-id))
  (let* ((messages (get-history conversation-id :limit 100))
         (nodes (identify-key-dialog-nodes messages))
         (compressed (compress-redundant-dialogs messages nodes)))
    (generate-history-summary compressed)))

(defun identify-key-dialog-nodes (messages)
  "识别关键对话节点"
  (declare (type list messages))
  (let ((key-nodes nil))
    (loop for msg in messages
          for i from 0
          do (when (is-key-dialog-node-p msg messages)
               (push i key-nodes)))
    (nreverse key-nodes)))

(defun is-key-dialog-node-p (message all-messages)
  "判断是否为关键对话节点"
  (declare (type list message)
           (ignore all-messages))
  (let ((content (message-content message))
        (type (message-message-type message))
        (mentions (message-mentions message)))
    (or
     ;; 系统消息
     (eq type :system)
     ;; 包含问题
     (lispim-string-contains-p content "?")
     ;; 包含强调
     (lispim-string-contains-p content "!")
     ;; 被提及
     (not (null mentions))
     ;; 包含决策关键词
     (or (lispim-string-contains-p content "决定")
         (lispim-string-contains-p content "确认")
         (lispim-string-contains-p content "好的")
         (lispim-string-contains-p content "同意")
         (lispim-string-contains-p content "完成")))))

(defun compress-redundant-dialogs (messages key-nodes)
  "压缩冗余对话"
  (declare (type list messages)
           (type list key-nodes))
  (let ((compressed nil)
        (current-bucket nil)
        (bucket-start 0))
    (loop for msg in messages
          for i from 0
          do (if (member i key-nodes)
                 (progn
                   ;; 保存之前的桶
                   (when current-bucket
                     (push (make-dialog-bucket
                            :messages (copy-list current-bucket)
                            :start-index bucket-start
                            :is-key nil)
                           compressed))
                   ;; 开始新桶
                   (setf current-bucket (list msg))
                   (setf bucket-start i)
                   ;; 保存关键节点
                   (push (make-dialog-bucket
                          :messages (list msg)
                          :start-index i
                          :is-key t)
                         compressed))
                 (push msg current-bucket))
          finally (when current-bucket
                    (push (make-dialog-bucket
                           :messages (copy-list current-bucket)
                           :start-index bucket-start
                           :is-key nil)
                          compressed)))
    (nreverse compressed)))

(defstruct dialog-bucket
  "对话桶"
  (messages nil :type list)
  (start-index 0 :type integer)
  (is-key nil :type boolean))

(defun generate-history-summary (buckets)
  "生成历史摘要"
  (declare (type list buckets))
  (let ((summary-parts nil))
    (dolist (bucket buckets)
      (if (dialog-bucket-is-key bucket)
          ;; 关键节点保留原消息
          (push (format nil "[关键] ~a"
                        (message-content (first (dialog-bucket-messages bucket))))
                summary-parts)
          ;; 非关键桶压缩为摘要
          (let ((compressed (compress-bucket bucket)))
            (when compressed
              (push compressed summary-parts)))))
    (format nil "~{~a~^~%~}" (nreverse summary-parts))))

(defun compress-bucket (bucket)
  "压缩对话桶"
  (declare (type dialog-bucket bucket))
  (let ((messages (dialog-bucket-messages bucket)))
    (when (and messages (> (length messages) 1))
      (format nil "[对话 ~d 条] 主题：~a"
              (length messages)
              (extract-bucket-topic messages)))))

(defun extract-bucket-topic (messages)
  "提取对话桶的主题"
  (declare (type list messages))
  ;; 提取第一和最后一条消息的关键词
  (let* ((first-msg (first messages))
         (last-msg (car (last messages)))
         (first-words (tokenize-message (message-content first-msg)))
         (last-words (tokenize-message (message-content last-msg))))
    ;; 返回前几个关键词
    (format nil "~{~a~^, ~}"
            (subseq (append first-words last-words) 0 (min 5 (length (append first-words last-words)))))))

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

(defstruct oc-stream-chunk
  "流式消息块"
  (sequence 0 :type integer)      ; 块序号
  (content "" :type string)       ; 块内容
  (complete-p nil :type boolean)) ; 是否完成

(defvar *active-streams* (make-hash-table :test 'equal)
  "活跃流会话表")

(defun handle-stream-response (conversation-id response-handler &key (stream-id nil))
  "处理流式响应"
  (declare (type integer conversation-id)
           (type function response-handler))
  (let ((sid (or stream-id (write-to-string (uuid:make-v4-uuid)))))
    ;; 创建流会话
    (setf (gethash sid *active-streams*)
          (list :conversation-id conversation-id
                :chunks nil
                :sequence 0
                :started-at (get-universal-time)))

    (log-info "Starting stream response for conversation ~a (stream: ~a)"
              conversation-id sid)

    ;; 发送流式请求
    (handler-case
        (let ((request `((:type . "STREAM_REQUEST")
                         (:conversation-id . ,conversation-id)
                         (:stream-id . ,sid)
                         (:stream-p . t))))
          (let ((response (drakma:http-request (format nil "~a/chat/stream" *oc-endpoint*)
                                               :method :post
                                               :content-type "application/json"
                                               :content (cl-json:encode-json-to-string request)
                                               :additional-headers
                                               `(("Authorization" . ,(format nil "Bearer ~a" *oc-api-key*))
                                                 ("Accept" . "text/event-stream"))
                                               :keep-alive t)))
            ;; 处理 SSE 流式响应
            (process-sse-stream response response-handler sid)))
      (error (c)
        (log-error "Stream request failed: ~a" c)
        (remhash sid *active-streams*)
        ;; Fallback 到普通响应
        (oc-send-message conversation-id "流式响应失败，请稍后重试")))))

(defun process-sse-stream (response handler stream-id)
  "处理 SSE 流式响应"
  (declare (type stream response)
           (type function handler)
           (type string stream-id))
  (let ((sequence 0)
        (chunks nil)
        (buffer ""))
    (loop
      (let ((line (read-line response nil nil)))
        (when (null line)
          ;; EOF，流结束
          (let ((full-content (apply #'concatenate 'string (nreverse chunks))))
            (funcall handler full-content t) ; 完成标志
            (log-info "Stream ~a completed: ~a chunks" stream-id sequence)
            (return)))

        (cond
          ;; SSE 数据行
          ((starts-with-p line "data: ")
           (let* ((data (subseq line 6))
                  (chunk-data (cl-json:decode-json-from-string data)))
             (let ((content (getf chunk-data :content))
                   (done-p (getf chunk-data :done)))
               (when content
                 (push content chunks)
                 (incf sequence)
                 ;; 实时推送块
                 (funcall handler content nil))
               (when done-p
                 ;; 流完成
                 (let ((full-content (apply #'concatenate 'string (nreverse chunks))))
                   (funcall handler full-content t))
                 (log-info "Stream ~a completed (done flag)" stream-id)
                 (return)))))))

      (when (>= sequence 1000)
        ;; 安全限制
        (log-warn "Stream ~a exceeded 1000 chunks, stopping" stream-id)
        (return)))))

(defun stream-to-client (connection content sequence &key (complete-p nil))
  "流式推送到客户端"
  (declare (type integer connection)
           (type string content)
           (type integer sequence))
  (send-to-connection connection
    (encode-ws-message
     `(:type "AI_STREAM_CHUNK"
       :payload (:content ,content
                :sequence ,sequence
                :complete-p ,complete-p)))))

(defun handle-ai-stream-chunk (connection chunk)
  "处理 AI 流式块推送"
  (let* ((content (getf chunk :content))
         (sequence (getf chunk :sequence))
         (complete-p (getf chunk :complete-p)))
    (stream-to-client connection content sequence :complete-p complete-p)))

;;;; Token 成本详细记录

(defstruct token-record
  "Token 消耗记录"
  (timestamp 0 :type integer)
  (conversation-id 0 :type integer)
  (user-id 0 :type integer)
  (prompt-tokens 0 :type integer)
  (completion-tokens 0 :type integer)
  (total-tokens 0 :type integer)
  (cost-usd 0.0 :type float)
  (model "" :type string))

(defvar *token-records* nil
  "Token 消耗记录列表")

(defun record-token-cost-detailed (conversation-id user-id &key prompt-tokens completion-tokens model)
  "记录详细的 Token 消耗"
  (declare (type integer conversation-id user-id)
           (type integer prompt-tokens completion-tokens))
  (let* ((total (+ prompt-tokens completion-tokens))
         (cost (calculate-token-cost prompt-tokens completion-tokens model))
         (record (make-token-record
                  :timestamp (get-universal-time)
                  :conversation-id conversation-id
                  :user-id user-id
                  :prompt-tokens prompt-tokens
                  :completion-tokens completion-tokens
                  :total-tokens total
                  :cost-usd cost
                  :model (or model "gpt-4"))))
    (push record *token-records*)
    ;; 更新计数器
    (incf *oc-token-cost-counter* cost)
    (setf (gethash conversation-id *oc-token-costs*)
          (+ (gethash conversation-id *oc-token-costs* 0) cost))
    record))

(defun calculate-token-cost (prompt-tokens completion-tokens model)
  "计算 Token 成本 (USD)"
  (declare (type integer prompt-tokens completion-tokens))
  (let ((rates ' (("gpt-4" . (0.00003d0 . 0.00006d0))      ; prompt / completion
                 ("gpt-3.5-turbo" . (0.0000015d0 . 0.000002d0))
                 ("claude-3" . (0.000003d0 . 0.000015d0))
                 ("default" . (0.000002d0 . 0.000004d0)))))
    (let* ((rate (or (cdr (assoc model rates :test #'string=))
                     (cdr (assoc "default" rates))))
           (prompt-cost (* prompt-tokens (car rate)))
           (completion-cost (* completion-tokens (cdr rate))))
      (+ prompt-cost completion-cost))))

(defun get-token-cost-stats (&optional user-id)
  "获取 Token 成本统计"
  (let ((records (if user-id
                     (remove-if-not (lambda (r) (eq (token-record-user-id r) user-id))
                                    *token-records*)
                     *token-records*)))
    `((:total-cost . ,(reduce #'+ records :key #'token-record-cost-usd))
      (:total-tokens . ,(reduce #'+ records :key #'token-record-total-tokens))
      (:total-requests . ,(length records))
      (:by-model . ,(let ((model-stats (make-hash-table :test 'equal)))
                      (dolist (r records)
                        (let ((model (token-record-model r))
                              (cost (token-record-cost-usd r)))
                          (incf (gethash model model-stats 0) cost)))
                      (let ((result nil))
                        (maphash (lambda (k v) (push (cons k v) result)) model-stats)
                        result))))))

(defun starts-with-p (string prefix)
  "检查字符串是否以指定前缀开始"
  (and (>= (length string) (length prefix))
       (string= string prefix :start1 0 :end1 (length prefix))))

;;;; Phase 4: 预算告警

(defstruct budget-config
  "预算配置"
  (daily-limit 100.0 :type float)       ; 每日预算限制 (USD)
  (weekly-limit 500.0 :type float)      ; 每周预算限制
  (monthly-limit 2000.0 :type float)    ; 每月预算限制
  (alert-threshold 0.8 :type float)     ; 告警阈值 (80%)
  (enabled t :type boolean))            ; 是否启用

(defvar *budget-configs* (make-hash-table :test 'eql)
  "用户预算配置表：user-id -> budget-config")

(defvar *budget-alerts* nil
  "预算告警记录列表")

(defvar *budget-alerts-lock* (bordeaux-threads:make-lock "budget-alerts-lock")
  "预算告警锁")

(defun set-budget-config (user-id &key daily weekly monthly threshold)
  "设置用户预算配置"
  (declare (type integer user-id))
  (let ((config (make-budget-config
                 :daily-limit (or daily 100.0)
                 :weekly-limit (or weekly 500.0)
                 :monthly-limit (or monthly 2000.0)
                 :alert-threshold (or threshold 0.8))))
    (setf (gethash user-id *budget-configs*) config)
    (log-info "Set budget config for user ~a" user-id)
    config))

(defun get-budget-config (user-id)
  "获取用户预算配置"
  (gethash user-id *budget-configs*))

(defun calculate-period-cost (user-id period)
  "计算指定时间段内的成本"
  (declare (type integer user-id)
           (type (member :daily :weekly :monthly) period))
  (let* ((now (get-universal-time))
         (period-seconds (case period
                           (:daily (* 24 60 60))
                           (:weekly (* 7 24 60 60))
                           (:monthly (* 30 24 60 60))))
         (start-time (- now period-seconds))
         (records (remove-if-not (lambda (r)
                                   (and (eq (token-record-user-id r) user-id)
                                        (>= (token-record-timestamp r) start-time)))
                                 *token-records*)))
    (reduce #'+ records :key #'token-record-cost-usd :initial-value 0.0)))

(defun check-budget-alert (user-id)
  "检查预算并发送告警"
  (declare (type integer user-id))
  (let ((config (get-budget-config user-id)))
    (unless config
      (return-from check-budget-alert nil))

    (unless (budget-config-enabled config)
      (return-from check-budget-alert nil))

    (let* ((daily-cost (calculate-period-cost user-id :daily))
           (weekly-cost (calculate-period-cost user-id :weekly))
           (monthly-cost (calculate-period-cost user-id :monthly))
           (daily-ratio (/ daily-cost (budget-config-daily-limit config)))
           (weekly-ratio (/ weekly-cost (budget-config-weekly-limit config)))
           (monthly-ratio (/ monthly-cost (budget-config-monthly-limit config))))

      (let ((alerts nil))
        (when (>= daily-ratio (budget-config-alert-threshold config))
          (push (list :type :daily
                      :ratio daily-ratio
                      :cost daily-cost
                      :limit (budget-config-daily-limit config))
                alerts))
        (when (>= weekly-ratio (budget-config-alert-threshold config))
          (push (list :type :weekly
                      :ratio weekly-ratio
                      :cost weekly-cost
                      :limit (budget-config-weekly-limit config))
                alerts))
        (when (>= monthly-ratio (budget-config-alert-threshold config))
          (push (list :type :monthly
                      :ratio monthly-ratio
                      :cost monthly-cost
                      :limit (budget-config-monthly-limit config))
                alerts))

        (when alerts
          ;; 记录告警
          (bordeaux-threads:with-lock-held (*budget-alerts-lock*)
            (dolist (alert alerts)
              (let ((record (list :user-id user-id
                                  :type (getf alert :type)
                                  :ratio (getf alert :ratio)
                                  :cost (getf alert :cost)
                                  :limit (getf alert :limit)
                                  :timestamp (get-universal-time))))
                (push record *budget-alerts*)
                (log-warn "Budget alert for user ~a: ~a ~a% of ~a"
                          user-id (getf alert :type)
                          (* (getf alert :ratio) 100)
                          (getf alert :limit))))))

        alerts))))

(defun get-budget-stats (user-id)
  "获取预算统计"
  (declare (type integer user-id))
  (let ((config (get-budget-config user-id)))
    (if config
        (let ((daily-cost (calculate-period-cost user-id :daily))
              (weekly-cost (calculate-period-cost user-id :weekly))
              (monthly-cost (calculate-period-cost user-id :monthly)))
          `((:daily . (:cost ,daily-cost
                       :limit ,(budget-config-daily-limit config)
                       :remaining ,(- (budget-config-daily-limit config) daily-cost)
                       :ratio ,(/ daily-cost (budget-config-daily-limit config))))
            (:weekly . (:cost ,weekly-cost
                        :limit ,(budget-config-weekly-limit config)
                        :remaining ,(- (budget-config-weekly-limit config) weekly-cost)
                        :ratio ,(/ weekly-cost (budget-config-weekly-limit config))))
            (:monthly . (:cost ,monthly-cost
                         :limit ,(budget-config-monthly-limit config)
                         :remaining ,(- (budget-config-monthly-limit config) monthly-cost)
                         :ratio ,(/ monthly-cost (budget-config-monthly-limit config))))))
        nil)))

(defun get-budget-alerts (&optional user-id)
  "获取预算告警记录"
  (declare (type (or null integer) user-id))
  (bordeaux-threads:with-lock-held (*budget-alerts-lock*)
    (if user-id
        (remove-if-not (lambda (r) (eq (getf r :user-id) user-id)) *budget-alerts*)
        *budget-alerts*)))

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
