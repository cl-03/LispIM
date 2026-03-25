;;;; chat.lisp - 聊天核心模块
;;;;
;;;; 负责消息处理、会话管理、消息推送
;;;;
;;;; 参考：Common Lisp Cookbook - Conditions, Types, Optimization

(in-package :lispim-core)

;;;; 依赖声明

(eval-when (:compile-toplevel :load-toplevel :execute)
  (ql:quickload '(:uuid :bordeaux-threads :cl-json :babel)))

;;;; 外部变量声明（在 storage.lisp 中定义）

(defvar *memory-users* nil
  "内存用户存储（在 storage.lisp 中定义）")
(defvar *memory-conversations* nil
  "内存会话存储（在 storage.lisp 中定义）")
(defvar *memory-messages* nil
  "内存消息存储（在 storage.lisp 中定义）")

;;;; 类型定义 - 增强的类型检查

(deftype message-id ()
  "消息 ID 类型"
  '(integer 0 *))

(deftype sequence-number ()
  "序列号类型"
  '(integer 0 *))

(deftype user-id ()
  "用户 ID 类型"
  'string)

(deftype conversation-id ()
  "会话 ID 类型"
  '(integer 0 *))

(deftype message-type ()
  "消息类型"
  '(member :text :image :voice :video :file :system :notification :link))

(deftype conversation-type ()
  "会话类型"
  '(member :direct :group :channel))

(deftype read-receipt ()
  "已读回执类型 - 用户 ID 和时间的列表"
  '(list (cons string integer)))

(deftype attachment ()
  "附件类型 - plist with :type, :url, :size, :name keys"
  'plist)

;;;; 消息结构 - 增强的文档和类型

(declaim (inline make-message message-id message-sequence
                 message-conversation-id message-sender-id))

(defstruct message
  "IM 消息 - 表示一条聊天消息"
  (id 0 :type message-id)
  (sequence 0 :type sequence-number)
  (conversation-id 0 :type conversation-id)
  (sender-id "" :type user-id)
  (message-type :text :type message-type)
  (content nil :type (or null string))
  (attachments nil :type list)
  (created-at (get-universal-time) :type integer)
  (edited-at nil :type (or null integer))
  (recalled-p nil :type boolean)
  (read-by nil :type list)
  (mentions nil :type list)
  (reply-to nil :type (or null message-id))
  (metadata (make-hash-table :test 'equal) :type hash-table))

(defstruct conversation
  "会话 - 表示一对一或群组聊天"
  (id 0 :type conversation-id)
  (type :direct :type conversation-type)
  (participants nil :type list)
  (name nil :type (or null string))
  (avatar nil :type (or null string))
  (creator-id "" :type user-id)
  (last-message nil :type (or null message))
  (last-activity (get-universal-time) :type integer)
  (last-sequence 0 :type sequence-number)
  (is-pinned nil :type boolean)
  (is-muted nil :type boolean)
  (metadata (make-hash-table :test 'equal) :type hash-table)
  (member-roles (make-hash-table :test 'equal) :type hash-table)
  (draft nil :type (or null string))
  (unread-count 0 :type integer))

;;;; 会话管理器 - 增强的缓存和锁

(declaim (optimize (speed 3) (safety 1) (debug 1)))

(defvar *conversations* (make-hash-table :test 'eql :size 1000)
  "会话缓存：conversation-id -> conversation")

(defvar *conversations-lock* (bordeaux-threads:make-lock "conversations-lock")
  "会话缓存锁")

(defvar *message-sequence-counter* (make-hash-table :test 'eql)
  "消息序列号计数器：conversation-id -> sequence")

(defvar *message-sequence-lock* (bordeaux-threads:make-lock "message-sequence-lock")
  "消息序列号锁")

(defvar *pending-messages* (make-hash-table :test 'eql)
  "待发送消息队列：conversation-id -> queue")

(defvar *pending-messages-lock* (bordeaux-threads:make-lock "pending-messages-lock")
  "待发送消息锁")

;;;; 消息发送 - 增强的错误处理

(declaim (inline send-message))

(defun load-conversation-from-db (conversation-id)
  "Load a conversation from database into cache"
  (declare (type conversation-id conversation-id)
           (optimize (speed 2) (safety 2)))
  (ensure-pg-connected)
  (let* ((row (postmodern:query "SELECT * FROM conversations WHERE id = $1" conversation-id))
         (participants (postmodern:query
                        "SELECT user_id FROM conversation_participants WHERE conversation_id = $1 AND is_deleted = FALSE"
                        conversation-id)))
    (when row
      (let* ((conv-id (caar row))
             (conv-type (keywordify (cadar row)))
             (participant-ids (mapcar #'write-to-string (mapcar #'car participants)))
             (conv (make-conversation
                    :id conv-id
                    :type conv-type
                    :participants participant-ids
                    :creator-id (write-to-string (elt (car row) 4))
                    :last-activity (get-universal-time))))
        (log-info "load-conversation-from-db: conversation=~a, participant-ids=~A" conv-id participant-ids)
        (bordeaux-threads:with-lock-held (*conversations-lock*)
          (setf (gethash conversation-id *conversations*) conv))
        (log-info "Loaded conversation ~a from database" conv-id)
        conv))))

(defun send-message (conversation-id content &key (type :text) attachments mentions reply-to)
  "发送消息到会话"
  (declare (type conversation-id conversation-id)
           (type (or null string) content)
           (type message-type type)
           (optimize (speed 2) (safety 2)))

  (handler-case
      (progn
        ;; 验证会话存在
        (let ((conv (get-conversation conversation-id)))
          ;; If not in cache, try to load from database
          (unless conv
            (setf conv (load-conversation-from-db conversation-id)))
          (unless conv
            (error 'conversation-not-found :conversation-id conversation-id))

          ;; 验证用户权限
          (log-info "send-message: *current-user-id*='~A', participants=~A" *current-user-id* (conversation-participants conv))
          (unless (member *current-user-id* (conversation-participants conv)
                          :test #'string=)
            (error 'conversation-access-denied
                   :conversation-id conversation-id
                   :user-id *current-user-id*)))

        ;; 验证消息长度
        (when (and content (> (length content) 10000))
          (error 'message-too-long :length (length content) :max-length 10000))

        (let* ((conv (get-conversation conversation-id))
               (seq (get-next-sequence conversation-id))
               (msg (make-message
                     :id (generate-message-id)
                     :sequence seq
                     :conversation-id conversation-id
                     :sender-id *current-user-id*
                     :message-type type
                     :content content
                     :attachments attachments
                     :mentions mentions
                     :reply-to reply-to)))

          ;; 持久化
          (store-message msg)

          ;; 更新会话
          (when conv
            (setf (conversation-last-message conv) msg
                  (conversation-last-activity conv) (get-universal-time)
                  (conversation-last-sequence conv) seq)
            (update-conversation conv))

          ;; 推送给在线用户
          (push-to-online-users conversation-id msg)

          ;; 通知 AI 助手（如果启用）
          (when (ai-enabled-p conversation-id)
            (oc-notify-message msg))

          (log-info "Message sent: ~a to conversation ~a" (message-id msg) conversation-id)
          msg))
    (conversation-not-found (c)
      (log-error "Conversation not found: ~a" (format nil "~A" c))
      (signal c))
    (conversation-access-denied (c)
      (log-error "Access denied: ~a" (format nil "~A" c))
      (signal c))
    (message-too-long (c)
      (log-warn "Message too long: ~a chars" (format nil "~A" c))
      (signal c))))

;;;; 消息序列号 - 线程安全的原子操作

(declaim (inline get-next-sequence))

(defun get-next-sequence (conversation-id)
  "获取下一个消息序列号（原子操作）"
  (declare (type conversation-id conversation-id)
           (optimize (speed 3) (safety 1)))
  (bordeaux-threads:with-lock-held (*message-sequence-lock*)
    (let ((current (gethash conversation-id *message-sequence-counter* 0)))
      (setf (gethash conversation-id *message-sequence-counter*) (1+ current))
      (1+ current))))

(defun initialize-sequence-counters ()
  "从数据库初始化消息序列计数器"
  (log-info "Initializing message sequence counters from database...")
  (ensure-pg-connected)
  (handler-case
      (let ((rows (postmodern:query
                    "SELECT conversation_id, COALESCE(MAX(sequence), 0) as max_seq FROM messages GROUP BY conversation_id")))
        (bordeaux-threads:with-lock-held (*message-sequence-lock*)
          (dolist (row rows)
            (let ((conv-id (first row))
                  (max-seq (second row)))
              (setf (gethash conv-id *message-sequence-counter*) max-seq)
              (log-debug "  Conversation ~a: initialized sequence counter to ~a" conv-id max-seq))))
        (log-info "Sequence counters initialized: ~a conversations" (hash-table-count *message-sequence-counter*)))
    (error (c)
      (log-error "Failed to initialize sequence counters: ~a" c)
      (log-warn "Message sequence numbers may conflict after server restart"))))

;;;; 消息推送 - 增强的错误处理

(defun push-to-online-users (conversation-id message)
  "推送消息到会话中的在线用户"
  (declare (type conversation-id conversation-id)
           (type message message)
           (optimize (speed 2) (safety 2)))
  (let ((conv (get-conversation conversation-id)))
    (when conv
      (handler-case
          (dolist (user-id (conversation-participants conv))
            (let ((conns (get-user-connections user-id)))
              (dolist (conn conns)
                (handler-case
                    (send-to-connection conn (encode-message message))
                  (connection-error (c)
                    (log-warn "Failed to send to connection ~a: ~a"
                              (format nil "~A" c)
                              (format nil "~A" c)))))))
        (error (c)
          (log-error "Push message failed: ~a" c)
          ;; 将消息加入待发送队列
          (queue-pending-message conversation-id message))))))

(defun queue-pending-message (conversation-id message)
  "将消息加入待发送队列"
  (declare (type conversation-id conversation-id)
           (type message message))
  (bordeaux-threads:with-lock-held (*pending-messages-lock*)
    (let ((queue (gethash conversation-id *pending-messages* nil)))
      (if queue
          (push message (gethash conversation-id *pending-messages*))
          (setf (gethash conversation-id *pending-messages*) (list message))))))

(defun encode-message (message)
  "编码消息为二进制格式"
  (declare (type message message)
           (optimize (speed 3) (safety 1)))
  ;; 简化版本，实际应使用 TLV 协议
  (let ((json (cl-json:encode-json-to-string
               `((:id . ,(message-id message))
                 (:seq . ,(message-sequence message))
                 (:conv . ,(message-conversation-id message))
                 (:from . ,(message-sender-id message))
                 (:type . ,(symbol-name (message-message-type message)))
                 (:content . ,(message-content message))
                 (:ts . ,(lispim-universal-to-unix-ms (message-created-at message)))))))
    (babel:string-to-octets json :encoding :utf-8)))

;;;; 消息已读回执 - 增强的类型和错误处理

(defun mark-as-read (conversation-id message-ids)
  "标记消息为已读"
  (declare (type conversation-id conversation-id)
           (type list message-ids)
           (optimize (speed 2) (safety 2)))
  (handler-case
      (progn
        (dolist (msg-id message-ids)
          (let ((msg (get-message msg-id)))
            (when msg
              ;; 检查是否已读过
              (unless (find *current-user-id* (message-read-by msg)
                            :key #'car :test #'string=)
                (push (cons *current-user-id* (get-universal-time))
                      (message-read-by msg))
                (update-message msg)
                ;; 通知发送者
                (notify-read-receipt msg *current-user-id*)))))
        t)
    (message-not-found (c)
      (log-warn "Message not found for read receipt: ~a" (format nil "~A" c))
      nil)
    (error (c)
      (log-error "Mark as read failed: ~a" c)
      nil)))

(defun notify-read-receipt (message reader-id)
  "通知已读回执"
  (declare (type message message)
           (type user-id reader-id)
           (optimize (speed 2) (safety 1)))
  (let ((receipt `((:type . :read-receipt)
                   (:message-id . ,(message-id message))
                   (:reader . ,reader-id)
                   (:ts . ,(lispim-universal-to-unix-ms (get-universal-time))))))
    (handler-case
        (push-to-online-users (message-conversation-id message)
                              (babel:string-to-octets
                               (cl-json:encode-json-to-string receipt)
                               :encoding :utf-8))
      (error (c)
        (log-warn "Failed to send read receipt: ~a" c)
        nil))))

;;;; 消息撤回 - 增强的权限和时限检查

(defun recall-message (message-id)
  "撤回消息"
  (declare (type message-id message-id)
           (optimize (speed 2) (safety 2)))

  (handler-case
      (let ((msg (get-message message-id)))
        (unless msg
          (error 'message-not-found :message-id message-id))

        ;; 检查撤回权限和时限
        (unless (or (string= (message-sender-id msg) *current-user-id*)
                    (is-admin-in-conversation (message-conversation-id msg) *current-user-id*))
          (error 'auth-error
                 :message "No permission to recall this message"
                 :user-id *current-user-id*))

        (let* ((elapsed (- (get-universal-time) (message-created-at msg)))
               (max-elapsed (* 2 60 60)))  ; 2 小时限制
          (when (> elapsed max-elapsed)
            (error 'message-recall-timeout
                   :message-id message-id
                   :elapsed elapsed
                   :max-elapsed max-elapsed)))

        ;; 标记撤回
        (setf (message-recalled-p msg) t
              (message-content msg) "[消息已撤回]")
        (update-message msg)

        ;; 通知相关用户
        (notify-recall message-id)

        (log-info "Message ~a recalled" message-id)
        t)
    (message-not-found (c)
      (log-error "Message not found for recall: ~a" (format nil "~A" c))
      (signal c))
    (auth-error (c)
      (log-warn "Auth error for recall: ~a" (format nil "~A" c))
      (signal c))
    (message-recall-timeout (c)
      (log-info "Recall timeout for message ~a" (format nil "~A" c))
      (signal c))))

(defun notify-recall (message-id)
  "通知消息已撤回"
  (declare (type message-id message-id)
           (optimize (speed 2) (safety 1)))
  (let ((msg (get-message message-id)))
    (when msg
      (let ((recall `((:type . :recall)
                      (:message-id . ,message-id)
                      (:ts . ,(lispim-universal-to-unix-ms (get-universal-time))))))
        (handler-case
            (push-to-online-users (message-conversation-id msg)
                                  (babel:string-to-octets
                                   (cl-json:encode-json-to-string recall)
                                   :encoding :utf-8))
          (error (c)
            (log-warn "Failed to notify recall: ~a" c)
            nil))))))

;;;; 会话管理 - 增强的类型和错误处理

(declaim (inline create-direct-conversation create-group-conversation))

(defun create-direct-conversation (user-id-1 user-id-2)
  "创建一对一会话"
  (declare (type user-id user-id-1 user-id-2)
           (optimize (speed 2) (safety 2)))

  (handler-case
      (progn
        ;; 检查是否已存在会话
        (let ((existing (find-direct-conversation user-id-1 user-id-2)))
          (when existing
            (return-from create-direct-conversation existing)))
        ;; 创建新会话
        (let* ((conv-id (generate-conversation-id))
               (conv (make-conversation
                      :id conv-id
                      :type :direct
                      :participants (list user-id-1 user-id-2)
                      :creator-id user-id-1
                      :last-activity (get-universal-time))))
          (store-conversation conv)
          (bordeaux-threads:with-lock-held (*conversations-lock*)
            (setf (gethash conv-id *conversations*) conv))
          (log-info "Created direct conversation ~a" conv-id)
          conv))
    (conversation-error (c)
      (log-error "Failed to create direct conversation: ~a" c)
      (signal c))))

(defun create-group-conversation (name creator-id participants &key (avatar nil))
  "创建群组会话"
  (declare (type string name creator-id)
           (type list participants)
           (optimize (speed 2) (safety 2)))

  (handler-case
      (progn
        ;; 验证参与者数量
        (when (null participants)
          (error 'conversation-error :message "Participants list cannot be empty"))

        (let* ((conv-id (generate-conversation-id))
               (all-members (cons creator-id participants))
               (conv (make-conversation
                      :id conv-id
                      :type :group
                      :name name
                      :creator-id creator-id
                      :participants all-members
                      :avatar avatar
                      :last-activity (get-universal-time))))
          ;; 设置创建者为管理员
          (setf (gethash creator-id (conversation-member-roles conv)) :admin)
          ;; 设置其他成员为普通成员
          (dolist (pid participants)
            (setf (gethash pid (conversation-member-roles conv)) :member))

          (store-conversation conv)
          (bordeaux-threads:with-lock-held (*conversations-lock*)
            (setf (gethash conv-id *conversations*) conv))
          (log-info "Created group conversation ~a: ~a" conv-id name)
          conv))
    (conversation-error (c)
      (log-error "Failed to create group conversation: ~a" c)
      (signal c))))

(defun get-conversation (conversation-id)
  "获取会话"
  (declare (type conversation-id conversation-id)
           (optimize (speed 3) (safety 1)))
  (bordeaux-threads:with-lock-held (*conversations-lock*)
    (gethash conversation-id *conversations*)))

(defun get-user-conversations (user-id)
  "获取用户的所有会话"
  (declare (type user-id user-id)
           (optimize (speed 2) (safety 1)))
  (bordeaux-threads:with-lock-held (*conversations-lock*)
    (loop for conv being the hash-values of *conversations*
          when (member user-id (conversation-participants conv) :test #'string=)
          collect conv)))

(defun find-direct-conversation (user-id-1 user-id-2)
  "查找一对一会话"
  (declare (type user-id user-id-1 user-id-2)
           (optimize (speed 2) (safety 1)))
  (bordeaux-threads:with-lock-held (*conversations-lock*)
    (loop for conv being the hash-values of *conversations*
          when (and (eq (conversation-type conv) :direct)
                    (or (and (string= (car (conversation-participants conv)) user-id-1)
                             (string= (cadr (conversation-participants conv)) user-id-2))
                        (and (string= (car (conversation-participants conv)) user-id-2)
                             (string= (cadr (conversation-participants conv)) user-id-1))))
          return conv)))

;;;; 历史消息查询 - 增强的类型和分页支持

(defun get-history (conversation-id &key (limit 50) before after)
  "获取历史消息"
  (declare (type conversation-id conversation-id)
           (type (integer 1 100) limit)
           (optimize (speed 2) (safety 2)))
  (handler-case
      (query-messages conversation-id :limit limit :before before :after after)
    (conversation-not-found (c)
      (log-error "Conversation not found for history: ~a" (format nil "~A" c))
      nil)
    (error (c)
      (log-error "Query history failed: ~a" c)
      nil)))

;;;; 权限检查 - 增强的类型

(declaim (inline is-admin-in-conversation is-member-in-conversation))

(defun is-admin-in-conversation (conversation-id user-id)
  "检查用户是否为会话管理员"
  (declare (type conversation-id conversation-id)
           (type user-id user-id)
           (optimize (speed 3) (safety 1)))
  (let ((conv (get-conversation conversation-id)))
    (when conv
      (eq (gethash user-id (conversation-member-roles conv)) :admin))))

(defun is-member-in-conversation (conversation-id user-id)
  "检查用户是否为会话成员"
  (declare (type conversation-id conversation-id)
           (type user-id user-id)
           (optimize (speed 2) (safety 1)))
  (let ((conv (get-conversation conversation-id)))
    (when conv
      (member user-id (conversation-participants conv) :test #'string=))))

;;;; AI 功能检测

(defun ai-enabled-p (conversation-id)
  "检查会话是否启用了 AI 功能"
  (declare (type conversation-id conversation-id)
           (optimize (speed 2) (safety 1)))
  (let ((conv (get-conversation conversation-id)))
    (when conv
      (gethash :ai-enabled (conversation-metadata conv) nil))))

(defun oc-notify-message (message)
  "通知 OpenClaw 消息"
  (declare (type message message)
           (optimize (speed 2) (safety 1)))
  ;; TODO: 实现在 oc-adapter.lisp
  (handler-case
      (progn
        (when (ai-enabled-p (message-conversation-id message))
          (log-debug "Notifying OpenClaw of message: ~a" (message-id message))
          t))
    (error (c)
      (log-error "OC notify failed: ~a" c)
      nil)))

;;;; 全局变量

(defvar *current-user-id* ""
  "当前用户 ID")
(declaim (type user-id *current-user-id*))

;;;; 导出函数

(export '(;; Types
          message-id
          sequence-number
          user-id
          conversation-id
          message-type
          conversation-type

          ;; Structs
          message
          conversation

          ;; Message operations
          send-message
          mark-as-read
          recall-message
          get-history

          ;; Conversation operations
          create-direct-conversation
          create-group-conversation
          get-conversation
          get-user-conversations
          find-direct-conversation

          ;; Permission checks
          is-admin-in-conversation
          is-member-in-conversation
          ai-enabled-p
          oc-notify-message

          ;; Pending messages
          queue-pending-message
          initialize-sequence-counters

          ;; Variables
          *current-user-id*

          ;; Conditions
          conversation-not-found
          conversation-access-denied
          message-not-found
          message-too-long
          message-recall-timeout)
        :lispim-core)
