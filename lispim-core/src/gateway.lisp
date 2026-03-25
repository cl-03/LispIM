;;;; gateway.lisp - HTTP/WebSocket Gateway using Hunchentoot
;;;;
;;;; Responsible for HTTP request handling and basic connection management
;;;; API versioning: /api/v1/

(in-package :lispim-core)

;;;; Special variable declarations (for dynamic binding)

(declaim (special *current-user-id*))

;;;; Dependencies

(eval-when (:compile-toplevel :load-toplevel :execute)
  (ql:quickload '(:hunchentoot :bordeaux-threads :uuid :cl-json :flexi-streams :cl-base64 :ironclad)))

;;;; Helper Functions

(defun session-user-id (session)
  "Get user-id from session plist"
  (getf session :user-id))

(defun session-username (session)
  "Get username from session plist"
  (getf session :username))

(defun get-session-by-token (token)
  "Get session by token/session-id"
  (get-session token))

(defun user-id (user)
  "Get id from user plist"
  (getf user :id))

(defun user-username (user)
  "Get username from user plist"
  (getf user :username))

(defun user-display-name (user)
  "Get display name from user plist"
  (getf user :displayName))

(defun user-email (user)
  "Get email from user plist"
  (getf user :email))

(defun user-avatar (user)
  "Get avatar from user plist"
  (getf user :avatar))

(defun conversation-id (conv)
  "Get id from conversation plist"
  (getf conv :id))

(defun conversation-name (conv)
  "Get name from conversation plist"
  (getf conv :name))

(defun conversation-type (conv)
  "Get type from conversation plist"
  (getf conv :type))

(defun conversation-last-message (conv)
  "Get last message from conversation plist"
  (getf conv :lastMessage))

(defun conversation-unread-count (conv)
  "Get unread count from conversation plist"
  (getf conv :unreadCount))

;;;; Message plist accessors (for API responses, not chat.lisp message structs)

(defun api-message-id (msg)
  "Get id from message plist"
  (getf msg :id))

(defun api-message-conversation-id (msg)
  "Get conversation id from message plist"
  (getf msg :conversationId))

(defun api-message-sender-id (msg)
  "Get sender id from message plist"
  (getf msg :senderId))

(defun api-message-content (msg)
  "Get content from message plist"
  (getf msg :content))

(defun api-message-type (msg)
  "Get type from message plist"
  (getf msg :type))

(defun api-message-created-at (msg)
  "Get created at from message plist"
  (getf msg :createdAt))

;;;; Helper Functions

(defun get-request-body-string ()
  "Get request body as string, handling both byte arrays and strings"
  (handler-case
      (let ((raw (hunchentoot:raw-post-data :force-binary t)))
        (cond
          ((null raw) "")
          ((stringp raw) raw)
          ((typep raw '(simple-array (unsigned-byte 8)))
           ;; Use flexi-streams for proper UTF-8 decoding
           (flexi-streams:octets-to-string raw :external-format :utf-8))))
    (flexi-streams:external-format-encoding-error (c)
      ;; Fallback: try with latin-1 which accepts any byte sequence
      (let ((raw (hunchentoot:raw-post-data :force-binary t)))
        (if (typep raw '(simple-array (unsigned-byte 8)))
            (flexi-streams:octets-to-string raw :external-format :latin-1)
            "")))))

;;;; API Response Format - Unified JSON structure

(defun kebab-to-camel-case (str &optional (capitalize-first nil))
  "Convert kebab-case string to camelCase"
  (declare (type string str)
           (optimize (speed 2) (safety 1)))
  (let ((parts (split-sequence:split-sequence #\- str))
        (result ""))
    (loop for part in parts
          for i from 0
          do (if (or (zerop i) capitalize-first)
                 (setf result (concatenate 'string result part))
                 (setf result (concatenate 'string result
                                           (string-upcase (subseq part 0 1))
                                           (subseq part 1)))))
    result))

(declaim (inline make-api-response make-api-error encode-api-response require-auth))

(defun require-auth ()
  "验证 Token 并返回user-id，如果无效则设置 401 状态并返回 nil"
  (handler-case
      (let ((token (hunchentoot:header-in "Authorization" hunchentoot:*request*)))
        (log-info "Require-auth: token header=~A" token)
        (unless token
          (setf (hunchentoot:return-code*) 401)
          (return-from require-auth nil))
        (let ((user-id (verify-token (remove-prefix token "Bearer "))))
          (log-info "Require-auth: verify-token returned=~A" user-id)
          (unless user-id
            (setf (hunchentoot:return-code*) 401)
            (return-from require-auth nil))
          user-id))
    (error (c)
      (log-error "Require-auth error: ~A" c)
      (setf (hunchentoot:return-code*) 500)
      nil)))

(defun make-api-response (data &key (success t) message)
  "创建统一 API 响应"
  (declare (optimize (speed 3) (safety 1)))
  (append (list :success success)
          (when success (list :data data))
          (when message (list :message message))))

(defun make-api-error (code message &optional data)
  "创建统一 API 错误响应"
  (declare (type string code message)
           (optimize (speed 2) (safety 1)))
  (list :success nil
        :error (list :code code
                     :message message
                     :details data)))

(defun encode-api-response (response)
  "编码 API 响应中JSON 字符串"
  (declare (type list response)
           (optimize (speed 2) (safety 1)))
  ;; Convert plists to alists with camelCase keys for JSON encoding
  (let ((converted (convert-response-to-camelcase response)))
    (cl-json:encode-json-to-string converted)))

(defun convert-response-to-camelcase (data)
  "Recursively convert plist response to alist with camelCase keys"
  (cond
    ;; Null - JSON null
    ((null data) nil)
    ;; Plist - convert to alist with camelCase keys
    ((and (consp data) (keywordp (car data)))
     (let ((result nil))
       (loop for (key value) on data by #'cddr do
         (push (cons (kebab-to-camel-case (string-downcase (symbol-name key)))
                     (convert-response-to-camelcase value))
               result))
       (nreverse result)))
    ;; List - convert each element
    ((listp data)
     (mapcar #'convert-response-to-camelcase data))
    ;; String "null" - convert to nil (JSON null)
    ((and (stringp data) (string= data "null"))
     nil)
    ;; Keyword - convert to string (for friend-status etc.)
    ((keywordp data)
     (string-downcase (symbol-name data)))
    ;; Primitive
    (t data)))

(defmacro with-api-handler ((&key method content-type) &body body)
  "API 处理器宏 - 统一错误处理和响应格式"
  `(progn
     ;; Add CORS headers for all API requests
     (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
     (setf (hunchentoot:header-out "Access-Control-Allow-Methods") "GET, POST, PUT, DELETE, OPTIONS")
     (setf (hunchentoot:header-out "Access-Control-Allow-Headers") "Content-Type, Authorization")
     (when (and ,method (not (string= (hunchentoot:request-method hunchentoot:*request*) ,method)))
       (setf (hunchentoot:return-code*) 405)
       (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed")))
     (when ,content-type
       (setf (hunchentoot:content-type*) ,content-type))
     (handler-case
         (progn ,@body)
       (auth-error (c)
         (setf (hunchentoot:return-code*) 401)
         (encode-api-response (make-api-error "AUTH_ERROR" (format nil "~A" c))))
       (conversation-not-found (c)
         (setf (hunchentoot:return-code*) 404)
         (encode-api-response (make-api-error "NOT_FOUND" (format nil "~A" c))))
       (message-too-long (c)
         (setf (hunchentoot:return-code*) 400)
         (encode-api-response (make-api-error "INVALID_REQUEST" (format nil "~A" c))))
       (error (c)
         (log-error "API error: ~a" c)
         (setf (hunchentoot:return-code*) 500)
         (encode-api-response (make-api-error "INTERNAL_ERROR" "Internal server error"))))))

(defvar *current-handler* nil
  "当前处理器函数名")

;;;; Types

(deftype connection-state ()
  '(member :connecting :authenticated :active :closing :closed))

(deftype connection-id ()
  '(or uuid:uuid string))

;;;; Connection structure

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

;;;; Connection manager

(defvar *connections* (make-hash-table :test 'equal)
  "Active connection table: connection-id -> connection")

(defvar *connections-lock* (bordeaux-threads:make-lock "connections-lock")
  "Connection table lock")

(defvar *connections-active-gauge* 0
  "Active connection count metric")

(defvar *heartbeat-interval* 30
  "Heartbeat interval (seconds)")

(defvar *heartbeat-timeout* 90
  "Heartbeat timeout (seconds)")

;;;; Connection management functions

(defun register-connection (conn)
  "Register new connection"
  (declare (type connection conn))
  (bordeaux-threads:with-lock-held (*connections-lock*)
    (setf (gethash (connection-id conn) *connections*) conn)
    (incf *connections-active-gauge*))
  (log-info "Connection registered: ~a (user: ~a)"
            (connection-id conn)
            (connection-user-id conn))
  conn)

(defun unregister-connection (conn-id)
  "Unregister connection"
  (declare (type uuid:uuid conn-id))
  (bordeaux-threads:with-lock-held (*connections-lock*)
    (let ((conn (gethash conn-id *connections*)))
      (when conn
        (remhash conn-id *connections*)
        (decf *connections-active-gauge*)
        (log-info "Connection unregistered: ~a" conn-id))))
  nil)

(defun get-connection (conn-id)
  "Get connection"
  (declare (type uuid:uuid conn-id))
  (bordeaux-threads:with-lock-held (*connections-lock*)
    (gethash conn-id *connections*)))

(defun get-user-connections (user-id)
  "Get all connections for user (supports multi-device login)"
  (declare (type string user-id))
  (bordeaux-threads:with-lock-held (*connections-lock*)
    (loop for conn being the hash-values of *connections*
          when (and (connection-user-id conn)
                    (string= (connection-user-id conn) user-id))
          collect conn)))

(defun set-connection-state (conn-id state)
  "Set connection state"
  (declare (type uuid:uuid conn-id)
           (type connection-state state))
  (bordeaux-threads:with-lock-held (*connections-lock*)
    (let ((conn (gethash conn-id *connections*)))
      (when conn
        (setf (connection-state conn) state)))))

(defun update-connection-heartbeat (conn-id)
  "Update connection heartbeat time"
  (declare (type uuid:uuid conn-id))
  (bordeaux-threads:with-lock-held (*connections-lock*)
    (let ((conn (gethash conn-id *connections*)))
      (when conn
        (setf (connection-last-heartbeat conn) (get-universal-time))))))

;;;; Message routing

(defun broadcast-to-user (user-id message)
  "Broadcast message to all user connections"
  (declare (type string user-id)
           (type (or string vector) message))
  (let ((conns (get-user-connections user-id)))
    (dolist (conn conns)
      (send-to-connection conn message)))
  nil)

(defun broadcast-to-all (message)
  "Broadcast message to all connections"
  (declare (type (or string vector) message))
  (bordeaux-threads:with-lock-held (*connections-lock*)
    (maphash (lambda (id conn)
               (send-to-connection conn message))
             *connections*)))

;;;; WebSocket helpers

(defvar *ws-connections* (make-hash-table :test 'equal)
  "WebSocket connection hash table")

(defvar *ws-connections-lock* (bordeaux-threads:make-lock "ws-connections-lock")
  "WebSocket connection table lock")

(defstruct ws-frame
  "WebSocket frame structure"
  (fin t :type boolean)
  (opcode 0 :type (unsigned-byte 4))
  (mask-p nil :type boolean)
  (mask-key nil :type (or null (simple-array (unsigned-byte 8) (4))))
  (payload-length 0 :type integer)
  (payload nil :type (or null (simple-array (unsigned-byte 8) (*)))))

;;;; WebSocket Protocol v1 - Enhanced with ACK mechanism and standard message types

;; Standard WebSocket message types for LispIM Protocol v1
(defparameter +ws-msg-auth+ :auth)
(defparameter +ws-msg-auth-response+ :auth-response)
(defparameter +ws-msg-message+ :message)
(defparameter +ws-msg-message-received+ :message-received)
(defparameter +ws-msg-message-delivered+ :message-delivered)
(defparameter +ws-msg-message-read+ :message-read)
(defparameter +ws-msg-ping+ :ping)
(defparameter +ws-msg-pong+ :pong)
(defparameter +ws-msg-error+ :error)
(defparameter +ws-msg-notification+ :notification)
(defparameter +ws-msg-presence+ :presence)
(defparameter +ws-msg-typing+ :typing)

;; Message acknowledgment structure
(defstruct ws-ack
  "WebSocket ACK structure"
  (message-id nil :type (or null string))
  (ack-type :received :type (member :received :delivered :read))
  (timestamp (get-universal-time) :type integer)
  (error nil :type (or null string)))

(defun make-ws-message (type payload &key (message-id nil) (ack-required nil))
  "创建标准 WebSocket 消息"
  (declare (type keyword type)
           (type list payload)
           (optimize (speed 2) (safety 1)))
  (let ((msg (list :type type
                   :payload payload
                   :version "1.0"
                   :timestamp (lispim-universal-to-unix-ms (get-universal-time)))))
    (when message-id
      (setf (getf msg :message-id) message-id))
    (when ack-required
      (setf (getf msg :ack-required) t))
    msg))

(defun encode-ws-message (message)
  "编码 WebSocket 消息中JSON"
  (declare (type list message)
           (optimize (speed 2) (safety 1)))
  (cl-json:encode-json-to-string message))

(defun send-ws-message (conn type payload &key (ack-required nil))
  "发送标准WebSocket 消息"
  (declare (type connection conn)
           (type keyword type)
           (type list payload))
  (let* ((message-id (when ack-required
                       (format nil "msg-~a-~a"
                               (connection-id conn)
                               (get-universal-time))))
         (message (make-ws-message type payload :message-id message-id :ack-required ack-required)))
    (send-to-connection conn (encode-ws-message message))
    message-id))

(defun send-ack (conn message-id &key (ack-type :received) error)
  "发送ACK 响应"
  (declare (type connection conn)
           (type string message-id)
           (type (member :received :delivered :read) ack-type))
  (let ((ack-payload (list :message-id message-id
                           :ack-type ack-type
                           :timestamp (lispim-universal-to-unix-ms (get-universal-time))
                           :error error)))
    (send-ws-message conn +ws-msg-message-received+ ack-payload)))

(defun handle-ack (conn ack-data)
  "处理收到的ACK"
  (declare (type connection conn)
           (type list ack-data))
  (let* ((message-id (getf ack-data :message-id))
         (ack-type (getf ack-data :ack-type)))
    (log-debug "Received ACK ~a for message ~a" ack-type message-id)
    ;; 可以在这里添加消息状态跟踪逻辑
    t))
(defparameter +ws-op-continuation+ #b0000)
(defparameter +ws-op-text+ #b0001)
(defparameter +ws-op-binary+ #b0010)
(defparameter +ws-op-close+ #b1000)
(defparameter +ws-op-ping+ #b1001)
(defparameter +ws-op-pong+ #b1010)

(defun encode-ws-frame (frame)
  "Encode WebSocket frame to binary"
  (declare (type ws-frame frame))
  (let ((payload (or (ws-frame-payload frame) #())))
    (with-output-to-byte-vector (stream)
      ;; First byte: FIN + OPCODE
      (write-byte (logior (if (ws-frame-fin frame) #b10000000 0)
                          (ws-frame-opcode frame))
                  stream)
      ;; Second byte: MASK + length
      (let ((len (length payload))
            (mask-bit (if (ws-frame-mask-p frame) #b10000000 0)))
        (cond
          ((< len 126)
           (write-byte (logior mask-bit len) stream))
          ((< len 65536)
           (write-byte (logior mask-bit 126) stream)
           (write-u16-be len stream))
          (t
           (write-byte (logior mask-bit 127) stream)
           (write-u64-be len stream))))
      ;; Mask key
      (when (and (ws-frame-mask-p frame) (ws-frame-mask-key frame))
        (loop for i from 0 below 4
              do (write-byte (aref (ws-frame-mask-key frame) i) stream)))
      ;; Payload
      (loop for byte across payload
            do (write-byte byte stream)))))

(defun decode-ws-frame (stream)
  "Decode WebSocket frame from binary"
  (declare (optimize (speed 3) (safety 1)))
  (let* ((first-byte (read-byte stream nil nil)))
    (unless first-byte
      (return-from decode-ws-frame nil))
    (let* ((fin (plusp (logand first-byte #b10000000)))
           (opcode (logand first-byte #b00001111))
           (second-byte (read-byte stream))
           (mask-p (plusp (logand second-byte #b10000000)))
           (length (logand second-byte #b01111111))
           (payload-length
            (cond
              ((< length 126) length)
              ((= length 126) (the (unsigned-byte 16) (read-u16-be stream)))
              (t (the (unsigned-byte 64) (read-u64-be stream)))))
           (mask-key
            (when mask-p
              (let ((key (make-array 4 :element-type '(unsigned-byte 8))))
                (loop for i from 0 below 4
                      do (setf (aref key i) (read-byte stream)))
                key)))
           (payload
             (let ((data (make-array payload-length :element-type '(unsigned-byte 8))))
               (loop for i from 0 below payload-length
                     do (setf (aref data i) (read-byte stream)))
               ;; Unmask if needed
               (when mask-key
                 (loop for i from 0 below payload-length
                       do (setf (aref data i)
                                (logxor (aref data i)
                                        (aref mask-key (mod i 4))))))
               data)))
      (make-ws-frame
       :fin fin
       :opcode opcode
       :mask-p mask-p
       :mask-key mask-key
       :payload-length payload-length
       :payload payload))))

(defun send-to-connection (conn data)
  "Send data to connection via WebSocket"
  (declare (type connection conn)
           (type (or string (simple-array (unsigned-byte 8) (*))) data))
  (handler-case
      (let* ((string-data (if (stringp data)
                              data
                              (babel:octets-to-string data :encoding :utf-8)))
             (payload (babel:string-to-octets string-data :encoding :utf-8))
             (frame (make-ws-frame :fin t :opcode +ws-op-text+ :payload payload))
             (frame-bytes (encode-ws-frame frame))
             (socket-stream (connection-socket-stream conn)))
        ;; Write to socket stream
        (when (and socket-stream (streamp socket-stream))
          (write-sequence frame-bytes socket-stream)
          (finish-output socket-stream))
        (incf (connection-message-count conn))
        (log-debug "Sent to connection ~a: ~d bytes" (connection-id conn) (length string-data)))
    (error (c)
      (log-error "Failed to send to connection ~a: ~a" (connection-id conn) c)
      (unregister-connection (connection-id conn)))))

(defun receive-from-connection (conn data)
  "Receive data from connection"
  (declare (type connection conn)
           (type (simple-array (unsigned-byte 8) (*)) data))
  (handler-case
      (let* ((json-str (babel:octets-to-string data :encoding :utf-8))
             (message (cl-json:decode-json-from-string json-str)))
        (incf (connection-message-count conn))
        (process-ws-message conn message))
    (error (c)
      (log-error "Failed to receive from connection ~a: ~a" (connection-id conn) c))))

(defun process-ws-message (conn message)
  "Process WebSocket message with Protocol v1"
  (declare (type connection conn)
           (type list message))
  (let* ((msg-type (getf message :type))
         (payload (getf message :payload))
         (message-id (getf message :message-id))
         (ack-required (getf message :ack-required)))
    ;; 发送ACK 如果需要
    (when (and ack-required message-id)
      (send-ack conn message-id :ack-type :received))
    ;; 处理消息
    (case msg-type
      ;; 兼容旧版 ping/pong
      (:ping
       (send-pong conn (getf message :data)))
      (:pong
       (update-connection-heartbeat (connection-id conn)))
      ;; Protocol v1 ping/pong
      ((+ws-msg-ping+)
       (send-ws-message conn +ws-msg-pong+ (list :timestamp (lispim-universal-to-unix-ms (get-universal-time)))))
      ((+ws-msg-pong+)
       (update-connection-heartbeat (connection-id conn)))
      ;; 认证
      ((+ws-msg-auth+)
       (handle-auth-message conn payload))
      ;; 聊天消息
      ((+ws-msg-message+)
       (handle-chat-message conn payload))
      ;; ACK 处理
      ((+ws-msg-message-received+ +ws-msg-message-delivered+ +ws-msg-message-read+)
       (handle-ack conn message))
      ;; 在线状态
      ((+ws-msg-presence+)
       (handle-presence-update conn payload))
      ;; 输入状态
      ((+ws-msg-typing+)
       (handle-typing-update conn payload))
      ;; 未知类型
      (t
       (log-warn "Unknown message type: ~a" msg-type)
       (when message-id
         (send-ack conn message-id :ack-type :received :error "Unknown message type"))))))

(defun send-ping (conn)
  "Send ping to connection"
  (declare (type connection conn))
  (let ((frame (make-ws-frame
                :fin t
                :opcode +ws-op-ping+
                :payload (babel:string-to-octets (format nil "~a" (get-universal-time))
                                                 :encoding :utf-8))))
    (send-to-connection conn (encode-ws-frame frame))))

(defun send-pong (conn data)
  "Send pong to connection"
  (declare (type connection conn)
           (type (or null string) data))
  (let ((frame (make-ws-frame
                :fin t
                :opcode +ws-op-pong+
                :payload (when data
                           (babel:string-to-octets data :encoding :utf-8)))))
    (send-to-connection conn (encode-ws-frame frame))))

(defun handle-auth-message (conn message)
  "Handle authentication message with Protocol v1"
  (declare (type connection conn)
           (type list message))
  (let ((token (getf message :token))
        (user-id (getf message :user-id)))
    (declare (ignore token))
    ;; In a real implementation, validate the token
    (when user-id
      (setf (connection-user-id conn) user-id
            (connection-state conn) :authenticated)
      (log-info "Connection ~a authenticated as user ~a"
                (connection-id conn) user-id)
      (send-ws-message conn +ws-msg-auth-response+
                       (list :success t
                             :user-id user-id
                             :connection-id (connection-id conn))))))

(defun handle-chat-message (conn message)
  "Handle chat message with Protocol v1"
  (declare (type connection conn)
           (type list message))
  (let* ((content (getf message :content))
         (conversation-id (getf message :conversation-id))
         (type (getf message :type :text))
         (reply-to (getf message :reply-to))
         (mentions (getf message :mentions))
         (attachments (getf message :attachments)))
    (when (and conversation-id content)
      ;; 发送消息
          (handler-case
          (let ((msg (send-message conversation-id content
                                   :type type
                                   :attachments attachments
                                   :reply-to reply-to
                                   :mentions mentions)))
            ;; 返回发送成功的消息给发送者
            (send-ws-message conn +ws-msg-message+
                             (list :id (message-id msg)
                                   :sequence (message-sequence msg)
                                   :conversation-id conversation-id
                                   :sender-id (message-sender-id msg)
                                   :content (message-content msg)
                                   :type type
                                   :created-at (lispim-universal-to-unix-ms (message-created-at msg))))
            ;; 广播消息给会话中所有在线参与者
            (push-to-online-users conversation-id msg))
        (error (c)
          (log-error "Failed to send chat message: ~a" c)
          (send-ws-message conn +ws-msg-error+
                           (list :code "SEND_FAILED"
                                 :message (format nil "Failed to send message: ~a" c))))))))

(defun handle-presence-update (conn message)
  "处理在线状态更新"
  (declare (type connection conn)
           (type list message))
  (let ((status (getf message :status))  ; :online, :offline, :away, :busy
        (custom-message (getf message :message)))
    (when status
      ;; 更新用户在线状态
      (log-info "Presence update for user ~a: ~a" (connection-user-id conn) status)
      ;; TODO: 广播状态更新给其他用户
      )))

(defun handle-typing-update (conn message)
  "处理输入状态更新"
  (declare (type connection conn)
           (type list message))
  (let ((conversation-id (getf message :conversation-id))
        (is-typing (getf message :is-typing)))
    (when (and conversation-id is-typing)
      ;; 广播输入状态给会话中的其他用户
      (log-debug "User ~a is typing in conversation ~a"
                 (connection-user-id conn) conversation-id)
      ;; TODO: 广播输入状态给会话中的其他用户
      )))

;;;; Heartbeat monitor

(defvar *heartbeat-monitor-thread* nil
  "Heartbeat monitor thread")

(defun start-heartbeat-monitor ()
  "Start heartbeat monitor thread"
  (setf *heartbeat-monitor-thread*
        (bordeaux-threads:make-thread
         (lambda ()
           (log-info "Heartbeat monitor started")
           (loop do
                 (sleep *heartbeat-interval*)
                 (check-heartbeats)))
         :name "heartbeat-monitor"
         :initial-bindings `((*standard-output* . ,*standard-output*)))))

(defun stop-heartbeat-monitor ()
  "Stop heartbeat monitor thread"
  (when *heartbeat-monitor-thread*
    (bordeaux-threads:destroy-thread *heartbeat-monitor-thread*)
    (setf *heartbeat-monitor-thread* nil)
    (log-info "Heartbeat monitor stopped")))

(defun check-heartbeats ()
  "Check all connection heartbeats"
  (let ((now (get-universal-time))
        (timed-out-connections nil))
    (bordeaux-threads:with-lock-held (*connections-lock*)
      (maphash (lambda (id conn)
                 (declare (ignore id))
                 (when (> (- now (connection-last-heartbeat conn))
                          *heartbeat-timeout*)
                   (push conn timed-out-connections)))
               *connections*))
    (dolist (conn timed-out-connections)
      (log-warn "Connection ~a heartbeat timeout" (connection-id conn))
      (unregister-connection (connection-id conn)))))

;;;; Gateway start/stop

(defvar *acceptor* nil
  "Hunchentoot acceptor instance")

(defvar *gateway-host* "0.0.0.0"
  "Gateway host")

(defvar *gateway-port* 3000
  "Gateway port")

(defvar *gateway-start-time* nil
  "Gateway start time for uptime calculation")

(defun start-gateway (&key (host *gateway-host*)
                           (port *gateway-port*)
                           (use-ssl nil)
                           (ssl-cert nil)
                           (ssl-key nil))
  "Start HTTP gateway"
  (declare (type string host)
           (type integer port))
  (log-info "Starting gateway on ~a:~a~a" host port (if use-ssl " (SSL)" ""))

  ;; Record start time
  (setf *gateway-start-time* (get-universal-time))

  ;; Initialize web client path
  (init-web-client-path)

  ;; Add assets handler to dispatch table (must be before other handlers)
  (push (hunchentoot:create-regex-dispatcher "^/assets/(.*)" 'web-assets-handler)
        hunchentoot:*dispatch-table*)

  ;; Add emojis handler to dispatch table
  (push (hunchentoot:create-regex-dispatcher "^/emojis/(.*)" 'emoji-assets-handler)
        hunchentoot:*dispatch-table*)

  ;; Add CORS preflight handler for OPTIONS requests to /api/ endpoints
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/.*" 'api-options-handler)
        hunchentoot:*dispatch-table*)

  ;; Add login handler (must be before generic /api/v1/ handler)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/auth/login$" 'api-login-v1-handler)
        hunchentoot:*dispatch-table*)

  ;; Add register handler
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/auth/register$" 'api-register-v1)
        hunchentoot:*dispatch-table*)

  ;; Add user info handler
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/users/([^/]+)$" 'api-user-info-handler)
        hunchentoot:*dispatch-table*)

  ;; Add current user profile handler
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/users/me$" 'api-current-user-handler)
        hunchentoot:*dispatch-table*)

  ;; Add update user profile handler
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/users/profile$" 'api-update-profile-handler)
        hunchentoot:*dispatch-table*)

  ;; Add conversations handler
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/chat/conversations$" 'api-get-conversations-handler)
        hunchentoot:*dispatch-table*)

  ;; Add friend management handlers
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/friends$" 'api-get-friends-handler)
        hunchentoot:*dispatch-table*)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/friends/add$" 'api-add-friend-handler)
        hunchentoot:*dispatch-table*)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/friends/requests$" 'api-get-friend-requests-handler)
        hunchentoot:*dispatch-table*)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/friends/accept$" 'api-accept-friend-handler)
        hunchentoot:*dispatch-table*)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/users/search$" 'api-search-users-handler)
        hunchentoot:*dispatch-table*)

  ;; Add create conversation handler
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/chat/conversations/create$" 'api-create-conversation-handler)
        hunchentoot:*dispatch-table*)

  ;; Add conversation messages handler
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/chat/conversations/([^/]+)/messages$" 'api-conversation-messages-v1)
        hunchentoot:*dispatch-table*)

  ;; Add file upload handlers
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/upload$" 'api-upload-file-handler)
        hunchentoot:*dispatch-table*)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/files/([^/]+)$" 'api-get-file-handler)
        hunchentoot:*dispatch-table*)

  ;; Add FCM token handlers
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/device/fcm-token$" 'api-register-fcm-token-handler)
        hunchentoot:*dispatch-table*)

  ;; Start heartbeat monitor
  (start-heartbeat-monitor)

  ;; Create and start acceptor with the specified port
  (if use-ssl
      (setf *acceptor* (make-instance 'hunchentoot:easy-ssl-acceptor
                                      :port port
                                      :address host
                                      :ssl-certificate-file ssl-cert
                                      :ssl-privatekey-file ssl-key))
      (setf *acceptor* (make-instance 'hunchentoot:easy-acceptor
                                      :port port
                                      :address host)))
  (hunchentoot:start *acceptor*)
  (log-info "Gateway started"))

