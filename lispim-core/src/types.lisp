;;;; types.lisp - LispIM 类型定义
;;;;
;;;; 定义核心类型和结构体，供其他模块使用
;;;; 此文件在 conditions.lisp 之后编译，可以使用条件类

(in-package :lispim-core)

;;;; 类型定义

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
  '(member :text :image :voice :video :file :system :notification :link :audio :location :contact :sticker :gif))

(deftype conversation-type ()
  "会话类型"
  '(member :direct :group :channel))

(deftype read-receipt ()
  "已读回执类型 - 用户 ID 和时间的列表"
  '(list (cons string integer)))

(deftype attachment ()
  "附件类型 - plist with :type, :url, :size, :name keys"
  'plist)

;;;; 消息结构

(define-condition message-error (lispim-error)
  ()
  (:documentation "Base condition for message errors"))

(define-condition message-not-found (message-error)
  ((message-id :initarg :message-id :reader message-error-message-id))
  (:report (lambda (c s)
             (format s "Message not found: ~A" (message-error-message-id c)))))

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

;;;; 会话结构

(define-condition conversation-error (lispim-error)
  ()
  (:documentation "Base condition for conversation errors"))

(define-condition conversation-not-found (conversation-error)
  ((conversation-id :initarg :conversation-id :reader conversation-error-conversation-id))
  (:report (lambda (c s)
             (format s "Conversation not found: ~A" (conversation-error-conversation-id c)))))

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

;;;; Connection types and structures

(deftype connection-state ()
  "Connection state type"
  '(member :connecting :authenticated :active :closing :closed))

(deftype connection-id ()
  "Connection ID type"
  '(or uuid:uuid string))

(defstruct connection
  "Connection state management"
  (id (uuid:make-v4-uuid) :type uuid:uuid)
  (user-id nil :type (or null string))
  (state :connecting :type connection-state)
  (last-heartbeat (get-universal-time) :type integer)
  (connected-at (get-universal-time) :type integer)
  (metadata (make-hash-table :test 'equal) :type hash-table)
  (message-count 0 :type integer)
  (socket nil :type t)
  (socket-stream nil :type (or null stream)))
