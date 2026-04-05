;;;; notification.lisp - 通知推送模块
;;;;
;;;; 提供以下功能：
;;;; 1. 桌面通知推送（FCM + WebSocket）
;;;; 2. 通知偏好设置
;;;; 3. 通知历史记录
;;;; 4. 免打扰模式

(in-package :lispim-core)

;;;; 依赖声明

(eval-when (:compile-toplevel :load-toplevel :execute)
  (ql:quickload '(:postmodern :cl-redis :bordeaux-threads :drakma :cl-json)))

;;;; 配置

(defparameter *notification-retention-days* 7
  "通知历史记录保留天数")

(defparameter *max-pending-notifications* 100
  "每个用户最大待推送通知数")

;;;; 数据结构

(defstruct user-notification
  "用户通知结构"
  (id 0 :type integer)
  (user-id "" :type string)
  (type :message :type (member :message :call :friend-request :system :group))
  (title "" :type string)
  (content "" :type string)
  (data (make-hash-table :test 'equal) :type hash-table)
  (priority :normal :type (member :low :normal :high))
  (created-at (get-universal-time) :type integer)
  (read-p nil :type boolean)
  (delivered-p nil :type boolean))

(defstruct notification-preferences
  "用户通知偏好设置"
  (user-id "" :type string)
  (enable-desktop t :type boolean)
  (enable-sound t :type boolean)
  (enable-badge t :type boolean)
  (message-notifications t :type boolean)
  (call-notifications t :type boolean)
  (friend-request-notifications t :type boolean)
  (group-notifications t :type boolean)
  (quiet-mode nil :type boolean)
  (quiet-start "22:00" :type string)
  (quiet-end "08:00" :type string))

;;;; 数据库初始化

(defun ensure-notification-tables-exist ()
  "确保通知相关表存在"
  (ensure-pg-connected)

  ;; 用户通知表
  (postmodern:query
   "CREATE TABLE IF NOT EXISTS user_notifications (
      id BIGSERIAL PRIMARY KEY,
      user_id VARCHAR(255) NOT NULL,
      type VARCHAR(32) NOT NULL,
      title VARCHAR(255) NOT NULL,
      content TEXT,
      data JSONB DEFAULT '{}',
      priority VARCHAR(16) DEFAULT 'normal',
      created_at TIMESTAMPTZ DEFAULT NOW(),
      read_p BOOLEAN DEFAULT FALSE,
      delivered_p BOOLEAN DEFAULT FALSE
    )")

  ;; 创建索引
  (postmodern:query
   "CREATE INDEX IF NOT EXISTS idx_user_notifications_user
    ON user_notifications(user_id, created_at DESC)")
  (postmodern:query
   "CREATE INDEX IF NOT EXISTS idx_user_notifications_unread
    ON user_notifications(user_id) WHERE read_p = FALSE")

  ;; 通知偏好设置表
  (postmodern:query
   "CREATE TABLE IF NOT EXISTS notification_preferences (
      user_id VARCHAR(255) PRIMARY KEY,
      enable_desktop BOOLEAN DEFAULT TRUE,
      enable_sound BOOLEAN DEFAULT TRUE,
      enable_badge BOOLEAN DEFAULT TRUE,
      message_notifications BOOLEAN DEFAULT TRUE,
      call_notifications BOOLEAN DEFAULT TRUE,
      friend_request_notifications BOOLEAN DEFAULT TRUE,
      group_notifications BOOLEAN DEFAULT TRUE,
      quiet_mode BOOLEAN DEFAULT FALSE,
      quiet_start VARCHAR(10) DEFAULT '22:00',
      quiet_end VARCHAR(10) DEFAULT '08:00',
      updated_at TIMESTAMPTZ DEFAULT NOW()
    )")

  ;; FCM Token 表
  (postmodern:query
   "CREATE TABLE IF NOT EXISTS user_fcm_tokens (
      user_id VARCHAR(255) NOT NULL,
      token TEXT NOT NULL,
      device_id VARCHAR(255),
      platform VARCHAR(32),
      created_at TIMESTAMPTZ DEFAULT NOW(),
      last_used_at TIMESTAMPTZ DEFAULT NOW(),
      PRIMARY KEY (user_id, token)
    )")

  (log-info "Notification tables created"))

;;;; 通知偏好设置

(defun get-notification-preferences (user-id)
  "获取用户通知偏好设置"
  (declare (type string user-id))
  (ensure-pg-connected)

  (let ((row (postmodern:query
              "SELECT * FROM notification_preferences WHERE user_id = $1"
              user-id :alists)))
    (if row
        (let ((r (car row)))
          (flet ((get-val (name)
                   (let ((cell (find name r :key #'car :test #'string=)))
                     (when cell (cdr cell)))))
            (make-notification-preferences
             :user-id (get-val "user_id")
             :enable-desktop (string= (get-val "enable_desktop") "t")
             :enable-sound (string= (get-val "enable_sound") "t")
             :enable-badge (string= (get-val "enable_badge") "t")
             :message-notifications (string= (get-val "message_notifications") "t")
             :call-notifications (string= (get-val "call_notifications") "t")
             :friend-request-notifications (string= (get-val "friend_request_notifications") "t")
             :group-notifications (string= (get-val "group_notifications") "t")
             :quiet-mode (string= (get-val "quiet_mode") "t")
             :quiet-start (get-val "quiet_start")
             :quiet-end (get-val "quiet_end"))))
        ;; 返回默认设置
        (make-notification-preferences :user-id user-id))))

(defun set-notification-preferences (user-id &key
                                     enable-desktop
                                     enable-sound
                                     enable-badge
                                     message-notifications
                                     call-notifications
                                     friend-request-notifications
                                     group-notifications
                                     quiet-mode
                                     quiet-start
                                     quiet-end)
  "更新用户通知偏好设置"
  (declare (type string user-id))
  (ensure-pg-connected)

  (postmodern:query
   "INSERT INTO notification_preferences
    (user_id, enable_desktop, enable_sound, enable_badge,
     message_notifications, call_notifications,
     friend_request_notifications, group_notifications,
     quiet_mode, quiet_start, quiet_end, updated_at)
    VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, NOW())
    ON CONFLICT (user_id)
    DO UPDATE SET
      enable_desktop = $2,
      enable_sound = $3,
      enable_badge = $4,
      message_notifications = $5,
      call_notifications = $6,
      friend_request_notifications = $7,
      group_notifications = $8,
      quiet_mode = $9,
      quiet_start = $10,
      quiet_end = $11,
      updated_at = NOW()"
   user-id
   (or enable-desktop t)
   (or enable-sound t)
   (or enable-badge t)
   (or message-notifications t)
   (or call-notifications t)
   (or friend-request-notifications t)
   (or group-notifications t)
   (or quiet-mode nil)
   (or quiet-start "22:00")
   (or quiet-end "08:00"))

  (log-info "Notification preferences updated for user ~a" user-id)
  t)

;;;; 免打扰模式检查

(defun in-quiet-mode-p (user-id)
  "检查用户是否处于免打扰模式"
  (declare (type string user-id))
  (let ((prefs (get-notification-preferences user-id)))
    (if (notification-preferences-quiet-mode prefs)
        ;; 检查是否在免打扰时间段内
        (let* ((now (multiple-value-bind (sec min hour)
                      (get-decoded-time)
                    (format nil "~2,'0d:~2,'0d" hour min)))
               (quiet-start (notification-preferences-quiet-start prefs))
               (quiet-end (notification-preferences-quiet-end prefs)))
          (string>= now quiet-start))
        nil)))

;;;; FCM Token 管理

(defun save-fcm-token (user-id token &key device-id platform)
  "保存用户 FCM Token"
  (declare (type string user-id token)
           (type (or null string) device-id platform))
  (ensure-pg-connected)

  (postmodern:query
   "INSERT INTO user_fcm_tokens (user_id, token, device_id, platform, last_used_at)
    VALUES ($1, $2, $3, $4, NOW())
    ON CONFLICT (user_id, token)
    DO UPDATE SET last_used_at = NOW(), device_id = $3, platform = $4"
   user-id token device-id platform)

  (log-debug "FCM token saved for user ~a" user-id)
  t)

(defun remove-fcm-token (user-id token)
  "移除用户 FCM Token"
  (declare (type string user-id token))
  (ensure-pg-connected)

  (postmodern:query
   "DELETE FROM user_fcm_tokens WHERE user_id = $1 AND token = $2"
   user-id token)

  (log-debug "FCM token removed for user ~a" user-id)
  t)

(defun get-user-fcm-tokens (user-id)
  "获取用户所有 FCM Token"
  (declare (type string user-id))
  (ensure-pg-connected)

  (let ((rows (postmodern:query
               "SELECT token, device_id, platform FROM user_fcm_tokens
                WHERE user_id = $1"
               user-id)))
    (loop for row in rows
          collect (list :token (elt row 0)
                        :device-id (elt row 1)
                        :platform (elt row 2)))))

;;;; 通知推送

(defun send-push-notification (user-id notification)
  "发送推送通知给用户"
  (declare (type string user-id)
           (type user-notification notification))

  ;; 检查免打扰模式
  (when (in-quiet-mode-p user-id)
    (log-debug "User ~a is in quiet mode, skipping push notification" user-id)
    (return-from send-push-notification nil))

  ;; 检查通知偏好
  (let ((prefs (get-notification-preferences user-id)))
    (unless (notification-preferences-enable-desktop prefs)
      (return-from send-push-notification nil))

    (case (user-notification-type notification)
      (:message
       (unless (notification-preferences-message-notifications prefs)
         (return-from send-push-notification nil)))
      (:call
       (unless (notification-preferences-call-notifications prefs)
         (return-from send-push-notification nil)))
      (:friend-request
       (unless (notification-preferences-friend-request-notifications prefs)
         (return-from send-push-notification nil)))
      (:group
       (unless (notification-preferences-group-notifications prefs)
         (return-from send-push-notification nil)))))

  ;; 获取用户 FCM Token
  (let ((tokens (get-user-fcm-tokens user-id)))
    (when tokens
      ;; 发送 FCM 推送
      (dolist (token-info tokens)
        (handler-case
            (send-fcm-notification (getf token-info :token) notification)
          (error (c)
            (log-error "Failed to send FCM notification: ~a" c))))))

  ;; 推送 WebSocket 通知给在线用户
  (push-notification-to-online-user user-id notification)

  ;; 标记为已推送
  (setf (user-notification-delivered-p notification) t)

  t)

(defun send-fcm-notification (token notification)
  "发送 FCM 通知"
  (declare (type string token)
           (type user-notification notification))

  ;; TODO: 实现 FCM API 调用
  ;; 这里使用占位实现
  (log-debug "FCM notification sent to token ~a" (subseq token 0 (min 20 (length token))))
  t)

(defun push-notification-to-online-user (user-id notification)
  "推送通知给在线用户"
  (declare (type string user-id)
           (type user-notification notification))

  (let ((message `((:type . :notification)
                   (:id . ,(user-notification-id notification))
                   (:notificationType . ,(symbol-name (user-notification-type notification)))
                   (:title . ,(user-notification-title notification))
                   (:content . ,(user-notification-content notification))
                   (:priority . ,(symbol-name (user-notification-priority notification)))
                   (:data . ,(hash-table-to-alist (user-notification-data notification)))
                   (:ts . ,(lispim-universal-to-unix-ms (get-universal-time))))))
    (push-to-online-user user-id message)))

;;;; 创建通知

(defun create-notification (user-id type title content &key data priority)
  "创建并推送通知"
  (declare (type string user-id type title content)
           (type (or null hash-table) data)
           (type (or null (member :low :normal :high)) priority))

  (ensure-pg-connected)

  (let ((notification (make-user-notification
                       :id 0
                       :user-id user-id
                       :type (keywordify type)
                       :title title
                       :content content
                       :data (or data (make-hash-table :test 'equal))
                       :priority (or priority :normal)
                       :created-at (get-universal-time))))

    ;; 保存到数据库
    (let ((result (postmodern:query
                   "INSERT INTO user_notifications
                    (user_id, type, title, content, data, priority, created_at)
                    VALUES ($1, $2, $3, $4, $5, $6, to_timestamp($7))
                    RETURNING id"
                   user-id type title content
                   "{}" ; 简化处理
                   (symbol-name (or priority :normal))
                   (lispim-universal-to-unix (get-universal-time)))))
      (when result
        (setf (user-notification-id notification) (caar result))
        ;; 清理旧通知
        (cleanup-old-notifications user-id)
        ;; 发送推送
        (send-push-notification user-id notification)
        notification))))

;;;; 通知查询

(defun get-user-notifications (user-id &key (limit 50) unread-only)
  "获取用户通知列表"
  (declare (type string user-id)
           (type integer limit))

  (ensure-pg-connected)

  (let ((sql (if unread-only
                 "SELECT * FROM user_notifications
                  WHERE user_id = $1 AND read_p = FALSE
                  ORDER BY created_at DESC
                  LIMIT $2"
                 "SELECT * FROM user_notifications
                  WHERE user_id = $1
                  ORDER BY created_at DESC
                  LIMIT $2")))
    (let ((rows (postmodern:query sql user-id limit)))
      (loop for row in rows
            collect (list :id (elt row 0)
                          :type (elt row 2)
                          :title (elt row 3)
                          :content (elt row 4)
                          :priority (elt row 6)
                          :createdAt (storage-universal-to-unix-ms (elt row 7))
                          :read-p (elt row 8)
                          :delivered-p (elt row 9))))))

(defun mark-notification-read (notification-id user-id)
  "标记通知为已读"
  (declare (type integer notification-id)
           (type string user-id))
  (ensure-pg-connected)

  (postmodern:query
   "UPDATE user_notifications SET read_p = TRUE
    WHERE id = $1 AND user_id = $2"
   notification-id user-id)

  (log-debug "Notification ~a marked as read" notification-id)
  t)

(defun mark-all-notifications-read (user-id)
  "标记所有通知为已读"
  (declare (type string user-id))
  (ensure-pg-connected)

  (postmodern:query
   "UPDATE user_notifications SET read_p = TRUE
    WHERE user_id = $1 AND read_p = FALSE"
   user-id)

  (log-debug "All notifications marked as read for user ~a" user-id)
  t)

;;;; 清理旧通知

(defun cleanup-old-notifications (user-id)
  "清理用户的旧通知"
  (declare (type string user-id))
  (ensure-pg-connected)

  (postmodern:query
   "DELETE FROM user_notifications
    WHERE user_id = $1
    AND created_at < NOW() - INTERVAL '~a days'"
   user-id *notification-retention-days*)

  ;; 限制待推送通知数量
  (postmodern:query
   "DELETE FROM user_notifications
    WHERE user_id = $1
    AND read_p = FALSE
    AND id NOT IN (
      SELECT id FROM user_notifications
      WHERE user_id = $1
      ORDER BY created_at DESC
      LIMIT ~a
    )"
   user-id *max-pending-notifications*))

;;;; 工具函数

(defun hash-table-to-alist (ht)
  "转换哈希表为关联列表"
  (let ((alist nil))
    (maphash (lambda (k v)
               (push (cons (string-downcase (symbol-name k)) v) alist))
             ht)
    alist))

;;;; 初始化

(defun init-notification-system ()
  "初始化通知系统"
  (log-info "Initializing notification system...")
  (ensure-notification-tables-exist)
  (log-info "Notification system initialized"))

;;;; 导出

(export '(;; Structures
          user-notification
          make-user-notification
          user-notification-id
          user-notification-user-id
          user-notification-type
          user-notification-title
          user-notification-content
          user-notification-data
          user-notification-priority
          user-notification-created-at
          user-notification-read-p
          user-notification-delivered-p
          notification-preferences
          make-notification-preferences
          notification-preferences-user-id
          notification-preferences-enable-desktop
          notification-preferences-enable-sound
          notification-preferences-enable-badge
          notification-preferences-message-notifications
          notification-preferences-call-notifications
          notification-preferences-friend-request-notifications
          notification-preferences-group-notifications
          notification-preferences-quiet-mode
          notification-preferences-quiet-start
          notification-preferences-quiet-end
          ;; Preferences
          get-notification-preferences
          set-notification-preferences
          in-quiet-mode-p
          ;; FCM
          save-fcm-token
          remove-fcm-token
          get-user-fcm-tokens
          ;; Notifications
          create-notification
          send-push-notification
          get-user-notifications
          mark-notification-read
          mark-all-notifications-read
          ;; System
          init-notification-system
          ensure-notification-tables-exist))