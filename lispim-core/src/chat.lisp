;;;; chat.lisp - 聊天核心模块
;;;;
;;;; 负责消息处理、会话管理、消息推送
;;;;
;;;; 参考：Common Lisp Cookbook - Conditions, Types, Optimization

(in-package :lispim-core)

;;;; 依赖声明

(eval-when (:compile-toplevel :load-toplevel :execute)
  (ql:quickload '(:uuid :bordeaux-threads :cl-json :babel :dexador :alexandria)))

;;;; 外部变量声明（在 storage.lisp 中定义）

(defvar *memory-users* nil
  "内存用户存储（在 storage.lisp 中定义）")
(defvar *memory-conversations* nil
  "内存会话存储（在 storage.lisp 中定义）")
(defvar *memory-messages* nil
  "内存消息存储（在 storage.lisp 中定义）")

;;;; 类型定义已从 types.lisp 加载，此处不再重复定义
;;;; 消息和会话结构体也已从 types.lisp 加载

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
             (row-data (car row))
             (conv (make-conversation
                    :id conv-id
                    :type conv-type
                    :participants participant-ids
                    :creator-id (write-to-string (nth 4 row-data))
                    :last-activity (get-universal-time))))
        (log-info "load-conversation-from-db: conversation=~a, participant-ids=~A" conv-id participant-ids)
        (bordeaux-threads:with-lock-held (*conversations-lock*)
          (setf (gethash conversation-id *conversations*) conv))
        (log-info "Loaded conversation ~a from database" conv-id)
        conv))))

