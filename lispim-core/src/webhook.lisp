;;;; webhook.lisp - Webhook 集成模块
;;;;
;;;; 实现外部 API/Webhook 集成支持
;;;; Features: Webhook 注册、事件触发、异步推送、重试机制
;;;;
;;;; 参考：Discord Webhooks, Slack Incoming Webhooks, GitHub Webhooks

(in-package :lispim-core)

;;;; 依赖声明

(eval-when (:compile-toplevel :load-toplevel :execute)
  (ql:quickload '(:drakma :cl-json :bordeaux-threads)))

;;;; Webhook 结构定义

(defstruct webhook
  "Webhook 配置记录"
  (id "" :type string)
  (name "" :type string)
  (url "" :type string)
  (secret "" :type string)            ; HMAC 签名密钥
  (events nil :type list)             ; 订阅的事件列表
  (enabled t :type boolean)
  (content-type :json :type keyword)  ; :json / :form
  (headers nil :type list)            ; 自定义请求头
  (retry-count 3 :type integer)       ; 重试次数
  (timeout-seconds 30 :type integer)  ; 超时时间
  (created-at 0 :type integer)
  (updated-at 0 :type integer)
  (last-triggered-at nil :type (or null integer))
  (success-count 0 :type integer)
  (failure-count 0 :type integer))

(defstruct webhook-delivery
  "Webhook 投递记录"
  (id "" :type string)
  (webhook-id "" :type string)
  (event-type "" :type string)
  (payload nil :type list)
  (status :pending :type keyword)     ; :pending / :success / :failed
  (attempt 0 :type integer)
  (response-code nil :type (or null integer))
  (response-body nil :type (or null string))
  (error-message nil :type (or null string))
  (created-at 0 :type integer)
  (delivered-at nil :type (or null integer)))

;;;; 全局变量

(defvar *webhooks* (make-hash-table :test 'equal :size 100)
  "Webhook 配置缓存：webhook-id -> webhook")

(defvar *webhook-deliveries* (make-hash-table :test 'equal :size 1000)
  "Webhook 投递记录缓存：delivery-id -> webhook-delivery")

(defvar *webhook-queue* nil
  "Webhook 投递队列")

(defvar *webhook-queue-lock* (bordeaux-threads:make-lock "webhook-queue-lock")
  "Webhook 队列锁")

(defvar *webhook-worker* nil
  "Webhook 投递工作线程")

(defvar *webhook-running* nil
  "Webhook 服务运行状态")

;;;; 支持的事件类型

(defparameter *webhook-events*
  '(:message-sent           ; 消息发送
    :message-deleted        ; 消息删除
    :message-recalled       ; 消息撤回
    :user-joined            ; 用户加入群组
    :user-left              ; 用户离开群组
    :user-online            ; 用户上线
    :user-offline           ; 用户下线
    :group-created          ; 群组创建
    :group-updated          ; 群组更新
    :group-deleted          ; 群组删除
    :reaction-added         ; 表情反应添加
    :reaction-removed       ; 表情反应移除
    :poll-created           ; 投票创建
    :poll-voted             ; 投票参与
    :file-uploaded          ; 文件上传
    :call-started           ; 通话开始
    :call-ended             ; 通话结束
    )
  "支持的 Webhook 事件类型")

;;;; 数据库表初始化

(defun ensure-webhook-tables-exist ()
  "确保 Webhook 相关表存在"
  (ensure-pg-connected)

  ;; Webhook 配置表
  (postmodern:query
   "CREATE TABLE IF NOT EXISTS webhooks (
      id VARCHAR(255) PRIMARY KEY,
      name VARCHAR(255) NOT NULL,
      url VARCHAR(512) NOT NULL,
      secret VARCHAR(255) DEFAULT '',
      events JSONB DEFAULT '[]',
      enabled BOOLEAN DEFAULT TRUE,
      content_type VARCHAR(20) DEFAULT 'json',
      headers JSONB DEFAULT '{}',
      retry_count INTEGER DEFAULT 3,
      timeout_seconds INTEGER DEFAULT 30,
      created_at TIMESTAMPTZ DEFAULT NOW(),
      updated_at TIMESTAMPTZ DEFAULT NOW(),
      last_triggered_at TIMESTAMPTZ,
      success_count INTEGER DEFAULT 0,
      failure_count INTEGER DEFAULT 0
    )")

  ;; Webhook 投递记录表
  (postmodern:query
   "CREATE TABLE IF NOT EXISTS webhook_deliveries (
      id VARCHAR(255) PRIMARY KEY,
      webhook_id VARCHAR(255) REFERENCES webhooks(id) ON DELETE CASCADE,
      event_type VARCHAR(50) NOT NULL,
      payload JSONB NOT NULL,
      status VARCHAR(20) DEFAULT 'pending',
      attempt INTEGER DEFAULT 0,
      response_code INTEGER,
      response_body TEXT,
      error_message TEXT,
      created_at TIMESTAMPTZ DEFAULT NOW(),
      delivered_at TIMESTAMPTZ
    )")

  ;; 创建索引
  (postmodern:query
   "CREATE INDEX IF NOT EXISTS idx_webhook_deliveries_webhook
    ON webhook_deliveries(webhook_id)")

  (postmodern:query
   "CREATE INDEX IF NOT EXISTS idx_webhook_deliveries_status
    ON webhook_deliveries(status)")

  (log-info "Webhook tables created"))

;;;; Webhook CRUD

(defun create-webhook (name url &key events secret content-type headers retry-count timeout-seconds)
  "创建 Webhook"
  (declare (type string name url)
           (type (or null list) events)
           (type (or null string) secret)
           (type (or null keyword) content-type)
           (type (or null list) headers)
           (type (or null integer) retry-count timeout-seconds))

  (ensure-pg-connected)

  (let* ((webhook-id (uuid:make-v4-uuid))
         (now (get-universal-time))
         (events-json (cl-json:encode-json-to-string (or events '(:message-sent))))
         (headers-json (cl-json:encode-json-to-string (or headers '())))
         (secret-key (or secret (uuid:make-v4-uuid))))

    ;; 存入数据库
    (postmodern:query
     "INSERT INTO webhooks
      (id, name, url, secret, events, content_type, headers, retry_count, timeout_seconds, created_at, updated_at)
      VALUES ($1, $2, $3, $4, $5::jsonb, $6, $7::jsonb, $8, $9, to_timestamp($10), to_timestamp($11))"
     webhook-id name url secret-key events-json
     (string-downcase (or content-type :json))
     headers-json (or retry-count 3) (or timeout-seconds 30)
     (lispim-universal-to-unix now)
     (lispim-universal-to-unix now))

    ;; 创建结构体
    (let ((webhook (make-webhook
                    :id webhook-id
                    :name name
                    :url url
                    :secret secret-key
                    :events (or events '(:message-sent))
                    :content-type (or content-type :json)
                    :headers headers
                    :retry-count (or retry-count 3)
                    :timeout-seconds (or timeout-seconds 30)
                    :enabled t
                    :created-at now
                    :updated-at now)))

      ;; 更新缓存
      (setf (gethash webhook-id *webhooks*) webhook)

      (log-info "Webhook created: ~a (~a)" name webhook-id)
      webhook)))

(defun get-webhook (webhook-id)
  "获取 Webhook 配置"
  (declare (type string webhook-id))

  ;; 先查缓存
  (let ((cached (gethash webhook-id *webhooks*)))
    (when cached
      (return-from get-webhook cached)))

  ;; 查数据库
  (ensure-pg-connected)
  (let ((result (postmodern:query
                 "SELECT * FROM webhooks WHERE id = $1"
                 webhook-id :alists)))
    (when result
      (let ((row (car result)))
        (flet ((get-val (name)
                 (let ((cell (find name row :key #'car :test #'string=)))
                   (when cell (cdr cell)))))
          (let* ((events-str (get-val "EVENTS"))
                 (events (if events-str
                             (cl-json:decode-json-from-string events-str)
                             '()))
                 (headers-str (get-val "HEADERS"))
                 (headers (if headers-str
                              (cl-json:decode-json-from-string headers-str)
                              '()))
                 (webhook (make-webhook
                           :id (get-val "ID")
                           :name (get-val "NAME")
                           :url (get-val "URL")
                           :secret (get-val "SECRET")
                           :events events
                           :enabled (string= (get-val "ENABLED") "t")
                           :content-type (keywordify (get-val "CONTENT_TYPE"))
                           :headers headers
                           :retry-count (parse-integer (get-val "RETRY_COUNT"))
                           :timeout-seconds (parse-integer (get-val "TIMEOUT_SECONDS"))
                           :success-count (parse-integer (get-val "SUCCESS_COUNT"))
                           :failure-count (parse-integer (get-val "FAILURE_COUNT"))
                           :created-at (lispim-universal-to-unix (get-val "CREATED_AT"))
                           :updated-at (lispim-universal-to-unix (get-val "UPDATED_AT"))
                           :last-triggered-at (lispim-universal-to-unix (get-val "LAST_TRIGGERED_AT")))))
            ;; 更新缓存
            (setf (gethash webhook-id *webhooks*) webhook)
            webhook))))))

(defun get-all-webhooks ()
  "获取所有 Webhook 配置"
  (ensure-pg-connected)

  (let ((result (postmodern:query
                 "SELECT * FROM webhooks ORDER BY created_at DESC"
                 :alists)))
    (when result
      (loop for row in result
            collect
            (flet ((get-val (name)
                     (let ((cell (find name row :key #'car :test #'string=)))
                       (when cell (cdr cell)))))
              (let* ((events-str (get-val "EVENTS"))
                     (events (if events-str
                                 (cl-json:decode-json-from-string events-str)
                                 '()))
                     (headers-str (get-val "HEADERS"))
                     (headers (if headers-str
                                  (cl-json:decode-json-from-string headers-str)
                                  '())))
                (make-webhook
                 :id (get-val "ID")
                 :name (get-val "NAME")
                 :url (get-val "URL")
                 :secret (get-val "SECRET")
                 :events events
                 :enabled (string= (get-val "ENABLED") "t")
                 :content-type (keywordify (get-val "CONTENT_TYPE"))
                 :headers headers
                 :retry-count (parse-integer (get-val "RETRY_COUNT"))
                 :timeout-seconds (parse-integer (get-val "TIMEOUT_SECONDS"))
                 :success-count (parse-integer (get-val "SUCCESS_COUNT"))
                 :failure-count (parse-integer (get-val "FAILURE_COUNT"))
                 :created-at (lispim-universal-to-unix (get-val "CREATED_AT"))
                 :updated-at (lispim-universal-to-unix (get-val "UPDATED_AT"))
                 :last-triggered-at (lispim-universal-to-unix (get-val "LAST_TRIGGERED_AT")))))))))

(defun get-user-webhooks (user-id)
  "获取指定用户的所有 Webhook 配置"
  (declare (type string user-id))
  (ensure-pg-connected)
  (let ((result (postmodern:query
                 "SELECT * FROM webhooks WHERE owner_id = $1 ORDER BY created_at DESC"
                 user-id
                 :alists)))
    (when result
      (loop for row in result
            collect
            (flet ((get-val (name)
                     (let ((cell (find name row :key #'car :test #'string=)))
                       (when cell (cdr cell)))))
              (let* ((events-str (get-val "EVENTS"))
                     (events (if events-str
                                 (cl-json:decode-json-from-string events-str)
                                 '()))
                     (headers-str (get-val "HEADERS"))
                     (headers (if headers-str
                                  (cl-json:decode-json-from-string headers-str)
                                  '())))
                (make-webhook
                 :id (get-val "ID")
                 :name (get-val "NAME")
                 :url (get-val "URL")
                 :secret (get-val "SECRET")
                 :events events
                 :enabled (string= (get-val "ENABLED") "t")
                 :content-type (keywordify (get-val "CONTENT_TYPE"))
                 :headers headers
                 :retry-count (parse-integer (get-val "RETRY_COUNT"))
                 :timeout-seconds (parse-integer (get-val "TIMEOUT_SECONDS"))
                 :success-count (parse-integer (get-val "SUCCESS_COUNT"))
                 :failure-count (parse-integer (get-val "FAILURE_COUNT"))
                 :created-at (lispim-universal-to-unix (get-val "CREATED_AT"))
                 :updated-at (lispim-universal-to-unix (get-val "UPDATED_AT"))
                 :last-triggered-at (lispim-universal-to-unix (get-val "LAST_TRIGGERED_AT")))))))))

(defun update-webhook (webhook-id &key name url events secret enabled content-type headers retry-count timeout-seconds)
  "更新 Webhook 配置"
  (declare (type string webhook-id)
           (type (or null string) name url secret)
           (type (or null list) events headers)
           (type (or null boolean) enabled)
           (type (or null keyword) content-type)
           (type (or null integer) retry-count timeout-seconds))

  (let ((updates nil)
        (params nil)
        (param-idx 1))

    (when name
      (push (format nil "name = $~a" param-idx) updates)
      (push name params)
      (incf param-idx))

    (when url
      (push (format nil "url = $~a" param-idx) updates)
      (push url params)
      (incf param-idx))

    (when events
      (push (format nil "events = $~a::jsonb" param-idx) updates)
      (push (cl-json:encode-json-to-string events) params)
      (incf param-idx))

    (when secret
      (push (format nil "secret = $~a" param-idx) updates)
      (push secret params)
      (incf param-idx))

    (when enabled
      (push (format nil "enabled = $~a" param-idx) updates)
      (push (if enabled "TRUE" "FALSE") params)
      (incf param-idx))

    (when content-type
      (push (format nil "content_type = $~a" param-idx) updates)
      (push (string-downcase content-type) params)
      (incf param-idx))

    (when headers
      (push (format nil "headers = $~a::jsonb" param-idx) updates)
      (push (cl-json:encode-json-to-string headers) params)
      (incf param-idx))

    (when retry-count
      (push (format nil "retry_count = $~a" param-idx) updates)
      (push retry-count params)
      (incf param-idx))

    (when timeout-seconds
      (push (format nil "timeout_seconds = $~a" param-idx) updates)
      (push timeout-seconds params)
      (incf param-idx))

    (when updates
      (push (format nil "updated_at = to_timestamp($~a)" param-idx) updates)
      (push (lispim-universal-to-unix (get-universal-time)) params)
      (incf param-idx)

      (push webhook-id params)
      (let ((sql (format nil "UPDATE webhooks SET ~a WHERE id = $~a"
                         (format nil "~{~a~^, ~}" updates) param-idx)))
        (apply (function (lambda (s p) (postmodern:query s p :alists))) (list sql params))))

    ;; 清除缓存
    (remhash webhook-id *webhooks*)

    (log-info "Webhook ~a updated" webhook-id)))

(defun delete-webhook (webhook-id)
  "删除 Webhook"
  (declare (type string webhook-id))

  (ensure-pg-connected)

  (postmodern:query
   "DELETE FROM webhooks WHERE id = $1"
   webhook-id)

  ;; 清除缓存
  (remhash webhook-id *webhooks*)

  (log-info "Webhook ~a deleted" webhook-id)
  t)

(defun enable-webhook (webhook-id)
  "启用 Webhook"
  (declare (type string webhook-id))
  (update-webhook webhook-id :enabled t))

(defun disable-webhook (webhook-id)
  "禁用 Webhook"
  (declare (type string webhook-id))
  (update-webhook webhook-id :enabled nil))

;;;; Webhook 事件触发

(defun trigger-webhook (event-type payload)
  "触发 Webhook 事件"
  (declare (type keyword event-type)
           (type list payload))

  ;; 获取所有启用的 Webhook
  (let ((webhooks (remove-if-not
                   (lambda (wh)
                     (and (webhook-enabled wh)
                          (member event-type (webhook-events wh))))
                   (get-all-webhooks))))

    (when webhooks
      ;; 为每个 Webhook 创建投递任务
      (dolist (wh webhooks)
        (queue-webhook-delivery wh event-type payload)))

    (length webhooks)))

(defun queue-webhook-delivery (webhook event-type payload)
  "将 Webhook 投递加入队列"
  (declare (type webhook webhook)
           (type keyword event-type)
           (type list payload))

  (let* ((delivery-id (uuid:make-v4-uuid))
         (now (get-universal-time))
         (delivery (make-webhook-delivery
                    :id delivery-id
                    :webhook-id (webhook-id webhook)
                    :event-type (symbol-name event-type)
                    :payload payload
                    :status :pending
                    :attempt 0
                    :created-at now)))

    ;; 存入缓存
    (setf (gethash delivery-id *webhook-deliveries*) delivery)

    ;; 加入队列
    (bordeaux-threads:with-lock-held (*webhook-queue-lock*)
      (push delivery *webhook-queue*))

    (log-debug "Queued webhook delivery: ~a for event ~a" delivery-id event-type)))

;;;; Webhook 投递

(defun deliver-webhook (delivery)
  "执行 Webhook 投递"
  (declare (type webhook-delivery delivery))

  (let* ((webhook (get-webhook (webhook-delivery-webhook-id delivery)))
         (url (webhook-url webhook))
         (secret (webhook-secret webhook))
         (content-type (webhook-content-type webhook))
         (timeout (webhook-timeout-seconds webhook))
         (payload (webhook-delivery-payload delivery))
         (json-body (cl-json:encode-json-to-string `((:event . ,(webhook-delivery-event-type delivery))
                                                      (:data . ,payload)
                                                      (:ts . ,(lispim-universal-to-unix-ms (get-universal-time))))))
         (signature (when (and secret (> (length secret) 0))
                      (generate-hmac-signature json-body secret)))
         (headers `(("Content-Type" . ,(if (eq content-type :json)
                                           "application/json"
                                           "application/x-www-form-urlencoded"))
                    ("User-Agent" . "LispIM-Webhook/1.0"))))

    ;; 添加签名头
    (when signature
      (push (cons "X-LispIM-Signature" signature) headers))

    ;; 添加自定义头
    (when (webhook-headers webhook)
      (loop for (k . v) in (webhook-headers webhook)
            do (push (cons k v) headers)))

    ;; 发送 HTTP POST 请求
    (let ((start-time (get-universal-time)))
      (handler-case
          (let* ((response (drakma:http-request url
                                                :method :post
                                                :content json-body
                                                :additional-headers headers
                                                :read-timeout (* timeout 1000)
                                                :connect-timeout (* timeout 1000))))
            (setf (webhook-delivery-status delivery) :success
                  (webhook-delivery-delivered-at delivery) (get-universal-time)
                  (webhook-delivery-response-code delivery) 200
                  (webhook-delivery-response-body delivery) (if (stringp response) response ""))

            ;; 更新统计
            (incf (webhook-success-count webhook))
            (setf (webhook-last-triggered-at webhook) start-time)

            (log-info "Webhook delivered successfully: ~a" (webhook-delivery-id delivery))
            t)

        (error (c)
          (setf (webhook-delivery-status delivery) :failed
                (webhook-delivery-error-message delivery) (format nil "~a" c)
                (webhook-delivery-delivered-at delivery) (get-universal-time))

          ;; 更新统计
          (incf (webhook-failure-count webhook))

          (log-error "Webhook delivery failed: ~a - ~a" (webhook-delivery-id delivery) c)
          nil)))))

(defun generate-hmac-signature (payload secret)
  "生成 HMAC-SHA256 签名"
  (declare (type string payload secret))
  (let* ((key (babel:string-to-octets secret))
         (data (babel:string-to-octets payload))
         (hmac (ironclad:make-hmac key :sha256)))
    (ironclad:update-hmac hmac data)
    (cl-base64:usb8-array-to-base64-string (ironclad:hmac-digest hmac))))

;;;; Webhook 重试机制

(defun retry-webhook-delivery (delivery)
  "重试 Webhook 投递"
  (declare (type webhook-delivery delivery))

  (let ((max-retries (let ((wh (get-webhook (webhook-delivery-webhook-id delivery))))
                       (if wh (webhook-retry-count wh) 3))))

    (when (< (webhook-delivery-attempt delivery) max-retries)
      ;; 增加重试次数
      (incf (webhook-delivery-attempt delivery))

      ;; 重新加入队列（延迟重试）
      (let ((delay (expt 2 (webhook-delivery-attempt delivery)))) ; 指数退避
        (bordeaux-threads:with-lock-held (*webhook-queue-lock*)
          (push delivery *webhook-queue*))
        (log-info "Scheduled webhook retry ~a for ~a seconds later"
                  (webhook-delivery-id delivery) delay)))

    (when (>= (webhook-delivery-attempt delivery) max-retries)
      (log-error "Webhook ~a failed after ~a attempts"
                 (webhook-delivery-id delivery)
                 (webhook-delivery-attempt delivery)))))

;;;; Webhook 工作线程

(defun start-webhook-worker ()
  "启动 Webhook 投递工作线程"
  (when *webhook-running*
    (log-warn "Webhook worker already running")
    (return-from start-webhook-worker))

  (setf *webhook-running* t)

  (setf *webhook-worker*
        (bordeaux-threads:make-thread
         (lambda ()
           (log-info "Webhook worker started")

           (loop while *webhook-running*
                 do
                 (handler-case
                     (progn
                       ;; 检查队列
                       (let ((delivery nil))

                         ;; 从队列获取投递任务
                         (bordeaux-threads:with-lock-held (*webhook-queue-lock*)
                           (when *webhook-queue*
                             (setf delivery (pop *webhook-queue*))))

                         (when delivery
                           ;; 执行投递
                           (let ((success (deliver-webhook delivery)))
                             (unless success
                               ;; 投递失败，重试
                               (retry-webhook-delivery delivery)))))

                       ;; 短暂休眠
                       (sleep 1))
                   (error (c)
                     (log-error "Webhook worker error: ~a" c)))))
         :name "webhook-worker"))

  (log-info "Webhook worker started"))

(defun stop-webhook-worker ()
  "停止 Webhook 投递工作线程"
  (setf *webhook-running* nil)

  (when *webhook-worker*
    (bordeaux-threads:destroy-thread *webhook-worker*)
    (setf *webhook-worker* nil))

  (log-info "Webhook worker stopped"))

;;;; 统计和查询

(defun get-webhook-stats ()
  "获取 Webhook 统计"
  (let ((webhooks (get-all-webhooks))
        (pending-count 0)
        (total-success 0)
        (total-failure 0))

    ;; 统计待投递数量
    (bordeaux-threads:with-lock-held (*webhook-queue-lock*)
      (setf pending-count (length *webhook-queue*)))

    ;; 统计成功/失败数量
    (dolist (wh webhooks)
      (incf total-success (webhook-success-count wh))
      (incf total-failure (webhook-failure-count wh)))

    `((:total-webhooks . ,(length webhooks))
      (:enabled-webhooks . ,(length (remove-if-not #'webhook-enabled webhooks)))
      (:pending-deliveries . ,pending-count)
      (:total-success . ,total-success)
      (:total-failures . ,total-failure))))

(defun get-webhook-deliveries (webhook-id &key (limit 100) (status nil))
  "获取 Webhook 投递记录"
  (declare (type string webhook-id)
           (type integer limit)
           (type (or null keyword) status))

  (ensure-pg-connected)

  (let ((sql "SELECT * FROM webhook_deliveries WHERE webhook_id = $1")
        (params (list webhook-id))
        (param-idx 2))

    (when status
      (setf sql (concatenate 'string sql (format nil " AND status = $~a" param-idx)))
      (push (symbol-name status) params)
      (incf param-idx))

    (setf sql (concatenate 'string sql (format nil " ORDER BY created_at DESC LIMIT $~a" param-idx)))
    (push limit params)

    (let ((result (postmodern:query sql params :alists)))
      (when result
        (loop for row in result
              collect
              (flet ((get-val (name)
                       (let ((cell (find name row :key #'car :test #'string=)))
                         (when cell (cdr cell)))))
                (make-webhook-delivery
                 :id (get-val "ID")
                 :webhook-id (get-val "WEBHOOK_ID")
                 :event-type (get-val "EVENT_TYPE")
                 :status (keywordify (get-val "STATUS"))
                 :attempt (parse-integer (get-val "ATTEMPT"))
                 :response-code (let ((code (get-val "RESPONSE_CODE")))
                                  (when code (parse-integer code)))
                 :response-body (get-val "RESPONSE_BODY")
                 :error-message (get-val "ERROR_MESSAGE")
                 :created-at (lispim-universal-to-unix (get-val "CREATED_AT"))
                 :delivered-at (lispim-universal-to-unix (get-val "DELIVERED_AT")))))))))

;;;; 初始化

(defun init-webhook-system ()
  "初始化 Webhook 系统"
  (log-info "Initializing webhook system...")

  ;; 创建数据库表
  (ensure-webhook-tables-exist)

  ;; 启动工作线程
  (start-webhook-worker)

  (log-info "Webhook system initialized"))

(defun shutdown-webhook-system ()
  "关闭 Webhook 系统"
  (log-info "Shutting down webhook system...")

  ;; 停止工作线程
  (stop-webhook-worker)

  ;; 清空队列
  (bordeaux-threads:with-lock-held (*webhook-queue-lock*)
    (setf *webhook-queue* nil))

  (log-info "Webhook system shut down"))

;;;; 导出

(export '(;; Webhook management
          create-webhook
          get-webhook
          get-all-webhooks
          update-webhook
          delete-webhook
          enable-webhook
          disable-webhook

          ;; Event triggering
          trigger-webhook
          queue-webhook-delivery

          ;; Delivery
          deliver-webhook
          retry-webhook-delivery

          ;; Worker
          start-webhook-worker
          stop-webhook-worker

          ;; Statistics
          get-webhook-stats
          get-webhook-deliveries

          ;; Initialization
          init-webhook-system
          shutdown-webhook-system
          ensure-webhook-tables-exist)
        :lispim-core)

;;;; End of webhook.lisp
