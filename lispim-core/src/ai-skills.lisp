;;;; ai-skills.lisp - AI 技能插件框架
;;;;
;;;; 提供类似 Telegram Bot 的技能扩展机制
;;;; 支持内置技能和插件式技能

(in-package :lispim-core)

;;;; 依赖声明

(eval-when (:compile-toplevel :load-toplevel :execute)
  (ql:quickload '(:cl-json :bordeaux-threads :uuid)))

;;;; AI 技能数据结构

(defstruct ai-skill
  "AI 技能定义"
  (name "" :type string)                  ; 技能唯一标识
  (label "" :type string)                 ; 显示名称
  (description "" :type string)           ; 技能描述
  (handler nil :type function)            ; 技能处理函数
  (parameters nil :type list)             ; 参数定义
  (requires-auth nil :type boolean)       ; 是否需要认证
  (rate-limit 60 :type integer)           ; 速率限制（次/分钟）
  (enabled t :type boolean)               ; 是否启用
  (category "general" :type string))      ; 技能分类

(defstruct ai-skill-context
  "AI 技能执行上下文"
  (user-id nil :type (or null integer))
  (conversation-id nil :type (or null integer))
  (message-id nil :type (or null integer))
  (args nil :type list)
  (kwargs nil :type hash-table))

;;;; 全局技能注册表

(defvar *ai-skills* (make-hash-table :test 'equal)
  "AI 技能注册表：skill-name -> ai-skill")

(defvar *ai-skills-lock* (bordeaux-threads:make-lock "ai-skills-lock")
  "AI 技能注册表锁")

(defvar *ai-skill-rate-limits* (make-hash-table :test 'equal)
  "AI 技能速率限制表：user-id -> (skill-name . last-call-time)")

;;;; 技能注册

(defun register-ai-skill (name handler &key label description parameters
                               requires-auth rate-limit category)
  "注册 AI 技能"
  (let ((skill (make-ai-skill
                :name name
                :label (or label name)
                :description (or description "")
                :handler handler
                :parameters (or parameters '())
                :requires-auth (or requires-auth nil)
                :rate-limit (or rate-limit 60)
                :category (or category "general"))))
    (bordeaux-threads:with-lock-held (*ai-skills-lock*)
      (setf (gethash name *ai-skills*) skill))
    (log-info "Registered AI skill: ~a" name)
    skill))

(defun unregister-ai-skill (name)
  "注销 AI 技能"
  (bordeaux-threads:with-lock-held (*ai-skills-lock*)
    (remhash name *ai-skills*)
    (log-info "Unregistered AI skill: ~a" name)))

(defun get-ai-skill (name)
  "获取 AI 技能"
  (gethash name *ai-skills*))

(defun list-ai-skills (&optional category)
  "列出所有 AI 技能"
  (let ((result nil))
    (bordeaux-threads:with-lock-held (*ai-skills-lock*)
      (maphash (lambda (name skill)
                 (when (or (null category)
                           (string= (ai-skill-category skill) category))
                   (push (list :name name
                               :label (ai-skill-label skill)
                               :description (ai-skill-description skill)
                               :parameters (ai-skill-parameters skill)
                               :category (ai-skill-category skill))
                         result)))
               *ai-skills*))
    result))

;;;; 技能执行

(defun execute-ai-skill (skill-name user-id &rest args &key conversation-id message-id)
  "执行 AI 技能"
  (let ((skill (get-ai-skill skill-name)))
    (unless skill
      (error "AI skill not found: ~a" skill-name))

    (unless (ai-skill-enabled skill)
      (error "AI skill disabled: ~a" skill-name))

    ;; 速率限制检查
    (unless (check-skill-rate-limit skill-name user-id (ai-skill-rate-limit skill))
      (error "AI skill rate limit exceeded: ~a" skill-name))

    ;; 创建上下文
    (let ((context (make-ai-skill-context
                    :user-id user-id
                    :conversation-id conversation-id
                    :message-id message-id
                    :args args
                    :kwargs (make-hash-table :test 'equal))))
      ;; 执行技能
      (funcall (ai-skill-handler skill) context))))

;;;; 速率限制

(defun check-skill-rate-limit (skill-name user-id limit)
  "检查技能速率限制"
  (let* ((key (format nil "~a:~a" user-id skill-name))
         (now (get-universal-time))
         (last-call (gethash key *ai-skill-rate-limits* 0)))
    (if (< (- now last-call) (/ limit 60.0))
        nil
        (progn
          (setf (gethash key *ai-skill-rate-limits*) now)
          t))))

;;;; 内置技能

;;;;; 天气查询技能

(defun skill-weather-handler (context)
  "天气查询技能"
  (let* ((args (ai-skill-context-args context))
         (city (or (car args) "北京")))
    ;; 实际实现应调用天气 API
    (list :success t
          :data (format nil "~a 今天晴朗，温度 25°C，空气质量优" city)
          :metadata (:source "weather-api"))))

(register-ai-skill
 "weather"
 #'skill-weather-handler
 :label "天气查询"
 :description "查询指定城市的天气情况"
 :parameters '((:name "city" :type "string" :required t :description "城市名称"))
 :category "utility")

;;;;; 翻译技能

(defun skill-translate-handler (context)
  "翻译技能"
  (let* ((args (ai-skill-context-args context))
         (text (getf args :text))
         (target-lang (getf args :target-lang "zh")))
    ;; 调用翻译服务
    (let ((translation (translate-text text :target target-lang)))
      (list :success t
            :data translation
            :metadata (:source "translation-service")))))

(register-ai-skill
 "translate"
 #'skill-translate-handler
 :label "翻译"
 :description "翻译文本到指定语言"
 :parameters '((:name "text" :type "string" :required t :description "要翻译的文本")
               (:name "target-lang" :type "string" :required nil :description "目标语言"))
 :category "utility")

;;;;; 摘要技能

(defun skill-summarize-handler (context)
  "摘要技能"
  (let* ((args (ai-skill-context-args context))
         (conversation-id (ai-skill-context-conversation-id context))
         (messages (get-history conversation-id :limit 50)))
    (let ((summary (summarize-conversation messages)))
      (list :success t
            :data summary
            :metadata (:source "summarization-service")))))

(register-ai-skill
 "summarize"
 #'skill-summarize-handler
 :label "对话摘要"
 :description "总结对话内容"
 :parameters '()
 :category "productivity")

;;;;; 代码执行技能

(defun skill-code-handler (context)
  "代码执行技能"
  (let* ((args (ai-skill-context-args context))
         (language (getf args :language "python"))
         (code (getf args :code)))
    ;; 沙箱执行代码
    (handler-case
        (let ((result (execute-code-in-sandbox language code)))
          (list :success t
                :data result
                :metadata (:language language)))
      (error (c)
        (list :success nil
              :error (format nil "代码执行失败：~a" c))))))

(register-ai-skill
 "code"
 #'skill-code-handler
 :label "代码执行"
 :description "执行指定编程语言的代码"
 :parameters '((:name "language" :type "string" :required t :description "编程语言")
               (:name "code" :type "string" :required t :description "要执行的代码"))
 :category "developer")

;;;;; 加密货币价格技能

(defun skill-crypto-handler (context)
  "加密货币价格查询技能"
  (let* ((args (ai-skill-context-args context))
         (symbol (or (car args) "BTC")))
    ;; 调用价格 API
    (let ((price (get-crypto-price symbol)))
      (list :success t
            :data (format nil "~a 当前价格：$~,2f" symbol price)
            :metadata (:symbol symbol :price price)))))

(register-ai-skill
 "crypto"
 #'skill-crypto-handler
 :label "加密货币价格"
 :description "查询加密货币的实时价格"
 :parameters '((:name "symbol" :type "string" :required t :description "加密货币符号"))
 :category "finance")

;;;;; 搜索技能

(defun skill-search-handler (context)
  "搜索技能"
  (let* ((args (ai-skill-context-args context))
         (query (getf args :query)))
    ;; 调用搜索 API
    (let ((results (search-web query)))
      (list :success t
            :data results
            :metadata (:query query :count (length results))))))

(register-ai-skill
 "search"
 #'skill-search-handler
 :label "网络搜索"
 :description "搜索网络信息"
 :parameters '((:name "query" :type "string" :required t :description "搜索关键词"))
 :category "utility")

;;;;; 提醒技能

(defun skill-reminder-handler (context)
  "提醒技能"
  (let* ((args (ai-skill-context-args context))
         (user-id (ai-skill-context-user-id context))
         (message (getf args :message))
         (delay (getf args :delay 60)))
    ;; 创建定时提醒
    (schedule-reminder user-id message delay)
    (list :success t
          :data (format nil "已设置提醒，~a 秒后提醒你：~a" delay message)
          :metadata (:delay delay :message message))))

(register-ai-skill
 "reminder"
 #'skill-reminder-handler
 :label "提醒"
 :description "设置定时提醒"
 :parameters '((:name "message" :type "string" :required t :description "提醒内容")
               (:name "delay" :type "integer" :required nil :description "延迟秒数"))
 :category "productivity")

;;;;; 增强的翻译技能

(defun skill-translate-full-handler (context)
  "完整翻译技能"
  (let* ((args (ai-skill-context-args context))
         (text (getf args :text))
         (source-lang (getf args :source-lang "auto"))
         (target-lang (getf args :target-lang "zh")))
    (handler-case
        (let ((translation (translate-text text :target target-lang :source source-lang)))
          (list :success t
                :data translation
                :metadata (:source-lang source-lang
                          :target-lang target-lang
                          :source "openclaw-translate")))
      (error (c)
        (list :success nil
              :error (format nil "翻译失败：~a" c))))))

(register-ai-skill
 "translate-full"
 #'skill-translate-full-handler
 :label "翻译（完整）"
 :description "多语言翻译支持"
 :parameters '((:name "text" :type "string" :required t :description "要翻译的文本")
               (:name "source-lang" :type "string" :required nil :description "源语言")
               (:name "target-lang" :type "string" :required nil :description "目标语言"))
 :category "utility")

;;;;; 增强的摘要技能

(defun skill-summarize-full-handler (context)
  "完整摘要技能"
  (let* ((args (ai-skill-context-args context))
         (conversation-id (ai-skill-context-conversation-id context))
         (text (getf args :text))
         (max-length (getf args :max-length 200)))
    (handler-case
        (let ((summary (if text
                          ;; 摘要单条文本
                          (subseq text 0 (min (length text) max-length))
                          ;; 摘要对话
                          (let ((messages (get-history conversation-id :limit 50)))
                            (summarize-conversation messages)))))
          (list :success t
                :data summary
                :metadata (:source "summarize-service"
                          :length (length summary))))
      (error (c)
        (list :success nil
              :error (format nil "摘要失败：~a" c))))))

(register-ai-skill
 "summarize-full"
 #'skill-summarize-full-handler
 :label "摘要（完整）"
 :description "总结对话或文章内容"
 :parameters '((:name "text" :type "string" :required nil :description "要摘要的文本")
               (:name "max-length" :type "integer" :required nil :description "最大长度"))
 :category "productivity")

;;;;; 实体提取技能

(defun skill-extract-handler (context)
  "实体提取技能"
  (let* ((args (ai-skill-context-args context))
         (text (getf args :text))
         (entity-type (getf args :type "all")))
    (handler-case
        (let ((entities (extract-entities text entity-type)))
          (list :success t
                :data entities
                :metadata (:type entity-type
                          :count (length entities))))
      (error (c)
        (list :success nil
              :error (format nil "提取失败：~a" c))))))

(register-ai-skill
 "extract"
 #'skill-extract-handler
 :label "实体提取"
 :description "提取文本中的关键实体（URL、邮箱、提及等）"
 :parameters '((:name "text" :type "string" :required t :description "要分析的文本")
               (:name "type" :type "string" :required nil :description "实体类型"))
 :category "utility")

;;;;; 代码审查技能

(defun skill-code-review-handler (context)
  "代码审查技能"
  (let* ((args (ai-skill-context-args context))
         (code (getf args :code))
         (language (getf args :language "common-lisp")))
    (handler-case
        (let ((issues (analyze-code code language))
              (report (generate-code-review issues)))
          (list :success t
                :data report
                :metadata (:language language
                          :issues-count (length issues))))
      (error (c)
        (list :success nil
              :error (format nil "代码审查失败：~a" c))))))

(register-ai-skill
 "code-review"
 #'skill-code-review-handler
 :label "代码审查"
 :description "分析代码质量并提供改进建议"
 :parameters '((:name "code" :type "string" :required t :description "要审查的代码")
               (:name "language" :type "string" :required nil :description "编程语言"))
 :category "developer")

;;;; WebSocket 消息处理

(defun handle-ai-skill-message (conn message)
  "处理 AI 技能相关的 WebSocket 消息"
  (let* ((user-id (get-connection-user-id conn))
         (msg-type (getf message :type)))
    (cond
      ((string= msg-type "AI_SKILL_LIST")
       ;; 列出所有技能
       (let ((category (getf message :category)))
         (send-to-connection conn (encode-ws-message
                                   (list :type "AI_SKILL_LIST_RESPONSE"
                                         :payload (list :skills (list-ai-skills category)))))))

      ((string= msg-type "AI_SKILL_EXECUTE")
       ;; 执行技能
       (let ((payload (getf message :payload))
             (skill-name (getf payload :skill))
             (args (getf payload :args))
             (conversation-id (getf payload :conversation-id)))
         (handler-case
             (let ((result (apply #'execute-ai-skill
                                  skill-name user-id
                                  :conversation-id conversation-id
                                  args)))
               (send-to-connection conn (encode-ws-message
                                         (list :type "AI_SKILL_RESULT"
                                               :payload result))))
           (error (c)
             (send-to-connection conn (encode-ws-message
                                       (list :type "AI_SKILL_ERROR"
                                             :payload (list :error (princ-to-string c)))))))))

      ((string= msg-type "AI_SKILL_ENABLE")
       ;; 启用技能
       (let ((skill-name (getf message :skill-name)))
         (let ((skill (get-ai-skill skill-name)))
           (when skill
             (setf (ai-skill-enabled skill) t)
             (send-to-connection conn (encode-ws-message
                                       (list :type "AI_SKILL_ENABLED"
                                             :payload (list :name skill-name))))))))

      ((string= msg-type "AI_SKILL_DISABLE")
       ;; 禁用技能
       (let ((skill-name (getf message :skill-name)))
         (let ((skill (get-ai-skill skill-name)))
           (when skill
             (setf (ai-skill-enabled skill) nil)
             (send-to-connection conn (encode-ws-message
                                       (list :type "AI_SKILL_DISABLED"
                                             :payload (list :name skill-name))))))))

      (t
       (log-debug "Unknown AI skill message type: ~a" msg-type)))))

;;;; 辅助函数

(defun summarize-conversation (messages)
  "总结对话内容"
  (let ((key-points (extract-key-points messages)))
    (format nil "对话摘要：~{~a~^; ~}" key-points)))

(defun extract-key-points (messages)
  "提取对话要点"
  (mapcar (lambda (m) (message-content m))
          (remove-if (lambda (m)
                       (or (< (length (message-content m)) 10)
                           (string-prefix-p "/" (message-content m))))
                     messages)))

(defun translate-text (text &key target source)
  "翻译文本"
  (declare (type string text)
           (type string target)
           (type (or null string) source))
  ;; 调用 OpenClaw 翻译 API
  (handler-case
      (let ((request `((:text . ,text)
                       (:target . ,target)
                       (:source . ,(or source "auto")))))
        ;; 实际应调用翻译服务
        (format nil "[翻译~a] ~a" target text))
    (error (c)
      (log-error "Translation failed: ~a" c)
      (format nil "翻译失败：~a" c))))

(defun extract-entities (text &optional entity-type)
  "提取文本中的实体"
  (declare (type string text)
           (type (or null string) entity-type))
  ;; 使用 NLP 技术提取实体
  (let ((entities nil))
    ;; 简化实现：提取 URL、邮箱、提及等
    (when (lispim-string-contains-p text "http")
      (push '(:type "url" :value "URL 链接") entities))
    (when (lispim-string-contains-p text "@")
      (push '(:type "mention" :value "用户提及") entities))
    (when (lispim-string-contains-p text "#")
      (push '(:type "hashtag" :value "话题标签") entities))
    entities))

(defun analyze-code (code language)
  "分析代码质量"
  (declare (type string code)
           (type string language))
  ;; 代码分析实现
  (let ((issues nil))
    ;; 简化实现
    (when (> (length code) 1000)
      (push '(:severity :warning :message "代码过长，建议拆分") issues))
    (when (and (string= language "common-lisp")
               (lispim-string-contains-p code "eval"))
      (push '(:severity :critical :message "避免使用 eval") issues))
    issues))

(defun generate-code-review (issues)
  "生成代码审查报告"
  (declare (type list issues))
  (if (null issues)
      "代码质量良好，未发现明显问题。"
      (format nil "发现 ~d 个问题：~{~%  - ~a~}"
              (length issues)
              (mapcar (lambda (i)
                        (format nil "[~a] ~a"
                                (getf i :severity)
                                (getf i :message)))
                      issues))))

(defun execute-code-in-sandbox (language code)
  "在沙箱中执行代码"
  ;; 简化实现，实际应使用安全的沙箱环境
  (declare (ignore language code))
  "代码执行结果")

(defun get-crypto-price (symbol)
  "获取加密货币价格"
  ;; 简化实现，实际应调用 API
  (declare (ignore symbol))
  50000.0)

(defun search-web (query)
  "搜索网络"
  ;; 简化实现
  (declare (ignore query))
  '("结果 1" "结果 2" "结果 3"))

(defun schedule-reminder (user-id message delay)
  "设置提醒"
  (bordeaux-threads:make-thread
   (lambda ()
     (sleep delay)
     (send-notification user-id "提醒" message))
   :name (format nil "reminder-thread-~a" user-id)))

(defun send-notification (user-id title content)
  "发送通知"
  (let ((connections (get-user-connections user-id)))
    (dolist (conn connections)
      (send-to-connection conn (encode-ws-message
                                (list :type "NOTIFICATION"
                                      :title title
                                      :content content))))))

;;;; 初始化

(defun init-ai-skills-system ()
  "初始化 AI 技能系统"
  (log-info "Initializing AI skills system...")
  ;; 内置技能已在注册时初始化
  (log-info "AI skills system initialized"))

;;;; 结束
