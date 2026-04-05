;;;; user-status.lisp - 用户状态/动态功能
;;;;
;;;; 参考 WhatsApp Status、微信朋友圈、Instagram Stories
;;;; 功能：
;;;; - 24 小时过期状态
;;;; - 状态查看统计
;;;; - 状态媒体处理

(in-package :lispim-core)

;;;; 依赖声明

(eval-when (:compile-toplevel :load-toplevel :execute)
  (ql:quickload '(:postmodern :cl-redis :bordeaux-threads :cl-json :uuid)))

;;;; 类型定义

(defstruct user-status
  "用户状态结构"
  (id 0 :type integer)
  (user-id "" :type string)
  (username "" :type string)
  (user-avatar "" :type string)
  (content "" :type string)
  (media-type :text :type (member :text :image :video))
  (media-url nil :type (or null string))
  (thumbnail-url nil :type (or null string))
  (expires-in 86400 :type integer)  ; 过期时间（秒），默认 24 小时
  (created-at (get-universal-time) :type integer)
  (expires-at 0 :type integer)
  (viewer-count 0 :type integer)
  (viewers nil :type list))

;;;; 全局缓存

(defvar *user-status-cache* (make-hash-table :test 'equal)
  "用户状态缓存")

(defvar *user-status-lock* (bordeaux-threads:make-lock "user-status-lock")
  "用户状态缓存锁")

;;;; 状态创建

(defun create-user-status (user-id content &key username user-avatar media-type media-file expires-in)
  "创建用户状态"
  (declare (type string user-id content)
           (type (or null string) username user-avatar media-file)
           (type (member :text :image :video) media-type)
           (type integer expires-in))
  (let* ((status-id (or (gethash (format nil "status:~A:~A" user-id (get-universal-time)) *user-status-cache*)
                        (incf *reactions-counter*)))
         (created-at (get-universal-time))
         (expires-at (+ created-at expires-in))
         (media-url (when media-file
                      (generate-media-url user-id status-id media-file)))
         (thumbnail-url (when (and media-file (eq media-type :video))
                          (generate-thumbnail-url user-id status-id))))
    (let ((status (make-user-status
                   :id status-id
                   :user-id user-id
                   :username (or username "")
                   :user-avatar (or user-avatar "")
                   :content content
                   :media-type media-type
                   :media-url media-url
                   :thumbnail-url thumbnail-url
                   :expires-in expires-in
                   :created-at created-at
                   :expires-at expires-at)))
      ;; 保存到数据库
      (save-status-to-db status)
      ;; 添加到缓存
      (cache-user-status status)
      ;; 添加到用户状态列表
      (add-to-user-status-list user-id status-id)
      ;; 通知好友
      (notify-friends-of-status user-id status-id)
      status)))

(defun get-user-status (status-id)
  "获取用户状态"
  (declare (type integer status-id))
  (or (gethash status-id *user-status-cache*)
      (get-status-from-db status-id)))

(defun get-friends-statuses (user-id)
  "获取好友状态列表"
  (declare (type string user-id))
  (let* ((friend-ids (get-friend-list user-id))
         (statuses nil))
    (dolist (friend-id friend-ids)
      (let* ((status-ids (get-user-status-list friend-id))
             (now (get-universal-time)))
        (dolist (status-id status-ids)
          (let ((status (get-user-status status-id)))
            (when (and status
                       (< now (user-status-expires-at status)))
              (push status statuses))))))
    ;; 按创建时间倒序排序
    (sort statuses #'> :key #'user-status-created-at)))

(defun delete-user-status (user-id status-id)
  "删除用户状态"
  (declare (type string user-id)
           (type integer status-id))
  (let ((status (get-user-status status-id)))
    (when (and status (string= (user-status-user-id status) user-id))
      ;; 从数据库删除
      (delete-status-from-db status-id)
      ;; 从缓存移除
      (remhash status-id *user-status-cache*)
      ;; 从用户状态列表移除
      (remove-from-user-status-list user-id status-id)
      t)))

;;;; 状态查看

(defun view-status (status-id viewer-id)
  "查看状态（增加观看次数）"
  (declare (type integer status-id)
           (type string viewer-id))
  (let ((status (get-user-status status-id)))
    (when status
      ;; 检查是否已查看
      (unless (member viewer-id (user-status-viewers status) :test #'string=)
        ;; 增加查看次数
        (incf (user-status-viewer-count status))
        ;; 添加查看者
        (push viewer-id (user-status-viewers status))
        ;; 更新缓存
        (setf (gethash status-id *user-status-cache*) status)
        ;; 更新数据库
        (update-status-viewers status-id (user-status-viewer-count status) (user-status-viewers status)))
      t)))

;;;; 媒体处理

(defun generate-media-url (user-id status-id media-file)
  "生成媒体文件 URL"
  (declare (type string user-id media-file)
           (type integer status-id))
  (let* ((filename (format nil "~A_~A_~A" user-id status-id (uuid:make-v4-uuid)))
         (url (format nil "/api/v1/status/media/~A" filename)))
    ;; 保存媒体文件到存储
    (save-status-media filename media-file)
    url))

(defun generate-thumbnail-url (user-id status-id)
  "生成视频缩略图 URL"
  (declare (type string user-id)
           (type integer status-id))
  (format nil "/api/v1/status/thumbnail/~A_~A" user-id status-id))

(defun save-status-media (filename media-file)
  "保存状态媒体文件"
  (declare (type string filename media-file))
  ;; TODO: 集成文件存储系统
  (log-message :info "Saving status media: ~A" filename))

;;;; 数据库操作

(defun save-status-to-db (status)
  "保存状态到数据库"
  (declare (type user-status status))
  (ensure-pg-connected)
  (postmodern:query
   (format nil
           "INSERT INTO user_statuses
            (id, user_id, username, user_avatar, content, media_type, media_url, thumbnail_url,
             expires_in, created_at, expires_at, viewer_count, viewers)
            VALUES (~A, '~A', '~A', '~A', '~A', '~A', '~A', '~A', ~A, to_timestamp(~A), to_timestamp(~A), ~A, '~A')"
           (user-status-id status)
           (user-status-user-id status)
           (user-status-username status)
           (user-status-user-avatar status)
           (escape-string (user-status-content status))
           (symbol-name (user-status-media-type status))
           (or (user-status-media-url status) "")
           (or (user-status-thumbnail-url status) "")
           (user-status-expires-in status)
           (user-status-created-at status)
           (user-status-expires-at status)
           (user-status-viewer-count status)
           (with-output-to-string (s)
             (cl-json:encode-json (user-status-viewers status) s)))))

(defun get-status-from-db (status-id)
  "从数据库获取状态"
  (declare (type integer status-id))
  (ensure-pg-connected)
  (let ((result (postmodern:query
                 (format nil
                         "SELECT id, user_id, username, user_avatar, content, media_type,
                                 media_url, thumbnail_url, expires_in,
                                 EXTRACT(EPOCH FROM created_at)::INTEGER,
                                 EXTRACT(EPOCH FROM expires_at)::INTEGER,
                                 viewer_count, viewers
                          FROM user_statuses
                          WHERE id = $1"
                         status-id)
                 :single)))
    (when result
      (destructuring-bind (id user-id username user-avatar content media-type media-url thumbnail-url expires-in created-at expires-at viewer-count viewers-json)
          result
        (let ((status (make-user-status
                       :id id
                       :user-id user-id
                       :username username
                       :user-avatar user-avatar
                       :content content
                       :media-type (intern (string media-type) :keyword)
                       :media-url media-url
                       :thumbnail-url thumbnail-url
                       :expires-in expires-in
                       :created-at created-at
                       :expires-at expires-at
                       :viewer-count viewer-count
                       :viewers (handler-case (cl-json:decode-json-from-string viewers-json)
                                  (condition (e)
                                    (declare (ignore e))
                                    nil)))))
          ;; 缓存
          (setf (gethash id *user-status-cache*) status)
          status)))))

(defun delete-status-from-db (status-id)
  "从数据库删除状态"
  (declare (type integer status-id))
  (ensure-pg-connected)
  (postmodern:query (format nil "DELETE FROM user_statuses WHERE id = ~A" status-id)))

(defun update-status-viewers (status-id viewer-count viewers)
  "更新状态查看者"
  (declare (type integer status-id viewer-count)
           (type list viewers))
  (ensure-pg-connected)
  (postmodern:query
   (format nil
           "UPDATE user_statuses
            SET viewer_count = $1, viewers = $2
            WHERE id = $3"
           viewer-count
           (with-output-to-string (s)
             (cl-json:encode-json viewers s))
           status-id)))

;;;; 缓存和列表管理

(defun cache-user-status (status)
  "缓存用户状态"
  (declare (type user-status status))
  (bordeaux-threads:with-lock-held (*user-status-lock*)
    (setf (gethash (user-status-id status) *user-status-cache*) status)))

(defun add-to-user-status-list (user-id status-id)
  "添加到用户状态列表"
  (declare (type string user-id)
           (type integer status-id))
  (with-redis-lock ()
    (redis-zadd (format nil "lispim:status:users:~A" user-id)
                (get-universal-time)
                status-id)))

(defun get-user-status-list (user-id)
  "获取用户状态 ID 列表"
  (declare (type string user-id))
  (with-redis-lock ()
    (redis-zrange (format nil "lispim:status:users:~A" user-id) 0 -1)))

(defun remove-from-user-status-list (user-id status-id)
  "从用户状态列表移除"
  (declare (type string user-id)
           (type integer status-id))
  (with-redis-lock ()
    (redis-zrem (format nil "lispim:status:users:~A" user-id) status-id)))

;;;; 通知

(defun notify-friends-of-status (user-id status-id)
  "通知好友有新状态"
  (declare (type string user-id)
           (type integer status-id))
  (let ((friend-ids (get-friend-list user-id)))
    (dolist (friend-id friend-ids)
      ;; 通过 WebSocket 推送通知
      (send-notification-to-user friend-id :new-status
                                 `(:userId ,user-id
                                   :statusId ,status-id)))))

;;;; 辅助函数

(defun get-friend-list (user-id)
  "获取好友列表"
  (declare (type string user-id))
  ;; TODO: 从 storage.lisp 获取
  (get-friends user-id))

(defun send-notification-to-user (user-id type data)
  "发送通知给用户"
  (declare (type string user-id type)
           (type list data))
  ;; TODO: 集成通知系统
  (log-message :info "Sending notification to ~A: ~A" user-id type))

(defun escape-string (str)
  "转义字符串用于 SQL"
  (declare (type string str))
  (replace-re-all "[']" "''" str))

;;;; 数据库表初始化

(defun init-user-status-db ()
  "初始化用户状态数据库表"
  (ensure-pg-connected)
  (handler-case
      (progn
        ;; 创建用户状态表
        (postmodern:query
         "CREATE TABLE IF NOT EXISTS user_statuses (
            id BIGINT PRIMARY KEY,
            user_id VARCHAR(64) NOT NULL,
            username VARCHAR(128),
            user_avatar VARCHAR(512),
            content TEXT,
            media_type VARCHAR(16) DEFAULT 'text',
            media_url VARCHAR(512),
            thumbnail_url VARCHAR(512),
            expires_in INTEGER DEFAULT 86400,
            created_at TIMESTAMPTZ DEFAULT NOW(),
            expires_at TIMESTAMPTZ NOT NULL,
            viewer_count INTEGER DEFAULT 0,
            viewers JSONB DEFAULT '[]'
          )")
        ;; 创建索引
        (postmodern:query
         "CREATE INDEX IF NOT EXISTS idx_user_statuses_user_id
          ON user_statuses(user_id)")
        (postmodern:query
         "CREATE INDEX IF NOT EXISTS idx_user_statuses_expires_at
          ON user_statuses(expires_at)")
        (log-message :info "User status table initialized"))
    (condition (e)
      (log-message :error "Failed to initialize user status table: ~A" e))))

;;;; 过期状态清理

(defun cleanup-expired-statuses ()
  "清理过期状态"
  (ensure-pg-connected)
  (let ((now (get-universal-time)))
    (postmodern:query
     (format nil "DELETE FROM user_statuses WHERE expires_at < to_timestamp(~A)" now))
    (log-message :info "Cleaned up expired statuses")))

;; 启动定期清理任务
(defun start-status-cleanup-task ()
  "启动状态清理任务"
  (bordeaux-threads:make-thread
   (lambda ()
     (loop do
           (sleep 3600) ; 每小时清理一次
           (cleanup-expired-statuses)))))

;;;; API 辅助函数

(defun user-status-to-plist (status)
  "转换用户状态为 plist"
  (declare (type user-status status))
  `(:id ,(user-status-id status)
        :userId ,(user-status-user-id status)
        :username ,(user-status-username status)
        :userAvatar ,(user-status-user-avatar status)
        :content ,(user-status-content status)
        :mediaType ,(symbol-name (user-status-media-type status))
        :mediaUrl ,(user-status-media-url status)
        :thumbnailUrl ,(user-status-thumbnail-url status)
        :expiresIn ,(user-status-expires-in status)
        :createdAt ,(user-status-created-at status)
        :expiresAt ,(user-status-expires-at status)
        :viewerCount ,(user-status-viewer-count status)
        :viewers ,(user-status-viewers status)))

;; 导出公共函数
(export '(create-user-status
          get-user-status
          get-friends-statuses
          delete-user-status
          view-status
          init-user-status-db
          start-status-cleanup-task
          user-status-to-plist))
