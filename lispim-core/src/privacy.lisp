;;;; privacy.lisp - 隐私与安全增强模块
;;;;
;;;; 实现以下隐私保护功能：
;;;; 1. 阅后即焚/自毁消息 (Disappearing Messages)
;;;; 2. 消息双向删除 (Delete for Everyone)
;;;; 3. 元数据最小化 (Metadata Minimization)
;;;;
;;;; 参考：Signal Protocol, Session, Threema

(in-package :lispim-core)

;;;; 依赖声明

(eval-when (:compile-toplevel :load-toplevel :execute)
  (ql:quickload '(:bordeaux-threads)))

;;;; ============================================================================
;;;; 1. 阅后即焚/自毁消息 (Signal-style Disappearing Messages)
;;;; ============================================================================

;; 自毁消息配置
(defparameter *disappearing-message-timers*
  '(5          ; 5 秒
    30         ; 30 秒
    60         ; 1 分钟
    300        ; 5 分钟
    900        ; 15 分钟
    3600       ; 1 小时
    86400      ; 24 小时
    604800     ; 7 天
    )
  "支持的自毁定时器选项（秒）")

(defparameter *default-disappearing-timer* 86400
  "默认自毁定时器：24 小时")

(defparameter *disappearing-message-worker* nil
  "自毁消息清理工作线程")

(defparameter *disappearing-message-running* nil
  "自毁消息服务运行状态")

;; 自毁消息配置结构
(defstruct disappearing-message-config
  "自毁消息配置"
  (enabled nil :type boolean)
  (timer-seconds 86400 :type integer)  ; 默认 24 小时
  (timer-start :first-read :type (member :immediate :first-read)))

;; 会话自毁配置缓存
(defvar *conversation-disappearing-configs*
  (make-hash-table :test 'eql :size 1000)
  "会话自毁配置缓存：conversation-id -> disappearing-message-config")

(defvar *conversation-disappearing-lock*
  (bordeaux-threads:make-lock "disappearing-config-lock")
  "自毁配置缓存锁")

;; 数据库表初始化
(defun ensure-disappearing-message-tables-exist ()
  "确保自毁消息相关表存在"
  (ensure-pg-connected)

  ;; 会话自毁配置表
  (postmodern:query
   "CREATE TABLE IF NOT EXISTS conversation_disappearing_settings (
      conversation_id BIGINT PRIMARY KEY REFERENCES conversations(id) ON DELETE CASCADE,
      enabled BOOLEAN DEFAULT FALSE,
      timer_seconds INTEGER DEFAULT 86400,
      timer_start VARCHAR(20) DEFAULT 'first-read',
      updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )")

  ;; 消息自毁时间表
  (postmodern:query
   "CREATE TABLE IF NOT EXISTS message_deletion_schedule (
      message_id BIGINT PRIMARY KEY REFERENCES messages(id) ON DELETE CASCADE,
      scheduled_delete_at TIMESTAMP NOT NULL,
      deleted_p BOOLEAN DEFAULT FALSE,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )")

  ;; 创建索引
  (postmodern:query
   "CREATE INDEX IF NOT EXISTS idx_message_deletion_schedule_time
    ON message_deletion_schedule(scheduled_delete_at)
    WHERE deleted_p = FALSE")

  (log-info "Disappearing message tables created"))

;; 设置会话自毁消息
(defun set-conversation-disappearing-messages (conversation-id enabled &key (timer-seconds 86400) (timer-start :first-read))
  "设置会话的自毁消息功能"
  (declare (type conversation-id conversation-id)
           (type boolean enabled)
           (type (integer 1 604800) timer-seconds))

  (ensure-pg-connected)

  ;; 验证定时器值
  (unless (member timer-seconds *disappearing-message-timers*)
    (setf timer-seconds 86400))  ; 使用默认值

  ;; 更新数据库
  (postmodern:query
   "INSERT INTO conversation_disappearing_settings
    (conversation_id, enabled, timer_seconds, timer_start, updated_at)
    VALUES ($1, $2, $3, $4, CURRENT_TIMESTAMP)
    ON CONFLICT (conversation_id)
    DO UPDATE SET enabled = $2, timer_seconds = $3, timer_start = $4, updated_at = CURRENT_TIMESTAMP"
   conversation-id enabled timer-seconds (symbol-name timer-start))

  ;; 更新缓存
  (bordeaux-threads:with-lock-held (*conversation-disappearing-lock*)
    (if enabled
        (setf (gethash conversation-id *conversation-disappearing-configs*)
              (make-disappearing-message-config :enabled t
                                                 :timer-seconds timer-seconds
                                                 :timer-start timer-start))
        (remhash conversation-id *conversation-disappearing-configs*)))

  ;; 通知会话成员
  (notify-disappearing-messages-changed conversation-id enabled timer-seconds)

  (log-info "Set disappearing messages for conversation ~a: enabled=~a, timer=~as"
            conversation-id enabled timer-seconds)
  t)

;; 获取会话自毁配置
(defun get-conversation-disappearing-config (conversation-id)
  "获取会话的自毁消息配置"
  (declare (type conversation-id conversation-id))

  ;; 先查缓存
  (bordeaux-threads:with-lock-held (*conversation-disappearing-lock*)
    (let ((cached (gethash conversation-id *conversation-disappearing-configs*)))
      (when cached
        (return-from get-conversation-disappearing-config cached))))

  ;; 查数据库
  (ensure-pg-connected)
  (let ((row (postmodern:query
              "SELECT enabled, timer_seconds, timer_start
               FROM conversation_disappearing_settings
               WHERE conversation_id = $1"
              conversation-id)))
    (if row
        (let* ((enabled (caar row))
               (timer (cadar row))
               (start (keywordify (cadar row))))
          (bordeaux-threads:with-lock-held (*conversation-disappearing-lock*)
            (let ((config (make-disappearing-message-config
                           :enabled enabled
                           :timer-seconds timer
                           :timer-start start)))
              (setf (gethash conversation-id *conversation-disappearing-configs*) config)
              config)))
        ;; 默认配置
        (make-disappearing-message-config :enabled nil :timer-seconds 86400 :timer-start :first-read))))

;; 安排消息自毁
(defun schedule-message-deletion (message-id delay-seconds)
  "安排消息在指定时间后删除"
  (declare (type message-id message-id)
           (type (integer 1 604800) delay-seconds))

  (ensure-pg-connected)

  (let ((delete-time (get-universal-time)))
    ;; 计算删除时间
    (incf delete-time delay-seconds)

    ;; 存入数据库
    (postmodern:query
     "INSERT INTO message_deletion_schedule
      (message_id, scheduled_delete_at, deleted_p)
      VALUES ($1, to_timestamp($2), FALSE)
      ON CONFLICT (message_id) DO NOTHING"
     message-id (lispim-universal-to-unix delete-time))

    (log-debug "Scheduled message ~a for deletion at ~a" message-id delete-time)
    t))

;; 启动自毁消息清理工作线程
(defun start-disappearing-message-worker ()
  "启动自毁消息清理工作线程"
  (when *disappearing-message-running*
    (log-warn "Disappearing message worker already running")
    (return-from start-disappearing-message-worker))

  (setf *disappearing-message-running* t)

  (setf *disappearing-message-worker*
        (bordeaux-threads:make-thread
         (lambda ()
           (log-info "Disappearing message worker started")

           (loop while *disappearing-message-running*
                 do
                 (handler-case
                     (progn
                       ;; 每 10 秒检查一次
                       (sleep 10)
                       (cleanup-expired-messages))
                   (error (c)
                     (log-error "Disappearing message worker error: ~a" c)))))
         :name "disappearing-message-worker"))

  (log-info "Disappearing message worker started"))

;; 停止清理工作线程
(defun stop-disappearing-message-worker ()
  "停止自毁消息清理工作线程"
  (setf *disappearing-message-running* nil)

  (when *disappearing-message-worker*
    (bordeaux-threads:destroy-thread *disappearing-message-worker*)
    (setf *disappearing-message-worker* nil))

  (log-info "Disappearing message worker stopped"))

;; 清理过期消息
(defun cleanup-expired-messages ()
  "清理已到期的自毁消息"
  (ensure-pg-connected)

  (let* ((now (get-universal-time))
         (now-ts (lispim-universal-to-unix now))
         ;; 查询到期消息
         (expired-rows
          (postmodern:query
           "SELECT message_id FROM message_deletion_schedule
            WHERE scheduled_delete_at <= to_timestamp($1)
            AND deleted_p = FALSE
            LIMIT 100"
           now-ts)))

    (dolist (row expired-rows)
      (let ((message-id (car row)))
        (handler-case
            (progn
              ;; 执行删除
              (delete-message-for-all message-id "自毁消息")

              ;; 标记为已删除
              (postmodern:query
               "UPDATE message_deletion_schedule
                SET deleted_p = TRUE
                WHERE message_id = $1"
               message-id)

              (log-debug "Auto-deleted expired message ~a" message-id))
          (error (c)
            (log-error "Failed to auto-delete message ~a: ~a" message-id c)))))

    (when (plusp (length expired-rows))
      (log-info "Cleaned up ~a expired messages" (length expired-rows)))))

;; 通知自毁消息配置变更
(defun notify-disappearing-messages-changed (conversation-id enabled timer-seconds)
  "通知会话成员自毁消息配置已变更"
  (declare (type conversation-id conversation-id)
           (type boolean enabled)
           (type integer timer-seconds))

  (let ((notification `((:type . :disappearing-messages-changed)
                        (:conversation-id . ,conversation-id)
                        (:enabled . ,enabled)
                        (:timer-seconds . ,timer-seconds)
                        (:ts . ,(lispim-universal-to-unix-ms (get-universal-time))))))
    (push-to-online-users conversation-id notification)))

;;;; ============================================================================
;;;; 2. 消息双向删除 (Telegram-style Delete for Everyone)
;;;; ============================================================================

;; 双向删除条件
(defparameter *delete-for-everyone-time-limit* (* 48 60 60)
  "双向删除时间限制：48 小时（Telegram 风格）")

;; 删除消息（双向）
(defun delete-message-for-all (message-id &optional (reason ""))
  "删除消息，对所有人生效"
  (declare (type message-id message-id)
           (type string reason))

  (handler-case
      (let ((msg (get-message message-id)))
        (unless msg
          (error 'message-not-found :message-id message-id))

        ;; 检查删除权限
        (unless (or (string= (message-sender-id msg) *current-user-id*)
                    (is-admin-in-conversation (message-conversation-id msg) *current-user-id*))
          (error 'auth-error
                 :message "No permission to delete this message"
                 :user-id *current-user-id*))

        ;; 检查时间限制
        (let* ((elapsed (- (get-universal-time) (message-created-at msg))))
          (when (> elapsed *delete-for-everyone-time-limit*)
            (error 'message-recall-timeout
                   :message-id message-id
                   :elapsed elapsed
                   :max-elapsed *delete-for-everyone-time-limit*)))

        ;; 标记删除
        (setf (message-recalled-p msg) t
              (message-content msg) (format nil "[消息已删除~A]"
                                             (if (plusp (length reason))
                                                 (format nil ": ~a" reason)
                                                 "")))
        (update-message msg)

        ;; 通知所有用户
        (notify-message-deleted message-id (message-conversation-id msg) reason)

        ;; 如果是自毁消息，同时从数据库物理删除
        (let ((config (get-conversation-disappearing-config (message-conversation-id msg))))
          (when (disappearing-message-config-enabled config)
            ;; 物理删除消息内容
            (postmodern:query
             "UPDATE messages SET content = '[已删除]', attachments = '[]'
              WHERE id = $1"
             message-id)))

        (log-info "Message ~a deleted for all" message-id)
        t)

    (message-not-found (c)
      (log-error "Message not found for delete: ~a" (format nil "~A" c))
      (signal c))
    (auth-error (c)
      (log-warn "Auth error for delete: ~a" (format nil "~A" c))
      (signal c))
    (message-recall-timeout (c)
      (log-info "Delete timeout for message ~a" (format nil "~A" c))
      (signal c))))

;; 通知消息已删除
(defun notify-message-deleted (message-id conversation-id reason)
  "通知消息已删除"
  (declare (type message-id message-id)
           (type conversation-id conversation-id)
           (type string reason))

  (let ((deleted `((:type . :message-deleted)
                   (:message-id . ,message-id)
                   (:reason . ,reason)
                   (:ts . ,(lispim-universal-to-unix-ms (get-universal-time))))))
    (push-to-online-users conversation-id deleted)))

;; 单向删除（仅对自己可见）
(defun delete-message-for-self (message-id)
  "删除消息，仅对自己生效"
  (declare (type message-id message-id))

  (handler-case
      (let ((msg (get-message message-id)))
        (unless msg
          (error 'message-not-found :message-id message-id))

        ;; 验证用户是消息发送者或接收者
        (let ((conv (get-conversation (message-conversation-id msg))))
          (unless (member *current-user-id* (conversation-participants conv) :test #'string=)
            (error 'conversation-access-denied
                   :conversation-id (message-conversation-id msg)
                   :user-id *current-user-id*)))

        ;; 在用户消息列表中隐藏
        (postmodern:query
         "INSERT INTO user_message_visibility (user_id, message_id, visible_p)
          VALUES ($1, $2, FALSE)
          ON CONFLICT (user_id, message_id)
          DO UPDATE SET visible_p = FALSE"
         *current-user-id* message-id)

        (log-info "Message ~a deleted for user ~a" message-id *current-user-id*)
        t)

    (message-not-found (c)
      (log-info "Message not found for self delete: ~a" message-id)
      (signal c))
    (conversation-access-denied (c)
      (log-warn "Access denied for self delete: ~a" message-id)
      (signal c))))

;;;; ============================================================================
;;;; 3. 元数据最小化 (Session-style Metadata Minimization)
;;;; ============================================================================

;; 元数据最小化配置
(defparameter *metadata-minimization-enabled* t
  "启用元数据最小化")

(defparameter *minimal-metadata-retention-period* (* 24 60 60)
  "最小元数据保留时间：24 小时")

;; 禁用详细日志
(defun disable-verbose-logging ()
  "禁用详细日志以减少元数据收集"
  (setf *log-level* :warn)
  (log-info "Verbose logging disabled for privacy"))

;; 最小化连接日志
(defun log-minimal-connection-info (user-id connection-id)
  "记录最小化连接信息（不包含 IP 等敏感数据）"
  (declare (type string user-id connection-id))
  (log-debug "User ~a connected via ~a" user-id connection-id))

;; 不记录 IP 地址的认证函数
(defun authenticate-minimal (username password)
  "认证但不记录 IP 地址"
  (declare (type string username password))

  ;; 不记录请求来源 IP
  (let ((user (get-user-by-username username)))
    (if user
        (let ((stored-hash (getf user :password-hash))
              (salt (getf user :password-salt)))
          (if (verify-password password stored-hash salt)
              (progn
                ;; 仅记录用户 ID，不记录 IP
                (log-debug "User ~a authenticated" (getf user :user-id))
                (create-session (getf user :user-id)))
              (progn
                ;; 失败时也不记录尝试的 IP
                (log-warn "Authentication failed for user: ~a" username)
                nil)))
        (progn
          ;; 失败时也不记录尝试的 IP
          (log-warn "Authentication failed for user: ~a" username)
          nil))))

;; 清理旧元数据
(defun cleanup-old-metadata ()
  "清理超过保留期的元数据"
  (ensure-pg-connected)

  (let ((cutoff (- (get-universal-time) *minimal-metadata-retention-period*)))
    ;; 清理旧会话日志
    (postmodern:query
     "DELETE FROM session_logs
      WHERE created_at < to_timestamp($1)"
     (lispim-universal-to-unix cutoff))

    ;; 清理旧连接日志
    (postmodern:query
     "DELETE FROM connection_logs
      WHERE created_at < to_timestamp($1)"
     (lispim-universal-to-unix cutoff))

    (log-info "Cleaned up metadata older than ~a seconds"
              *minimal-metadata-retention-period*)))

;; 启动元数据清理工作线程
(defun start-metadata-cleanup-worker ()
  "启动元数据清理工作线程"
  (bordeaux-threads:make-thread
   (lambda ()
     (loop
       (sleep (* 60 60))  ;; 每小时清理一次
       (handler-case
           (cleanup-old-metadata)
         (error (c)
           (log-error "Metadata cleanup error: ~a" c)))))
   :name "metadata-cleanup-worker"))

;; 获取隐私设置统计
(defun get-privacy-stats ()
  "获取隐私功能使用统计"
  (ensure-pg-connected)

  (let ((disappearing-count
         (caar (postmodern:query
                "SELECT COUNT(*) FROM conversation_disappearing_settings WHERE enabled = TRUE")))
        (scheduled-deletions
         (caar (postmodern:query
                "SELECT COUNT(*) FROM message_deletion_schedule WHERE deleted_p = FALSE"))))

    `((:disappearing-conversations . ,disappearing-count)
      (:scheduled-deletions . ,scheduled-deletions)
      (:metadata-minimization-enabled . ,*metadata-minimization-enabled*)
      (:metadata-retention-hours . ,(/ *minimal-metadata-retention-period* 3600)))))

;;;; ============================================================================
;;;; 4. 用户隐私设置 (Privacy Settings)
;;;; ============================================================================

;; 隐私设置结构
(defstruct user-privacy-settings
  "用户隐私设置"
  (hide-online-status nil :type boolean)      ; 隐藏在线状态
  (hide-read-receipt nil :type boolean)       ; 隐藏已读回执
  (show-profile-photo t :type boolean)        ; 显示头像
  (show-last-seen t :type boolean))           ; 显示最后在线时间

;; 隐私设置缓存
(defvar *user-privacy-settings-cache*
  (make-hash-table :test 'equal :size 10000)
  "用户隐私设置缓存：user-id -> user-privacy-settings")

(defvar *user-privacy-settings-lock*
  (bordeaux-threads:make-lock "privacy-settings-lock")
  "隐私设置缓存锁")

;; 获取用户隐私设置
(defun get-user-privacy-settings (user-id)
  "获取用户的隐私设置"
  (declare (type string user-id))

  ;; 先查缓存
  (bordeaux-threads:with-lock-held (*user-privacy-settings-lock*)
    (let ((cached (gethash user-id *user-privacy-settings-cache*)))
      (when cached
        (return-from get-user-privacy-settings cached))))

  ;; 查数据库
  (ensure-pg-connected)
  (let ((row (postmodern:query
              "SELECT hide_online_status, hide_read_receipt,
                      COALESCE((privacy_settings->>'show_profile_photo')::boolean, true) as show_profile_photo,
                      COALESCE((privacy_settings->>'show_last_seen')::boolean, true) as show_last_seen
               FROM users WHERE id = $1"
              user-id)))
    (if row
        (let* ((hide-online (caar row))
               (hide-read (cadar row))
               (show-photo (cadddr (car row)))
               (show-seen (car (last (car row)))))
          (bordeaux-threads:with-lock-held (*user-privacy-settings-lock*)
            (let ((settings (make-user-privacy-settings
                             :hide-online-status (if hide-online t nil)
                             :hide-read-receipt (if hide-read t nil)
                             :show-profile-photo (if show-photo t nil)
                             :show-last-seen (if show-seen t nil))))
              (setf (gethash user-id *user-privacy-settings-cache*) settings)
              settings)))
        ;; 默认设置
        (make-user-privacy-settings))))

;; 更新用户隐私设置
(defun set-user-privacy-settings (user-id &key hide-online-status hide-read-receipt show-profile-photo show-last-seen)
  "更新用户的隐私设置"
  (declare (type string user-id)
           (type (or boolean null) hide-online-status)
           (type (or boolean null) hide-read-receipt)
           (type (or boolean null) show-profile-photo)
           (type (or boolean null) show-last-seen))

  (ensure-pg-connected)

  ;; 构建更新 SQL
  (let ((updates nil)
        (params nil)
        (param-idx 1))
    (when (booleanp hide-online-status)
      (push (format nil "hide_online_status = $~a" param-idx) updates)
      (push hide-online-status params)
      (incf param-idx))
    (when (booleanp hide-read-receipt)
      (push (format nil "hide_read_receipt = $~a" param-idx) updates)
      (push hide-read-receipt params)
      (incf param-idx))
    (when (booleanp show-profile-photo)
      (push (format nil "privacy_settings = jsonb_set(COALESCE(privacy_settings, '{}'), '{show_profile_photo}', $~a)" param-idx) updates)
      (push (if show-profile-photo "true" "false") params)
      (incf param-idx))
    (when (booleanp show-last-seen)
      (push (format nil "privacy_settings = jsonb_set(COALESCE(privacy_settings, '{}'), '{show_last_seen}', $~a)" param-idx) updates)
      (push (if show-last-seen "true" "false") params)
      (incf param-idx))

    (when updates
      ;; 合并 privacy_settings 更新
      (let ((final-sql (format nil "UPDATE users SET ~{~a~^, ~} WHERE id = $~a"
                               updates param-idx)))
        (postmodern:query final-sql (nreverse (append params (list user-id)))))

      ;; 清除缓存
      (bordeaux-threads:with-lock-held (*user-privacy-settings-lock*)
        (remhash user-id *user-privacy-settings-cache*))

      (log-info "Updated privacy settings for user ~a" user-id)
      t)))

;; 检查用户是否隐藏在线状态
(defun user-hides-online-status (user-id)
  "检查用户是否隐藏在线状态"
  (declare (type string user-id))
  (user-privacy-settings-hide-online-status (get-user-privacy-settings user-id)))

;; 检查用户是否隐藏已读回执
(defun user-hides-read-receipt (user-id)
  "检查用户是否隐藏已读回执"
  (declare (type string user-id))
  (user-privacy-settings-hide-read-receipt (get-user-privacy-settings user-id)))

;; 检查是否可以显示用户头像
(defun can-show-user-profile-photo (user-id)
  "检查是否可以显示用户头像"
  (declare (type string user-id))
  (user-privacy-settings-show-profile-photo (get-user-privacy-settings user-id)))

;; 检查是否可以显示用户最后在线时间
(defun can-show-user-last-seen (user-id)
  "检查是否可以显示用户最后在线时间"
  (declare (type string user-id))
  (user-privacy-settings-show-last-seen (get-user-privacy-settings user-id)))

;; 清除用户隐私设置缓存
(defun clear-user-privacy-settings-cache (user-id)
  "清除用户隐私设置缓存"
  (declare (type string user-id))
  (bordeaux-threads:with-lock-held (*user-privacy-settings-lock*)
    (remhash user-id *user-privacy-settings-cache*)))

;;;; ============================================================================
;;;; 初始化
;;;; ============================================================================

(defun init-privacy-features ()
  "初始化隐私增强功能"
  (log-info "Initializing privacy features...")

  ;; 创建数据库表
  (ensure-disappearing-message-tables-exist)

  ;; 确保用户消息可见性表存在
  (postmodern:query
   "CREATE TABLE IF NOT EXISTS user_message_visibility (
      user_id VARCHAR(255) NOT NULL,
      message_id BIGINT NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
      visible_p BOOLEAN DEFAULT TRUE,
      PRIMARY KEY (user_id, message_id)
    )")

  ;; 启动工作线程
  (start-disappearing-message-worker)
  (start-metadata-cleanup-worker)

  ;; 禁用详细日志（如果启用元数据最小化）
  (when *metadata-minimization-enabled*
    (disable-verbose-logging))

  (log-info "Privacy features initialized"))

(defun shutdown-privacy-features ()
  "关闭隐私增强功能"
  (log-info "Shutting down privacy features...")

  (stop-disappearing-message-worker)

  (log-info "Privacy features shut down"))

;;;; ============================================================================
;;;; 导出函数
;;;; ============================================================================

(export '(;; Disappearing messages
          *disappearing-message-timers*
          *default-disappearing-timer*
          disappearing-message-config
          make-disappearing-message-config
          disappearing-message-config-enabled
          disappearing-message-config-timer-seconds
          disappearing-message-config-timer-start
          set-conversation-disappearing-messages
          get-conversation-disappearing-config
          schedule-message-deletion
          start-disappearing-message-worker
          stop-disappearing-message-worker
          cleanup-expired-messages
          ;; Delete for everyone
          *delete-for-everyone-time-limit*
          delete-message-for-all
          delete-message-for-self
          notify-message-deleted
          ;; Metadata minimization
          *metadata-minimization-enabled*
          *minimal-metadata-retention-period*
          authenticate-minimal
          log-minimal-connection-info
          cleanup-old-metadata
          start-metadata-cleanup-worker
          get-privacy-stats
          ;; Privacy settings
          user-privacy-settings
          make-user-privacy-settings
          user-privacy-settings-hide-online-status
          user-privacy-settings-hide-read-receipt
          user-privacy-settings-show-profile-photo
          user-privacy-settings-show-last-seen
          get-user-privacy-settings
          set-user-privacy-settings
          user-hides-online-status
          user-hides-read-receipt
          can-show-user-profile-photo
          can-show-user-last-seen
          clear-user-privacy-settings-cache
          ;; Initialization
          init-privacy-features
          shutdown-privacy-features
          ensure-disappearing-message-tables-exist)
    :lispim-core)