;;;; Top-level HTTP API handlers
;;;; These are defined at compile-time, not inside start-gateway

(defvar *web-client-path* nil
  "Web client static file path")

(defun init-web-client-path ()
  "Initialize web client path"
  ;; Use direct path construction for reliability
  (let* ((web-path #P"D:/Claude/LispIM/web-client/dist/"))
    (when (probe-file web-path)
      (setf *web-client-path* (namestring web-path))
      (log-info "Web client path: ~a" *web-client-path*))))

(defun serve-static-file (path)
  "Serve static file from web-client/dist"
  (declare (type string path))
  ;; Convert Unix-style path separators to Windows-style and build full path
  (let* ((normalized-path (subst #\\ #\/ path))
         (file-path (concatenate 'string *web-client-path* normalized-path)))
    (if (and *web-client-path*
             (cl-fad:file-exists-p file-path))
        (let ((content-type (cond
                              ((ends-with-p path ".html") "text/html")
                              ((ends-with-p path ".css") "text/css")
                              ((ends-with-p path ".js") "application/javascript")
                              ((ends-with-p path ".json") "application/json")
                              ((ends-with-p path ".png") "image/png")
                              ((ends-with-p path ".jpg") "image/jpeg")
                              ((ends-with-p path ".svg") "image/svg+xml")
                              ((ends-with-p path ".ico") "image/x-icon")
                              (t "application/octet-stream"))))
          (setf (hunchentoot:content-type*) content-type)
          ;; For binary files (PNG, JPG, ICO), read as bytes and write directly to socket
          (if (or (ends-with-p path ".png")
                  (ends-with-p path ".jpg")
                  (ends-with-p path ".ico"))
              (progn
                (with-open-file (in file-path :direction :input :element-type '(unsigned-byte 8))
                  (let ((data (make-array (file-length in) :element-type '(unsigned-byte 8))))
                    (read-sequence data in)
                    (setf (hunchentoot:content-length*) (length data))
                    (setf (hunchentoot:return-code*) 200)
                    ;; Send headers first, then write binary data
                    (hunchentoot::send-headers)
                    (write-sequence data hunchentoot::*hunchentoot-stream*)
                    (finish-output hunchentoot::*hunchentoot-stream*)
                    ;; Return nil to signal response already sent
                    nil)))
              ;; For text files, use alexandria
              (alexandria:read-file-into-string file-path)))
        nil)))

(defun ends-with-p (string suffix)
  "Check if string ends with suffix"
  (and (>= (length string) (length suffix))
       (search suffix string :from-end t)))

;; Static file handler for web client
(hunchentoot:define-easy-handler (web-index :uri "/") ()
  "Serve web client index.html"
  (or (serve-static-file "index.html")
      (progn
        (setf (hunchentoot:content-type*) "text/plain")
        "LispIM Enterprise Server - Web client not found")))

;; Raw WebSocket dispatcher - handles WebSocket upgrade before easy-handlers
(defun websocket-raw-dispatcher (request)
  "Raw dispatcher for WebSocket connections - handles upgrade and takes over connection"
  (declare (ignore request))
  (let ((upgrade (hunchentoot:header-in "Upgrade" hunchentoot:*request*)))
    (when (and upgrade (string-equal upgrade "websocket"))
      ;; This is a WebSocket upgrade request - handle it completely
      (let* ((key (hunchentoot:header-in "Sec-WebSocket-Key" hunchentoot:*request*))
             (version (hunchentoot:header-in "Sec-WebSocket-Version" hunchentoot:*request*)))
        (when (and key version (string= version "13"))
          ;; Calculate Sec-WebSocket-Accept
          (let* ((magic "258EAFA5-E914-47DA-95CA-C5AB0DC85B11")
                 (key+magic (concatenate 'string key magic))
                 (octets (flexi-streams:string-to-octets key+magic))
                 (digest (ironclad:digest-sequence :sha1 octets :start 0 :end (length octets)))
                 (accept (cl-base64:usb8-array-to-base64-string digest))
                 (stream hunchentoot::*hunchentoot-stream*))
            ;; Set *headers-sent* to prevent Hunchentoot from sending its own response
            (setf hunchentoot::*headers-sent* t)
            ;; Write raw HTTP 101 response
            (write-sequence (flexi-streams:string-to-octets "HTTP/1.1 101 Switching Protocols") stream)
            (write-byte #.(char-code #\Return) stream)
            (write-byte #.(char-code #\Linefeed) stream)
            (write-sequence (flexi-streams:string-to-octets "Upgrade: websocket") stream)
            (write-byte #.(char-code #\Return) stream)
            (write-byte #.(char-code #\Linefeed) stream)
            (write-sequence (flexi-streams:string-to-octets "Connection: Upgrade") stream)
            (write-byte #.(char-code #\Return) stream)
            (write-byte #.(char-code #\Linefeed) stream)
            (write-sequence (flexi-streams:string-to-octets (format nil "Sec-WebSocket-Accept: ~a" accept)) stream)
            (write-byte #.(char-code #\Return) stream)
            (write-byte #.(char-code #\Linefeed) stream)
            ;; Empty line to end headers
            (write-byte #.(char-code #\Return) stream)
            (write-byte #.(char-code #\Linefeed) stream)
            (finish-output stream)
            ;; Create connection state
            (let* ((conn (make-connection :socket-stream stream)))
              (register-connection conn)
              ;; Send connection established message
              (send-ws-message conn +ws-msg-auth-response+
                               (list :success t
                                     :connection-id (connection-id conn)
                                     :status "connected"))
              ;; Spawn WebSocket message loop in separate thread
              (bordeaux-threads:make-thread
               (lambda ()
                 (loop
                   (handler-case
                       (let ((frame (decode-ws-frame stream)))
                         (unless frame
                           ;; Connection closed
                           (unregister-connection (connection-id conn))
                           (return))
                         ;; Process frame based on opcode
                         (case (ws-frame-opcode frame)
                           ;; Text frame
                           (+ws-op-text+
                            (when (ws-frame-payload frame)
                              (receive-from-connection conn (ws-frame-payload frame))))
                           ;; Ping frame - send pong
                           (+ws-op-ping+
                            (let ((pong-frame (make-ws-frame :fin t :opcode +ws-op-pong+
                                                             :payload (ws-frame-payload frame))))
                              (write-sequence (encode-ws-frame pong-frame) stream)
                              (finish-output stream)))
                           ;; Pong frame - update heartbeat
                           (+ws-op-pong+
                            (update-connection-heartbeat (connection-id conn)))
                           ;; Close frame
                           (+ws-op-close+
                            (unregister-connection (connection-id conn))
                            (return))
                           (t
                            (log-warn "Unknown WebSocket opcode: ~a" (ws-frame-opcode frame)))))
                     (stream-error (c)
                       ;; Connection lost
                       (log-info "WebSocket connection lost: ~a" (connection-id conn))
                       (unregister-connection (connection-id conn)))
                     (error (c)
                       (log-error "Error processing WebSocket message: ~a" c)
                       (unregister-connection (connection-id conn))))))
               :name (format nil "ws-thread-~a" (connection-id conn)))
              ;; Return immediately - WebSocket handling is now in separate thread
              (return-from websocket-raw-dispatcher (lambda () nil))))))))
  ;; Not a WebSocket request - let other handlers process
  nil)

;; Add WebSocket dispatcher FIRST (before other dispatchers)
(push #'websocket-raw-dispatcher hunchentoot::*dispatch-table*)

;; Use a regex-based dispatcher for assets
(defun web-assets-handler ()
  "Serve web client assets"
  (let* ((uri (hunchentoot:request-uri hunchentoot:*request*))
         ;; Match /assets/xxx and extract xxx
         (match-start (search "/assets/" uri :test #'char=))
         (file-name (if match-start
                        (subseq uri (+ match-start 8))
                        "")))
    (declare (type string file-name))
    ;; Log for debugging
    (log-info "web-assets-handler: uri=~A, file-name=~A" uri file-name)
    ;; Security check - reject path traversal attempts
    (when (or (search ".." file-name) (find #\\ file-name))
      (setf (hunchentoot:return-code*) 400)
      (return-from web-assets-handler "Invalid file name"))
    (let* ((file-path (concatenate 'string *web-client-path* "assets\\" file-name)))
      (declare (type string file-path))
      (log-info "web-assets-handler: file-path=~A, exists=~A" file-path (cl-fad:file-exists-p file-path))
      (if (and *web-client-path*
               (cl-fad:file-exists-p file-path))
          (let ((content-type (cond
                                ((ends-with-p file-name ".css") "text/css")
                                ((ends-with-p file-name ".js") "application/javascript")
                                ((ends-with-p file-name ".map") "application/json")
                                (t "application/octet-stream"))))
            (setf (hunchentoot:content-type*) content-type)
            (alexandria:read-file-into-string file-path))
          (progn
            (log-error "web-assets-handler: File not found: ~A" file-path)
            (setf (hunchentoot:return-code*) 404)
            "Not found")))))

(defun emoji-assets-handler ()
  "Serve emoji GIF assets from web-client/public/emojis"
  (let* ((uri (hunchentoot:request-uri hunchentoot:*request*))
         ;; Match /emojis/xxx and extract xxx
         (match-start (search "/emojis/" uri :test #'char=))
         (file-name (if match-start
                        (subseq uri (+ match-start 8))
                        "")))
    (declare (type string file-name))
    ;; Log for debugging
    (log-info "emoji-assets-handler: uri=~A, file-name=~A" uri file-name)
    ;; Security check - reject path traversal attempts
    (when (or (search ".." file-name) (find #\\ file-name))
      (setf (hunchentoot:return-code*) 400)
      (return-from emoji-assets-handler "Invalid file name"))
    ;; Only allow .gif files
    (unless (ends-with-p file-name ".gif")
      (setf (hunchentoot:return-code*) 404)
      (return-from emoji-assets-handler "Not found"))
    (let* ((file-path (concatenate 'string "D:/Claude/LispIM/web-client/public/emojis/" file-name)))
      (declare (type string file-path))
      (log-info "emoji-assets-handler: file-path=~A, exists=~A" file-path (cl-fad:file-exists-p file-path))
      (if (cl-fad:file-exists-p file-path)
          (progn
            (setf (hunchentoot:content-type*) "image/gif")
            ;; Read as binary and write directly to socket
            (with-open-file (in file-path :direction :input :element-type '(unsigned-byte 8))
              (let ((data (make-array (file-length in) :element-type '(unsigned-byte 8))))
                (read-sequence data in)
                (setf (hunchentoot:content-length*) (length data))
                (setf (hunchentoot:return-code*) 200)
                ;; Send headers first, then write binary data
                (hunchentoot::send-headers)
                (write-sequence data hunchentoot::*hunchentoot-stream*)
                (finish-output hunchentoot::*hunchentoot-stream*)
                ;; Return nil to signal response already sent
                nil)))
          (progn
            (log-error "emoji-assets-handler: File not found: ~A" file-path)
            (setf (hunchentoot:return-code*) 404)
            "Not found")))))

;; OPTIONS handler for API preflight requests - handles ONLY OPTIONS requests
(defun api-options-handler ()
  "Handle OPTIONS preflight requests for API endpoints"
  (let ((method (hunchentoot:request-method hunchentoot:*request*)))
    (when (string= method "OPTIONS")
      (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
      (setf (hunchentoot:header-out "Access-Control-Allow-Methods") "GET, POST, PUT, DELETE, OPTIONS")
      (setf (hunchentoot:header-out "Access-Control-Allow-Headers") "Content-Type, Authorization")
      (setf (hunchentoot:header-out "Access-Control-Max-Age") "86400")
      (setf (hunchentoot:return-code*) 204)
      (return-from api-options-handler ""))
    ;; For non-OPTIONS requests, do nothing and return nil to continue processing
    nil))

;; Manifest and PWA files
(hunchentoot:define-easy-handler (web-manifest :uri "/manifest.webmanifest") ()
  "Serve PWA manifest"
  (or (serve-static-file "manifest.webmanifest")
      (progn
        (setf (hunchentoot:return-code*) 404)
        "Not found")))

(hunchentoot:define-easy-handler (web-sw :uri "/sw.js") ()
  "Serve service worker"
  (or (serve-static-file "sw.js")
      (progn
        (setf (hunchentoot:return-code*) 404)
        "Not found")))

(hunchentoot:define-easy-handler (web-register-sw :uri "/registerSW.js") ()
  "Serve register SW script"
  (or (serve-static-file "registerSW.js")
      (progn
        (setf (hunchentoot:return-code*) 404)
        "Not found")))

;;;; Static File Serving

;; PWA icons - use serve-static-file which handles binary files correctly
(hunchentoot:define-easy-handler (web-pwa-icon-192 :uri "/pwa-192x192.png") ()
  "Serve PWA icon 192x192"
  (let ((result (serve-static-file "pwa-192x192.png")))
    (if result
        result
        (progn
          (setf (hunchentoot:content-type*) "text/plain")
          (setf (hunchentoot:return-code*) 404)
          "Not found"))))

(hunchentoot:define-easy-handler (web-pwa-icon-512 :uri "/pwa-512x512.png") ()
  "Serve PWA icon 512x512"
  (let ((result (serve-static-file "pwa-512x512.png")))
    (if result
        result
        (progn
          (setf (hunchentoot:content-type*) "text/plain")
          (setf (hunchentoot:return-code*) 404)
          "Not found"))))

;; Handle explicit /index.html request
(hunchentoot:define-easy-handler (web-index-html :uri "/index.html") ()
  "Serve web client index.html"
  (or (serve-static-file "index.html")
      (progn
        (setf (hunchentoot:content-type*) "text/plain")
        (setf (hunchentoot:return-code*) 404)
        "Not found")))

;; Catch-all handler for static files at root level
(defun static-file-catchall ()
  "Serve any static file from web-client/dist"
  (let* ((uri (hunchentoot:request-uri hunchentoot:*request*))
         ;; Remove leading slash to get file name
         (file-name (if (and (> (length uri) 1) (char= (char uri 0) #\/))
                        (subseq uri 1)
                        uri)))
    (declare (type string file-name))
    ;; Security check - reject path traversal attempts
    (when (or (search ".." file-name) (find #\\ file-name))
      (setf (hunchentoot:return-code*) 400)
      (return-from static-file-catchall "Invalid file name"))
    (let ((result (serve-static-file file-name)))
      (if result
          result
          nil)))) ;; Return nil to let other handlers try

;; Add catch-all dispatcher for static files
(defun static-file-dispatcher (request)
  "Dispatch static file requests"
  (let ((uri (hunchentoot:request-uri request)))
    ;; Only handle paths that don't match other handlers
    (unless (or (string= uri "/")
                (string= uri "/index.html")
                (string= uri "/manifest.webmanifest")
                (string= uri "/sw.js")
                (string= uri "/registerSW.js")
                (string= uri "/pwa-192x192.png")
                (string= uri "/pwa-512x512.png")
                (search "/api/" uri)
                (search "/healthz" uri)
                (search "/readyz" uri)
                (search "/metrics" uri)
                (search "/assets/" uri))
      (static-file-catchall))))

(push #'static-file-dispatcher hunchentoot::*dispatch-table*)

;; Health check endpoint
(hunchentoot:define-easy-handler (healthz :uri "/healthz") ()
  (setf (hunchentoot:content-type*) "text/plain")
  "OK")

;; Ready check endpoint
(hunchentoot:define-easy-handler (readyz :uri "/readyz") ()
  (setf (hunchentoot:content-type*) "text/plain")
  (if *server-running* "READY" "NOT_READY"))

;; Metrics endpoint
(hunchentoot:define-easy-handler (metrics :uri "/metrics") ()
  (setf (hunchentoot:content-type*) "text/plain")
  (get-metrics))

;;;; WebSocket Handler

;; Helper function to create WebSocket text frame
(defun make-websocket-text-frame (text)
  "Create a WebSocket text frame from a string"
  (declare (type string text))
  (let* ((text-bytes (flexi-streams:string-to-octets text))
         (payload-length (length text-bytes))
         (frame (make-array (if (< payload-length 126)
                                (+ 2 payload-length)
                                (+ 4 payload-length))
                            :element-type '(unsigned-byte 8))))
    ;; Set FIN bit (1) and opcode for text frame (1) = #x81
    (setf (aref frame 0) #x81)
    ;; Set payload length (server doesn't mask)
    (cond
      ((< payload-length 126)
       (setf (aref frame 1) payload-length))
      ((< payload-length 65536)
       (setf (aref frame 1) 126)
       (setf (aref frame 2) (ldb (byte 8 8) payload-length))
       (setf (aref frame 3) (ldb (byte 8 0) payload-length)))
      (t
       (setf (aref frame 1) 127)
       ;; 64-bit length in network byte order (simplified for small cases)
       (setf (aref frame 2) 0) (setf (aref frame 3) 0)
       (setf (aref frame 4) 0) (setf (aref frame 5) 0)
       (setf (aref frame 6) (ldb (byte 8 24) payload-length))
       (setf (aref frame 7) (ldb (byte 8 16) payload-length))
       (setf (aref frame 8) (ldb (byte 8 8) payload-length))
       (setf (aref frame 9) (ldb (byte 8 0) payload-length))))
    ;; Copy payload
    (replace frame text-bytes :start1 (if (< payload-length 126) 2 (if (< payload-length 65536) 4 10)))
    frame))

;; WebSocket upgrade handler - handles the HTTP upgrade handshake
(defun handle-websocket-upgrade (request)
  "Handle WebSocket upgrade request"
  (let* ((key (hunchentoot:header-in "Sec-WebSocket-Key" request))
         (version (hunchentoot:header-in "Sec-WebSocket-Version" request)))
    (unless (and key version)
      (setf (hunchentoot:return-code*) 400)
      (return-from handle-websocket-upgrade nil))
    (unless (string= version "13")
      (setf (hunchentoot:return-code*) 426)
      (return-from handle-websocket-upgrade nil))
    ;; Calculate Sec-WebSocket-Accept
    (let* ((magic "258EAFA5-E914-47DA-95CA-C5AB0DC85B11")
           (key+magic (concatenate 'string key magic))
           (octets (flexi-streams:string-to-octets key+magic))
           (digest (ironclad:digest-sequence :sha1 octets :start 0 :end (length octets)))
           (accept (cl-base64:usb8-array-to-base64-string digest)))
      ;; Send upgrade response manually to avoid chunked encoding
      (let ((stream hunchentoot::*hunchentoot-stream*))
        ;; Write raw HTTP 101 response with proper CRLF
        (write-byte #.(char-code #\Return) stream)
        (write-byte #.(char-code #\Linefeed) stream)
        (write-sequence (flexi-streams:string-to-octets "HTTP/1.1 101 Switching Protocols") stream)
        (write-byte #.(char-code #\Return) stream)
        (write-byte #.(char-code #\Linefeed) stream)
        (write-sequence (flexi-streams:string-to-octets "Upgrade: websocket") stream)
        (write-byte #.(char-code #\Return) stream)
        (write-byte #.(char-code #\Linefeed) stream)
        (write-sequence (flexi-streams:string-to-octets "Connection: Upgrade") stream)
        (write-byte #.(char-code #\Return) stream)
        (write-byte #.(char-code #\Linefeed) stream)
        (write-sequence (flexi-streams:string-to-octets (format nil "Sec-WebSocket-Accept: ~a" accept)) stream)
        (write-byte #.(char-code #\Return) stream)
        (write-byte #.(char-code #\Linefeed) stream)
        ;; Empty line to end headers
        (write-byte #.(char-code #\Return) stream)
        (write-byte #.(char-code #\Linefeed) stream)
        (finish-output stream)
        ;; Return the stream for further use
        stream))))

;; WebSocket connection handler
(defun handle-websocket-connection (stream)
  "Handle WebSocket connection after upgrade - minimal implementation"
  (declare (type stream stream))
  (when stream
    ;; Send a WebSocket text frame with pong message
    (let* ((pong-message "{\"type\":\"pong\",\"payload\":{\"status\":\"connected\"}}")
           (frame (make-websocket-text-frame pong-message)))
      (write-sequence frame stream)
      (finish-output stream))
    ;; Don't close the stream - let Hunchentoot handle it after the lambda returns
    ))

;; Auth API v1 - Login - using regex dispatcher for testing
(defun api-login-v1-handler ()
  "Handle login requests"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:header-out "Access-Control-Allow-Methods") "GET, POST, PUT, DELETE, OPTIONS")
  (setf (hunchentoot:header-out "Access-Control-Allow-Headers") "Content-Type, Authorization")
  ;; Log request info for debugging
  (log-info "=== LOGIN REQUEST START ===")
  (log-info "Request method: ~A" (hunchentoot:request-method hunchentoot:*request*))
  (log-info "Request URI: ~A" (hunchentoot:request-uri hunchentoot:*request*))
  (log-info "Remote addr: ~A" (hunchentoot:remote-addr hunchentoot:*request*))
  ;; Handle OPTIONS preflight request
  (when (string= (hunchentoot:request-method hunchentoot:*request*) "OPTIONS")
    (log-info "OPTIONS preflight request, returning 204")
    (setf (hunchentoot:return-code*) 204)
    (return-from api-login-v1-handler ""))
  (setf (hunchentoot:content-type*) "application/json")
  (handler-case
      (progn
        (unless (string= (hunchentoot:request-method hunchentoot:*request*) "POST")
          (log-info "Not a POST request, returning 405")
          (setf (hunchentoot:return-code*) 405)
          (return-from api-login-v1-handler (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed"))))
        (let* ((json-str (get-request-body-string)))
          (log-info "Request body length: ~A" (length json-str))
          (log-info "Request body: ~A" json-str)
          (when (> (length json-str) 0)
            (log-info "JSON first 100 chars: ~A" (subseq json-str 0 (min 100 (length json-str)))))
          (let ((data (cl-json:decode-json-from-string json-str)))
            (log-info "JSON decoded: ~A" data)
            (log-info "JSON keys: ~A" (mapcar #'car data))
            (let* ((raw-username (cdr (assoc :username data)))
                  (raw-password (cdr (assoc :password data)))
                  (username (string-trim " " raw-username))
                  (password (string-trim " " raw-password)))
              (log-info "Username field (trimmed): ~A (type: ~A)" username (type-of username))
              (log-info "Password field present: ~A" (if password t nil))
              (unless (and username password)
                (log-info "Missing username or password")
                (setf (hunchentoot:return-code*) 400)
                (return-from api-login-v1-handler (encode-api-response (make-api-error "MISSING_FIELDS" "Missing username or password"))))
              (log-info "Calling authenticate for: ~A" username)
              (let ((result (authenticate username password :ip-address (hunchentoot:remote-addr hunchentoot:*request*))))
                (log-info "Authenticate result - success: ~A, user-id: ~A, error: ~A"
                          (auth-result-success result) (auth-result-user-id result) (auth-result-error result))
                (if (auth-result-success result)
                    (progn
                      (log-info "Login successful for: ~A" username)
                      (return-from api-login-v1-handler (encode-api-response (make-api-response (list :userId (auth-result-user-id result) :username (auth-result-username result) :token (auth-result-token result))))))
                  (progn
                    (log-info "Login failed for: ~A, error: ~A" username (auth-result-error result))
                    (setf (hunchentoot:return-code*) 401)
                    (return-from api-login-v1-handler (encode-api-response (make-api-error "AUTH_FAILED" (auth-result-error result)))))))))))
    (auth-error (c)
      (log-error "Auth error: ~A" (format nil "~A" c))
      (setf (hunchentoot:return-code*) 401)
      (return-from api-login-v1-handler (encode-api-response (make-api-error "AUTH_ERROR" (format nil "~A" c)))))
    (simple-error (c)
      (log-error "Simple error: ~A" (format nil "~A" c))
      (let ((error-str (format nil "Error: ~a" (format nil "~A" c))))
        (setf (hunchentoot:return-code*) 500)
        (return-from api-login-v1-handler (encode-api-response (make-api-error "INTERNAL_ERROR" error-str)))))
    (error (c)
      ;; Generic error handler that works for any error type including cl-postgres-error
      (let ((error-str (format nil "~A" c)))
        (log-error "API error: ~A" error-str)
        (setf (hunchentoot:return-code*) 500)
        (return-from api-login-v1-handler (encode-api-response (make-api-error "INTERNAL_ERROR" error-str)))))))

(log-info "=== LOGIN REQUEST END ===")

;; GET /api/v1/users/me - Get current user info
(defun api-current-user-handler ()
  "Get current authenticated user info"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (handler-case
      (let ((user-id (require-auth)))
        (unless user-id
          (setf (hunchentoot:return-code*) 401)
          (return-from api-current-user-handler
            (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
        (let ((user (get-user user-id)))
          (if user
              (encode-api-response
               (make-api-response
                (list :id (getf user :id)
                      :username (getf user :username)
                      :displayName (getf user :display-name)
                      :email (getf user :email)
                      :avatar (or (getf user :avatar-url) ""))))
              (progn
                (setf (hunchentoot:return-code*) 404)
                (encode-api-response (make-api-error "NOT_FOUND" "User not found"))))))
    (error (c)
      (log-error "Get current user error: ~A" c)
      (setf (hunchentoot:return-code*) 500)
      (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c))))))

;; User Info API

;; User API v1 - Get User Info
(defun api-user-info-handler ()
  "Get user info by ID"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (handler-case
      (progn
        (let* ((uri (hunchentoot:request-uri hunchentoot:*request*))
               (user-id (multiple-value-bind (match-start match-end reg-start reg-end)
                          (cl-ppcre:scan "^/api/v1/users/([^/]+)$" uri)
                          (if match-start
                              (subseq uri (aref reg-start 0) (aref reg-end 0))
                              (return-from api-user-info-handler
                                (progn
                                  (setf (hunchentoot:return-code*) 400)
                                  (encode-api-response (make-api-error "INVALID_URI" "Invalid user URI"))))))))
          (log-info "Getting user info for: ~A" user-id)
          (let ((user (get-user user-id)))
            (if user
                (encode-api-response
                 (make-api-response
                  (list :id (getf user :id)
                        :username (getf user :username)
                        :displayName (getf user :display-name)
                        :email (getf user :email)
                        :avatar (or (getf user :avatar-url) ""))))
                (progn
                  (setf (hunchentoot:return-code*) 404)
                  (encode-api-response (make-api-error "NOT_FOUND" "User not found")))))))
    (error (c)
      (log-error "Get user error: ~A" c)
      (setf (hunchentoot:return-code*) 500)
      (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c))))))

;; PUT /api/v1/users/profile - Update user profile
(defun api-update-profile-handler ()
  "Update current user's profile"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (handler-case
      (progn
        (unless (string= (hunchentoot:request-method hunchentoot:*request*) "PUT")
          (setf (hunchentoot:return-code*) 405)
          (return-from api-update-profile-handler
            (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed"))))
        (let ((user-id (require-auth)))
          (unless user-id
            (setf (hunchentoot:return-code*) 401)
            (return-from api-update-profile-handler
              (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
          (let* ((json-str (get-request-body-string))
                 (data (cl-json:decode-json-from-string json-str))
                 (display-name (cdr (assoc :display-name data)))
                 (avatar (cdr (assoc :avatar data))))
            (multiple-value-bind (success updated-user error)
                (update-user user-id
                             :display-name display-name
                             :avatar-url avatar)
              (if success
                  (encode-api-response
                   (make-api-response
                    (list :id (getf updated-user :id)
                          :username (getf updated-user :username)
                          :displayName (getf updated-user :display-name)
                          :email (getf updated-user :email)
                          :avatar (or (getf updated-user :avatar-url) ""))))
                  (progn
                    (setf (hunchentoot:return-code*) 400)
                    (encode-api-response (make-api-error "UPDATE_FAILED" error))))))))
    (error (c)
      (log-error "Update profile error: ~A" c)
      (setf (hunchentoot:return-code*) 500)
      (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c))))))

;; POST /api/v1/chat/conversations/create - Create conversation
(defun api-create-conversation-handler ()
  "Create or get existing direct conversation with a user"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (handler-case
      (progn
        (unless (string= (hunchentoot:request-method hunchentoot:*request*) "POST")
          (setf (hunchentoot:return-code*) 405)
          (return-from api-create-conversation-handler
            (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed"))))
        (let ((current-user-id (require-auth)))
          (unless current-user-id
            (setf (hunchentoot:return-code*) 401)
            (return-from api-create-conversation-handler
              (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
          (let* ((json-str (get-request-body-string))
                 (data (cl-json:decode-json-from-string json-str))
                 (participant-id (cdr (assoc :participant-id data))))
            (unless participant-id
              (setf (hunchentoot:return-code*) 400)
              (return-from api-create-conversation-handler
                (encode-api-response (make-api-error "MISSING_FIELDS" "participantId is required"))))
            ;; Convert string ID to integer
            (let ((participant-int (parse-integer participant-id :junk-allowed t)))
              (let ((conv-id (get-or-create-direct-conversation (parse-integer current-user-id :junk-allowed t)
                                                                participant-int)))
                (let ((conv (get-conversation conv-id)))
                  (if conv
                      (encode-api-response
                       (make-api-response
                        (list :id (getf conv :id)
                              :type (getf conv :type)
                              :name (getf conv :name)
                              :avatar (getf conv :avatar-url)
                              :participants (list current-user-id participant-id)
                              :createdAt (storage-universal-to-unix-ms (getf conv :created-at))
                              :updatedAt (storage-universal-to-unix-ms (getf conv :updated-at)))))
                      (progn
                        (setf (hunchentoot:return-code*) 404)
                        (encode-api-response (make-api-error "NOT_FOUND" "Conversation not found"))))))))))
    (error (c)
      (log-error "Create conversation error: ~A" c)
      (setf (hunchentoot:return-code*) 500)
      (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c))))))

;; Chat API v1 - Get Conversations
(defun api-get-conversations-handler ()
  "Get conversations list"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (handler-case
      (progn
        (log-info "Getting conversations")
        ;; Get user ID from token using require-auth
        (let ((user-id (require-auth)))
          (log-info "User-id from require-auth: ~A" user-id)
          (if user-id
              (progn
                ;; Ensure system admin conversation exists for this user
                (let ((user-id-int (handler-case (parse-integer user-id :junk-allowed t)
                                   (error (c)
                                     (log-error "Failed to parse user-id '~A': ~A" user-id c)
                                     0))))
                  (when (and user-id-int (> user-id-int 0))
                    (get-or-create-system-admin-conversation user-id-int)))
                (log-info "Calling get-conversations with user-id: ~A" user-id)
                (let ((conversations (get-conversations user-id)))
                  (encode-api-response
                   (make-api-response
                    (mapcar (lambda (conv)
                              (let* ((conv-id (getf conv :id))
                                     (conv-type (getf conv :type))
                                     (conv-name (getf conv :name))
                                     ;; For direct conversations, get the other user's display name
                                     (display-name (if (and (string= conv-type "direct")
                                                            (or (null conv-name) (string= conv-name "") (string= conv-name "false")))
                                                       ;; Query the other participant's display name
                                                       (let* ((other-user (postmodern:query
                                                                           "SELECT u.display_name, u.username FROM users u
                                                                            JOIN conversation_participants cp ON u.id = cp.user_id
                                                                            WHERE cp.conversation_id = $1 AND cp.user_id != $2
                                                                            LIMIT 1"
                                                                           conv-id user-id))
                                                              (row (when other-user (car other-user))))
                                                         (if row
                                                             (or (elt row 0) (elt row 1) "Unknown")
                                                             "Unknown"))
                                                       conv-name)))
                                (list :id conv-id
                                      :name (or display-name "")
                                      :type conv-type
                                      :lastMessage ""
                                      :unreadCount 0)))
                            conversations)))))
              (progn
                (setf (hunchentoot:return-code*) 401)
                (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))))
    (error (c)
      (log-error "Get conversations error: ~A~%Backtrace:~%" c)
      (setf (hunchentoot:return-code*) 500)
      (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "Error: ~A" c))))))

;; Chat API v1 - Get Message History
(defun api-get-history-handler ()
  "Get message history for conversation"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (handler-case
      (progn
        (let* ((uri (hunchentoot:request-uri hunchentoot:*request*))
               (conversation-id (multiple-value-bind (match-start match-end reg-start reg-end)
                                  (cl-ppcre:scan "^/api/v1/chat/conversations/([^/]+)/messages$" uri)
                                  (if match-start
                                      (subseq uri (aref reg-start 0) (aref reg-end 0))
                                      (return-from api-get-history-handler
                                        (progn
                                          (setf (hunchentoot:return-code*) 400)
                                          (encode-api-response (make-api-error "INVALID_URI" "Invalid conversation URI"))))))))
          (log-info "Getting history for conversation: ~A" conversation-id)
          (multiple-value-bind (success messages has-more)
              (get-messages "1" conversation-id :limit 50)
            (declare (ignore has-more))
            (if success
                (encode-api-response
                 (make-api-response
                  (mapcar (lambda (msg)
                            (list :id (elt msg 0)
                                  :conversationId (elt msg 1)
                                  :senderId (elt msg 2)
                                  :content (or (elt msg 3) "")
                                  :type (elt msg 4)
                                  :createdAt (elt msg 5)))
                          messages)))
                (progn
                  (setf (hunchentoot:return-code*) 404)
                  (encode-api-response (make-api-error "NOT_FOUND" "No messages")))))))
    (error (c)
      (log-error "Get history error: ~A" c)
      (setf (hunchentoot:return-code*) 500)
      (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c))))))

;; Chat API v1 - Send Message
(defun api-send-message-handler ()
  "Send message to conversation"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (handler-case
      (progn
        (unless (string= (hunchentoot:request-method hunchentoot:*request*) "POST")
          (setf (hunchentoot:return-code*) 405)
          (return-from api-send-message-handler
            (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed"))))
        (let* ((uri (hunchentoot:request-uri hunchentoot:*request*))
               (conversation-id (multiple-value-bind (match-start match-end reg-start reg-end)
                                  (cl-ppcre:scan "^/api/v1/chat/conversations/([^/]+)/messages$" uri)
                                  (if match-start
                                      (subseq uri (aref reg-start 0) (aref reg-end 0))
                                      (return-from api-send-message-handler
                                        (progn
                                          (setf (hunchentoot:return-code*) 400)
                                          (encode-api-response (make-api-error "INVALID_URI" "Invalid conversation URI")))))))
               (json-str (get-request-body-string))
               (data (cl-json:decode-json-from-string json-str))
               (content (cdr (assoc :content data)))
               (message-type (or (cdr (assoc :type data)) (cdr (assoc :message-type data)) "text")))
          (log-info "Sending message to conversation: ~A" conversation-id)
          (unless content
            (setf (hunchentoot:return-code*) 400)
            (return-from api-send-message-handler
              (encode-api-response (make-api-error "MISSING_FIELDS" "Missing content"))))
          ;; Get user ID from token
          (let* ((token (hunchentoot:header-in "Authorization"))
                 (user-id (when token
                            (let* ((clean-token (if (search "Bearer " token)
                                                    (subseq token 7)
                                                    token))
                                   (session (get-session-by-token clean-token)))
                              (when session (session-user-id session))))))
            (log-info "DEBUG: token=~a user-id=~a" token user-id)
            (if user-id
                (progn
                  ;; Bind *current-user-id* for send-message function
                  (let ((*current-user-id* user-id))
                    (log-info "Creating message: conv=~a, user=~a, content=~a, type=~a" conversation-id user-id content message-type)
                    ;; Use proper send-message function from chat.lisp (handles sequence counters correctly)
                    (let ((msg (send-message conversation-id content :type (intern (string-upcase message-type) :keyword))))
                      (log-info "DEBUG: send-message returned=~a" msg)
                      (if msg
                          (progn
                            (log-info "Message sent: ~a" (message-id msg))
                            (encode-api-response
                             (make-api-response
                              (list :id (princ-to-string (message-id msg))
                                    :conversationId (princ-to-string (message-conversation-id msg))
                                    :senderId (message-sender-id msg)
                                    :content (message-content msg)
                                    :type (string-downcase (message-message-type msg))
                                    :createdAt (lispim-universal-to-unix-ms (message-created-at msg))))))
                          (progn
                            (log-error "Failed to send message")
                            (setf (hunchentoot:return-code*) 500)
                            (encode-api-response (make-api-error "MESSAGE_SEND_FAILED" "Failed to send message")))))))
                (progn
                  (setf (hunchentoot:return-code*) 401)
                  (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required")))))))
    (error (c)
      (log-error "Send message error: ~A" c)
      (setf (hunchentoot:return-code*) 500)
      (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c))))))

;; Auth API v1 - Register
(hunchentoot:define-easy-handler (api-register-v1 :uri "/api/v1/auth/register") ()
  (setf *current-handler* 'api-register-v1)
  (if (not (string= (hunchentoot:request-method hunchentoot:*request*) "POST"))
      (progn
        (setf (hunchentoot:return-code*) 405)
        (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed")))
      (progn
        (with-open-file (log-stream "D:/Claude/LispIM/lispim-core/register_debug.log"
                                    :direction :output
                                    :if-exists :append
                                    :if-does-not-exist :create)
          (format log-stream "~&~A: Received POST request~%" (get-universal-time))
          (finish-output log-stream))
        (setf (hunchentoot:content-type*) "application/json")
        (let* ((json-str (get-request-body-string))
               (data (cl-json:decode-json-from-string json-str))
               (method (cdr (assoc :method data)))
               (username (cdr (assoc :username data)))
               (password (cdr (assoc :password data)))
               (phone (cdr (assoc :phone data)))
               (phone-code (cdr (assoc :phone-code data)))
               (email (cdr (assoc :email data)))
               (email-code (cdr (assoc :email-code data)))
               (invitation-code (cdr (assoc :invitation-code data)))
               (display-name (cdr (assoc :display-name data))))
          (declare (ignore invitation-code))
          (cond
            ((string= method "username")
             (if (not (and username password email))
                 (progn
                   (setf (hunchentoot:return-code*) 400)
                   (encode-api-response (make-api-error "MISSING_FIELDS" "Missing required fields")))
                 (multiple-value-bind (user-id error)
                     (register-user username password email
                                    :phone phone
                                    :display-name display-name)
                   (if user-id
                       (encode-api-response (make-api-response (list :userId user-id)))
                       (progn
                         (setf (hunchentoot:return-code*) 400)
                         (encode-api-response (make-api-error "REGISTER_FAILED" error)))))))
            ((string= method "phone")
             (if (not (and phone phone-code password))
                 (progn
                   (setf (hunchentoot:return-code*) 400)
                   (encode-api-response (make-api-error "MISSING_FIELDS" "Missing phone or code")))
                 (multiple-value-bind (success user-id token error)
                     (register-by-phone phone password phone-code :display-name display-name)
                   (if success
                       (encode-api-response (make-api-response (list :userId user-id :token token)))
                       (progn
                         (setf (hunchentoot:return-code*) 400)
                         (encode-api-response (make-api-error "PHONE_REGISTER_FAILED" error)))))))
            ((string= method "email")
             (if (not (and email email-code password))
                 (progn
                   (setf (hunchentoot:return-code*) 400)
                   (encode-api-response (make-api-error "MISSING_FIELDS" "Missing email or code")))
                 (multiple-value-bind (success user-id token error)
                     (register-by-email email password email-code :display-name display-name)
                   (if success
                       (encode-api-response (make-api-response (list :userId user-id :token token)))
                       (progn
                         (setf (hunchentoot:return-code*) 400)
                         (encode-api-response (make-api-error "EMAIL_REGISTER_FAILED" error)))))))
            (t (encode-api-response (make-api-error "INVALID_METHOD" "Invalid registration method"))))))))

;; Auth API v1 - Send Code
(hunchentoot:define-easy-handler (api-send-code-v1 :uri "/api/v1/auth/send-code") ()
  (setf *current-handler* 'api-send-code-v1)
  (if (not (string= (hunchentoot:request-method hunchentoot:*request*) "POST"))
      (progn
        (setf (hunchentoot:return-code*) 405)
        (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed")))
      (progn
        (setf (hunchentoot:content-type*) "application/json")
        (let* ((json-str (get-request-body-string))
               (data (cl-json:decode-json-from-string json-str))
               ;; Support both 'type'/'target' and 'method'/'value' formats
               (type (or (cdr (assoc :type data)) (cdr (assoc :method data))))
               (target (or (cdr (assoc :target data)) (cdr (assoc :value data)))))
          (cond
            ((string= type "phone")
             (multiple-value-bind (success error) (send-phone-code target)
               (if success
                   (encode-api-response (make-api-response nil :message "Code sent"))
                   (progn
                     (setf (hunchentoot:return-code*) 400)
                     (encode-api-response (make-api-error "SEND_CODE_FAILED" error))))))
            ((string= type "email")
             (multiple-value-bind (success error) (send-email-code target)
               (if success
                   (encode-api-response (make-api-response nil :message "Code sent"))
                   (progn
                     (setf (hunchentoot:return-code*) 400)
                     (encode-api-response (make-api-error "SEND_CODE_FAILED" error))))))
            (t (encode-api-response (make-api-error "INVALID_TYPE" "Invalid type"))))))))

;; Auth API v1 - WeChat login
(hunchentoot:define-easy-handler (api-wechat-v1 :uri "/api/v1/auth/wechat") ()
  (setf *current-handler* 'api-wechat-v1)
  (if (not (string= (hunchentoot:request-method hunchentoot:*request*) "POST"))
      (progn
        (setf (hunchentoot:return-code*) 405)
        (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed")))
      (progn
        (setf (hunchentoot:content-type*) "application/json")
        (let* ((json-str (get-request-body-string))
               (data (cl-json:decode-json-from-string json-str))
               (code (cdr (assoc :code data))))
          (multiple-value-bind (success user-id token error)
              (login-by-wechat code)
            (if success
                (encode-api-response (make-api-response (list :userId user-id :token token)))
                (progn
                  (setf (hunchentoot:return-code*) 401)
                  (encode-api-response (make-api-error "WECHAT_LOGIN_FAILED" error)))))))))

;; Auth API v1 - Logout
(hunchentoot:define-easy-handler (api-logout-v1 :uri "/api/v1/auth/logout") ()
  (setf *current-handler* 'api-logout-v1)
  (let ((token (hunchentoot:header-in "Authorization" hunchentoot:*request*)))
    (when (and token (string= (hunchentoot:request-method hunchentoot:*request*) "POST"))
      (invalidate-token (remove-prefix token "Bearer "))))
  (setf (hunchentoot:content-type*) "application/json")
  "{\"success\":true,\"message\":\"Logged out\"}")

;; Chat API v1 - Conversations
(hunchentoot:define-easy-handler (api-conversations-v1 :uri "/api/v1/chat/conversations") ()
  (setf *current-handler* 'api-conversations-v1)
  (setf (hunchentoot:content-type*) "application/json")
  (let ((user-id (require-auth)))
    (log-info "Conversations API: user-id=~A" user-id)
    (unless user-id
      (log-info "Conversations API: unauthorized")
      (return-from api-conversations-v1 (encode-api-response (make-api-error "UNAUTHORIZED" "Unauthorized"))))
    (let ((type (hunchentoot:get-parameter "type"))
          (page (parse-integer (or (hunchentoot:get-parameter "page") "1") :junk-allowed t))
          (page-size (parse-integer (or (hunchentoot:get-parameter "page_size") "20") :junk-allowed t)))
      (log-info "Conversations API: calling get-conversations with user-id=~A type=~A page=~A" user-id type page)
      (handler-case
          (let ((conversations (get-conversations user-id :type type :page page :page-size page-size)))
            (log-info "Conversations API: got ~A conversations" (length conversations))
            (encode-api-response (make-api-response (list :conversations conversations :total (length conversations)))))
        (error (c)
          (log-error "Conversations API error: ~A" c)
          (setf (hunchentoot:return-code*) 500)
          (encode-api-response (make-api-error "SERVER_ERROR" (format nil "Error: ~A" c))))))))

;; Chat API v1 - Conversation Messages
(defun api-conversation-messages-v1 ()
  "Handle conversation messages API"
  (setf *current-handler* 'api-conversation-messages-v1)
  (setf (hunchentoot:content-type*) "application/json")
  (let* ((uri (hunchentoot:request-uri hunchentoot:*request*))
         (conversation-id-str (multiple-value-bind (match-start match-end reg-start reg-end)
                                  (cl-ppcre:scan "^/api/v1/chat/conversations/([^/]+)/messages" uri)
                                (if match-start
                                    (subseq uri (aref reg-start 0) (aref reg-end 0))
                                    (return-from api-conversation-messages-v1
                                      (progn
                                        (setf (hunchentoot:return-code*) 400)
                                        (encode-api-response (make-api-error "INVALID_URI" "Invalid conversation URI")))))))
         (conversation-id (parse-integer conversation-id-str))
         (user-id (require-auth)))
    (unless user-id
      (return-from api-conversation-messages-v1 (encode-api-response (make-api-error "UNAUTHORIZED" "Unauthorized"))))
    (let ((method (hunchentoot:request-method hunchentoot:*request*)))
      (cond
        ((string= method "GET")
         (let ((before (hunchentoot:get-parameter "before"))
               (limit (parse-integer (or (hunchentoot:get-parameter "limit") "20") :junk-allowed t)))
           (multiple-value-bind (success messages has-more)
               (get-messages user-id conversation-id :before before :limit limit)
             (if success
                 (encode-api-response (make-api-response (list :messages messages :has-more has-more)))
                 (progn
                   (setf (hunchentoot:return-code*) 404)
                   (encode-api-response (make-api-error "NOT_FOUND" "Conversation not found")))))))
        ((string= method "POST")
         (let* ((json-str (get-request-body-string))
                (data (cl-json:decode-json-from-string json-str))
                (type-str (cdr (assoc :type data)))
                (type (if type-str (intern (string-upcase type-str) 'keyword) :text))
                (content (cdr (assoc :content data))))
           (log-info "POST /api/v1/chat/conversations/~A/messages: user-id='~A'" conversation-id user-id)
           (let ((*current-user-id* user-id))
             (let ((message (send-message conversation-id content :type type)))
               (if message
                   (encode-api-response
                    (make-api-response
                     (list :id (princ-to-string (message-id message))
                           :sequence (message-sequence message)
                           :conversation-id (princ-to-string (message-conversation-id message))
                           :sender-id (message-sender-id message)
                           :type (string-downcase (message-message-type message))
                           :content (message-content message)
                           :createdAt (lispim-universal-to-unix-ms (message-created-at message)))
                     :message "Message sent"))
                   (progn
                     (setf (hunchentoot:return-code*) 400)
                     (encode-api-response (make-api-error "SEND_FAILED" "Failed to send message"))))))))
        (t (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed")))))))

;; Chat API v1 - Mark Read
(hunchentoot:define-easy-handler (api-mark-read-v1 :uri "/api/v1/chat/conversations/:id/read") ()
  (setf *current-handler* 'api-mark-read-v1)
  (unless (string= (hunchentoot:request-method hunchentoot:*request*) "POST")
    (setf (hunchentoot:return-code*) 405)
    (return-from api-mark-read-v1 (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed"))))
  (setf (hunchentoot:content-type*) "application/json")
  (let ((conversation-id (hunchentoot:get-parameter "id"))
        (user-id (require-auth)))
    (unless user-id
      (return-from api-mark-read-v1 (encode-api-response (make-api-error "UNAUTHORIZED" "Unauthorized"))))
    (mark-as-read user-id conversation-id)
    (encode-api-response (make-api-response nil :message "Marked as read"))))

;; Chat API v1 - Recall Message
(hunchentoot:define-easy-handler (api-recall-message-v1 :uri "/api/v1/chat/messages/:id/recall") ()
  (setf *current-handler* 'api-recall-message-v1)
  (if (not (string= (hunchentoot:request-method hunchentoot:*request*) "POST"))
      (progn
        (setf (hunchentoot:return-code*) 405)
        (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed")))
      (progn
        (let ((token (hunchentoot:header-in :authorization hunchentoot:*request*))
              (message-id (hunchentoot:get-parameter "id")))
          (if (not token)
              (progn
                (setf (hunchentoot:return-code*) 401)
                (encode-api-response (make-api-error "UNAUTHORIZED" "Unauthorized")))
              (progn
                (let ((user-id (verify-token (remove-prefix token "Bearer "))))
                  (if (not user-id)
                      (progn
                        (setf (hunchentoot:return-code*) 401)
                        (encode-api-response (make-api-error "UNAUTHORIZED" "Unauthorized")))
                      (progn
                        (handler-case
                          (progn
                            (let ((*current-user-id* user-id))
                              (recall-message message-id))
                            (encode-api-response (make-api-response nil :message "Message recalled")))
                        (message-not-found (c)
                          (setf (hunchentoot:return-code*) 404)
                          (encode-api-response (make-api-error "NOT_FOUND" (format nil "~A" c))))
                        (auth-error (c)
                          (setf (hunchentoot:return-code*) 403)
                          (encode-api-response (make-api-error "ACCESS_DENIED" (format nil "~A" c))))
                        (message-recall-timeout (c)
                          (setf (hunchentoot:return-code*) 400)
                          (encode-api-response (make-api-error "RECALL_TIMEOUT" (format nil "~A" c))))))))))))))

(defun stop-gateway ()
  "Stop HTTP gateway"
  (log-info "Stopping gateway...")

  ;; Stop heartbeat monitor
  (stop-heartbeat-monitor)

  ;; Close all connections
  (bordeaux-threads:with-lock-held (*connections-lock*)
    (maphash (lambda (id conn)
               (declare (ignore id))
               (setf (connection-state conn) :closed))
             *connections*)
    (clrhash *connections*)
    (setf *connections-active-gauge* 0))

  ;; Stop Hunchentoot
  (when *acceptor*
    (hunchentoot:stop *acceptor*))

  (log-info "Gateway stopped"))

;;;; Friend Management APIs

;; GET /api/v1/friends - List friends
(defun api-get-friends-handler ()
  "Get user's friends list"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (handler-case
      (let ((user-id (require-auth)))
        (unless user-id
          (setf (hunchentoot:return-code*) 401)
          (return-from api-get-friends-handler
            (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
        (let ((friends (get-friends user-id)))
          (encode-api-response
           (make-api-response friends))))
    (error (c)
      (log-error "Get friends error: ~A" c)
      (setf (hunchentoot:return-code*) 500)
      (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c))))))

;; POST /api/v1/friends/add - Send friend request
(defun api-add-friend-handler ()
  "Send a friend request"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (unless (string= (hunchentoot:request-method hunchentoot:*request*) "POST")
    (setf (hunchentoot:return-code*) 405)
    (return-from api-add-friend-handler
      (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed"))))
  (let ((user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-add-friend-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (let* ((json-str (get-request-body-string))
           (data (cl-json:decode-json-from-string json-str))
           (friend-id (cdr (assoc :friend-id data)))
           (message (cdr (assoc :message data))))
      (unless friend-id
        (setf (hunchentoot:return-code*) 400)
        (return-from api-add-friend-handler
          (encode-api-response (make-api-error "MISSING_FIELDS" "friendId is required"))))
      (multiple-value-bind (success request-id err-msg)
          (add-friend-request user-id friend-id message)
        (if success
            (progn
              (log-info "Friend request created with id: ~A" request-id)
              (setf (hunchentoot:return-code*) 200)
              (setf (hunchentoot:content-type*) "application/json")
              (return-from api-add-friend-handler
                (cl-json:encode-json-to-string `(:success t :data (:requestid ,request-id)))))
            (progn
              (log-error "Failed to create friend request: ~A" err-msg)
              (setf (hunchentoot:return-code*) 400)
              (encode-api-response (make-api-error "SEND_FAILED" err-msg))))))))

;; GET /api/v1/friends/requests - Get friend requests
(defun api-get-friend-requests-handler ()
  "Get pending friend requests"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (let ((user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-get-friend-requests-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (let ((requests (get-friend-requests (princ-to-string user-id))))
      (encode-api-response
       (make-api-response requests)))))

;; POST /api/v1/friends/accept - Accept friend request
(defun api-accept-friend-handler ()
  "Accept a friend request"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (unless (string= (hunchentoot:request-method hunchentoot:*request*) "POST")
    (setf (hunchentoot:return-code*) 405)
    (return-from api-accept-friend-handler
      (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed"))))
  (let ((user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-accept-friend-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (let* ((json-str (get-request-body-string))
           (data (cl-json:decode-json-from-string json-str))
           (request-id (cdr (assoc :request-id data))))
      (unless request-id
        (setf (hunchentoot:return-code*) 400)
        (return-from api-accept-friend-handler
          (encode-api-response (make-api-error "MISSING_FIELDS" "requestId is required"))))
      (multiple-value-bind (success error)
          (accept-friend-request request-id)
        (if success
            (encode-api-response
             (make-api-response nil :message "Friend request accepted"))
            (progn
              (setf (hunchentoot:return-code*) 400)
              (encode-api-response (make-api-error "ACCEPT_FAILED" error))))))))

;; GET /api/v1/users/search?q={query} - Search users
(defun api-search-users-handler ()
  "Search users by username or display name"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (let ((user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-search-users-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (let* ((query (hunchentoot:get-parameter "q"))
           (limit (parse-integer (or (hunchentoot:get-parameter "limit") "20") :junk-allowed t)))
      (unless query
        (setf (hunchentoot:return-code*) 400)
        (return-from api-search-users-handler
          (encode-api-response (make-api-error "MISSING_FIELDS" "Query parameter 'q' is required"))))
      (let ((users (search-users query :limit limit)))
        (encode-api-response
         (make-api-response users))))))

;;;; File Upload API

;; POST /api/v1/upload - Upload file
(defun api-upload-file-handler ()
  "Handle file upload"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (unless (string= (hunchentoot:request-method hunchentoot:*request*) "POST")
    (setf (hunchentoot:return-code*) 405)
    (return-from api-upload-file-handler
      (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed"))))
  (let ((user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-upload-file-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    ;; Create uploads directory if not exists
    (let* ((uploads-dir "D:/Claude/LispIM/lispim-core/uploads/")
           (dir-exists (probe-file uploads-dir)))
      (unless dir-exists
        (ensure-directories-exist uploads-dir))
      ;; Get file from multipart form data
      ;; hunchentoot:post-parameter returns a list: (temp-file-path filename mime-type)
      (handler-case
          (let* ((file-list (hunchentoot:post-parameter "file"))
                 (filename (hunchentoot:post-parameter "filename"))
                 (mime-type (hunchentoot:content-type*)))
            ;; file-list is (temp-file-path filename mime-type)
            (if (and file-list (consp file-list))
                ;; Get the temp file path from the list
                (let* ((temp-file-path (first file-list))
                       (original-filename (or filename (second file-list)))
                       (unique-filename (format nil "~A-~A" (get-universal-time) original-filename))
                       (file-path (concatenate 'string uploads-dir unique-filename))
                       (file-size (with-open-file (s temp-file-path :direction :input :element-type '(unsigned-byte 8))
                                    (file-length s))))
                  ;; Copy temp file to uploads directory
                  (uiop:copy-file temp-file-path file-path)
                  ;; Save metadata to database
                  (multiple-value-bind (success file-id error)
                      (save-file-metadata original-filename unique-filename file-path file-size (or mime-type "application/octet-stream") user-id nil)
                    (if success
                        (encode-api-response
                         (make-api-response
                          (list :fileId file-id
                                :filename original-filename
                                :url (format nil "/api/v1/files/~A" file-id)
                                :size file-size)
                          :message "File uploaded successfully"))
                        (progn
                          (setf (hunchentoot:return-code*) 500)
                          (encode-api-response (make-api-error "UPLOAD_FAILED" error))))))
                ;; Missing file or filename
                (progn
                  (setf (hunchentoot:return-code*) 400)
                  (encode-api-response (make-api-error "MISSING_FIELDS" "File and filename are required")))))
        (error (c)
          (log-error "File upload error: ~a" c)
          (setf (hunchentoot:return-code*) 500)
          (encode-api-response (make-api-error "UPLOAD_FAILED" (format nil "Upload error: ~a" c))))))))

;; GET /api/v1/files/{file-id} - Get file
(defun api-get-file-handler ()
  "Get file by ID"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (let* ((uri (hunchentoot:request-uri hunchentoot:*request*))
         (file-id (multiple-value-bind (match-start match-end reg-start reg-end)
                    (cl-ppcre:scan "^/api/v1/files/([^/]+)$" uri)
                    (if match-start
                        (subseq uri (aref reg-start 0) (aref reg-end 0))
                        (return-from api-get-file-handler
                          (progn
                            (setf (hunchentoot:return-code*) 400)
                            (encode-api-response (make-api-error "INVALID_URI" "Invalid file URI")))))))
         (user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-get-file-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    ;; Validate file-id format (UUID format check)
    (unless (cl-ppcre:scan "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$" file-id)
      (setf (hunchentoot:return-code*) 400)
      (return-from api-get-file-handler
        (encode-api-response (make-api-error "INVALID_FILE_ID" "Invalid file ID format"))))
    (handler-case
        (let ((metadata (get-file-metadata file-id)))
          (if metadata
              (let ((file-path (getf metadata :file-path)))
                (if (probe-file file-path)
                    (progn
                      ;; Set response headers
                      (setf (hunchentoot:content-type*) (getf metadata :mime-type))
                      (setf (hunchentoot:header-out "Content-Disposition")
                            (format nil "attachment; filename=\"~A\"" (getf metadata :original-filename)))
                      ;; Increment download count
                      (increment-file-download-count file-id)
                      ;; Read file data and return as binary
                      (let ((file-data (with-open-file (s file-path :direction :input :element-type '(unsigned-byte 8))
                                         (let ((data (make-array (file-length s) :element-type '(unsigned-byte 8))))
                                           (read-sequence data s)
                                           data))))
                        (setf (hunchentoot:header-out "Content-Length") (length file-data))
                        (setf (hunchentoot:content-type*) (getf metadata :mime-type))
                        file-data))
                    (progn
                      (setf (hunchentoot:return-code*) 404)
                      (encode-api-response (make-api-error "NOT_FOUND" "File not found")))))
              (progn
                (setf (hunchentoot:return-code*) 404)
                (encode-api-response (make-api-error "NOT_FOUND" "File not found")))))
      (error (c)
        (log-error "Get file error: ~a" c)
        (setf (hunchentoot:return-code*) 500)
        (encode-api-response (make-api-error "SERVER_ERROR" (format nil "Error: ~a" c)))))))

;;;; Metrics

(defun get-metrics ()
  "Get Prometheus format metrics"
  (let ((uptime (if *gateway-start-time*
                    (floor (- (get-universal-time) *gateway-start-time*))
                    0)))
    (format nil "# HELP lispim_connections_active Active connections~%
# TYPE lispim_connections_active gauge~%
lispim_connections_active ~a~%
# HELP lispim_uptime Uptime (seconds)~%
# TYPE lispim_uptime counter~%
lispim_uptime ~a~%"
            *connections-active-gauge*
            uptime)))

;;;; Mobile / FCM API

;; POST /api/v1/device/fcm-token - Register FCM token
(defun api-register-fcm-token-handler ()
  "Register or update FCM token for push notifications"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (unless (string= (hunchentoot:request-method hunchentoot:*request*) "POST")
    (setf (hunchentoot:return-code*) 405)
    (return-from api-register-fcm-token-handler
      (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed"))))
  (let ((user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-register-fcm-token-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (handler-case
        (let* ((json-str (get-request-body-string))
               (data (cl-json:decode-json-from-string json-str))
               (fcm-token (cdr (assoc :fcm-token data)))
               (device-id (cdr (assoc :device-id data)))
               (platform (cdr (assoc :platform data)))
               (device-name (cdr (assoc :device-name data)))
               (app-version (cdr (assoc :app-version data)))
               (os-version (cdr (assoc :os-version data))))
          (unless fcm-token
            (setf (hunchentoot:return-code*) 400)
            (return-from api-register-fcm-token-handler
              (encode-api-response (make-api-error "MISSING_FIELDS" "fcmToken is required"))))
          (multiple-value-bind (success error)
              (save-fcm-token user-id fcm-token
                              :device-id device-id
                              :platform (or platform "android")
                              :device-name device-name
                              :app-version app-version
                              :os-version os-version)
            (if success
                (encode-api-response (make-api-response nil :message "FCM token registered"))
                (progn
                  (setf (hunchentoot:return-code*) 500)
                  (encode-api-response (make-api-error "SAVE_FAILED" error))))))
      (error (c)
        (log-error "Register FCM token error: ~A" c)
        (setf (hunchentoot:return-code*) 500)
        (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c)))))))

;; DELETE /api/v1/device/fcm-token - Remove FCM token
(defun api-remove-fcm-token-handler ()
  "Remove FCM token for a device or user"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (unless (string= (hunchentoot:request-method hunchentoot:*request*) "DELETE")
    (setf (hunchentoot:return-code*) 405)
    (return-from api-remove-fcm-token-handler
      (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed"))))
  (let ((user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-remove-fcm-token-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (handler-case
        (let* ((json-str (get-request-body-string))
               (data (cl-json:decode-json-from-string json-str))
               (device-id (cdr (assoc :device-id data))))
          (multiple-value-bind (success error)
              (remove-fcm-token user-id :device-id device-id)
            (if success
                (encode-api-response (make-api-response nil :message "FCM token removed"))
                (progn
                  (setf (hunchentoot:return-code*) 500)
                  (encode-api-response (make-api-error "REMOVE_FAILED" error))))))
      (error (c)
        (log-error "Remove FCM token error: ~A" c)
        (setf (hunchentoot:return-code*) 500)
        (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c)))))))

;; GET /api/v1/device/fcm-token - Get user's FCM tokens
(defun api-get-fcm-tokens-handler ()
  "Get all FCM tokens for current user"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (unless (string= (hunchentoot:request-method hunchentoot:*request*) "GET")
    (setf (hunchentoot:return-code*) 405)
    (return-from api-get-fcm-tokens-handler
      (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed"))))
  (let ((user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-get-fcm-tokens-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (handler-case
        (let ((tokens (get-user-fcm-tokens user-id)))
          (encode-api-response (make-api-response (list :devices tokens))))
      (error (c)
        (log-error "Get FCM tokens error: ~A" c)
        (setf (hunchentoot:return-code*) 500)
        (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c)))))))

;;; End of gateway.lisp