(defun send-message (conversation-id content &key (type :text) attachments mentions reply-to)
  "发送消息到会话（集成消息状态追踪）"
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

        ;; Render Markdown for text messages
        ;; Store both original and rendered content
        (let ((rendered-content (if (eq type :text)
                                    (render-markdown content)
                                    content)))

          (let* ((conv (get-conversation conversation-id))
                 (seq (get-next-sequence conversation-id))
                 (msg-id (generate-message-id))
                 (msg (make-message
                       :id msg-id
                       :sequence seq
                       :conversation-id conversation-id
                       :sender-id *current-user-id*
                       :message-type type
                       :content rendered-content  ;; Use rendered content
                       :attachments attachments
                       :mentions mentions
                       :reply-to reply-to)))

            ;; Store original markdown in metadata for editing
            (when (eq type :text)
              (setf (gethash :original-content (message-metadata msg)) content))

            ;; 存储消息并设置状态为 :sending
            (store-message-with-status msg :status :sending)

            ;; 更新会话
            (when conv
              (setf (conversation-last-message conv) msg
                    (conversation-last-activity conv) (get-universal-time)
                    (conversation-last-sequence conv) seq)
              (update-conversation conv))

            ;; 推送给在线用户（使用 WebSocket Protocol v1 格式）
            (broadcast-message-to-conversation conversation-id msg)

            ;; 创建 ACK 追踪（30 秒超时）
            (let ((recipients (remove *current-user-id* (conversation-participants conv) :test #'string=)))
              (when recipients
                (create-message-ack msg-id recipients :timeout-seconds 30
                                    :callback (lambda (id status)
                                                (log-info "ACK callback: message ~a status ~a" id status)))))

            ;; 通知 AI 助手（如果启用）
            (when (ai-enabled-p conversation-id)
              (oc-notify-message msg))

            ;; 触发 Webhook 事件
            (trigger-webhook :message-sent
                             `((:message-id . ,(message-id msg))
                               (:conversation-id . ,conversation-id)
                               (:sender-id . ,(message-sender-id msg))
                               (:type . ,(message-message-type msg))
                               (:content . ,(message-content msg))
                               (:ts . ,(lispim-universal-to-unix-ms (message-created-at msg)))))

            (log-info "Message sent: ~a to conversation ~a" msg-id conversation-id)
            msg)))
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

(defun push-to-online-user (user-id message)
  "推送消息到单个在线用户"
  (declare (type string user-id)
           (type list message)
           (optimize (speed 2) (safety 2)))
  (let ((conns (get-user-connections user-id)))
    (dolist (conn conns)
      (handler-case
          (send-to-connection conn (cl-json:encode-json-to-string message))
        (connection-error (c)
          (log-warn "Failed to send to connection ~a: ~a"
                    (connection-id conn)
                    (format nil "~A" c)))))))

(defun push-to-online-users (conversation-id message)
  "推送消息到会话中的在线用户（集成状态追踪）"
  (declare (type conversation-id conversation-id)
           (type message message)
           (optimize (speed 2) (safety 2)))
  (let ((conv (get-conversation conversation-id)))
    (when conv
      (let ((success-p nil)
            (error-msg nil))
        (handler-case
            (progn
              (dolist (user-id (conversation-participants conv))
                (let ((conns (get-user-connections user-id)))
                  (dolist (conn conns)
                    (handler-case
                        (progn
                          (send-to-connection conn (encode-message message))
                          (setf success-p t))
                      (connection-error (c)
                        (log-warn "Failed to send to connection ~a: ~a"
                                  (format nil "~A" c)
                                  (format nil "~A" c)))))))
              ;; 推送成功，更新状态为 :sent
              (when success-p
                (update-message-status (message-id message) :sent)))
          (error (c)
            (setf error-msg (format nil "~a" c))
            (log-error "Push message failed: ~a" c)
            ;; 推送失败，更新状态为 :failed 并加入重试队列
            (update-message-status (message-id message) :failed
                                   :error-message error-msg)
            (enqueue-failed-message (message-id message)
                                    conversation-id
                                    (message-content message)
                                    :type (message-message-type message))))))))

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
            (progn
              (push-to-online-users (message-conversation-id msg) recall)
              t)
          (error (c)
            (log-error "Failed to notify recall: ~a" c)
            nil)))))
  t)

;;;; 消息编辑 - 支持修改消息内容

(defun edit-message (message-id new-content)
  "编辑消息内容"
  (declare (type message-id message-id)
           (type string new-content)
           (optimize (speed 2) (safety 2)))

  (handler-case
      (let ((msg (get-message message-id)))
        (unless msg
          (error 'message-not-found :message-id message-id))

        ;; 检查编辑权限
        (unless (or (string= (message-sender-id msg) *current-user-id*)
                    (is-admin-in-conversation (message-conversation-id msg) *current-user-id*))
          (error 'auth-error
                 :message "No permission to edit this message"
                 :user-id *current-user-id*))

        ;; 检查编辑时限
        (let* ((elapsed (- (get-universal-time) (message-created-at msg)))
               (max-elapsed (* 2 60 60)))  ; 2 小时限制
          (when (> elapsed max-elapsed)
            (error 'message-recall-timeout
                   :message-id message-id
                   :elapsed elapsed
                   :max-elapsed max-elapsed)))

        ;; 更新内容
        (setf (message-content msg) new-content
              (message-edited-at msg) (get-universal-time))
        (update-message msg)

        ;; 通知相关用户
        (notify-edit message-id new-content)

        (log-info "Message ~a edited" message-id)
        t)
    (message-not-found (c)
      (log-error "Message not found for edit: ~a" (format nil "~A" c))
      (signal c))
    (auth-error (c)
      (log-warn "Auth error for edit: ~a" (format nil "~A" c))
      (signal c))
    (message-recall-timeout (c)
      (log-info "Edit timeout for message ~a" (format nil "~A" c))
      (signal c))))

(defun notify-edit (message-id new-content)
  "通知消息已编辑"
  (declare (type message-id message-id)
           (type string new-content)
           (optimize (speed 2) (safety 1)))
  (let ((msg (get-message message-id)))
    (when msg
      (let ((edit `((:type . :edit)
                    (:message-id . ,message-id)
                    (:content . ,new-content)
                    (:edited-at . ,(lispim-universal-to-unix-ms (get-universal-time))))))
        (handler-case
            (progn
              (push-to-online-users (message-conversation-id msg) edit)
              t)
          (error (c)
            (log-warn "Failed to notify edit: ~a" c)
            nil)))))
  t)

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

;;;; 消息置顶功能

(defun pin-message (message-id conversation-id &optional pinned-by)
  "置顶消息"
  (declare (type integer message-id conversation-id)
           (type (or null string) pinned-by))
  (ensure-pg-connected)

  (let ((pinner (or pinned-by *current-user-id* "")))
    ;; 更新消息状态
    (postmodern:query
     "UPDATE messages SET is_pinned = TRUE, pinned_at = NOW(), pinned_by = (SELECT id FROM users WHERE username = $1)
      WHERE id = $2 AND conversation_id = $3"
     pinner message-id conversation-id)

    ;; 记录到 pinned_messages 表
    (postmodern:query
     "INSERT INTO pinned_messages (message_id, conversation_id, pinned_by, pin_order)
      VALUES ($1, $2, (SELECT id FROM users WHERE username = $3),
              (SELECT COALESCE(MAX(pin_order), 0) + 1 FROM pinned_messages WHERE conversation_id = $2 AND unpinned_at IS NULL))
      ON CONFLICT (message_id, conversation_id)
      DO UPDATE SET pinned_at = NOW(), pinned_by = (SELECT id FROM users WHERE username = $3), unpinned_at = NULL"
     message-id conversation-id pinner)

    ;; 通知在线用户
    (push-to-online-user pinner
                         `((:type . :message-pinned)
                           (:messageId . ,message-id)
                           (:conversationId . ,conversation-id)
                           (:pinnedBy . ,pinner)
                           (:ts . ,(lispim-universal-to-unix-ms (get-universal-time)))))

    (log-info "Message ~a pinned in conversation ~a by ~a" message-id conversation-id pinner)
    t))

(defun unpin-message (message-id conversation-id &optional unpinned-by)
  "取消置顶消息"
  (declare (type integer message-id conversation-id)
           (type (or null string) unpinned-by))
  (ensure-pg-connected)

  (let ((unpinner (or unpinned-by *current-user-id* "")))
    ;; 更新消息状态
    (postmodern:query
     "UPDATE messages SET is_pinned = FALSE
      WHERE id = $1 AND conversation_id = $2"
     message-id conversation-id)

    ;; 更新 pinned_messages 表
    (postmodern:query
     "UPDATE pinned_messages SET unpinned_at = NOW(), unpinned_by = (SELECT id FROM users WHERE username = $1)
      WHERE message_id = $2 AND conversation_id = $3 AND unpinned_at IS NULL"
     unpinner message-id conversation-id)

    ;; 通知在线用户
    (push-to-online-user unpinner
                         `((:type . :message-unpinned)
                           (:messageId . ,message-id)
                           (:conversationId . ,conversation-id)
                           (:unpinnedBy . ,unpinner)
                           (:ts . ,(lispim-universal-to-unix-ms (get-universal-time)))))

    (log-info "Message ~a unpinned in conversation ~a by ~a" message-id conversation-id unpinner)
    t))

(defun get-pinned-messages (conversation-id)
  "获取会话中所有置顶消息"
  (declare (type integer conversation-id))
  (ensure-pg-connected)

  (let ((rows (postmodern:query
               "SELECT pm.message_id, m.content, m.sender_id, m.type, pm.pinned_at, pm.pinned_by, u.username as pinned_by_username
                FROM pinned_messages pm
                JOIN messages m ON pm.message_id = m.id
                JOIN users u ON pm.pinned_by = u.id
                WHERE pm.conversation_id = $1 AND pm.unpinned_at IS NULL AND m.is_pinned = TRUE
                ORDER BY pm.pin_order ASC, pm.pinned_at ASC"
               conversation-id)))
    (loop for row in rows
          collect (list :messageId (elt row 0)
                        :content (elt row 1)
                        :senderId (elt row 2)
                        :type (elt row 3)
                        :pinnedAt (storage-universal-to-unix-ms (elt row 4))
                        :pinnedBy (elt row 5)
                        :pinnedByUsername (elt row 6)))))

(defun is-message-pinned (message-id)
  "检查消息是否已置顶"
  (declare (type integer message-id))
  (ensure-pg-connected)

  (let ((result (postmodern:query
                 "SELECT is_pinned FROM messages WHERE id = $1"
                 message-id)))
    (when result
      (caar result))))

;;;; 群聊免打扰功能

(defun mute-conversation (conversation-id user-id &optional duration-minutes)
  "静音会话（群聊免打扰）"
  (declare (type integer conversation-id)
           (type string user-id)
           (type (or null integer) duration-minutes))
  (ensure-pg-connected)

  (let ((result (postmodern:query
                 "SELECT set_conversation_mute($1, (SELECT id FROM users WHERE username = $2), TRUE, $3)"
                 conversation-id user-id duration-minutes)))
    (when (caar result)
      (log-info "Conversation ~a muted for user ~a" conversation-id user-id)
      t)))

(defun unmute-conversation (conversation-id user-id)
  "取消静音会话"
  (declare (type integer conversation-id)
           (type string user-id))
  (ensure-pg-connected)

  (let ((result (postmodern:query
                 "SELECT set_conversation_mute($1, (SELECT id FROM users WHERE username = $2), FALSE, NULL)"
                 conversation-id user-id)))
    (when (caar result)
      (log-info "Conversation ~a unmuted for user ~a" conversation-id user-id)
      t)))

(defun is-conversation-muted (conversation-id user-id)
  "检查会话是否被静音"
  (declare (type integer conversation-id)
           (type string user-id))
  (ensure-pg-connected)

  (let ((result (postmodern:query
                 "SELECT is_conversation_muted($1, (SELECT id FROM users WHERE username = $2))"
                 conversation-id user-id)))
    (when result
      (caar result))))

(defun get-muted-conversations (user-id)
  "获取用户静音的会话列表"
  (declare (type string user-id))
  (ensure-pg-connected)

  (let ((rows (postmodern:query
               "SELECT cp.conversation_id, c.name, cp.is_muted, cp.mute_until,
                       CASE WHEN cp.mute_until IS NOT NULL AND cp.mute_until > NOW()
                            THEN EXTRACT(EPOCH FROM (cp.mute_until - NOW()))::INTEGER
                            ELSE NULL
                       END as remaining_seconds
                FROM conversation_participants cp
                JOIN conversations c ON cp.conversation_id = c.id
                WHERE cp.user_id = (SELECT id FROM users WHERE username = $1)
                  AND cp.is_muted = TRUE
                  AND cp.is_deleted = FALSE
                  AND (cp.mute_until IS NULL OR cp.mute_until > NOW())"
               user-id)))
    (loop for row in rows
          collect (list :conversationId (elt row 0)
                        :name (elt row 1)
                        :isMuted (elt row 2)
                        :muteUntil (if (elt row 3) (storage-universal-to-unix-ms (elt row 3)) nil)
                        :remainingSeconds (elt row 4)))))

;;;; 消息转发功能

(defun forward-message (message-id conversation-id &optional comment)
  "转发消息到另一个会话"
  (declare (type integer message-id conversation-id)
           (type (or null string) comment))
  (ensure-pg-connected)

  (let ((result (postmodern:query
                 "SELECT forward_message($1, $2, (SELECT id FROM users WHERE username = $3), $4)"
                 message-id conversation-id *current-user-id* comment)))
    (when result
      (let ((new-msg-id (caar result)))
        (log-info "Message ~a forwarded to ~a as ~a" message-id conversation-id new-msg-id)
        new-msg-id))))

(defun forward-messages (message-ids conversation-id &optional comment)
  "批量转发消息到另一个会话"
  (declare (type list message-ids)
           (type integer conversation-id)
           (type (or null string) comment))
  (let ((forwarded-ids nil))
    (dolist (msg-id message-ids)
      (let ((new-id (forward-message msg-id conversation-id comment)))
        (when new-id
          (push new-id forwarded-ids))))
    (nreverse forwarded-ids)))

(defun get-message-forward-count (message-id)
  "获取消息被转发次数"
  (declare (type integer message-id))
  (ensure-pg-connected)

  (let ((result (postmodern:query
                 "SELECT forward_count FROM messages WHERE id = $1"
                 message-id)))
    (when result
      (caar result))))

(defun get-forwarded-message-origin (message-id)
  "获取转发消息的原始信息"
  (declare (type integer message-id))
  (ensure-pg-connected)

  (let ((result (postmodern:query
                 "SELECT m.id, m.content, m.sender_id, u.username, m.created_at
                  FROM messages m
                  JOIN users u ON m.sender_id = u.id
                  WHERE m.id = (SELECT forwarded_from_message_id FROM messages WHERE id = $1)"
                 message-id)))
    (when result
      (let ((row (car result)))
        (list :messageId (elt row 0)
              :content (elt row 1)
              :senderId (elt row 2)
              :senderName (elt row 3)
              :createdAt (storage-universal-to-unix-ms (elt row 4)))))))

;;;; 群精华消息功能

(defun add-highlighted-message (message-id conversation-id user-id &optional note)
  "添加精华消息"
  (declare (type integer message-id conversation-id)
           (type string user-id)
           (type (or null string) note))
  (ensure-pg-connected)

  (let ((result (postmodern:query
                 "SELECT add_highlighted_message($1, $2, (SELECT id FROM users WHERE username = $3), $4)"
                 message-id conversation-id user-id note)))
    (when result
      (let ((highlight-id (caar result)))
        (log-info "Message ~a added to highlights in conversation ~a" message-id conversation-id)
        highlight-id))))

(defun remove-highlighted-message (highlight-id user-id)
  "移除精华消息"
  (declare (type integer highlight-id)
           (type string user-id))
  (ensure-pg-connected)

  (let ((result (postmodern:query
                 "SELECT remove_highlighted_message($1, (SELECT id FROM users WHERE username = $2))"
                 highlight-id user-id)))
    (when (caar result)
      (log-info "Highlight ~a removed by ~a" highlight-id user-id)
      t)))

(defun get-highlighted-messages (conversation-id)
  "获取群精华消息列表"
  (declare (type integer conversation-id))
  (ensure-pg-connected)

  (let ((rows (postmodern:query
               "SELECT * FROM get_highlighted_messages($1)"
               conversation-id)))
    (loop for row in rows
          collect (list :highlightId (elt row 0)
                        :messageId (elt row 1)
                        :content (elt row 2)
                        :senderId (elt row 3)
                        :senderName (elt row 4)
                        :type (elt row 5)
                        :addedAt (storage-universal-to-unix-ms (elt row 6))
                        :addedBy (elt row 7)
                        :addedByName (elt row 8)
                        :note (elt row 9)
                        :displayOrder (elt row 10))))
  t)

;;;; 链接预览功能

(defun extract-urls-from-text (text)
  "从文本中提取 URL 列表"
  (declare (type string text))
  (let ((url-regex "https?://[^\\s\\)\\]>]+")
        (urls nil)
        (start 0))
    (loop
      (multiple-value-bind (match-start match-end)
          (cl-ppcre:scan url-regex text :start start)
        (if match-start
            (progn
              (push (subseq text match-start match-end) urls)
              (setf start match-end))
            (return))))
    (nreverse urls)))

(defun fetch-url-metadata (url)
  "获取 URL 的元数据（Open Graph 等）"
  (declare (type string url))
  (block nil
    (handler-bind
        ((error #'(lambda (c)
                    (log-error "Error fetching URL ~a: ~a" url c)
                    (return (list :error (format nil "Fetch error: ~a" c))))))
      (let* ((response (dex:get url :wants-stream t))
             (status (first response))
             (headers (second response))
             (stream (fourth response))
             (content-type (gethash "content-type" headers "")))
        (if (not (or (eql status 200)
                     (search "text/html" content-type :test #'char-equal)))
            (progn
              (close stream)
              (list :error (format nil "HTTP ~a" status)))
            (let* ((content (babel:octets-to-string
                             (alexandria:read-stream-content-into-byte-vector stream)
                             :encoding :utf-8))
                   (metadata (parse-html-metadata content url)))
              (close stream)
              metadata))))))

(defun parse-html-metadata (html url)
  "解析 HTML 中的 Open Graph 和 meta 标签"
  (declare (type string html) (type string url))
  (let* ((domain (extract-domain url))
         (title (or (extract-og-tag html "og:title")
                    (extract-meta-tag html "title")
                    (extract-title-tag html)))
         (description (or (extract-og-tag html "og:description")
                          (extract-meta-tag html "description")))
         (image (or (extract-og-tag html "og:image")
                    (extract-meta-tag html "twitter:image")))
         (site-name (or (extract-og-tag html "og:site_name")
                        (extract-meta-tag html "application-name")))
         (favicon (or (extract-link-tag html "icon")
                      (extract-link-tag html "shortcut icon")
                      (format nil "https://~a/favicon.ico" domain))))
    (list :title (clean-meta-text title)
          :description (clean-meta-text description)
          :image-url (resolve-url image url)
          :site-name (clean-meta-text site-name)
          :favicon-url favicon
          :domain domain
          :content-type "text/html")))

(defun extract-og-tag (html property)
  "提取 Open Graph 标签内容"
  (declare (type string html) (type string property))
  (let* ((quote-pattern "[\"']")
         (regex (format nil "<meta[^>]*property=~Aog:~A~A[^>]*content=~A([^~A]*)~A"
                        quote-pattern property quote-pattern
                        quote-pattern quote-pattern quote-pattern))
         (regex-alt (format nil "<meta[^>]*content=~A([^~A]*)~A[^>]*property=~Aog:~A~A"
                            quote-pattern quote-pattern quote-pattern
                            quote-pattern property quote-pattern)))
    (multiple-value-bind (match-start match-end reg-start reg-end)
        (cl-ppcre:scan regex html)
      (if match-start
          (subseq html (aref reg-start 0) (aref reg-end 0))
          (multiple-value-bind (match-start match-end reg-start reg-end)
              (cl-ppcre:scan regex-alt html)
            (if match-start
                (subseq html (aref reg-start 0) (aref reg-end 0))
                nil))))))

(defun extract-meta-tag (html name)
  "提取普通 meta 标签内容"
  (declare (type string html) (type string name))
  (let ((quote-pattern "[\"']")
        (regex (format nil "<meta[^>]*name=~A~A~A[^>]*content=~A([^~A]*)~A"
                       quote-pattern name quote-pattern
                       quote-pattern quote-pattern quote-pattern)))
    (multiple-value-bind (match-start match-end reg-start reg-end)
        (cl-ppcre:scan regex html)
      (if match-start
          (subseq html (aref reg-start 0) (aref reg-end 0))
          nil))))

(defun extract-title-tag (html)
  "提取<title>标签内容"
  (declare (type string html))
  (multiple-value-bind (match-start match-end reg-start reg-end)
      (cl-ppcre:scan "<title>([^<]*)</title>" html)
    (if match-start
        (subseq html (aref reg-start 0) (aref reg-end 0))
        nil)))

(defun extract-link-tag (html rel)
  "提取<link>标签的 href"
  (declare (type string html) (type string rel))
  (let ((quote-pattern "[\"']")
        (regex (format nil "<link[^>]*rel=~A~A~A[^>]*href=~A([^~A]*)~A"
                       quote-pattern rel quote-pattern
                       quote-pattern quote-pattern quote-pattern)))
    (multiple-value-bind (match-start match-end reg-start reg-end)
        (cl-ppcre:scan regex html)
      (if match-start
          (subseq html (aref reg-start 0) (aref reg-end 0))
          nil))))

(defun extract-domain (url)
  "从 URL 提取域名"
  (declare (type string url))
  (let ((start (search "://" url)))
    (if start
        (let* ((host-start (+ start 3))
               (end (or (position #\/ url :start host-start)
                        (position #\? url :start host-start)
                        (length url))))
          (subseq url host-start end))
        url)))

(defun resolve-url (url base)
  "将相对 URL 转换为绝对 URL"
  (declare (type (or null string) url) (type string base))
  (cond
    ((null url) nil)
    ((or (search "http://" url) (search "https://" url)) url)
    ((char= (char url 0) #\/)
     (let ((domain-end (position #\/ base :start (if (search "://" base) (+ 3 (search "://" base)) 0))))
       (if domain-end
           (concatenate 'string (subseq base 0 domain-end) url)
           url)))
    (t
     (let ((base-dir (subseq base 0 (1+ (or (position #\/ base :from-end t) 0)))))
       (concatenate 'string base-dir url)))))

(defun clean-meta-text (text)
  "清理 meta 文本内容"
  (declare (type (or null string) text))
  (when text
    (string-trim '(#\Space #\Tab #\Newline #\Return) text)))

(defun get-or-create-link-preview (url)
  "获取或创建链接预览"
  (declare (type string url))
  (ensure-pg-connected)

  (let* ((result (postmodern:query
                  "SELECT * FROM get_or_create_link_preview($1, 24)"
                  url))
         (row (when result (car result))))
    (if (and row (elt row 1)) ; title exists
        (list :previewId (elt row 0)
              :url (elt row 1)
              :title (elt row 2)
              :description (elt row 3)
              :imageUrl (elt row 4)
              :siteName (elt row 5)
              :faviconUrl (elt row 6)
              :domain (elt row 7)
              :isValid (elt row 8)
              :fetchedAt (storage-universal-to-unix-ms (elt row 9)))
        ;; Need to fetch - return nil to indicate cache miss
        nil)))

(defun store-link-preview (url title description image-url site-name favicon-url domain content-type &optional metadata)
  "存储链接预览到缓存"
  (declare (type string url)
           (type (or null string) title description image-url site-name favicon-url domain content-type)
           (type (or null list) metadata))
  (ensure-pg-connected)

  (let* ((metadata-json (or metadata '(:json . "{}")))
         (result (postmodern:query
                  "SELECT store_link_preview($1, $2, $3, $4, $5, $6, $7, $8, $9::jsonb, 24)"
                  url title description image-url site-name favicon-url domain content-type metadata-json)))
    (when result
      (caar result))))

(defun invalidate-link-preview (url)
  "使链接预览缓存失效"
  (declare (type string url))
  (ensure-pg-connected)

  (let ((result (postmodern:query
                 "SELECT invalidate_link_preview($1)"
                 url)))
    (when result
      (caar result))))

(defun generate-link-preview (url)
  "生成链接预览（获取元数据并存储）"
  (declare (type string url))
  (let ((metadata (fetch-url-metadata url)))
    (if (getf metadata :error)
        (list :error (getf metadata :error)
              :url url)
        (let ((preview-id (store-link-preview
                           url
                           (getf metadata :title)
                           (getf metadata :description)
                           (getf metadata :image-url)
                           (getf metadata :site-name)
                           (getf metadata :favicon-url)
                           (getf metadata :domain)
                           (getf metadata :content-type))))
          (list :previewId preview-id
                :url url
                :title (getf metadata :title)
                :description (getf metadata :description)
                :imageUrl (getf metadata :image-url)
                :siteName (getf metadata :site-name)
                :faviconUrl (getf metadata :favicon-url)
                :domain (getf metadata :domain))))))

(defun get-link-preview (url)
  "获取链接预览（先查缓存，未命中则抓取）"
  (declare (type string url))
  (ensure-pg-connected)

  (let ((cached (get-or-create-link-preview url)))
    (if cached
        cached
        ;; Cache miss - fetch and store
        (generate-link-preview url))))

(defun extract-link-previews (text)
  "从文本中提取所有 URL 并生成预览"
  (declare (type string text))
  (let ((urls (extract-urls-from-text text))
        (previews nil))
    (dolist (url urls)
      (let ((preview (get-link-preview url)))
        (when preview
          (push preview previews))))
    (nreverse previews)))

;;;; @Mention 功能 - @全员、@特定角色

(defun parse-mentions (content group-id)
  "解析消息中的@提及，返回提及的用户 ID 列表
   支持：@all (所有人), @admin (管理员), @owner (群主)
   返回：(values user-ids mention-type)"
  (declare (type string content)
           (type (or null integer) group-id))

  (let ((user-ids nil)
        (mention-types nil)
        (all-mentioned nil)
        (admin-mentioned nil)
        (owner-mentioned nil))

    ;; 检查特殊提及
    (when (cl-ppcre:scan "@all\\b" content)
      (setf all-mentioned t)
      (push :all mention-types))

    (when (cl-ppcre:scan "@admin\\b" content)
      (setf admin-mentioned t)
      (push :admin mention-types))

    (when (cl-ppcre:scan "@owner\\b" content)
      (setf owner-mentioned t)
      (push :owner mention-types))

    ;; 如果是群组消息，获取对应角色的用户
    (when group-id
      (let ((members (get-group-members group-id)))
        (when all-mentioned
          ;; @all - 通知所有成员（排除自己）
          (dolist (m members)
            (let ((uid (group-member-user-id m)))
              (unless (string= uid *current-user-id*)
                (push uid user-ids)))))

        (when admin-mentioned
          ;; @admin - 通知所有管理员和群主
          (dolist (m members)
            (let ((role (group-member-role m))
                  (uid (group-member-user-id m)))
              (when (and (member role '(:admin :owner))
                         (not (string= uid *current-user-id*)))
                (push uid user-ids)))))

        (when owner-mentioned
          ;; @owner - 通知群主
          (dolist (m members)
            (let ((role (group-member-role m))
                  (uid (group-member-user-id m)))
              (when (and (eq role :owner)
                         (not (string= uid *current-user-id*))
                         (not (member uid user-ids :test #'string=)))
                (push uid user-ids)))))))

    ;; 解析普通@用户提及 (@username 或@userId)
    (let ((mention-regex "@([\\w-]+)")
          (start 0))
      (loop
        (multiple-value-bind (match-start match-end reg-start reg-end)
            (cl-ppcre:scan mention-regex content :start start)
          (if match-start
              (progn
                (let ((mentioned-name (subseq content (aref reg-start 0) (aref reg-end 0))))
                  ;; 跳过特殊提及
                  (unless (member mentioned-name '("all" "admin" "owner") :test #'string=)
                    ;; 尝试查找用户
                    (let ((user (get-user-by-username mentioned-name)))
                      (when user
                        (let ((uid (gethash "id" user)))
                          (unless (or (string= uid *current-user-id*)
                                      (member uid user-ids :test #'string=))
                            (push uid user-ids)))))))
                (setf start match-end))
              (return)))))

    (values (nreverse user-ids) (nreverse mention-types))))

(defun notify-mentioned-users (message-id conversation-id user-ids mention-types)
  "通知被提及的用户"
  (declare (type message-id message-id)
           (type conversation-id conversation-id)
           (type list user-ids)
           (type list mention-types))

  (when (or user-ids mention-types)
    (let ((notification `((:type . :mentioned)
                          (:message-id . ,message-id)
                          (:conversation-id . ,conversation-id)
                          (:mention-types . ,mention-types)
                          (:ts . ,(lispim-universal-to-unix-ms (get-universal-time))))))
      ;; 通知每个被提及的用户
      (dolist (uid user-ids)
        (handler-case
            (let ((user-convs (get-user-conversations uid)))
              (dolist (conv user-convs)
                (when (eq (conversation-id conv) conversation-id)
                  (push-to-online-user uid notification))))
          (error (c)
            (log-error "Failed to notify mentioned user ~a: ~a" uid c))))

      (log-info "Notified ~a mentioned users in conversation ~a" (length user-ids) conversation-id)))

  t)

(defun enhance-send-message-with-mentions (conversation-id content &key (type :text) attachments mentions reply-to)
  "增强的 send-message，支持@提及通知"
  (declare (type conversation-id conversation-id)
           (type (or null string) content)
           (type message-type type)
           (type (or null list) attachments mentions reply-to))

  ;; 调用原始的 send-message
  (let ((msg (send-message conversation-id content
                           :type type
                           :attachments attachments
                           :mentions mentions
                           :reply-to reply-to)))
    ;; 解析并通知提及
    (when content
      (multiple-value-bind (user-ids mention-types)
          (parse-mentions content (get-group-id-from-conversation conversation-id))
        (when (or user-ids mention-types)
          (notify-mentioned-users (message-id msg) conversation-id user-ids mention-types))))

    msg))

(defun get-group-id-from-conversation (conversation-id)
  "从会话 ID 获取群组 ID"
  (declare (type conversation-id conversation-id))
  (let ((conv (get-conversation conversation-id)))
    (when conv
      (let ((metadata (conversation-metadata conv)))
        (gethash :group-id metadata)))))

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

          ;; Message pinning
          pin-message
          unpin-message
          get-pinned-messages
          is-message-pinned

          ;; Group DND
          mute-conversation
          unmute-conversation
          is-conversation-muted
          get-muted-conversations

          ;; Message forwarding
          forward-message
          forward-messages
          get-message-forward-count
          get-forwarded-message-origin

          ;; Highlight messages
          add-highlighted-message
          remove-highlighted-message
          get-highlighted-messages

          ;; Link preview
          extract-urls-from-text
          get-link-preview
          generate-link-preview
          extract-link-previews
          store-link-preview
          invalidate-link-preview

          ;; Online users
          push-to-online-user
          push-to-online-users

          ;; @Mentions
          parse-mentions
          notify-mentioned-users
          enhance-send-message-with-mentions
          get-group-id-from-conversation

          ;; Variables
          *current-user-id*

          ;; Conditions
          conversation-not-found
          conversation-access-denied
          message-not-found
          message-too-long
          message-recall-timeout)
        :lispim-core)
