;;;; reactions.lisp - 消息反应（表情回应）
;;;;
;;;; 参考 Tailchat 的 MessageReaction 设计
;;;; 支持用户对消息添加表情回应
;;;;
;;;; 设计原则：
;;;; - 纯 Common Lisp 实现
;;;; - 高效的反应查询和统计
;;;; - 支持多种表情符号

(in-package :lispim-core)

;;;; 依赖声明

(eval-when (:compile-toplevel :load-toplevel :execute)
  (ql:quickload '(:bordeaux-threads :postmodern :cl-redis :cl-json)))

;;;; 类型定义

(deftype emoji ()
  "表情符号类型"
  'string)

(deftype reaction-id ()
  "反应 ID 类型"
  'integer)

;;;; 消息反应结构

(defstruct message-reaction
  "消息反应
   参考 Tailchat 的 MessageReaction 设计"
  (id 0 :type reaction-id)
  (message-id 0 :type integer)
  (emoji "" :type emoji)
  (user-ids nil :type list)
  (count 0 :type integer)
  (created-at (get-universal-time) :type integer)
  (updated-at (get-universal-time) :type integer))

(defstruct reaction-entry
  "单个反应条目"
  (user-id "" :type string)
  (emoji "" :type emoji)
  (created-at (get-universal-time) :type integer))

;;;; 全局缓存

(defvar *message-reactions* (make-hash-table :test 'eql)
  "消息反应缓存：message-id -> (reaction*)")

(defvar *message-reactions-lock* (bordeaux-threads:make-lock "message-reactions-lock")
  "消息反应缓存锁")

(defvar *reactions-counter* 0
  "反应计数器（用于生成唯一 ID）")

;;;; 数据库初始化

(defun init-reactions-db ()
  "初始化消息反应数据库表"
  (ensure-pg-connected)
  (handler-case
      (progn
        ;; 创建消息反应表
        (postmodern:query
         "CREATE TABLE IF NOT EXISTS message_reactions (
            id BIGSERIAL PRIMARY KEY,
            message_id BIGINT NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
            emoji VARCHAR(32) NOT NULL,
            user_id VARCHAR(64) NOT NULL REFERENCES users(id),
            created_at TIMESTAMPTZ DEFAULT NOW(),
            UNIQUE(message_id, emoji, user_id)
          )")
        ;; 创建索引
        (postmodern:query
         "CREATE INDEX IF NOT EXISTS idx_message_reactions_message_id
          ON message_reactions(message_id)")
        (postmodern:query
         "CREATE INDEX IF NOT EXISTS idx_message_reactions_user_id
          ON message_reactions(user_id)")
        (log-info "Message reactions table initialized"))
    (error (c)
      (log-error "Failed to init reactions DB: ~a" c))))

;;;; 反应操作

(defun add-reaction (message-id emoji user-id)
  "添加消息反应

   Parameters:
     message-id - 消息 ID
     emoji      - 表情符号
     user-id    - 用户 ID

   Returns:
     (values success-p reaction-info)"
  (declare (type integer message-id)
           (type emoji)
           (type string user-id))
  (ensure-pg-connected)

  (handler-case
      (let ((reaction-id 0)
            (new-count 0))
        ;; 尝试插入（ON CONFLICT DO UPDATE 实现 upsert）
        (let ((result (postmodern:query
                       "INSERT INTO message_reactions (message_id, emoji, user_id)
                        VALUES ($1, $2, $3)
                        ON CONFLICT (message_id, emoji, user_id) DO NOTHING
                        RETURNING id"
                       message-id emoji user-id)))
          (if result
              ;; 新反应
              (progn
                (setf reaction-id (caar result))
                (incf *reactions-counter*))
              ;; 已存在，跳过
              (return-from add-reaction
                (values nil nil))))

        ;; 统计该消息该表情的总人数
        (let ((count-row (postmodern:query
                          "SELECT COUNT(DISTINCT user_id) FROM message_reactions
                           WHERE message_id = $1 AND emoji = $2"
                          message-id emoji)))
          (setf new-count (parse-integer (caar count-row))))

        ;; 更新缓存
        (bordeaux-threads:with-lock-held (*message-reactions-lock*)
          (let ((reactions (gethash message-id *message-reactions*)))
            (if reactions
                (let ((reaction (find emoji reactions
                                      :key #'message-reaction-emoji
                                      :test 'string=)))
                  (if reaction
                      (unless (member user-id (message-reaction-user-ids reaction)
                                      :test 'string=)
                        (push user-id (message-reaction-user-ids reaction))
                        (setf (message-reaction-count reaction) new-count))
                      (push (make-message-reaction
                             :id reaction-id
                             :message-id message-id
                             :emoji emoji
                             :user-ids (list user-id)
                             :count new-count)
                            reactions)))
                (setf (gethash message-id *message-reactions*)
                      (list (make-message-reaction
                             :id reaction-id
                             :message-id message-id
                             :emoji emoji
                             :user-ids (list user-id)
                             :count new-count))))))

        (log-info "Reaction added: ~a -> ~a (~a)" user-id emoji message-id)
        (values t (list :reaction-id reaction-id
                        :emoji emoji
                        :count new-count)))
    (error (c)
      (log-error "Failed to add reaction: ~a" c)
      (values nil nil))))

(defun remove-reaction (message-id emoji user-id)
  "移除消息反应

   Parameters:
     message-id - 消息 ID
     emoji      - 表情符号
     user-id    - 用户 ID

   Returns:
     (values success-p remaining-count)"
  (declare (type integer message-id)
           (type emoji)
           (type string user-id))
  (ensure-pg-connected)

  (handler-case
      (progn
        ;; 删除反应
        (postmodern:query
         "DELETE FROM message_reactions
          WHERE message_id = $1 AND emoji = $2 AND user_id = $3"
         message-id emoji user-id)

        ;; 统计剩余人数
        (let ((count-row (postmodern:query
                          "SELECT COUNT(DISTINCT user_id) FROM message_reactions
                           WHERE message_id = $1 AND emoji = $2"
                          message-id emoji)))
          (let ((new-count (parse-integer (caar count-row))))
            ;; 更新缓存
            (bordeaux-threads:with-lock-held (*message-reactions-lock*)
              (let ((reactions (gethash message-id *message-reactions*)))
                (when reactions
                  (let ((reaction (find emoji reactions
                                        :key #'message-reaction-emoji
                                        :test 'string=)))
                    (when reaction
                      (setf (message-reaction-user-ids reaction)
                            (remove user-id (message-reaction-user-ids reaction)
                                    :test 'string=))
                      (setf (message-reaction-count reaction) new-count)
                      (when (zerop new-count)
                        ;; 没有人反应了，移除该反应
                        (setf (gethash message-id *message-reactions*)
                              (remove reaction reactions)))))))))

            (log-info "Reaction removed: ~a <- ~a (~a remaining)"
                      user-id emoji new-count)
            (values t new-count)))
    (error (c)
      (log-error "Failed to remove reaction: ~a" c)
      (values nil 0))))

(defun get-message-reactions (message-id)
  "获取消息的所有反应

   Parameters:
     message-id - 消息 ID

   Returns:
     (reaction*) 列表，每个 reaction 包含：
       :emoji   - 表情符号
       :count   - 人数
       :user-ids - 用户 ID 列表
       :self    - 当前用户是否已反应"
  (declare (type integer message-id))

  ;; 先查缓存
  (bordeaux-threads:with-lock-held (*message-reactions-lock*)
    (let ((cached (gethash message-id *message-reactions*)))
      (when cached
        (return-from get-message-reactions
          (mapcar (lambda (r)
                    (list :emoji (message-reaction-emoji r)
                          :count (message-reaction-count r)
                          :user-ids (message-reaction-user-ids r)))
                  cached)))))

  ;; 查数据库
  (ensure-pg-connected)
  (let ((rows (postmodern:query
               "SELECT emoji, user_id, COUNT(*) OVER (PARTITION BY emoji) as cnt
                FROM message_reactions
                WHERE message_id = $1
                ORDER BY emoji"
               message-id)))
    (if (null rows)
        nil
        (let ((reactions-hash (make-hash-table :test 'equal)))
          (dolist (row rows)
            (let ((emoji (elt row 0))
                  (user-id (elt row 1))
                  (count (parse-integer (elt row 2))))
              (let ((existing (gethash emoji reactions-hash)))
                (if existing
                    (push user-id (getf existing :user-ids))
                    (setf (gethash emoji reactions-hash)
                          (list :emoji emoji :count count :user-ids (list user-id)))))))
          ;; 转换为列表并更新缓存
          (let ((result nil))
            (maphash (lambda (emoji data)
                       (declare (ignore emoji))
                       (push data result))
                     reactions-hash)
            ;; 更新缓存
            (setf (gethash message-id *message-reactions*)
                  (mapcar (lambda (data)
                            (make-message-reaction
                             :message-id message-id
                             :emoji (getf data :emoji)
                             :count (getf data :count)
                             :user-ids (getf data :user-ids)))
                          result))
            result)))))

(defun get-message-reaction-count (message-id)
  "获取消息反应总数"
  (declare (type integer message-id))
  (let ((reactions (get-message-reactions message-id)))
    (reduce #'+ reactions :key #'second)))

(defun user-has-reacted-p (message-id emoji user-id)
  "检查用户是否已对消息添加某表情反应"
  (declare (type integer message-id)
           (type emoji)
           (type string user-id))
  (let ((reactions (get-message-reactions message-id)))
    (let ((reaction (find emoji reactions :key #'first :test 'string=)))
      (and reaction
           (member user-id (getf reaction :user-ids) :test 'string=)))))

(defun get-user-reactions (message-id user-id)
  "获取用户对某消息添加的所有表情"
  (declare (type integer message-id)
           (type string user-id))
  (let ((reactions (get-message-reactions message-id)))
    (remove-if-not (lambda (r)
                     (member user-id (getf r :user-ids) :test 'string=))
                   reactions)))

;;;; 与聊天系统集成

(defun send-message-with-reaction (conversation-id content &optional reaction-emoji)
  "发送带反应的消息

   先发送消息，然后自动添加一个反应"
  (declare (type string conversation-id content)
           (type (or null emoji) reaction-emoji))
  (let ((msg (send-message conversation-id content :type :text)))
    (when (and msg reaction-emoji)
      (add-reaction (message-id msg) reaction-emoji *current-user-id*))
    msg))

;;;; 表情建议

(defparameter *common-emojis*
  '("👍" "❤️" "😂" "😮" "😢" "😡" "🎉" "🔥" "✅" "❌")
  "常用表情列表")

(defun get-suggested-reactions ()
  "获取建议的表情列表"
  *common-emojis*)

;;;; 统计

(defun get-reactions-stats ()
  "获取反应统计信息"
  (let ((total-messages 0)
        (total-reactions 0))
    (maphash (lambda (msg-id reactions)
               (declare (ignore msg-id))
               (incf total-messages)
               (incf total-reactions (length reactions)))
             *message-reactions*)
    (list :messages-with-reactions total-messages
          :total-reactions total-reactions
          :average (/ total-reactions (max 1 total-messages)))))

;;;; 清理

(defun cleanup-message-reactions (message-id)
  "清理消息的反应（当消息被删除时调用）"
  (declare (type integer message-id))
  (ensure-pg-connected)
  (handler-case
      (progn
        (postmodern:query
         "DELETE FROM message_reactions WHERE message_id = $1"
         message-id)
        (bordeaux-threads:with-lock-held (*message-reactions-lock*)
          (remhash message-id *message-reactions*))
        (log-info "Reactions cleaned up for message ~a" message-id))
    (error (c)
      (log-error "Failed to cleanup reactions: ~a" c))))

;;;; 初始化

(defun init-reactions ()
  "初始化消息反应系统"
  (init-reactions-db)
  (log-info "Message reactions system initialized"))

;;;; 导出公共 API
;;;; (Symbols are exported via package.lisp)
