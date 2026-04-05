;;;; server.lisp - LispIM 服务器主入口
;;;;
;;;; 整合所有模块，提供统一的启动入口

(in-package :lispim-core)

;;;; 依赖声明

(eval-when (:compile-toplevel :load-toplevel :execute)
  (ql:quickload '(:log4cl)))

;;;; 服务器状态

(defvar *server-start-time* (get-universal-time)
  "服务器启动时间")

(defvar *server-running* nil
  "服务器运行状态")

;;;; 服务器配置

(defparameter *default-config*
  (make-config
   :host "0.0.0.0"
   :port 3000
   :database-url (or (uiop:getenv "DATABASE_URL")
                     "postgresql://lispim:Clsper03@127.0.0.1:5432/lispim")
   :redis-url (or (uiop:getenv "REDIS_URL")
                  "redis://127.0.0.1:6379/0")
   :ssl-cert nil
   :ssl-key nil
   :oc-endpoint ""
   :oc-api-key ""
   :log-level :info
   :max-connections 10000
   :heartbeat-interval 30
   :heartbeat-timeout 90)
  "默认配置")

;;;; 服务器初始化

(defun init-server (&optional (config *default-config*))
  "初始化服务器"
  (declare (type config config))
  (setf *config* config)

  (log-info "Initializing LispIM Server...")

  ;; 初始化日志
  (setup-logging :level (config-log-level config))

  ;; 初始化存储
  (init-storage (config-database-url config)
                (config-redis-url config))

  ;; 确保消息状态列存在（migration 004）
  (ensure-message-status-column)

  ;; 初始化消息序列计数器（从数据库恢复）
  (initialize-sequence-counters)

  ;; 启动消息重试工作线程
  (start-retry-worker)

  ;; 初始化连接池
  (init-connection-pool :max-size (config-max-connections config))

  ;; 启动健康监控
  (start-health-monitor)

  ;; 初始化多级缓存
  (init-multi-level-cache
   :l1-max-size 10000
   :bloom-size 1000000
   :redis-host "localhost"
   :redis-port 6379)

  ;; 初始化离线消息队列
  (init-offline-queue :redis-host "localhost" :redis-port 6379)

  ;; 启动离线队列工作线程
  (start-offline-queue-worker)

  ;; 初始化客户端增量同步
  (init-sync)

  ;; 初始化 Redis Streams 消息队列
  (init-message-queue :redis-host "localhost" :redis-port 6379)

  ;; 启动消息消费者
  (start-message-consumer)

  ;; 初始化多实例集群
  (init-cluster :redis-host "localhost" :redis-port 6379
                :host (config-host config) :port (config-port config))

  ;; 初始化 CDN 存储
  (init-cdn-storage :provider :minio)

  ;; 初始化数据库读写分离（可选）
  ;; (init-db-replica :master-host "localhost" :master-port 5432
  ;;                  :slaves-config '(:connections
  ;;                                   ((:host "localhost" :port 5433 :database "lispim"
  ;;                                     :user "lispim" :password "Clsper03"))))

  ;; 初始化全文搜索
  (init-search "localhost" 6379)

  ;; 初始化消息去重
  (init-message-dedup :window-size 10000 :window-ttl 3600 :bloom-size 1000000)

  ;; 初始化速率限制
  (init-rate-limiting :default-rate 100 :default-burst 200)

  ;; 初始化速率限制
  (init-rate-limiting :default-rate 100 :default-burst 200)

  ;; 初始化 QR 码服务（扫一扫功能）
  ;; QR 码生成和验证

  ;; 初始化位置服务（附近的人功能）
  ;; 使用 Redis Geo 实现基于位置的用户发现

  ;; 初始化 WebSocket 中间件管道（新）
  (register-default-middleware)

  ;; 初始化房间管理系统（新）
  ;; 参考 Fiora/Tailchat 的房间设计

  ;; 初始化消息反应系统（新）
  ;; 参考 Tailchat 的 MessageReaction 设计
  (init-reactions)

  ;; 初始化在线用户缓存（新）
  ;; 参考 Fiora 的 GroupOnlineMembersCache 设计
  (init-online-cache :max-entries 10000 :expire-time 60)

  ;; 初始化系统命令（新）
  ;; 参考 Fiora 的系统命令设计（-roll, -rps 等）
  (init-system-commands)

  ;; 初始化默认用户（admin, user1, user2）
  (ensure-default-users-exist)

  ;; 初始化隐私增强功能（阅后即焚、双向删除、元数据最小化）
  (init-privacy-features)

  ;; 初始化通知系统（桌面通知、免打扰、FCM 推送）
  (init-notification-system)

  ;; 初始化投票功能（群投票）
  (ensure-poll-tables-exist)

  ;; 初始化 Webhook 系统（外部集成）
  (init-webhook-system)

  ;; 初始化语音消息（大文件传输优化）
  (init-voice-messages-db)

  ;; 初始化用户状态/动态功能（24 小时过期）
  (init-user-status-db)
  ;; 启动过期状态清理任务
  (start-status-cleanup-task)

  ;; 初始化聊天文件夹（类似 Telegram）
  (init-chat-folders-db)

  ;; 初始化群组频道（类似 Discord）
  (init-group-channels-db)

  ;; 初始化翻译模块（消息翻译）
  (init-translation :provider :openclaw :cache-enabled t)

  ;; 初始化可观测性
  (init-observability :log-level (config-log-level config))

  ;; 注册健康检查
  (register-default-health-checks)

  ;; 初始化 OpenClaw 适配器（如果配置了）
  (when (and (config-oc-endpoint config)
             (not (str:emptyp (config-oc-endpoint config))))
    (init-oc-adapter :endpoint (config-oc-endpoint config)
                     :api-key (config-oc-api-key config)))

  (log-info "Server initialized"))

;;;; 服务器启动

(defun start-server (&optional (config *default-config*))
  "启动 LispIM 服务器"
  (declare (type config config))

  ;; 初始化
  (init-server config)

  (setf *server-running* t
        *server-start-time* (get-universal-time))

  (log-info "========================================")
  (log-info "  LispIM Enterprise Server v0.1.0")
  (log-info "========================================")
  (log-info "Host: ~a" (config-host config))
  (log-info "Port: ~a" (config-port config))
  (log-info "Database: ~a" (config-database-url config))
  (log-info "Redis: ~a" (config-redis-url config))
  (log-info "SSL: ~a" (if (config-ssl-cert config) "Enabled" "Disabled"))
  (log-info "OpenClaw: ~a" (if (config-oc-endpoint config) "Enabled" "Disabled"))
  (log-info "========================================")

  ;; 启动网关
  (start-gateway
   :host (config-host config)
   :port (config-port config)
   :use-ssl (if (config-ssl-cert config) t nil)
   :ssl-cert (config-ssl-cert config)
   :ssl-key (config-ssl-key config))

  (log-info "Server started successfully"))

;;;; 服务器停止

(defun stop-server ()
  "停止 LispIM 服务器"
  (log-info "Stopping server...")

  (setf *server-running* nil)

  ;; 停止网关
  (stop-gateway)

  ;; 停止消息重试工作线程
  (stop-retry-worker)

  ;; 停止离线队列工作线程
  (stop-offline-queue-worker)

  ;; 停止消息消费者
  (stop-message-consumer)

  ;; 停止集群
  (shutdown-cluster)

  ;; 停止全文搜索
  (shutdown-fulltext-search)

  ;; 停止消息去重清理工作线程
  (stop-dedup-cleanup-worker)

  ;; 停止健康监控
  ;; (Note: health monitor thread would need a stop flag - for now we just log)

  ;; 清理缓存
  (when *multi-level-cache*
    (log-info "Shutting down multi-level cache..."))

  ;; 关闭 OpenClaw 适配器
  (when *oc-connected*
    (shutdown-oc-adapter))

  ;; 关闭存储连接
  (close-storage)

  ;; 关闭可观测性
  (shutdown-observability)

  ;; 关闭隐私功能
  (shutdown-privacy-features)

  ;; 关闭通知系统
  (log-info "Shutting down notification system...")

  ;; 清理 E2EE 数据
  (secure-cleanup)

  (log-info "Server stopped"))

;;;; 重启

(defun restart-server ()
  "重启服务器"
  (stop-server)
  (sleep 1)
  (start-server *config*))

;;;; 辅助函数

;;;; 环境变量配置

(defun load-config-from-env ()
  "从环境变量加载配置"
  (make-config
   :host (or (uiop:getenv "LISPIM_HOST") "0.0.0.0")
   :port (parse-integer (or (uiop:getenv "LISPIM_PORT") "4321"))
   :database-url (or (uiop:getenv "DATABASE_URL")
                     "postgresql://localhost:5432/lispim")
   :redis-url (or (uiop:getenv "REDIS_URL")
                  "redis://localhost:6379/0")
   :ssl-cert (when (uiop:getenv "SSL_CERT_PATH")
               (pathname (uiop:getenv "SSL_CERT_PATH")))
   :ssl-key (when (uiop:getenv "SSL_KEY_PATH")
              (pathname (uiop:getenv "SSL_KEY_PATH")))
   :oc-endpoint (or (uiop:getenv "OPENCLAW_ENDPOINT") "")
   :oc-api-key (or (uiop:getenv "OPENCLAW_API_KEY") "")
   :log-level (keywordify (or (uiop:getenv "LOG_LEVEL") "info"))
   :max-connections (parse-integer (or (uiop:getenv "MAX_CONNECTIONS") "10000"))
   :heartbeat-interval (parse-integer (or (uiop:getenv "HEARTBEAT_INTERVAL") "30"))
   :heartbeat-timeout (parse-integer (or (uiop:getenv "HEARTBEAT_TIMEOUT") "90"))))

(defun keywordify (str)
  "字符串转关键词"
  (intern (string-upcase str) 'keyword))

;;;; REPL 辅助

(defun repl-start (&key (config nil))
  "REPL 启动辅助"
  (let ((cfg (or config (load-config-from-env))))
    (start-server cfg)))

(defun repl-stop ()
  "REPL 停止辅助"
  (stop-server))

;;;; 主函数

(defun main ()
  "主函数（用于 sbcl --script 启动）"
  (handler-case
      (progn
        (start-server *default-config*)
        ;; 保持运行
        (loop while *server-running*
              do (sleep 1)))
    (error (c)
      (log:error "Server error: ~a" c)
      (stop-server))))

;;;; 导出

(export '(start-server
          stop-server
          restart-server
          init-server
          *server-running*
          *server-start-time*
          *config*
          make-config
          config-host
          config-port
          config-database-url
          config-redis-url
          config-ssl-cert
          config-ssl-key
          config-oc-endpoint
          config-oc-api-key
          config-log-level
          load-config-from-env
          main)
        :lispim-core)
