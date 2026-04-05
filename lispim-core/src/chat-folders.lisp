;;;; chat-folders.lisp - 聊天文件夹功能
;;;;
;;;; 参考 Telegram 聊天文件夹功能
;;;; 功能：
;;;; - 自定义文件夹分类
;;;; - 文件夹内对话管理
;;;; - 文件夹排序

(in-package :lispim-core)

;;;; 依赖声明

(eval-when (:compile-toplevel :load-toplevel :execute)
  (ql:quickload '(:postmodern :cl-redis :bordeaux-threads :cl-json :uuid)))

;;;; 类型定义

(defstruct chat-folder
  "聊天文件夹结构"
  (id 0 :type integer)
  (user-id "" :type string)
  (name "" :type string)
  (icon "" :type string)
  (conversation-ids nil :type list)
  (is-default nil :type boolean)
  (position 0 :type integer)
  (created-at (get-universal-time) :type integer))

;;;; 全局缓存

(defvar *chat-folders-cache* (make-hash-table :test 'equal)
  "聊天文件夹缓存")

(defvar *chat-folders-lock* (bordeaux-threads:make-lock "chat-folders-lock")
  "聊天文件夹缓存锁")

;;;; 文件夹创建

(defun create-chat-folder (user-id name &key icon conversation-ids is-default)
  "创建聊天文件夹"
  (declare (type string user-id name)
           (type (or null string) icon)
           (type list conversation-ids)
           (type boolean is-default))
  (let* ((folder-id (incf *reactions-counter*))
         (position (get-next-folder-position user-id))
         (folder (make-chat-folder
                  :id folder-id
                  :user-id user-id
                  :name name
                  :icon (or icon "📁")
                  :conversation-ids conversation-ids
                  :is-default is-default
                  :position position)))
    ;; 保存到数据库
    (save-folder-to-db folder)
    ;; 添加到缓存
    (cache-chat-folder folder)
    folder))

(defun get-chat-folders (user-id)
  "获取用户文件夹列表"
  (declare (type string user-id))
  (or (gethash user-id *chat-folders-cache*)
      (progn
        (let ((folders (get-folders-from-db user-id)))
          (when folders
            (bordeaux-threads:with-lock-held (*chat-folders-lock*)
              (setf (gethash user-id *chat-folders-cache*) folders))
            folders)))))

(defun get-chat-folder (user-id folder-id)
  "获取单个文件夹"
  (declare (type string user-id)
           (type integer folder-id))
  (let ((folders (get-chat-folders user-id)))
    (find-if (lambda (f) (= (chat-folder-id f) folder-id)) folders)))

(defun update-chat-folder (user-id folder-id &key name icon conversation-ids)
  "更新文件夹"
  (declare (type string user-id)
           (type integer folder-id))
  (let ((folder (get-chat-folder user-id folder-id)))
    (when folder
      (when name (setf (chat-folder-name folder) name))
      (when icon (setf (chat-folder-icon folder) icon))
      (when conversation-ids (setf (chat-folder-conversation-ids folder) conversation-ids))
      ;; 更新数据库
      (update-folder-in-db folder)
      ;; 更新缓存
      (cache-chat-folder-folder user-id folder)
      folder)))

(defun delete-chat-folder (user-id folder-id)
  "删除文件夹"
  (declare (type string user-id)
           (type integer folder-id))
  (let ((folders (get-chat-folders user-id)))
    (when (and folders (find-if (lambda (f) (= (chat-folder-id f) folder-id)) folders))
      ;; 从数据库删除
      (delete-folder-from-db folder-id)
      ;; 从缓存移除
      (setf (gethash user-id *chat-folders-cache*)
            (remove-if (lambda (f) (= (chat-folder-id f) folder-id)) folders))
      t)))

;;;; 对话管理

(defun add-conversation-to-folder (user-id folder-id conversation-id)
  "添加对话到文件夹"
  (declare (type string user-id)
           (type integer folder-id conversation-id))
  (let ((folder (get-chat-folder user-id folder-id)))
    (when folder
      (unless (member conversation-id (chat-folder-conversation-ids folder))
        (push conversation-id (chat-folder-conversation-ids folder))
        (update-folder-in-db folder)
        (cache-chat-folder-folder user-id folder))
      t)))

(defun remove-conversation-from-folder (user-id folder-id conversation-id)
  "从文件夹移除对话"
  (declare (type string user-id)
           (type integer folder-id conversation-id))
  (let ((folder (get-chat-folder user-id folder-id)))
    (when folder
      (setf (chat-folder-conversation-ids folder)
            (remove conversation-id (chat-folder-conversation-ids folder)))
      (update-folder-in-db folder)
      (cache-chat-folder-folder user-id folder)
      t)))

(defun get-folder-conversations (user-id folder-id)
  "获取文件夹内对话"
  (declare (type string user-id)
           (type integer folder-id))
  (let ((folder (get-chat-folder user-id folder-id)))
    (when folder
      (get-conversations-by-ids (chat-folder-conversation-ids folder)))))

;;;; 数据库操作

(defun save-folder-to-db (folder)
  "保存文件夹到数据库"
  (declare (type chat-folder folder))
  (ensure-pg-connected)
  (postmodern:query
   (format nil
           "INSERT INTO chat_folders
            (id, user_id, name, icon, conversation_ids, is_default, position, created_at)
            VALUES ($1, $2, $3, $4, $5, $6, $7, to_timestamp($8))"
           (chat-folder-id folder)
           (chat-folder-user-id folder)
           (chat-folder-name folder)
           (chat-folder-icon folder)
           (with-output-to-string (s)
             (cl-json:encode-json (chat-folder-conversation-ids folder) s))
           (chat-folder-is-default folder)
           (chat-folder-position folder)
           (chat-folder-created-at folder))))

(defun get-folders-from-db (user-id)
  "从数据库获取文件夹"
  (declare (type string user-id))
  (ensure-pg-connected)
  (let ((results (postmodern:query
                  (format nil
                          "SELECT id, user_id, name, icon, conversation_ids,
                                  is_default, position,
                                  EXTRACT(EPOCH FROM created_at)::INTEGER
                           FROM chat_folders
                           WHERE user_id = '~A'
                           ORDER BY position"
                          user-id))))
    (when results
      (mapcar (lambda (row)
                (destructuring-bind (id uid name icon conv-ids-json is-default position created-at)
                    row
                  (make-chat-folder
                   :id id
                   :user-id uid
                   :name name
                   :icon icon
                   :conversation-ids (handler-case (cl-json:decode-json-from-string conv-ids-json)
                                       (condition (e)
                                         (declare (ignore e))
                                         nil))
                   :is-default is-default
                   :position position
                   :created-at created-at)))
              results))))

(defun update-folder-in-db (folder)
  "更新数据库文件夹"
  (declare (type chat-folder folder))
  (ensure-pg-connected)
  (postmodern:query
   (format nil
           "UPDATE chat_folders
            SET name = '~A', icon = '~A', conversation_ids = '~A', is_default = ~A
            WHERE id = ~A"
           (chat-folder-name folder)
           (chat-folder-icon folder)
           (with-output-to-string (s) (cl-json:encode-json (chat-folder-conversation-ids folder) s))
           (if (chat-folder-is-default folder) "true" "false")
           (chat-folder-id folder))))

(defun delete-folder-from-db (folder-id)
  "从数据库删除文件夹"
  (declare (type integer folder-id))
  (ensure-pg-connected)
  (postmodern:query (format nil "DELETE FROM chat_folders WHERE id = ~A" folder-id)))

;;;; 缓存管理

(defun cache-chat-folder (folders)
  "缓存文件夹列表"
  (declare (type list folders))
  (bordeaux-threads:with-lock-held (*chat-folders-lock*)
    (when folders
      (let ((user-id (chat-folder-user-id (car folders))))
        (setf (gethash user-id *chat-folders-cache*) folders)))))

(defun cache-chat-folder-folder (user-id folder)
  "缓存单个文件夹"
  (declare (type string user-id)
           (type chat-folder folder))
  (bordeaux-threads:with-lock-held (*chat-folders-lock*)
    (let ((folders (gethash user-id *chat-folders-cache*)))
      (if folders
          (let ((existing (find-if (lambda (f) (= (chat-folder-id f) (chat-folder-id folder))) folders)))
            (if existing
                (setf (car (member existing folders)) folder)
                (push folder folders)))
          (setf (gethash user-id *chat-folders-cache*) (list folder))))))

;;;; 辅助函数

(defun get-next-folder-position (user-id)
  "获取下一个文件夹位置"
  (declare (type string user-id))
  (let ((folders (get-chat-folders user-id)))
    (if folders
        (1+ (reduce #'max folders :key #'chat-folder-position :initial-value 0))
        0)))

(defun get-conversations-by-ids (conversation-ids)
  "根据 ID 列表获取对话"
  (declare (type list conversation-ids))
  (when conversation-ids
    (ensure-pg-connected)
    (let ((ids-str (format nil "~{~A~^,~}" conversation-ids)))
      (postmodern:query
       (format nil
               "SELECT id, type, name, avatar, creator_id, last_activity, last_sequence,
                       is_pinned, is_muted, unread_count
                FROM conversations
                WHERE id IN (~A)"
               ids-str)))))

;;;; 数据库表初始化

(defun init-chat-folders-db ()
  "初始化聊天文件夹数据库表"
  (ensure-pg-connected)
  (handler-case
      (progn
        ;; 创建聊天文件夹表
        (postmodern:query
         "CREATE TABLE IF NOT EXISTS chat_folders (
            id BIGINT PRIMARY KEY,
            user_id VARCHAR(64) NOT NULL,
            name VARCHAR(128) NOT NULL,
            icon VARCHAR(32) DEFAULT '📁',
            conversation_ids JSONB DEFAULT '[]',
            is_default BOOLEAN DEFAULT false,
            position INTEGER DEFAULT 0,
            created_at TIMESTAMPTZ DEFAULT NOW()
          )")
        ;; 创建索引
        (postmodern:query
         "CREATE INDEX IF NOT EXISTS idx_chat_folders_user_id
          ON chat_folders(user_id)")
        (postmodern:query
         "CREATE INDEX IF NOT EXISTS idx_chat_folders_position
          ON chat_folders(position)")
        (log-message :info "Chat folders table initialized"))
    (condition (e)
      (log-message :error "Failed to initialize chat folders table: ~A" e))))

;;;; API 辅助函数

(defun chat-folder-to-plist (folder)
  "转换文件夹为 plist"
  (declare (type chat-folder folder))
  `(:id ,(chat-folder-id folder)
        :userId ,(chat-folder-user-id folder)
        :name ,(chat-folder-name folder)
        :icon ,(chat-folder-icon folder)
        :conversationIds ,(chat-folder-conversation-ids folder)
        :isDefault ,(chat-folder-is-default folder)
        :position ,(chat-folder-position folder)
        :createdAt ,(chat-folder-created-at folder)))

;; 导出公共函数
(export '(create-chat-folder
          get-chat-folders
          get-chat-folder
          update-chat-folder
          delete-chat-folder
          add-conversation-to-folder
          remove-conversation-from-folder
          get-folder-conversations
          init-chat-folders-db
          chat-folder-to-plist))
