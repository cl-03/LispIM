;;;; group-channels.lisp - 群组频道功能
;;;;
;;;; 参考 Discord 频道功能
;;;; 功能：
;;;; - 文本频道
;;;; - 语音频道
;;;; - 频道分类
;;;; - 频道权限

(in-package :lispim-core)

;;;; 依赖声明

(eval-when (:compile-toplevel :load-toplevel :execute)
  (ql:quickload '(:postmodern :cl-redis :bordeaux-threads :cl-json :uuid)))

;;;; 类型定义

(defstruct group-channel
  "群组频道结构"
  (id 0 :type integer)
  (group-id 0 :type integer)
  (name "" :type string)
  (description "" :type string)
  (type :text :type (member :text :voice :category))
  (parent-id nil :type (or null integer))
  (position 0 :type integer)
  (is-muted nil :type boolean)
  (member-count 0 :type integer)
  (created-at (get-universal-time) :type integer))

;;;; 全局缓存

(defvar *group-channels-cache* (make-hash-table :test 'eql)
  "群组频道缓存")

(defvar *group-channels-lock* (bordeaux-threads:make-lock "group-channels-lock")
  "群组频道缓存锁")

;;;; 频道创建

(defun create-group-channel (group-id name type &key description parent-id)
  "创建群组频道"
  (declare (type integer group-id)
           (type string name)
           (type (member :text :voice :category) type))
  (let* ((channel-id (incf *reactions-counter*))
         (position (get-next-channel-position group-id))
         (channel (make-group-channel
                   :id channel-id
                   :group-id group-id
                   :name name
                   :description (or description "")
                   :type type
                   :parent-id parent-id
                   :position position)))
    ;; 保存到数据库
    (save-channel-to-db channel)
    ;; 添加到缓存
    (cache-group-channel group-id channel)
    ;; 通知群成员
    (notify-group-members group-id :channel-created channel)
    channel))

(defun get-group-channels (group-id)
  "获取群组频道列表"
  (declare (type integer group-id))
  (or (gethash group-id *group-channels-cache*)
      (progn
        (let ((channels (get-channels-from-db group-id)))
          (when channels
            (bordeaux-threads:with-lock-held (*group-channels-lock*)
              (setf (gethash group-id *group-channels-cache*) channels))
            channels)))))

(defun get-group-channel (group-id channel-id)
  "获取单个频道"
  (declare (type integer group-id channel-id))
  (let ((channels (get-group-channels group-id)))
    (find-if (lambda (c) (= (group-channel-id c) channel-id)) channels)))

(defun update-group-channel (group-id channel-id &key name description type parent-id is-muted)
  "更新频道"
  (declare (type integer group-id channel-id))
  (let ((channel (get-group-channel group-id channel-id)))
    (when channel
      (when name (setf (group-channel-name channel) name))
      (when description (setf (group-channel-description channel) description))
      (when type (setf (group-channel-type channel) type))
      (when parent-id (setf (group-channel-parent-id channel) parent-id))
      (when is-muted (setf (group-channel-is-muted channel) is-muted))
      ;; 更新数据库
      (update-channel-in-db channel)
      ;; 更新缓存
      (cache-group-channel-group group-id channel)
      ;; 通知群成员
      (notify-group-members group-id :channel-updated channel)
      channel)))

(defun delete-group-channel (group-id channel-id)
  "删除频道"
  (declare (type integer group-id channel-id))
  (let ((channels (get-group-channels group-id)))
    (when (and channels (find-if (lambda (c) (= (group-channel-id c) channel-id)) channels))
      ;; 从数据库删除
      (delete-channel-from-db channel-id)
      ;; 从缓存移除
      (setf (gethash group-id *group-channels-cache*)
            (remove-if (lambda (c) (= (group-channel-id c) channel-id)) channels))
      ;; 通知群成员
      (notify-group-members group-id :channel-deleted (list :id channel-id))
      t)))

;;;; 频道切换

(defun switch-channel (channel-id user-id)
  "切换到指定频道"
  (declare (type integer channel-id)
           (type string user-id))
  (let ((channel (get-channel-by-id channel-id)))
    (when channel
      ;; 记录用户当前频道
      (set-user-current-channel user-id channel-id)
      ;; 加入频道（语音频道）
      (when (eq (group-channel-type channel) :voice)
        (join-voice-channel channel-id user-id))
      channel)))

;;;; 数据库操作

(defun save-channel-to-db (channel)
  "保存频道到数据库"
  (declare (type group-channel channel))
  (ensure-pg-connected)
  (postmodern:query
   (format nil
           "INSERT INTO group_channels
            (id, group_id, name, description, type, parent_id, position, is_muted, member_count, created_at)
            VALUES (~A, ~A, '~A', '~A', '~A', ~:[NULL~;~A~], ~A, ~A, ~A, to_timestamp(~A))"
           (group-channel-id channel)
           (group-channel-group-id channel)
           (group-channel-name channel)
           (group-channel-description channel)
           (symbol-name (group-channel-type channel))
           (group-channel-parent-id channel)
           (group-channel-position channel)
           (if (group-channel-is-muted channel) "true" "false")
           (group-channel-member-count channel)
           (group-channel-created-at channel))))

(defun get-channels-from-db (group-id)
  "从数据库获取频道"
  (declare (type integer group-id))
  (ensure-pg-connected)
  (let ((results (postmodern:query
                  (format nil
                          "SELECT id, group_id, name, description, type, parent_id,
                                  position, is_muted, member_count,
                                  EXTRACT(EPOCH FROM created_at)::INTEGER
                           FROM group_channels
                           WHERE group_id = ~A
                           ORDER BY position"
                          group-id))))
    (when results
      (mapcar (lambda (row)
                (destructuring-bind (id gid name description type parent-id position is-muted member-count created-at)
                    row
                  (make-group-channel
                   :id id
                   :group-id gid
                   :name name
                   :description description
                   :type (intern (string type) :keyword)
                   :parent-id parent-id
                   :position position
                   :is-muted is-muted
                   :member-count member-count
                   :created-at created-at))))
              results)))

(defun get-channel-by-id (channel-id)
  "根据 ID 获取频道"
  (declare (type integer channel-id))
  (ensure-pg-connected)
  (let ((result (postmodern:query
                 (format nil
                         "SELECT id, group_id, name, description, type, parent_id,
                                 position, is_muted, member_count,
                                 EXTRACT(EPOCH FROM created_at)::INTEGER
                          FROM group_channels
                          WHERE id = $1"
                         channel-id)
                 :single)))
    (when result
      (destructuring-bind (id gid name description type parent-id position is-muted member-count created-at)
          result
        (make-group-channel
         :id id
         :group-id gid
         :name name
         :description description
         :type (intern (string type) :keyword)
         :parent-id parent-id
         :position position
         :is-muted is-muted
         :member-count member-count
         :created-at created-at)))))

(defun update-channel-in-db (channel)
  "更新数据库频道"
  (declare (type group-channel channel))
  (ensure-pg-connected)
  (postmodern:query
   (format nil
           "UPDATE group_channels
            SET name = '~A', description = '~A', type = '~A', parent_id = ~A,
                position = ~A, is_muted = ~A
            WHERE id = ~A"
           (group-channel-name channel)
           (group-channel-description channel)
           (symbol-name (group-channel-type channel))
           (if (group-channel-parent-id channel) (group-channel-parent-id channel) "NULL")
           (group-channel-position channel)
           (if (group-channel-is-muted channel) "true" "false")
           (group-channel-id channel))))

(defun delete-channel-from-db (channel-id)
  "从数据库删除频道"
  (declare (type integer channel-id))
  (ensure-pg-connected)
  (postmodern:query (format nil "DELETE FROM group_channels WHERE id = ~A" channel-id)))

;;;; 缓存管理

(defun cache-group-channel (group-id channel)
  "缓存频道列表"
  (declare (type integer group-id)
           (type group-channel channel))
  (bordeaux-threads:with-lock-held (*group-channels-lock*)
    (let ((channels (gethash group-id *group-channels-cache*)))
      (if channels
          (pushnew channel channels :test #'(lambda (a b) (= (group-channel-id a) (group-channel-id b))))
          (setf (gethash group-id *group-channels-cache*) (list channel))))))

(defun cache-group-channel-group (group-id channel)
  "更新缓存中的频道"
  (declare (type integer group-id)
           (type group-channel channel))
  (bordeaux-threads:with-lock-held (*group-channels-lock*)
    (let ((channels (gethash group-id *group-channels-cache*)))
      (when channels
        (let ((existing (find-if (lambda (c) (= (group-channel-id c) (group-channel-id channel))) channels)))
          (when existing
            (setf (car (member existing channels)) channel)))))))

;;;; 语音频道管理

(defun join-voice-channel (channel-id user-id)
  "加入语音频道"
  (declare (type integer channel-id)
           (type string user-id))
  (with-redis-lock ()
    (redis-sadd (format nil "lispim:voice:channel:~A" channel-id) user-id)
    ;; 更新成员计数
    (let ((count (redis-scard (format nil "lispim:voice:channel:~A" channel-id))))
      (update-channel-member-count channel-id count))
    ;; 通知频道内其他用户
    (notify-channel-members channel-id :user-joined user-id)))

(defun leave-voice-channel (channel-id user-id)
  "离开语音频道"
  (declare (type integer channel-id)
           (type string user-id))
  (with-redis-lock ()
    (redis-srem (format nil "lispim:voice:channel:~A" channel-id) user-id)
    ;; 更新成员计数
    (let ((count (redis-scard (format nil "lispim:voice:channel:~A" channel-id))))
      (update-channel-member-count channel-id count))
    ;; 通知频道内其他用户
    (notify-channel-members channel-id :user-left user-id)))

(defun get-voice-channel-members (channel-id)
  "获取语音频道成员"
  (declare (type integer channel-id))
  (with-redis-lock ()
    (redis-smembers (format nil "lispim:voice:channel:~A" channel-id))))

(defun update-channel-member-count (channel-id count)
  "更新频道成员计数"
  (declare (type integer channel-id count))
  (ensure-pg-connected)
  (postmodern:query
   (format nil "UPDATE group_channels SET member_count = ~A WHERE id = ~A" count channel-id)))

;;;; 用户当前频道跟踪

(defun set-user-current-channel (user-id channel-id)
  "设置用户当前频道"
  (declare (type string user-id)
           (type integer channel-id))
  (with-redis-lock ()
    (redis-set (format nil "lispim:user:channel:~A" user-id) channel-id)))

(defun get-user-current-channel (user-id)
  "获取用户当前频道"
  (declare (type string user-id))
  (with-redis-lock ()
    (let ((result (redis-get (format nil "lispim:user:channel:~A" user-id))))
      (when result (parse-integer result)))))

;;;; 辅助函数

(defun get-next-channel-position (group-id)
  "获取下一个频道位置"
  (declare (type integer group-id))
  (let ((channels (get-group-channels group-id)))
    (if channels
        (1+ (reduce #'max channels :key #'group-channel-position :initial-value 0))
        0)))

(defun notify-group-members (group-id event data)
  "通知群成员"
  (declare (type integer group-id event)
           (type list data))
  ;; TODO: 通过 WebSocket 推送
  (log-message :info "Notifying group ~A members of ~A" group-id event))

(defun notify-channel-members (channel-id event user-id)
  "通知频道成员"
  (declare (type integer channel-id event)
           (type string user-id))
  ;; 获取频道成员
  (let ((members (get-voice-channel-members channel-id)))
    (dolist (member-id members)
      (unless (string= member-id user-id)
        (send-notification-to-user member-id event
                                   `(:channelId ,channel-id
                                     :userId ,user-id))))))

;;;; 数据库表初始化

(defun init-group-channels-db ()
  "初始化群组频道数据库表"
  (ensure-pg-connected)
  (handler-case
      (progn
        ;; 创建群组频道表
        (postmodern:query
         "CREATE TABLE IF NOT EXISTS group_channels (
            id BIGINT PRIMARY KEY,
            group_id BIGINT NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
            name VARCHAR(128) NOT NULL,
            description TEXT,
            type VARCHAR(16) NOT NULL DEFAULT 'text',
            parent_id BIGINT REFERENCES group_channels(id) ON DELETE CASCADE,
            position INTEGER DEFAULT 0,
            is_muted BOOLEAN DEFAULT false,
            member_count INTEGER DEFAULT 0,
            created_at TIMESTAMPTZ DEFAULT NOW()
          )")
        ;; 创建索引
        (postmodern:query
         "CREATE INDEX IF NOT EXISTS idx_group_channels_group_id
          ON group_channels(group_id)")
        (postmodern:query
         "CREATE INDEX IF NOT EXISTS idx_group_channels_parent_id
          ON group_channels(parent_id)")
        (postmodern:query
         "CREATE INDEX IF NOT EXISTS idx_group_channels_position
          ON group_channels(position)")
        (log-message :info "Group channels table initialized"))
    (condition (e)
      (log-message :error "Failed to initialize group channels table: ~A" e))))

;;;; API 辅助函数

(defun group-channel-to-plist (channel)
  "转换频道为 plist"
  (declare (type group-channel channel))
  `(:id ,(group-channel-id channel)
        :groupId ,(group-channel-group-id channel)
        :name ,(group-channel-name channel)
        :description ,(group-channel-description channel)
        :type ,(symbol-name (group-channel-type channel))
        :parentId ,(group-channel-parent-id channel)
        :position ,(group-channel-position channel)
        :isMuted ,(group-channel-is-muted channel)
        :memberCount ,(group-channel-member-count channel)
        :createdAt ,(group-channel-created-at channel)))

;; 导出公共函数
(export '(create-group-channel
          get-group-channels
          get-group-channel
          update-group-channel
          delete-group-channel
          switch-channel
          join-voice-channel
          leave-voice-channel
          get-voice-channel-members
          init-group-channels-db
          group-channel-to-plist))
