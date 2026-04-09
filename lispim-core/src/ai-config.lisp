;;;; ai-config.lisp - AI 助手配置管理
;;;;
;;;; 提供类似 Telegram 的 AI 助手配置功能
;;;; 支持多 AI 后端、人设选择、上下文长度配置等

(in-package :lispim-core)

;;;; 依赖声明

(eval-when (:compile-toplevel :load-toplevel :execute)
  (ql:quickload '(:cl-json :bordeaux-threads :uuid)))

;;;; AI 配置数据结构

(defstruct ai-config
  "AI 助手配置（增强版）"
  (enabled nil :type boolean)                 ; 是否启用 AI
  (backend "openclaw" :type string)           ; AI 后端：openclaw, openai, claude, local
  (model "gpt-4" :type string)                ; 模型选择
  (personality "assistant" :type string)      ; 人设：assistant, creative, precise, friendly
  (context-length 4096 :type integer)         ; 上下文长度
  (rate-limit 60 :type integer)               ; 每分钟请求限制
  (max-tokens 2048 :type integer)             ; 最大生成 token 数
  (temperature 0.7 :type float)               ; 温度参数
  (system-prompt "" :type string)             ; 自定义系统提示
  (auto-summarize nil :type boolean)          ; 自动总结长对话
  (language "zh-CN" :type string)             ; 默认语言
  (streaming-p t :type boolean)               ; 启用流式响应
  (skills nil :type list)                     ; 启用的技能列表
  (budget-limit 100.0 :type float)            ; 每月预算限制 (USD)
  (auto-retry-p t :type boolean)              ; 自动重试失败请求
  (fallback-backend "local" :type string)    ; Fallback 后端
  (routing-rules nil :type list))             ; 消息路由规则

(defstruct ai-backend-config
  "AI 后端配置"
  (name "openclaw" :type string)
  (endpoint "" :type string)
  (api-key "" :type string)
  (models nil :type list)
  (capabilities nil :type list)
  (rate-limit 60 :type integer))

;;;; 全局配置存储

(defvar *ai-configs* (make-hash-table :test 'eql)
  "用户 AI 配置表：user-id -> ai-config")

(defvar *ai-configs-lock* (bordeaux-threads:make-lock "ai-configs-lock")
  "AI 配置表锁")

(defvar *ai-backend-configs* (make-hash-table :test 'equal)
  "AI 后端配置表：backend-name -> ai-backend-config")

;;;; 默认 AI 配置

(defparameter *default-ai-config*
  (make-ai-config
   :enabled nil
   :backend "openclaw"
   :model "gpt-4"
   :personality "assistant"
   :context-length 4096
   :rate-limit 60
   :max-tokens 2048
   :temperature 0.7
   :system-prompt ""
   :auto-summarize t
   :language "zh-CN")
  "默认 AI 配置")

;;;; AI 人设定义

(defparameter *ai-personalities*
  '((:assistant . "你是一个有用的 AI 助手，擅长解答各种问题并提供实用建议。")
    (:creative . "你是一个富有创造力的 AI 助手，擅长写作、头脑风暴和创意生成。")
    (:precise . "你是一个严谨的 AI 助手，回答精确、简洁，注重事实和数据。")
    (:friendly . "你是一个友好的 AI 助手，语气亲切，善于倾听和鼓励。")
    (:teacher . "你是一个耐心的 AI 老师，擅长解释复杂概念并引导学习。")
    (:coder . "你是一个专业的 AI 程序员，擅长代码编写、调试和架构设计。"))
  "AI 人设列表")

;;;; 配置管理函数

(defun get-user-ai-config (user-id)
  "获取用户 AI 配置"
  (declare (type integer user-id))
  (bordeaux-threads:with-lock-held (*ai-configs-lock*)
    (or (gethash user-id *ai-configs*)
        *default-ai-config*)))

(defun set-user-ai-config (user-id config)
  "设置用户 AI 配置"
  (declare (type integer user-id)
           (type ai-config config))
  (bordeaux-threads:with-lock-held (*ai-configs-lock*)
    (setf (gethash user-id *ai-configs*) config)
    ;; 持久化到 Redis
    (save-ai-config-to-redis user-id config)))

(defun update-ai-config (user-id &key (enabled nil enabled-p) (backend nil backend-p) (model nil model-p) (personality nil personality-p)
                                (context-length nil context-length-p) (rate-limit nil rate-limit-p) (max-tokens nil max-tokens-p)
                                (temperature nil temperature-p) (system-prompt nil system-prompt-p) (auto-summarize nil auto-summarize-p)
                                (language nil language-p) (streaming-p nil streaming-p-p) (skills nil skills-p)
                                (budget-limit nil budget-limit-p) (auto-retry-p nil auto-retry-p-p)
                                (fallback-backend nil fallback-backend-p) (routing-rules nil routing-rules-p))
  "更新 AI 配置（部分字段）"
  (let ((config (get-user-ai-config user-id)))
    (when enabled-p (setf (ai-config-enabled config) enabled))
    (when backend-p (setf (ai-config-backend config) backend))
    (when model-p (setf (ai-config-model config) model))
    (when personality-p (setf (ai-config-personality config) personality))
    (when context-length-p (setf (ai-config-context-length config) context-length))
    (when rate-limit-p (setf (ai-config-rate-limit config) rate-limit))
    (when max-tokens-p (setf (ai-config-max-tokens config) max-tokens))
    (when temperature-p (setf (ai-config-temperature config) temperature))
    (when system-prompt-p (setf (ai-config-system-prompt config) system-prompt))
    (when auto-summarize-p (setf (ai-config-auto-summarize config) auto-summarize))
    (when language-p (setf (ai-config-language config) language))
    (when streaming-p-p (setf (ai-config-streaming-p config) streaming-p))
    (when skills-p (setf (ai-config-skills config) skills))
    (when budget-limit-p (setf (ai-config-budget-limit config) budget-limit))
    (when auto-retry-p-p (setf (ai-config-auto-retry-p config) auto-retry-p))
    (when fallback-backend-p (setf (ai-config-fallback-backend config) fallback-backend))
    (when routing-rules-p (setf (ai-config-routing-rules config) routing-rules))
    (set-user-ai-config user-id config)
    config))

(defun enable-user-ai (user-id)
  "启用用户 AI"
  (update-ai-config user-id :enabled t))

(defun disable-user-ai (user-id)
  "禁用用户 AI"
  (update-ai-config user-id :enabled nil))

;;;; Redis 持久化

(defun save-ai-config-to-redis (user-id config)
  "保存 AI 配置到 Redis"
  (let ((json (cl-json:encode-json-to-string
               `((:enabled . ,(ai-config-enabled config))
                 (:backend . ,(ai-config-backend config))
                 (:model . ,(ai-config-model config))
                 (:personality . ,(ai-config-personality config))
                 (:context-length . ,(ai-config-context-length config))
                 (:rate-limit . ,(ai-config-rate-limit config))
                 (:max-tokens . ,(ai-config-max-tokens config))
                 (:temperature . ,(ai-config-temperature config))
                 (:system-prompt . ,(ai-config-system-prompt config))
                 (:auto-summarize . ,(ai-config-auto-summarize config))
                 (:language . ,(ai-config-language config))))))
    (redis:red-set (format nil "lispim:ai-config:~a" user-id) json)))

(defun load-ai-config-from-redis (user-id)
  "从 Redis 加载 AI 配置"
  (let ((json (redis:red-get (format nil "lispim:ai-config:~a" user-id))))
    (when json
      (let* ((data (cl-json:decode-json-from-string json))
             ;; Convert alist format from JSON to property list
             (plist (list :enabled (cdr (assoc :enabled data))
                          :backend (cdr (assoc :backend data))
                          :model (cdr (assoc :model data))
                          :personality (cdr (assoc :personality data))
                          :context-length (cdr (assoc :context-length data))
                          :rate-limit (cdr (assoc :rate-limit data))
                          :max-tokens (cdr (assoc :max-tokens data))
                          :temperature (cdr (assoc :temperature data))
                          :system-prompt (cdr (assoc :system-prompt data))
                          :auto-summarize (cdr (assoc :auto-summarize data))
                          :language (cdr (assoc :language data))))
             (config (make-ai-config
                      :enabled (or (getf plist :enabled) nil)
                      :backend (or (getf plist :backend) "openclaw")
                      :model (or (getf plist :model) "gpt-4")
                      :personality (or (getf plist :personality) "assistant")
                      :context-length (or (getf plist :context-length) 4096)
                      :rate-limit (or (getf plist :rate-limit) 60)
                      :max-tokens (or (getf plist :max-tokens) 2048)
                      :temperature (or (getf plist :temperature) 0.7)
                      :system-prompt (or (getf plist :system-prompt) "")
                      :auto-summarize (or (getf plist :auto-summarize) t)
                      :language (or (getf plist :language) "zh-CN"))))
        (bordeaux-threads:with-lock-held (*ai-configs-lock*)
          (setf (gethash user-id *ai-configs*) config))
        config))))

;;;; AI 后端管理

(defun register-ai-backend (name endpoint api-key &key models capabilities rate-limit)
  "注册 AI 后端"
  (let ((backend (make-ai-backend-config
                  :name name
                  :endpoint endpoint
                  :api-key api-key
                  :models (or models '())
                  :capabilities (or capabilities '())
                  :rate-limit (or rate-limit 60))))
    (setf (gethash name *ai-backend-configs*) backend)
    (log-info "Registered AI backend: ~a" name)))

(defun get-ai-backend (name)
  "获取 AI 后端配置"
  (gethash name *ai-backend-configs*))

(defun list-ai-backends ()
  "列出所有 AI 后端"
  (let ((result nil))
    (maphash (lambda (name backend)
               (push (list :name name
                           :endpoint (ai-backend-config-endpoint backend)
                           :models (ai-backend-config-models backend)
                           :capabilities (ai-backend-config-capabilities backend))
                     result))
             *ai-backend-configs*)
    result))

;;;; WebSocket 消息处理（增强版）

(defun handle-ai-config-message (c m)
  "处理 AI 配置相关的 WebSocket 消息（增强版）"
  (let* ((uid (get-connection-user-id c))
         (msg-type (getf m :type)))
    (cond
      ((string= msg-type "AI_CONFIG_GET")
       ;; 获取 AI 配置
       (let ((config (get-user-ai-config uid)))
         (send-to-connection c (encode-ws-message
                                   (list :type "AI_CONFIG_RESPONSE"
                                         :payload (list :config (ai-config-to-alist config)))))))

      ((string= msg-type "AI_CONFIG_UPDATE")
       ;; 更新 AI 配置
       (let ((payload (getf m :payload)))
         (handler-case
             (let ((config (update-ai-config
                            uid
                            :enabled (getf payload :enabled)
                            :backend (getf payload :backend)
                            :model (getf payload :model)
                            :personality (getf payload :personality)
                            :context-length (getf payload :context-length)
                            :rate-limit (getf payload :rate-limit)
                            :streaming-p (getf payload :streaming-p)
                            :skills (getf payload :skills)
                            :budget-limit (getf payload :budget-limit)
                            :auto-retry-p (getf payload :auto-retry-p)
                            :fallback-backend (getf payload :fallback-backend))))
               (send-to-connection c (encode-ws-message
                                         (list :type "AI_CONFIG_UPDATED"
                                               :payload (list :config (ai-config-to-alist config))))))
           (error (e)
             (send-to-connection c (encode-ws-message
                                       (list :type "ERROR"
                                             :payload (list :message (princ-to-string e)))))))))

      ((string= msg-type "AI_ENABLE")
       ;; 启用 AI
       (enable-user-ai uid)
       (send-to-connection c (encode-ws-message
                                 (list :type "AI_ENABLED"))))

      ((string= msg-type "AI_DISABLE")
       ;; 禁用 AI
       (disable-user-ai uid)
       (send-to-connection c (encode-ws-message
                                 (list :type "AI_DISABLED"))))

      ((string= msg-type "AI_BACKENDS_LIST")
       ;; 列出 AI 后端
       (send-to-connection c (encode-ws-message
                                 (list :type "AI_BACKENDS_RESPONSE"
                                       :payload (list :backends (list-ai-backends))))))

      ((string= msg-type "AI_PERSONALITIES_LIST")
       ;; 列出 AI 人设
       (send-to-connection c (encode-ws-message
                                 (list :type "AI_PERSONALITIES_RESPONSE"
                                       :payload (list :personalities
                                                      (mapcar (lambda (p)
                                                                (list :id (car p)
                                                                      :label (cdr p)
                                                                      :prompt (cdr p)))
                                                              *ai-personalities*))))))

      ((string= msg-type "AI_SKILLS_LIST")
       ;; 列出 AI 技能
       (send-to-connection c (encode-ws-message
                                 (list :type "AI_SKILLS_RESPONSE"
                                       :payload (list :skills (list-ai-skills))))))

      ((string= msg-type "AI_BUDGET_GET")
       ;; 获取预算统计
       (let ((stats (get-budget-stats uid)))
         (send-to-connection c (encode-ws-message
                                   (list :type "AI_BUDGET_RESPONSE"
                                         :payload (list :stats stats))))))

      ((string= msg-type "AI_BUDGET_SET")
       ;; 设置预算
       (let ((payload (getf m :payload)))
         (handler-case
             (progn
               (set-budget-config uid
                                  :daily (getf payload :daily)
                                  :weekly (getf payload :weekly)
                                  :monthly (getf payload :monthly)
                                  :threshold (getf payload :threshold))
               (send-to-connection c (encode-ws-message
                                         (list :type "AI_BUDGET_UPDATED"
                                               :payload (list :success t)))))
           (error (e)
             (send-to-connection c (encode-ws-message
                                       (list :type "ERROR"
                                             :payload (list :message (princ-to-string e)))))))))

      ((string= msg-type "AI_CHAT")
       ;; 发送 AI 聊天请求
       (let ((payload (getf m :payload)))
         (handler-case
             (let* ((conversation-id (getf payload :conversation-id))
                    (msg-text (getf payload :message))
                    (stream-p (getf payload :stream-p)))
               (handle-ai-auto-reply conversation-id msg-text
                                     :stream-p stream-p
                                     :connection c))
           (error (e)
             (send-to-connection c (encode-ws-message
                                       (list :type "ERROR"
                                             :payload (list :message (princ-to-string e)))))))))

      (t
       (log-debug "Unknown AI config message type: ~a" msg-type)))

;;;; AI 配置转换为 alist

(defun ai-config-to-alist (config)
  "将 AI 配置转换为 alist 以便 JSON 序列化"
  (list :enabled (ai-config-enabled config)
        :backend (ai-config-backend config)
        :model (ai-config-model config)
        :personality (ai-config-personality config)
        :context-length (ai-config-context-length config)
        :rate-limit (ai-config-rate-limit config)
        :max-tokens (ai-config-max-tokens config)
        :temperature (ai-config-temperature config)
        :system-prompt (ai-config-system-prompt config)
        :auto-summarize (ai-config-auto-summarize config)
        :language (ai-config-language config)
        :streaming-p (ai-config-streaming-p config)
        :skills (ai-config-skills config)
        :budget-limit (ai-config-budget-limit config)
        :auto-retry-p (ai-config-auto-retry-p config)
        :fallback-backend (ai-config-fallback-backend config)
        :routing-rules (ai-config-routing-rules config)))

;;;; AI 技能管理

(defparameter *ai-skills*
  '((:summarize . "总结对话内容")
    (:translate . "翻译消息")
    (:explain . "解释概念")
    (:code-review . "代码审查")
    (:debug . "调试帮助")
    (:brainstorm . "头脑风暴")
    (:write . "写作辅助")
    (:search . "信息搜索"))
  "AI 技能列表")

(defun list-ai-skills ()
  "列出所有可用的 AI 技能"
  (mapcar (lambda (skill)
            (list :id (car skill)
                  :name (car skill)
                  :description (cdr skill)))
          *ai-skills*))

(defun enable-ai-skill (user-id skill)
  "启用 AI 技能"
  (let ((config (get-user-ai-config user-id)))
    (unless (member skill (ai-config-skills config))
      (update-ai-config user-id :skills (append (ai-config-skills config) (list skill))))
    t))

(defun disable-ai-skill (user-id skill)
  "禁用 AI 技能"
  (let ((config (get-user-ai-config user-id)))
    (update-ai-config user-id :skills (remove skill (ai-config-skills config)))
    t))

;;;; 系统命令（增强版）

(defun define-ai-commands ()
  "定义 AI 相关命令（增强版）"
  ;; /ai enable - 启用 AI
  (register-command "/ai enable"
                    (lambda (conn args)
                      (declare (ignore args))
                      (let ((user-id (get-connection-user-id conn)))
                        (enable-user-ai user-id)
                        (send-to-connection conn (encode-ws-message
                                                  (list :type "NOTIFICATION"
                                                        :content "AI 已启用"))))))

  ;; /ai disable - 禁用 AI
  (register-command "/ai disable"
                    (lambda (conn args)
                      (declare (ignore args))
                      (let ((user-id (get-connection-user-id conn)))
                        (disable-user-ai user-id)
                        (send-to-connection conn (encode-ws-message
                                                  (list :type "NOTIFICATION"
                                                        :content "AI 已禁用"))))))

  ;; /ai config - 查看 AI 配置
  (register-command "/ai config"
                    (lambda (conn args)
                      (declare (ignore args))
                      (let ((user-id (get-connection-user-id conn))
                            (config (get-user-ai-config user-id)))
                        (send-to-connection conn (encode-ws-message
                                                  (list :type "NOTIFICATION"
                                                        :content (format nil
                                                                       "AI 配置：~%启用：~a~%后端：~a~%模型：~a~%人设：~a~%上下文：~a~%流式：~a~%预算：$~a"
                                                                       (ai-config-enabled config)
                                                                       (ai-config-backend config)
                                                                       (ai-config-model config)
                                                                       (ai-config-personality config)
                                                                       (ai-config-context-length config)
                                                                       (ai-config-streaming-p config)
                                                                       (ai-config-budget-limit config))))))))

  ;; /ai model <model> - 设置模型
  (register-command "/ai model"
                    (lambda (conn args)
                      (let ((user-id (get-connection-user-id conn))
                            (model (car args)))
                        (if model
                            (progn
                              (update-ai-config user-id :model model)
                              (send-to-connection conn (encode-ws-message
                                                        (list :type "NOTIFICATION"
                                                              :content (format nil "模型已设置为：~a" model)))))
                            (send-to-connection conn (encode-ws-message
                                                      (list :type "NOTIFICATION"
                                                            :content "用法：/ai model <模型名称>")))))))

  ;; /ai personality <personality> - 设置人设
  (register-command "/ai personality"
                    (lambda (conn args)
                      (let ((user-id (get-connection-user-id conn))
                            (personality (car args)))
                        (if (find (intern (string-upcase personality) 'keyword)
                                  (mapcar #'car *ai-personalities*))
                            (progn
                              (update-ai-config user-id :personality personality)
                              (send-to-connection conn (encode-ws-message
                                                        (list :type "NOTIFICATION"
                                                              :content (format nil "人设已设置为：~a" personality)))))
                            (send-to-connection conn (encode-ws-message
                                                      (list :type "NOTIFICATION"
                                                            :content (format nil "未知人设，可选：~{~a~^, ~}"
                                                                           (mapcar #'car *ai-personalities*)))))))))

  ;; /ai context <length> - 设置上下文长度
  (register-command "/ai context"
                    (lambda (conn args)
                      (let ((user-id (get-connection-user-id conn))
                            (length (parse-integer (car args) :junk-allowed t)))
                        (if (and length (>= length 512) (<= length 32768))
                            (progn
                              (update-ai-config user-id :context-length length)
                              (send-to-connection conn (encode-ws-message
                                                        (list :type "NOTIFICATION"
                                                              :content (format nil "上下文长度已设置为：~a" length)))))
                            (send-to-connection conn (encode-ws-message
                                                      (list :type "NOTIFICATION"
                                                            :content "用法：/ai context <512-32768>")))))))

  ;; /ai skill <skill> - 启用/禁用技能
  (register-command "/ai skill"
                    (lambda (conn args)
                      (let ((user-id (get-connection-user-id conn))
                            (action (car args))
                            (skill (intern (string-upcase (cadr args)) 'keyword)))
                        (cond
                          ((string= action "enable")
                           (enable-ai-skill user-id skill)
                           (send-to-connection conn (encode-ws-message
                                                     (list :type "NOTIFICATION"
                                                           :content (format nil "技能 ~a 已启用" skill)))))
                          ((string= action "disable")
                           (disable-ai-skill user-id skill)
                           (send-to-connection conn (encode-ws-message
                                                     (list :type "NOTIFICATION"
                                                           :content (format nil "技能 ~a 已禁用" skill)))))
                          (t
                           (send-to-connection conn (encode-ws-message
                                                     (list :type "NOTIFICATION"
                                                           :content "用法：/ai skill <enable|disable> <技能名>"))))))))

  ;; /ai budget - 查看预算统计
  (register-command "/ai budget"
                    (lambda (conn args)
                      (declare (ignore args))
                      (let ((user-id (get-connection-user-id conn))
                            (stats (get-budget-stats user-id)))
                        (if stats
                            (send-to-connection conn (encode-ws-message
                                                      (list :type "NOTIFICATION"
                                                            :content (format nil "预算统计：~%今日：$~a / $~a~%本周：$~a / $~a~%本月：$~a / $~a"
                                                                           (round-to-2 (getf (getf stats :daily) :cost))
                                                                           (round-to-2 (getf (getf stats :daily) :limit))
                                                                           (round-to-2 (getf (getf stats :weekly) :cost))
                                                                           (round-to-2 (getf (getf stats :weekly) :limit))
                                                                           (round-to-2 (getf (getf stats :monthly) :cost))
                                                                           (round-to-2 (getf (getf stats :monthly) :limit))))))
                            (send-to-connection conn (encode-ws-message
                                                      (list :type "NOTIFICATION"
                                                            :content "未配置预算")))))))

  ;; /ai backends - 列出后端
  (register-command "/ai backends"
                    (lambda (conn args)
                      (declare (ignore args))
                      (let ((backends (list-ai-backends)))
                        (send-to-connection conn (encode-ws-message
                                                  (list :type "NOTIFICATION"
                                                        :content (format nil "可用后端：~{~a~^, ~}"
                                                                       (mapcar (lambda (b) (getf b :name)) backends))))))))

  ;; /ai streaming <on|off> - 启用/禁用流式响应
  (register-command "/ai streaming"
                    (lambda (conn args)
                      (let ((user-id (get-connection-user-id conn))
                            (action (car args)))
                        (cond
                          ((string= action "on")
                           (update-ai-config user-id :streaming-p t)
                           (send-to-connection conn (encode-ws-message
                                                     (list :type "NOTIFICATION"
                                                           :content "流式响应已启用"))))
                          ((string= action "off")
                           (update-ai-config user-id :streaming-p nil)
                           (send-to-connection conn (encode-ws-message
                                                     (list :type "NOTIFICATION"
                                                           :content "流式响应已禁用"))))
                          (t
                           (send-to-connection conn (encode-ws-message
                                                     (list :type "NOTIFICATION"
                                                           :content "用法：/ai streaming <on|off>"))))))))))

(defun round-to-2 (num)
  "保留两位小数"
  (/ (round (* num 100)) 100))

;;;; HTTP API 端点

;; 在 gateway.lisp 中注册这些端点
;; 需要在 gateway.lisp 中添加 require

(defvar *ai-http-handlers-initialized* nil
  "AI HTTP 处理器初始化状态")

(defun init-ai-http-handlers ()
  "初始化 AI HTTP 处理器"
  (when *ai-http-handlers-initialized*
    (return-from init-ai-http-handlers))

  ;; 注册 API 处理器到 gateway
  ;; 这些处理器将在 gateway.lisp 中定义
  (log-info "AI HTTP handlers initialized")
  (setf *ai-http-handlers-initialized* t))

;; API 响应处理器（在 gateway.lisp 中调用）
(defun api-get-ai-config-handler (user-id)
  "GET /api/v1/ai/config - 获取用户 AI 配置"
  (let ((config (get-user-ai-config user-id)))
    (make-api-response
     (ai-config-to-alist config))))

(defun api-update-ai-config-handler (user-id payload)
  "PATCH /api/v1/ai/config - 更新用户 AI 配置"
  (handler-case
      (let* ((config (update-ai-config
                      user-id
                      :enabled (getf payload :enabled)
                      :backend (getf payload :backend)
                      :model (getf payload :model)
                      :personality (getf payload :personality)
                      :context-length (getf payload :context-length)
                      :rate-limit (getf payload :rate-limit)
                      :streaming-p (getf payload :streaming-p)
                      :skills (getf payload :skills)
                      :budget-limit (getf payload :budget-limit)))
             (result (ai-config-to-alist config)))
        (make-api-response result))
    (error (c)
      (make-api-error 400 (princ-to-string c)))))

(defun api-get-ai-backends-handler ()
  "GET /api/v1/ai/backends - 获取可用 AI 后端列表"
  (make-api-response
   (list :backends (list-ai-backends)
         :personalities (mapcar (lambda (p)
                                  (list :id (car p)
                                        :name (car p)
                                        :description (cdr p)))
                                *ai-personalities*)
         :skills (list-ai-skills))))

(defun api-get-ai-budget-handler (user-id)
  "GET /api/v1/ai/budget - 获取预算统计"
  (let ((stats (get-budget-stats user-id)))
    (if stats
        (make-api-response stats)
        (make-api-error 404 "Budget not configured"))))

(defun api-update-ai-budget-handler (user-id payload)
  "PUT /api/v1/ai/budget - 更新预算配置"
  (handler-case
      (progn
        (set-budget-config user-id
                           :daily (getf payload :daily)
                           :weekly (getf payload :weekly)
                           :monthly (getf payload :monthly)
                           :threshold (getf payload :threshold))
        (make-api-response (list :success t)))
    (error (c)
      (make-api-error 400 (princ-to-string c)))))

(defun api-get-ai-stats-handler (user-id)
  "GET /api/v1/ai/stats - 获取 AI 使用统计"
  (let ((stats (get-token-cost-stats user-id)))
    (make-api-response stats)))

(defun api-chat-completions-handler (user-id payload)
  "POST /api/v1/ai/chat - 发送聊天请求（OpenAI 兼容格式）"
  (handler-case
      (let* ((messages (getf payload :messages))
             (model (getf payload :model))
             (stream-p (getf payload :stream))
             (conversation-id (or (getf payload :conversation-id)
                                  (create-temp-conversation user-id))))
        ;; 更新用户配置的模型
        (when model
          (update-ai-config user-id :model model))
        ;; 发送聊天请求
        (let ((response (process-chat-messages conversation-id messages)))
          (if stream-p
              (stream-chat-response response)
              (make-api-response response))))
    (error (c)
      (make-api-error 500 (princ-to-string c)))))

;;;; 辅助函数

;;;; AI 聊天响应

(defun send-ai-chat-request (conversation-id message &key stream-p connection)
  "发送 AI 聊天请求"
  (declare (type integer conversation-id)
           (type string message))

  ;; 检查 OpenClaw 连接状态
  (unless *oc-connected*
    (log-warn "OpenClaw not connected, using fallback")
    (oc-fallback conversation-id message)
    (return-from send-ai-chat-request))

  ;; 发送消息到 OpenClaw
  (oc-send-message conversation-id message
                   :stream-p stream-p
                   :connection connection))

(defun handle-ai-auto-reply (conversation-id user-message &key stream-p connection)
  "处理 AI 自动回复"
  (declare (type integer conversation-id)
           (type string user-message))

  (handler-case
      (send-ai-chat-request conversation-id user-message
                            :stream-p stream-p
                            :connection connection)
    (error (c)
      (log-error "AI auto-reply failed: ~a" c)
      (oc-fallback conversation-id user-message))))

(defun init-ai-chat-integration ()
  "初始化 AI 聊天集成"
  (log-info "Initializing AI chat integration...")
  ;; 确保 OpenClaw 适配器已初始化
  (unless *oc-connected*
    (let ((endpoint (uiop:getenv "OPENCLAW_ENDPOINT"))
          (api-key (uiop:getenv "OPENCLAW_API_KEY")))
      (when (and endpoint api-key)
        (init-oc-adapter :endpoint endpoint :api-key api-key))))
  (log-info "AI chat integration initialized"))

;;;; 初始化

(defun init-ai-config-system ()
  "初始化 AI 配置系统"
  (log-info "Initializing AI config system...")

  ;; 注册默认后端
  (register-ai-backend "openclaw" "" ""
                       :models '("gpt-4" "gpt-3.5-turbo" "claude-3")
                       :capabilities '(:chat :summarize :translate :code)
                       :rate-limit 60)

  ;; 定义 AI 命令
  (define-ai-commands)

  ;; 初始化 AI 聊天集成
  (init-ai-chat-integration)

  (log-info "AI config system initialized")))

;;;; 结束
