;;;; message-reply.lisp - 消息回复/引用模块
;;;;
;;;; 支持消息回复、引用、线程功能
;;;;
;;;; 功能：
;;;; - 消息回复（@回复）
;;;; - 消息引用
;;;; - 回复链/线程
;;;; - 引用预览
;;;; - 嵌套回复
;;;;
;;;; 数据结构：
;;;; - message_replies 表存储回复关系
;;;; - reply_chain 支持线程对话

(in-package :lispim-core)

;;;; 依赖声明

(eval-when (:compile-toplevel :load-toplevel :execute)
  (ql:quickload '(:postmodern :cl-redis :bordeaux-threads)))

;;;; 配置

(defparameter *message-reply-config*
  '((:max-reply-depth . 10)           ; 最大回复深度
    (:max-quote-length . 500)         ; 引用最大长度
    (:thread-cache-ttl . 3600))       ; 线程缓存 TTL
  "消息回复配置")

;;;; 类型定义

(defstruct message-reply
  "消息回复"
  (id "" :type string)
  (message-id "" :type string)
  (reply-to-id "" :type string)
  (conversation-id "" :type string)
  (sender-id "" :type string)
  (reply-to-sender-id "" :type string)
  (quote-content "" :type string)
  (quote-type "" :type string)
  (depth 0 :type integer)
  (created-at 0 :type integer))

(defstruct reply-thread
  "回复线程"
  (root-message-id "" :type string)
  (reply-count 0 :type integer)
  (latest-reply-id "" :type string)
  (latest-reply-at 0 :type integer)
  (participants nil :type list))

;;;; 数据库操作

(defparameter *unix-epoch* (encode-universal-time 0 0 0 1 1 1970)
  "Unix epoch in universal time")

(defun create-reply (message-id reply-to-id conversation-id sender-id
                     &key quote-content quote-type)
  "创建消息回复"
  (declare (type string message-id reply-to-id conversation-id sender-id))
  (let* ((reply-to-msg-id (parse-integer reply-to-id))
         (reply-to (get-message reply-to-msg-id))
         ;; 从 message_replies 表查找回复目标的深度
         (parent-depth (when reply-to
                         (let ((result (postmodern:query
                                        (format nil "SELECT depth FROM message_replies WHERE message_id = $1")
                                        reply-to-id
                                        :alist)))
                           (when result
                             (cdr (assoc :depth result))))))
         (depth (1+ (or parent-depth -1)))
         (now (truncate (- (get-universal-time) *unix-epoch*))))
    ;; 检查最大深度
    (when (>= depth (cdr (assoc :max-reply-depth *message-reply-config*)))
      (error 'message-error :reason "Max reply depth exceeded"))
    ;; 存储回复关系
    (postmodern:query
     (format nil "INSERT INTO message_replies
      (message_id, reply_to_id, conversation_id, sender_id,
       quote_content, quote_type, depth, created_at)
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8)")
     message-id reply-to-id conversation-id sender-id
     (if quote-content
         (subseq quote-content 0
                 (min (length quote-content)
                      (cdr (assoc :max-quote-length *message-reply-config*))))
         "")
     (or quote-type "text")
     depth
     now)
    ;; 返回回复信息
    (make-message-reply
     :id (string-uuid)
     :message-id message-id
     :reply-to-id reply-to-id
     :conversation-id conversation-id
     :sender-id sender-id
     :reply-to-sender-id (if reply-to (write-to-string (getf reply-to :sender-id)) "")
     :quote-content (or quote-content "")
     :quote-type (or quote-type "text")
     :depth depth
     :created-at now)))

(defun get-reply-to-message (message-id)
  "获取回复的目标消息"
  (declare (type (or string integer) message-id))
  (let* ((id-str (if (integerp message-id) (write-to-string message-id) message-id))
         (result (postmodern:query
                  (format nil "SELECT mr.reply_to_id, m.content, m.sender_id, m.type
                   FROM message_replies mr
                   JOIN messages m ON mr.reply_to_id = m.id
                   WHERE mr.message_id = $1")
                  id-str
                  :alist)))
    (when result
      (list :reply-to-id (cdr (assoc :reply-to-id result))
            :content (cdr (assoc :content result))
            :sender-id (cdr (assoc :sender-id result))
            :type (cdr (assoc :type result))))))

(defun get-reply-chain (message-id &key (limit 50))
  "获取回复链（从根消息到当前消息）"
  (declare (type string message-id))
  (let ((chain nil)
        (current-id message-id))
    (loop while current-id
          for reply = (get-reply-to-message current-id)
          do (progn
               (push current-id chain)
               (setf current-id (if reply (getf reply :reply-to-id) nil)))
          ;; 防止无限循环
          when (> (length chain) limit)
            do (return nil))
    (nreverse chain)))

(defun get-message-replies (message-id &key (limit 100))
  "获取消息的所有回复"
  (declare (type string message-id))
  (postmodern:query
   (format nil "SELECT m.id, m.content, m.sender_id, m.created_at,
           mr.depth, u.username as sender_username
    FROM message_replies mr
    JOIN messages m ON mr.message_id = m.id
    LEFT JOIN users u ON m.sender_id = u.id
    WHERE mr.reply_to_id = $1
    ORDER BY mr.depth ASC, m.created_at ASC
    LIMIT $2")
   message-id limit))

(defun get-reply-thread (root-message-id)
  "获取完整的回复线程"
  (declare (type string root-message-id))
  (let ((replies (get-message-replies root-message-id :limit 100))
        (thread (make-reply-thread
                 :root-message-id root-message-id
                 :reply-count 0
                 :participants nil)))
    (setf (reply-thread-reply-count thread) (length replies))
    (when replies
      (let ((latest (car (last replies))))
        (setf (reply-thread-latest-reply-id thread) (getf latest :id)
              (reply-thread-latest-reply-at thread) (getf latest :created-at))))
    ;; 收集参与者
    (let ((participants (make-hash-table :test 'equal)))
      (dolist (reply replies)
        (setf (gethash (getf reply :sender-id) participants) t))
      (setf (reply-thread-participants thread)
            (loop for user being the hash-keys of participants
                  collect user)))
    thread))

;;;; 引用预览

(defun generate-quote-preview (message-id)
  "生成引用预览"
  (declare (type string message-id))
  (let ((message (get-message-by-id message-id)))
    (when message
      (let* ((content (getf message :content))
             (type (getf message :type))
             (preview-length 100)
             (preview (if (> (length content) preview-length)
                          (concatenate 'string
                                       (subseq content 0 preview-length)
                                       "...")
                          content)))
        (list :message-id message-id
              :content preview
              :type type
              :sender-id (getf message :sender-id)
              :created-at (getf message :created-at))))))

(defun format-quote-display (quote)
  "格式化引用显示"
  (declare (type list quote))
  (format nil "[~a] ~a: ~a"
          (getf quote :type)
          (getf quote :sender-id)
          (getf quote :content)))

;;;; 发送回复消息

(defun send-reply-message (conversation-id reply-to-id content
                           &key sender-id quote-content quote-type message-type)
  "发送回复消息"
  (declare (type string conversation-id reply-to-id content sender-id))
  (let* ((message-id-int (generate-message-id))
         (message-id (write-to-string message-id-int))
         (message-type (or message-type "text"))
         (conv-id-int (parse-integer conversation-id))
         (reply-to-int (parse-integer reply-to-id))
         (seq (get-next-sequence conv-id-int)))
    ;; 1. 创建消息结构
    (let ((msg (make-message
                :id message-id-int
                :sequence seq
                :conversation-id conv-id-int
                :sender-id sender-id
                :message-type (intern (string-upcase message-type) 'keyword)
                :content content
                :reply-to reply-to-int)))
      ;; 存储消息
      (store-message msg))
    ;; 2. 创建回复关系
    (create-reply message-id reply-to-id conversation-id sender-id
                  :quote-content quote-content
                  :quote-type quote-type)
    ;; 3. 更新会话的最后消息
    (update-conversation-last-message conversation-id message-id)
    ;; 4. 通知相关用户
    (let ((reply-to (get-reply-to-message reply-to-id)))
      (when reply-to
        (notify-reply (getf reply-to :sender-id) sender-id message-id)))
    message-id))

;;;; 通知

(defun update-conversation-last-message (conversation-id message-id)
  "更新会话的最后消息"
  (declare (type string conversation-id message-id))
  (let ((conv-int (parse-integer conversation-id))
        (msg-int (parse-integer message-id)))
    (postmodern:query
     (format nil "UPDATE conversations SET last_message_id = $1, updated_at = TO_TIMESTAMP($2) WHERE id = $3")
     msg-int (- (get-universal-time) (encode-universal-time 0 0 0 1 1 1970)) conv-int)))

(defun notify-reply (reply-to-sender sender message-id)
  "通知被回复的用户"
  (declare (type string reply-to-sender sender message-id))
  ;; 跳过自己回复自己
  (when (string/= reply-to-sender sender)
    ;; 创建通知
    (let ((notification-id (string-uuid)))
      (postmodern:query
       (format nil "INSERT INTO notifications
        (id, user_id, type, related_user_id, message_id, created_at, is_read)
        VALUES ($1, $2, 'reply', $3, $4, $5, false)")
       notification-id reply-to-sender sender message-id (get-universal-time))
      ;; 推送通知
      (push-notification reply-to-sender
                         :type :reply
                         :title "有人回复了你"
                         :body (format nil "~a 回复了你的消息" sender)
                         :data (list :message-id message-id)))))

;;;; 统计

(defun get-reply-stats (message-id)
  "获取回复统计"
  (declare (type string message-id))
  (let ((replies (get-message-replies message-id)))
    (list :message-id message-id
          :reply-count (length replies)
          :unique-reply-count (length (remove-duplicates
                                       (mapcar (lambda (r) (getf r :sender-id))
                                               replies)
                                       :test 'string=)))))

;;;; 删除回复

(defun delete-reply (message-id)
  "删除回复消息"
  (declare (type string message-id))
  ;; 删除回复关系
  (postmodern:query (format nil "DELETE FROM message_replies WHERE message_id = $1") message-id)
  ;; 删除消息本身
  (delete-message message-id))

(defun delete-reply-thread (root-message-id)
  "删除整个回复线程"
  (declare (type string root-message-id))
  (let ((replies (get-message-replies root-message-id :limit 1000)))
    (dolist (reply replies)
      (delete-reply (getf reply :id)))
    ;; 删除根消息的回复关系
    (postmodern:query (format nil "DELETE FROM message_replies WHERE reply_to_id = $1")
                      root-message-id)))

;;;; 缓存

(defvar *reply-thread-cache* (make-hash-table :test 'equal)
  "回复线程缓存")

(defun get-cached-reply-thread (root-message-id)
  "获取缓存的回复线程"
  (declare (type string root-message-id))
  (let ((cached (gethash root-message-id *reply-thread-cache*)))
    (when cached
      (let ((cache-time (getf cached :time))
            (ttl (cdr (assoc :thread-cache-ttl *message-reply-config*))))
        (if (< (- (get-universal-time) cache-time) ttl)
            (getf cached :thread)
            (progn
              (remhash root-message-id *reply-thread-cache*)
              nil))))))

(defun cache-reply-thread (root-message-id thread)
  "缓存回复线程"
  (declare (type string root-message-id)
           (type reply-thread thread))
  (setf (gethash root-message-id *reply-thread-cache*)
        (list :thread thread
              :time (get-universal-time))))

;;;; 高层 API

(defun create-message-reply (message-id content &key sender-id conversation-id
                              quote-content quote-type)
  "高层回复 API"
  (send-reply-message conversation-id message-id content
                      :sender-id sender-id
                      :quote-content quote-content
                      :quote-type quote-type))

(defun get-message-reply-info (message-id)
  "高层获取回复信息 API"
  (let ((reply-to (get-reply-to-message message-id))
        (replies (get-message-replies message-id)))
    (list :message-id message-id
          :reply-to reply-to
          :replies replies
          :reply-count (length replies))))

;;;; 导出

(export '(;; Message Reply
          create-reply
          get-reply-to-message
          get-reply-chain
          get-message-replies
          get-reply-thread
          send-reply-message

          ;; Quote
          generate-quote-preview
          format-quote-display

          ;; Thread
          get-cached-reply-thread
          cache-reply-thread

          ;; Statistics
          get-reply-stats

          ;; Delete
          delete-reply
          delete-reply-thread

          ;; High-level API
          create-message-reply
          get-message-reply-info

          ;; Config
          *message-reply-config*)
        :lispim-core)
