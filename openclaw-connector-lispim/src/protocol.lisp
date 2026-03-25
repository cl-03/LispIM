;;;; protocol.lisp - OpenClaw 通信协议
;;;;
;;;; 定义 OpenClaw 与 LispIM 之间的通信协议

(in-package :openclaw-connector)

;;;; 消息类型

(deftype oc-message-type ()
  '(member :handshake
           :chat
           :command
           :response
           :stream
           :error
           :heartbeat))

;;;; 消息结构

(defstruct oc-message
  "OpenClaw 消息"
  (id (uuid:to-string (uuid:make-v4-uuid)) :type string)
  (type :chat :type oc-message-type)
  (version *oc-protocol-version* :type string)
  (timestamp (get-universal-time) :type integer)
  (sender "" :type string)
  (recipient "" :type string)
  (conversation-id nil :type (or null string))
  (content nil :type (or null string))
  (metadata (make-hash-table :test 'equal) :type hash-table)
  (attachments nil :type list))

;;;; 消息编码

(defun encode-message (msg)
  "编码消息为 JSON"
  (declare (type oc-message msg))
  (cl-json:encode-json-to-string
   `(("id" . ,(oc-message-id msg))
     ("type" . ,(symbol-name (oc-message-type msg)))
     ("version" . ,(oc-message-version msg))
     ("timestamp" . ,(oc-message-timestamp msg))
     ("sender" . ,(oc-message-sender msg))
     ("recipient" . ,(oc-message-recipient msg))
     ("conversation_id" . ,(oc-message-conversation-id msg))
     ("content" . ,(oc-message-content msg))
     ("metadata" . ,(hash-to-plist (oc-message-metadata msg)))
     ("attachments" . ,(oc-message-attachments msg)))))

(defun decode-message (json-str)
  "解码 JSON 消息"
  (declare (type string json-str))
  (let ((data (cl-json:decode-json-from-string json-str)))
    (make-oc-message
     :id (getf data :id)
     :type (intern (string-upcase (getf data :type)) :keyword)
     :version (or (getf data :version) *oc-protocol-version*)
     :timestamp (or (getf data :timestamp) (get-universal-time))
     :sender (or (getf data :sender) "")
     :recipient (or (getf data :recipient) "")
     :conversation-id (getf data :conversation_id)
     :content (getf data :content)
     :metadata (plist-to-hash (or (getf data :metadata) nil))
     :attachments (or (getf data :attachments) nil))))

;;;; 消息构建器

(defun make-oc-message (type content &key sender recipient conversation-id metadata)
  "创建 OpenClaw 消息"
  (declare (type oc-message-type type)
           (type (or null string) content))
  (make-oc-message
   :type type
   :content content
   :sender (or sender "")
   :recipient (or recipient "")
   :conversation-id conversation-id
   :metadata (or metadata (make-hash-table :test 'equal))))

;;;; 握手消息

(defun make-handshake-message (client-id api-key)
  "创建握手消息"
  (declare (type string client-id api-key))
  (make-oc-message
   :handshake
   nil
   :metadata (let ((ht (make-hash-table :test 'equal)))
               (setf (gethash :client_id ht) client-id)
               (setf (gethash :api_key ht) api-key)
               (setf (gethash :capabilities ht)
                     '("streaming" "context-summarization" "skill-callback"))
               ht)))

;;;; 响应消息

(defun make-response-message (request-msg content &key error-p)
  "创建响应消息"
  (declare (type oc-message request-msg)
           (type (or null string) content))
  (make-oc-message
   (if error-p :error :response)
   content
   :recipient (oc-message-sender request-msg)
   :conversation-id (oc-message-conversation-id request-msg)
   :metadata (let ((ht (make-hash-table :test 'equal)))
               (setf (gethash :in-reply-to ht) (oc-message-id request-msg))
               ht)))

;;;; 心跳消息

(defun make-heartbeat-message ()
  "创建心跳消息"
  (make-oc-message
   :heartbeat
   nil
   :metadata (let ((ht (make-hash-table :test 'equal)))
               (setf (gethash :timestamp ht) (get-universal-time))
               ht)))

;;;; 工具函数

(defun hash-to-plist (ht)
  "哈希表转属性列表"
  (declare (type (or null hash-table) ht))
  (when ht
    (let ((plist nil))
      (maphash (lambda (k v)
                 (push (if (keywordp k) (symbol-name k) (format nil "~a" k)) plist)
                 (push v plist))
               ht)
      (nreverse plist))))

(defun plist-to-hash (plist)
  "属性列表转哈希表"
  (declare (type (or null list) plist))
  (if (null plist)
      (make-hash-table :test 'equal)
      (let ((ht (make-hash-table :test 'equal)))
        (loop for (k v) on plist by #'cddr
              do (setf (gethash k ht) v))
        ht)))

;;;; 协议常量

(defparameter +oc-max-message-size+ (* 1024 1024)  ; 1MB
  "最大消息大小")

(defparameter +oc-heartbeat-interval+ 30
  "心跳间隔（秒）")

(defparameter +oc-heartbeat-timeout+ 90
  "心跳超时（秒）")

(defparameter +oc-reconnect-delay+ 5
  "重连延迟（秒）")
