;;;; gateway.lisp - HTTP/WebSocket Gateway using Hunchentoot
;;;;
;;;; Responsible for HTTP request handling and basic connection management
;;;; API versioning: /api/v1/

(in-package :lispim-core)

;;;; External variable declarations
;;;; These variables are defined in other modules but used here

(eval-when (:compile-toplevel :load-toplevel :execute)
  ;; Declare external special variables
  (proclaim '(special
    *acceptor* *gateway-start-time* *heartbeat-monitor-thread*
    *chunk-size* *max-file-size* *moment-max-photos*
    *snowflake-last-timestamp* *current-user-id*
    *log-level* *oc-api-key* *oc-endpoint* *room-roles*
    ;; Other external variables
    *options-dispatcher* *ssl-cert* *ssl-key* *use-ssl*)))

;;;; External function declarations
;;;; These functions are defined in other modules but used here

(eval-when (:compile-toplevel :load-toplevel :execute)
  ;; Declare undefined functions to avoid SBCL fatal error
  (macrolet ((declare-external-functions (&rest names)
               `(progn ,@(loop for name in names
                               collect `(declaim (ftype (function (&rest t) t) ,name))))))
    (declare-external-functions
     ;; Storage functions
     get-session create-session invalidate-session
     get-user get-user-by-id store-message get-message-by-id
     ;; Snowflake
     generate-snowflake generate-token
     ;; Chat functions
     send-message mark-as-read edit-message delete-message
     broadcast-message push-to-online-user push-to-online-users
     ;; Room functions
     ;; Connection functions
     close-connection send-message-to-connection receive-from-connection
     ;; Redis functions
     ;; Utils
     log-warning replace-re-all regex-replace-all
     user-to-plist create-message decode-tlv-list)))

;;;; Special variable declarations (for dynamic binding)

(declaim (special *current-user-id*))

;;;; Dependencies

(eval-when (:compile-toplevel :load-toplevel :execute)
  (ql:quickload '(:hunchentoot :bordeaux-threads :uuid :cl-json :flexi-streams :cl-base64 :ironclad :drakma :uiop :postmodern)))

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

(defun cors-middleware-hook ()
  "CORS middleware hook - handles OPTIONS preflight and adds CORS headers to all API responses"
  (let ((method (hunchentoot:request-method hunchentoot:*request*))
        (uri (hunchentoot:request-uri hunchentoot:*request*)))
    ;; Only handle /api/v1/ endpoints
    (when (cl-ppcre:scan "^/api/v1/" uri)
      ;; Add CORS headers to all API responses
      (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
      (setf (hunchentoot:header-out "Access-Control-Allow-Methods") "GET, POST, PUT, DELETE, OPTIONS")
      (setf (hunchentoot:header-out "Access-Control-Allow-Headers") "Content-Type, Authorization")
      (setf (hunchentoot:header-out "Access-Control-Max-Age") "86400")

      ;; Handle OPTIONS preflight requests
      (when (string= method "OPTIONS")
        (log-info "CORS middleware: handling OPTIONS preflight for ~A" uri)
        (setf (hunchentoot:return-code*) 204)
        (return-from cors-middleware-hook "")))))

(defun api-options-handler ()
  "Handle OPTIONS preflight requests for CORS"
  (let ((uri (hunchentoot:request-uri hunchentoot:*request*))
        (method (hunchentoot:request-method hunchentoot:*request*)))
    ;; Write debug info to file
    (with-open-file (stream "D:/Claude/LispIM/lispim-core/options-debug.log"
                            :direction :output
                            :if-exists :append
                            :if-does-not-exist :create)
      (format stream "OPTIONS handler called: method=~A uri=~A~%" method uri))
    ;; Only handle OPTIONS requests to /api/v1/ endpoints
    (when (and (string= method "OPTIONS")
               (cl-ppcre:scan "^/api/v1/" uri))
      (with-open-file (stream "D:/Claude/LispIM/lispim-core/options-debug.log"
                              :direction :output
                              :if-exists :append
                              :if-does-not-exist :create)
        (format stream "OPTIONS handler: handling preflight~%"))
      ;; Add CORS headers
      (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
      (setf (hunchentoot:header-out "Access-Control-Allow-Methods") "GET, POST, PUT, DELETE, OPTIONS")
      (setf (hunchentoot:header-out "Access-Control-Allow-Headers") "Content-Type, Authorization")
      (setf (hunchentoot:header-out "Access-Control-Max-Age") "86400")
      ;; Return 204 No Content
      (setf (hunchentoot:return-code*) 204)
      (setf (hunchentoot:content-type*) "text/plain")
      (return-from api-options-handler ""))
    ;; For non-OPTIONS requests, return NIL to let other handlers process
    (with-open-file (stream "D:/Claude/LispIM/lispim-core/options-debug.log"
                            :direction :output
                            :if-exists :append
                            :if-does-not-exist :create)
      (format stream "OPTIONS handler: passing through for non-OPTIONS~%"))
    nil))

(defun keywordify (str)
  "Convert string to keyword"
  (declare (type string str))
  (intern (string-upcase str) 'keyword))

;; Add path-parameter function to hunchentoot package for compatibility
(defmacro with-path-parameter ((var uri pattern &optional (param-index 0)) &body body)
  "Bind var to extracted path parameter and execute body"
  `(let ((,var (parse-integer (get-path-parameter ,uri ,pattern ,param-index) :junk-allowed t)))
     ,@body))

;; Define hunchentoot:path-parameter for backward compatibility
;; Store current URI's regex groups in a special variable
(defvar *current-path-parameters* nil
  "Current request's path parameters extracted from regex")

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defun %extract-path-param (uri pattern &optional (param-index 0))
    "Extract path parameter from URI"
    (multiple-value-bind (match-start match-end reg-start reg-end)
        (cl-ppcre:scan pattern uri)
      (if match-start
          (subseq uri (aref reg-start param-index) (aref reg-end param-index))
          nil)))

  ;; Common API patterns for path parameter extraction
  (defparameter *api-path-patterns*
    '(("^/api/v1/notifications/([^/]+)/read$" . 1)
      ("^/api/v1/groups/([^/]+)/polls$" . 1)
      ("^/api/v1/polls/([^/]+)$" . 1)
      ("^/api/v1/polls/([^/]+)/vote$" . 1)
      ("^/api/v1/polls/([^/]+)/end$" . 1)
      ("^/api/v1/conversations/([^/]+)/mute$" . 1)
      ("^/api/v1/conversations/([^/]+)/mute-status$" . 1)
      ("^/api/v1/messages/([^/]+)/forward$" . 1)
      ("^/api/v1/messages/([^/]+)/forward-count$" . 1)
      ("^/api/v1/messages/([^/]+)/origin$" . 1)
      ("^/api/v1/conversations/([^/]+)/highlights$" . 1)
      ("^/api/v1/messages/([^/]+)/highlight$" . 1)
      ("^/api/v1/highlights/([^/]+)$" . 1)
      ("^/api/v1/moments/([^/]+)/like$" . 1)
      ("^/api/v1/moments/([^/]+)/comment$" . 1)
      ("^/api/v1/moments/([^/]+)/comments/([^/]+)$" . 2)
      ("^/api/v1/users/([^/]+)$" . 1)
      ("^/api/v1/chat/conversations/([^/]+)/messages$" . 1)
      ("^/api/v1/files/([^/]+)$" . 1)
      ("^/api/v1/files/([^/]+)/progress$" . 1)
      ("^/api/v1/files/([^/]+)/download$" . 1)
      ("^/api/v1/messages/([^/]+)/reply$" . 1)
      ("^/api/v1/messages/([^/]+)/replies$" . 1)
      ("^/api/v1/messages/([^/]+)/reply-chain$" . 1)
      ("^/api/v1/threads/([^/]+)$" . 1)
      ("^/api/v1/contacts/groups/([^/]+)$" . 1)
      ("^/api/v1/contacts/tags/([^/]+)$" . 1)
      ("^/api/v1/contacts/groups/([^/]+)/members$" . 1)
      ("^/api/v1/contacts/friends/([^/]+)/remark$" . 1)
      ("^/api/v1/contacts/friends/([^/]+)/groups$" . 1)
      ("^/api/v1/contacts/friends/([^/]+)/tags$" . 1)
      ("^/api/v1/contacts/blacklist/([^/]+)$" . 1)
      ("^/api/v1/contacts/starred/([^/]+)$" . 1)
      ("^/api/v1/reactions/([^/]+)/([^/]+)$" . 2)
      ("^/api/v1/conversations/([^/]+)/pinned$" . 1)
      ("^/api/v1/messages/([^/]+)/pin$" . 1)
      ("^/api/v1/messages/([^/]+)/unpin$" . 1)
      ("^/api/v1/conversations/([^/]+)/disappearing$" . 1)
      ("^/api/v1/messages/([^/]+)/delete$" . 1)
      ("^/api/v1/friend-requests/([^/]+)/accept$" . 1)
      ("^/api/v1/friend-requests/([^/]+)/reject$" . 1)))

  ;; Add path-parameter function to hunchentoot package
  (let ((pkg (find-package "HUNCHENTOOT")))
    (unless (find-symbol "PATH-PARAMETER" "HUNCHENTOOT")
      ;; Create the symbol in hunchentoot package
      (let ((sym (intern "PATH-PARAMETER" pkg)))
        (export sym pkg)
        (setf (symbol-function sym)
              (lambda (n)
                "Get path parameter N from current request URI"
                (let ((uri (hunchentoot:request-uri hunchentoot:*request*)))
                  (loop for (pattern . _) in *api-path-patterns*
                        for result = (multiple-value-bind (match-start match-end reg-start reg-end)
                                         (cl-ppcre:scan pattern uri)
                                       (when match-start
                                         (if (= n 1)
                                             (subseq uri (aref reg-start 0) (aref reg-end 0))
                                           (when (> (length reg-start) 1)
                                             (subseq uri (aref reg-start (1- n)) (aref reg-end (1- n)))))))
                          thereis result))))))))

(defmacro with-uri-path-params ((uri-var uri pattern params-list) &body body)
  "Extract path parameters from URI and bind to params-list variables"
  `(multiple-value-bind (match-start match-end reg-start reg-end)
       (cl-ppcre:scan ,pattern ,uri)
     (if match-start
         (let ,(loop for param in params-list
                     for i from 0
                     collect `(,param (parse-integer (subseq ,uri (aref reg-start i) (aref reg-end i))
                                                     :junk-allowed t)))
           ,@body)
         (progn
           (setf (hunchentoot:return-code*) 400)
           (encode-api-response (make-api-error "INVALID_URI" "Invalid URI"))))))

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

(defun download-image-to-file (url file-path)
  "Download image from URL to file path"
  (declare (type string url file-path))
  (handler-case
      (let ((response (drakma:http-request url :want-stream t)))
        (when (and (consp response)
                   (eq (car response) 200))
          (let ((stream (cdr response)))
            (with-open-file (out file-path :direction :output :element-type '(unsigned-byte 8)
                                             :if-exists :supersede)
              (copy-stream-to-file stream out))
            t)))
    (error (c)
      (log-error "Failed to download image from ~a: ~a" url c)
      nil)))

(defun copy-stream-to-file (input-stream output-stream)
  "Copy binary data from input stream to output file"
  (let ((buffer (make-array 4096 :element-type '(unsigned-byte 8))))
    (loop
      for end = (read-sequence buffer input-stream)
      while (plusp end)
      do (write-sequence buffer output-stream :end end))))

;;;; API Response Format - Unified JSON structure

(defun kebab-to-camel-case (str &optional (capitalize-first nil))
  "Convert kebab-case string to camelCase"
  (declare (type string str))
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
  "验证 Token 并返回 user-id，如果无效则设置 401 状态并返回 nil"
  ;; Allow OPTIONS requests to pass through without authentication
  (when (string= (hunchentoot:request-method hunchentoot:*request*) "OPTIONS")
    (return-from require-auth "options-bypass"))
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
  (declare (type string code message))
  (list :success nil
        :error (list :code code
                     :message message
                     :details data)))

(defun send-cors-headers ()
  "Send CORS headers for the current response"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:header-out "Access-Control-Allow-Methods") "GET, POST, PUT, DELETE, OPTIONS")
  (setf (hunchentoot:header-out "Access-Control-Allow-Headers") "Content-Type, Authorization")
  (setf (hunchentoot:header-out "Access-Control-Max-Age") "86400"))

(defun encode-api-response (response)
  "编码 API 响应中 JSON 字符串"
  (declare (type list response)
           (optimize (speed 2) (safety 1)))
  ;; Handle OPTIONS preflight - return 204 early
  (when (string= (hunchentoot:request-method hunchentoot:*request*) "OPTIONS")
    (setf (hunchentoot:return-code*) 204)
    (return-from encode-api-response ""))
  ;; Send CORS headers
  (send-cors-headers)
  ;; Convert plist to hash-table and encode as JSON object
  (let ((converted (convert-response-to-camelcase response)))
    (log-info "encode-api-response: converted type=~A" (type-of converted))
    (cl-json:encode-json-to-string converted)))
(defun convert-response-to-camelcase (data)
  "Recursively convert structure to hash-table or list for JSON encoding.
   Returns a hash-table for objects, list for arrays."
  (cond
    ;; Null - JSON null
    ((null data) nil)
    ;; Plist - convert to hash-table for JSON object
    ((and (consp data) (keywordp (car data)))
     (let ((hash (make-hash-table :test 'equal)))
       (loop for (key value) on data by #'cddr do
         (let ((camel-key (kebab-to-camel-case (string-downcase (symbol-name key)))))
           (setf (gethash camel-key hash)
                 (if (and (listp value) (not (null value)) (keywordp (car value)))
                     ;; Nested plist - recursively convert
                     (convert-response-to-camelcase value)
                     ;; Otherwise just convert nested structures
                     (if (listp value)
                         (mapcar #'(lambda (v) (if (and (listp v) (keywordp (car v)))
                                                   (convert-response-to-camelcase v)
                                                   v))
                                 value)
                         value)))))
       hash))
    ;; Proper list (JSON array) - convert each element
    ((listp data)
     (mapcar #'convert-response-to-camelcase data))
    ;; String "null" - convert to nil (JSON null)
    ((and (stringp data) (string= data "null"))
     nil)
    ;; Keyword - convert to string
    ((keywordp data)
     (string-downcase (symbol-name data)))
    ;; Primitive - return as-is
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

;;;; Types - defined in types.lisp
;;;;  connection-state, connection-id, connection struct

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

(defun broadcast-message-to-conversation (conversation-id message)
  "Broadcast message to all participants in a conversation (except sender)"
  (declare (type integer conversation-id)
           (type message message))
  (let* ((participants (conversation-participants (get-conversation conversation-id)))
         (sender-id *current-user-id*)
         (msg-data (encode-ws-message
                    `(:type ,+ws-msg-message+
                            :id ,(message-id message)
                            :sequence ,(message-sequence message)
                            :conversation-id ,conversation-id
                            :sender-id ,(message-sender-id message)
                            :content ,(message-content message)
                            :type ,(message-message-type message)
                            :created-at ,(lispim-universal-to-unix-ms (message-created-at message))))))
    ;; Send to all participants except sender
    (dolist (participant-id participants)
      (unless (string= participant-id sender-id)
        (broadcast-to-user participant-id msg-data)))))

(defun broadcast-to-conversation (conversation-id data)
  "Broadcast data to all participants in a conversation"
  (declare (type integer conversation-id)
           (type (or string vector) data))
  (let ((participants (conversation-participants (get-conversation conversation-id))))
    (dolist (participant-id participants)
      (broadcast-to-user participant-id data)))
  nil)

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
           (type list payload))
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
  "编码 WebSocket 消息为 JSON"
  (declare (type list message))
  ;; Recursively convert plists to alists for proper JSON object encoding
  (labels ((convert (obj)
             (cond ((null obj) nil)
                   ((listp obj)
                    (if (and (evenp (length obj))
                             (every #'keywordp (loop for (k v) on obj by #'cddr collect k)))
                        ;; This is a plist - convert to alist recursively
                        (loop for (k v) on obj by #'cddr
                              collect (cons (string-downcase (string k)) (convert v)))
                        ;; This is a regular list - convert each element
                        (mapcar #'convert obj)))
                   (t obj))))
    (cl-json:encode-json-to-string (convert message))))


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
(defconstant +ws-op-continuation+ #b0000)
(defconstant +ws-op-text+ #b0001)
(defconstant +ws-op-binary+ #b0010)
(defconstant +ws-op-close+ #b1000)
(defconstant +ws-op-ping+ #b1001)
(defconstant +ws-op-pong+ #b1010)

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
             (message (cl-json:decode-json-from-string json-str))
             ;; Convert alist with string keys to plist with keyword keys
             (message-plist (convert-json-to-plist message)))
        (log-info "Received JSON message: ~A" json-str)
        (log-info "Raw decoded message type: ~A" (type-of message))
        (log-info "Converted message plist: ~A" message-plist)
        (log-info "Message plist type: ~A" (type-of message-plist))
        (when (listp message-plist)
          (log-info "plist length: ~A, first few elements: ~A"
                    (length message-plist)
                    (subseq message-plist 0 (min 4 (length message-plist)))))
        (incf (connection-message-count conn))
        (process-ws-message conn message-plist))
    (error (c)
      (log-error "Failed to receive from connection ~a: ~a" (connection-id conn) c))))

(defun convert-json-to-plist (obj)
  "Convert JSON object (alist with string keys) to Lisp plist (keyword keys)"
  (cond
    ((null obj) nil)
    ((typep obj 'hash-table)
     ;; JSON object decoded as hash table - convert to proper plist
     (loop with result = nil
           for key being the hash-keys of obj
           for value being the hash-values of obj
           for lisp-key = (intern (string-upcase key) 'keyword)
           for converted-value = (convert-json-to-plist value)
           do (push lisp-key result)
              (push converted-value result)
           finally (return (nreverse result))))
    ((and (listp obj) (every #'consp obj))
     ;; Alist - convert each (key . value) cons to alternating keyword/value
     (loop for (k . v) in obj
           append (list (if (keywordp k)
                            k
                            (intern (string-upcase (string k)) 'keyword))
                        (convert-json-to-plist v))))
    ((listp obj)
     ;; Regular list (array) - convert each element
     (mapcar #'convert-json-to-plist obj))
    (t obj)))  ; Strings, numbers, etc pass through

(defun process-ws-message (conn message)
  "Process WebSocket message with Protocol v1"
  (declare (type connection conn)
           (type list message))
  (let* ((msg-type (getf message :type))
         ;; Convert string type to keyword if needed
         (msg-type-kw (if (stringp msg-type) (intern (string-upcase msg-type) (quote keyword)) msg-type))
         (payload (getf message :payload))
         (message-id (getf message :message-id))
         (ack-required (getf message :ack-required)))
    ;; 发送ACK 如果需要
    (when (and ack-required message-id)
      (send-ack conn (if (numberp message-id) (princ-to-string message-id) message-id) :ack-type :received))
    ;; 处理消息
    (cond
      ;; 兼容旧版 ping/pong
      ((eq msg-type-kw :ping)
       (send-pong conn (getf message :data)))
      ((eq msg-type-kw :pong)
       (update-connection-heartbeat (connection-id conn)))
      ;; Protocol v1 ping/pong
      ((eq msg-type-kw +ws-msg-ping+)
       (send-ws-message conn +ws-msg-pong+ (list :timestamp (lispim-universal-to-unix-ms (get-universal-time)))))
      ((eq msg-type-kw +ws-msg-pong+)
       (update-connection-heartbeat (connection-id conn)))
      ;; 认证
      ((eq msg-type-kw +ws-msg-auth+)
       (handle-auth-message conn payload))
      ;; 聊天消息
      ((eq msg-type-kw +ws-msg-message+)
       (handle-chat-message conn payload))
      ;; ACK 处理
      ((or (eq msg-type-kw +ws-msg-message-received+)
           (eq msg-type-kw +ws-msg-message-delivered+)
           (eq msg-type-kw +ws-msg-message-read+))
       (handle-ack conn message))
      ;; 在线状态
      ((eq msg-type-kw +ws-msg-presence+)
       (handle-presence-update conn payload))
      ;; 输入状态
      ((eq msg-type-kw +ws-msg-typing+)
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
         (type-val (getf message :type :text))
         ;; Convert string type to keyword if needed
         (type (if (stringp type-val)
                   (intern (string-upcase type-val) 'keyword)
                   type-val))
         (reply-to (getf message :reply-to))
         (mentions (getf message :mentions))
         (attachments (getf message :attachments))
         ;; Set *current-user-id* from connection
         (*current-user-id* (connection-user-id conn)))
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
  ;; Also support /api/v1/auth/current-user alias
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/auth/current-user$" 'api-current-user-handler)
        hunchentoot:*dispatch-table*)

  ;; Add update user profile handler
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/users/profile$" 'api-update-profile-handler)
        hunchentoot:*dispatch-table*)

  ;; Account Management API
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/account/change-password$" 'api-change-password-handler)
        hunchentoot:*dispatch-table*)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/account/bind-phone$" 'api-bind-phone-handler)
        hunchentoot:*dispatch-table*)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/account/bind-email$" 'api-bind-email-handler)
        hunchentoot:*dispatch-table*)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/account/unbind-phone$" 'api-unbind-phone-handler)
        hunchentoot:*dispatch-table*)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/account/unbind-email$" 'api-unbind-email-handler)
        hunchentoot:*dispatch-table*)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/account/sessions$" 'api-get-sessions-handler)
        hunchentoot:*dispatch-table*)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/account/sessions/([^/]+)$" 'api-revoke-session-handler)
        hunchentoot:*dispatch-table*)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/account/delete$" 'api-delete-account-handler)
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
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/friends/([^/]+)/delete$" 'api-delete-friend-handler)
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

  ;; File Transfer API (大文件传输)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/files/upload/init$" 'api-init-file-upload-handler)
        hunchentoot:*dispatch-table*)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/files/upload/chunk$" 'api-upload-chunk-handler)
        hunchentoot:*dispatch-table*)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/files/upload/complete$" 'api-complete-file-upload-handler)
        hunchentoot:*dispatch-table*)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/files/([^/]+)$" 'api-get-file-info-handler)
        hunchentoot:*dispatch-table*)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/files/([^/]+)/download$" 'api-download-file-handler)
        hunchentoot:*dispatch-table*)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/files/([^/]+)/progress$" 'api-get-upload-progress-handler)
        hunchentoot:*dispatch-table*)

  (push (hunchentoot:create-regex-dispatcher "^/api/v1/files/([^/]+)$" 'api-get-file-handler)
        hunchentoot:*dispatch-table*)

  ;; Add FCM token handlers
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/device/fcm-token$" 'api-register-fcm-token-handler)
        hunchentoot:*dispatch-table*)

  ;; Add fulltext search handler
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/search$" 'api-search-handler)
        hunchentoot:*dispatch-table*)

  ;; Add message reply handlers
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/messages/([^/]+)/reply$" 'api-reply-message-handler)
        hunchentoot:*dispatch-table*)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/messages/([^/]+)/replies$" 'api-get-replies-handler)
        hunchentoot:*dispatch-table*)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/messages/([^/]+)/reply-chain$" 'api-get-reply-chain-handler)
        hunchentoot:*dispatch-table*)

  ;; Add QR code API handlers (扫一扫功能)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/qr/generate$" 'api-generate-qr-handler)
        hunchentoot:*dispatch-table*)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/qr/scan$" 'api-scan-qr-handler)
        hunchentoot:*dispatch-table*)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/qr/scan-image$" 'api-scan-qr-image-handler)
        hunchentoot:*dispatch-table*)

  ;; Add location-based API handlers (附近的人功能)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/location/report$" 'api-report-location-handler)
        hunchentoot:*dispatch-table*)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/location/nearby$" 'api-get-nearby-users-handler)
        hunchentoot:*dispatch-table*)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/location/privacy$" 'api-set-location-privacy-handler)
        hunchentoot:*dispatch-table*)

  ;; Add Moments API handlers (朋友圈功能)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/moments$" 'api-get-moments-handler)
        hunchentoot:*dispatch-table*)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/moments/post$" 'api-create-moment-handler)
        hunchentoot:*dispatch-table*)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/moments/([^/]+)$" 'api-moment-detail-handler)
        hunchentoot:*dispatch-table*)

  ;; Notification Preferences API (通知偏好设置)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/notifications/preferences$" 'api-get-notification-preferences-handler)
        hunchentoot:*dispatch-table*)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/notifications/read-all$" 'api-mark-all-notifications-read-handler)
        hunchentoot:*dispatch-table*)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/notifications/([^/]+)/read$" 'api-mark-notification-read-handler)
        hunchentoot:*dispatch-table*)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/notifications$" 'api-get-notifications-handler)
        hunchentoot:*dispatch-table*)

  ;; Group Polls API (群投票)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/groups/([0-9]+)/polls$" 'api-get-group-polls-handler)
        hunchentoot:*dispatch-table*)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/polls/([0-9]+)$" 'api-get-poll-handler)
        hunchentoot:*dispatch-table*)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/polls/([0-9]+)/vote$" 'api-cast-vote-handler)
        hunchentoot:*dispatch-table*)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/polls/([0-9]+)/end$" 'api-end-poll-handler)
        hunchentoot:*dispatch-table*)

  (push (hunchentoot:create-regex-dispatcher "^/api/v1/groups/([0-9]+)/polls$" 'api-create-poll-handler)
        hunchentoot:*dispatch-table*)

  ;; Group DND API (群消息免打扰)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/conversations/([0-9]+)/mute$" 'api-mute-conversation-handler)
        hunchentoot:*dispatch-table*)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/conversations/([0-9]+)/mute-status$" 'api-get-conversation-mute-status-handler)
        hunchentoot:*dispatch-table*)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/conversations/muted$" 'api-get-muted-conversations-handler)
        hunchentoot:*dispatch-table*)

  ;; Message Forwarding API (消息转发)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/messages/([0-9]+)/forward$" 'api-forward-message-handler)
        hunchentoot:*dispatch-table*)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/messages/forward-batch$" 'api-forward-messages-batch-handler)
        hunchentoot:*dispatch-table*)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/messages/([0-9]+)/forward-count$" 'api-get-message-forward-count-handler)
        hunchentoot:*dispatch-table*)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/messages/([0-9]+)/origin$" 'api-get-forwarded-message-origin-handler)
        hunchentoot:*dispatch-table*)

  ;; Highlight Messages API (群精华消息)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/conversations/([0-9]+)/highlights$" 'api-get-highlighted-messages-handler)
        hunchentoot:*dispatch-table*)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/messages/([0-9]+)/highlight$" 'api-add-highlighted-message-handler)
        hunchentoot:*dispatch-table*)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/highlights/([0-9]+)$" 'api-remove-highlighted-message-handler)
        hunchentoot:*dispatch-table*)

  ;; Link Preview API (链接预览)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/links/preview$" 'api-get-link-preview-handler)
        hunchentoot:*dispatch-table*)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/links/generate-preview$" 'api-generate-link-preview-handler)
        hunchentoot:*dispatch-table*)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/links/extract$" 'api-extract-link-previews-handler)
        hunchentoot:*dispatch-table*)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/links/preview\\?url=.*$" 'api-invalidate-link-preview-handler)
        hunchentoot:*dispatch-table*)

  (push (hunchentoot:create-regex-dispatcher "^/api/v1/moments/([^/]+)/like$" 'api-like-moment-handler)
        hunchentoot:*dispatch-table*)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/moments/([^/]+)/comment$" 'api-comment-moment-handler)
        hunchentoot:*dispatch-table*)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/moments/([^/]+)/comments/([^/]+)$" 'api-delete-comment-handler)
        hunchentoot:*dispatch-table*)

  ;; Contacts API (通讯录)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/contacts/groups$" 'api-get-contact-groups-handler)
        hunchentoot:*dispatch-table*)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/contacts/tags$" 'api-get-contact-tags-handler)
        hunchentoot:*dispatch-table*)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/contacts/groups/([^/]+)$" 'api-contact-group-detail-handler)
        hunchentoot:*dispatch-table*)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/contacts/tags/([^/]+)$" 'api-contact-tag-detail-handler)
        hunchentoot:*dispatch-table*)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/contacts/groups/([^/]+)/members$" 'api-get-group-members-handler)
        hunchentoot:*dispatch-table*)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/contacts/friends/([^/]+)/remark$" 'api-set-contact-remark-handler)
        hunchentoot:*dispatch-table*)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/contacts/friends/([^/]+)/groups$" 'api-friend-groups-handler)
        hunchentoot:*dispatch-table*)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/contacts/friends/([^/]+)/tags$" 'api-friend-tags-handler)
        hunchentoot:*dispatch-table*)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/contacts/blacklist$" 'api-blacklist-handler)
        hunchentoot:*dispatch-table*)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/contacts/blacklist/([^/]+)$" 'api-blacklist-detail-handler)
        hunchentoot:*dispatch-table*)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/contacts/stars$" 'api-stars-handler)
        hunchentoot:*dispatch-table*)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/contacts/stars/([^/]+)$" 'api-stars-detail-handler)
        hunchentoot:*dispatch-table*)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/contacts/search$" 'api-search-contacts-handler)
        hunchentoot:*dispatch-table*)

  ;; Group API (群聊功能)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/groups$" 'api-create-group-handler)
        hunchentoot:*dispatch-table*)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/groups$" 'api-get-groups-handler)
        hunchentoot:*dispatch-table*)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/groups/([0-9]+)$" 'api-group-detail-handler)
        hunchentoot:*dispatch-table*)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/groups/([0-9]+)/members$" 'api-group-members-handler)
        hunchentoot:*dispatch-table*)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/groups/([0-9]+)/members/([^/]+)$" 'api-group-member-detail-handler)
        hunchentoot:*dispatch-table*)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/groups/([0-9]+)/announcement$" 'api-group-announcement-handler)
        hunchentoot:*dispatch-table*)

  ;; Group Announcements API (群公告)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/groups/([0-9]+)/announcement$" 'api-group-announcement-detail-handler)
        hunchentoot:*dispatch-table*)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/groups/([0-9]+)/announcement/history$" 'api-group-announcement-history-handler)
        hunchentoot:*dispatch-table*)

  ;; Group Invite Links API (群邀请链接)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/groups/([0-9]+)/invite-links$" 'api-group-invite-links-handler)
        hunchentoot:*dispatch-table*)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/groups/([0-9]+)/invite-links/create$" 'api-create-group-invite-link-handler)
        hunchentoot:*dispatch-table*)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/groups/invite/([A-Za-z0-9]+)$" 'api-join-via-invite-handler)
        hunchentoot:*dispatch-table*)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/groups/invite-links/([0-9]+)/revoke$" 'api-revoke-invite-link-handler)
        hunchentoot:*dispatch-table*)

  ;; Favorites API (收藏管理)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/favorites$" 'api-favorites-handler)
        hunchentoot:*dispatch-table*)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/favorites/([0-9]+)$" 'api-favorite-handler)
        hunchentoot:*dispatch-table*)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/favorites/categories$" 'api-favorite-categories-handler)
        hunchentoot:*dispatch-table*)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/favorites/categories/([0-9]+)$" 'api-favorite-category-handler)
        hunchentoot:*dispatch-table*)

  ;; Call API (语音/视频通话)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/calls$" 'api-create-call-handler)
        hunchentoot:*dispatch-table*)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/calls/([^/]+)$" 'api-get-call-handler)
        hunchentoot:*dispatch-table*)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/calls/([^/]+)/answer$" 'api-answer-call-handler)
        hunchentoot:*dispatch-table*)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/calls/([^/]+)/reject$" 'api-reject-call-handler)
        hunchentoot:*dispatch-table*)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/calls/([^/]+)/end$" 'api-end-call-handler)
        hunchentoot:*dispatch-table*)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/calls/([^/]+)/offer$" 'api-send-offer-handler)
        hunchentoot:*dispatch-table*)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/calls/([^/]+)/answer$" 'api-send-answer-handler)
        hunchentoot:*dispatch-table*)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/calls/([^/]+)/ice$" 'api-send-ice-candidate-handler)
        hunchentoot:*dispatch-table*)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/calls/history$" 'api-get-call-history-handler)
        hunchentoot:*dispatch-table*)

  ;; Privacy API (隐私增强)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/conversations/([0-9]+)/disappearing$" 'api-disappearing-settings-handler)
        hunchentoot:*dispatch-table*)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/messages/([0-9]+)/delete-all$" 'api-delete-message-for-all-handler)
        hunchentoot:*dispatch-table*)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/messages/([0-9]+)/delete-self$" 'api-delete-message-for-self-handler)
        hunchentoot:*dispatch-table*)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/privacy/settings$" 'api-privacy-settings-handler)
        hunchentoot:*dispatch-table*)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/privacy/stats$" 'api-privacy-stats-handler)
        hunchentoot:*dispatch-table*)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/privacy/user/(.+)$" 'api-privacy-user-settings-handler)
        hunchentoot:*dispatch-table*)

  ;; Contact Management API (联系人管理)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/contacts/friends$" 'api-friend-list-handler)
        hunchentoot:*dispatch-table*)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/contacts/friend-requests$" 'api-friend-requests-handler)
        hunchentoot:*dispatch-table*)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/contacts/friend-request/send$" 'api-send-friend-request-handler)
        hunchentoot:*dispatch-table*)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/contacts/friend-request/([^/]+)/accept$" 'api-accept-friend-request-handler)
        hunchentoot:*dispatch-table*)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/contacts/friend-request/([^/]+)/reject$" 'api-reject-friend-request-handler)
        hunchentoot:*dispatch-table*)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/contacts/blacklist$" 'api-blacklist-handler)
        hunchentoot:*dispatch-table*)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/contacts/blacklist/([^/]+)$" 'api-blacklist-user-handler)
        hunchentoot:*dispatch-table*)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/contacts/star$" 'api-star-contacts-handler)
        hunchentoot:*dispatch-table*)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/contacts/star/([^/]+)$" 'api-star-user-handler)
        hunchentoot:*dispatch-table*)

  ;; Message Reactions API (消息表情回应)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/messages/([0-9]+)/reactions$" 'api-message-reactions-handler)
        hunchentoot:*dispatch-table*)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/messages/([0-9]+)/reactions/([^/]+)$" 'api-message-reaction-user-handler)
        hunchentoot:*dispatch-table*)

  ;; Message Pinning API (消息置顶)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/conversations/([0-9]+)/pinned-messages$" 'api-get-pinned-messages-handler)
        hunchentoot:*dispatch-table*)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/messages/([0-9]+)/pin$" 'api-pin-message-handler)
        hunchentoot:*dispatch-table*)
  (push (hunchentoot:create-regex-dispatcher "^/api/v1/messages/([0-9]+)/unpin$" 'api-unpin-message-handler)
        hunchentoot:*dispatch-table*)

  ;; Note: CORS middleware hook handles OPTIONS requests via *hook-pre-call*

  ;; Add OPTIONS handler for CORS preflight using a closure (checked first due to push order)
  ;; This MUST come after all other API handlers so it's pushed before them
  (let ((options-dispatcher
         (lambda ()
           (let ((method (hunchentoot:request-method hunchentoot:*request*))
                 (uri (hunchentoot:request-uri hunchentoot:*request*)))
             (when (and (string= method "OPTIONS")
                        (cl-ppcre:scan "^/api/v1/" uri))
               ;; Add CORS headers
               (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
               (setf (hunchentoot:header-out "Access-Control-Allow-Methods") "GET, POST, PUT, DELETE, OPTIONS")
               (setf (hunchentoot:header-out "Access-Control-Allow-Headers") "Content-Type, Authorization")
               (setf (hunchentoot:header-out "Access-Control-Max-Age") "86400")
               ;; Return 204 No Content
               (setf (hunchentoot:return-code*) 204)
               (setf (hunchentoot:content-type*) "text/plain")
               "")))))
    (push options-dispatcher hunchentoot:*dispatch-table*))

  ;; Thread/Reply API

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
  ;; DEBUG: Log every request
  (log-info "websocket-raw-dispatcher called, URI=~A, Upgrade=~A" 
            (hunchentoot:request-uri hunchentoot:*request*)
            (hunchentoot:header-in "Upgrade" hunchentoot:*request*))
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
              ;; Extract token from query parameter
              (let* ((uri (hunchentoot:request-uri hunchentoot:*request*))
                     (token (when (and (search "?token=" uri)
                                       (> (length uri) 8))
                              ;; Extract token from ?token=XXX
                              (subseq uri (+ (search "?token=" uri) 7)))))
                (log-info "WebSocket URI: ~A, token: ~A" uri token)
                (when token
                  ;; Validate token and get user-id
                  (let ((user-id (verify-token token)))
                    (when user-id
                      (setf (connection-user-id conn) user-id
                            (connection-state conn) :authenticated)
                      (log-info "WebSocket connection authenticated: ~a as user ~a" (connection-id conn) user-id))))
              (register-connection conn)
              ;; Send auth response
              (let* ((auth-payload (list :success t
                                         :connection-id (connection-id conn)
                                         :user-id (connection-user-id conn)
                                         :status "connected"))
                     (auth-msg (list :type :authResponse
                                     :payload auth-payload
                                     :version "1.0"
                                     :timestamp (lispim-universal-to-unix-ms (get-universal-time)))))
                ;; Convert to alist and encode
                (labels ((convert (obj)
                           (cond ((null obj) nil)
                                 ((listp obj)
                                  (if (and (evenp (length obj))
                                           (every #'keywordp (loop for (k v) on obj by #'cddr collect k)))
                                      (loop for (k v) on obj by #'cddr
                                            collect (cons (string-downcase (string k)) (convert v)))
                                      (mapcar #'convert obj)))
                                 (t obj))))
                  (let* ((alist (convert auth-msg))
                         (json (cl-json:encode-json-to-string alist))
                         (payload (babel:string-to-octets json :encoding :utf-8))
                         (frame (make-ws-frame :fin t :opcode +ws-op-text+ :payload payload))
                         (frame-bytes (encode-ws-frame frame)))
                    (write-sequence frame-bytes stream)
                    (finish-output stream)))
                (log-info "Auth response sent to connection ~a (user: ~a)" (connection-id conn) (connection-user-id conn))))
              ;; Handle WebSocket messages in the SAME thread to keep stream alive
              (loop
                (handler-case
                    (let ((frame (decode-ws-frame stream)))
                      (unless frame
                        ;; Connection closed
                        (log-info "WebSocket connection closed normally: ~a" (connection-id conn))
                        (unregister-connection (connection-id conn))
                        (return))
                      ;; Process frame based on opcode
                      (let ((opcode (ws-frame-opcode frame)))
                        (log-info "WebSocket opcode received: ~A, +ws-op-text+=~A, equal=~A" 
                                  opcode +ws-op-text+ (= opcode +ws-op-text+))
                        (cond
                          ;; Text frame
                          ((= opcode +ws-op-text+)
                           (log-info "Received text frame, payload length: ~A" (length (ws-frame-payload frame)))
                           (when (ws-frame-payload frame)
                             (receive-from-connection conn (ws-frame-payload frame))))
                          ;; Ping frame - send pong
                          ((= opcode +ws-op-ping+)
                           (let ((pong-frame (make-ws-frame :fin t :opcode +ws-op-pong+
                                                            :payload (ws-frame-payload frame))))
                             (write-sequence (encode-ws-frame pong-frame) stream)
                             (finish-output stream)))
                          ;; Pong frame - update heartbeat
                          ((= opcode +ws-op-pong+)
                           (update-connection-heartbeat (connection-id conn)))
                          ;; Close frame
                          ((= opcode +ws-op-close+)
                           (log-info "WebSocket close frame received: ~a" (connection-id conn))
                           (unregister-connection (connection-id conn))
                           (return))
                          (t
                           (log-warn "Unknown WebSocket opcode: ~a (expected text=~A, close=~A)" 
                                     opcode +ws-op-text+ +ws-op-close+)))))
                  (stream-error (c)
                    ;; Connection lost
                    (log-info "WebSocket connection lost: ~a - ~a" (connection-id conn) c)
                    (unregister-connection (connection-id conn))
                    (return))
                  (error (c)
                    (log-error "Error processing WebSocket message: ~a - ~a" (connection-id conn) c)
                    (unregister-connection (connection-id conn))
                    (return))))
              ;; Return after WebSocket connection is closed
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
                (search "/assets/" uri)
                (search "/websocket" uri))
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
            ((string= method "anonymous")
             ;; Anonymous registration - no phone/email required
             (multiple-value-bind (success user-id token error)
                 (register-anonymous-user :display-name display-name
                                          :captcha-response (cdr (assoc :captcha-response data))
                                          :invitation-code (cdr (assoc :invitation-code data)))
               (if success
                   (encode-api-response (make-api-response (list :userId user-id :token token :anonymous t)))
                   (progn
                     (setf (hunchentoot:return-code*) 400)
                     (encode-api-response (make-api-error "ANONYMOUS_REGISTER_FAILED" error))))))
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

;; Chat API v1 - Edit Message
(hunchentoot:define-easy-handler (api-edit-message-v1 :uri "/api/v1/chat/messages/:id/edit") ()
  (setf *current-handler* 'api-edit-message-v1)
  (if (not (string= (hunchentoot:request-method hunchentoot:*request*) "POST"))
      (progn
        (setf (hunchentoot:return-code*) 405)
        (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed")))
      (progn
        (let ((token (hunchentoot:header-in :authorization hunchentoot:*request*))
              (message-id (hunchentoot:get-parameter "id"))
              (content (hunchentoot:post-parameter "content")))
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
                              (edit-message message-id content))
                            (encode-api-response (make-api-response nil :message "Message edited")))
                        (message-not-found (c)
                          (setf (hunchentoot:return-code*) 404)
                          (encode-api-response (make-api-error "NOT_FOUND" (format nil "~A" c))))
                        (auth-error (c)
                          (setf (hunchentoot:return-code*) 403)
                          (encode-api-response (make-api-error "ACCESS_DENIED" (format nil "~A" c))))
                        (message-recall-timeout (c)
                          (setf (hunchentoot:return-code*) 400)
                          (encode-api-response (make-api-error "EDIT_TIMEOUT" (format nil "~A" c))))))))))))))

;; Chat API v1 - Translate Message
(hunchentoot:define-easy-handler (api-translate-message-v1 :uri "/api/v1/chat/messages/:id/translate") ()
  (setf *current-handler* 'api-translate-message-v1)
  (if (not (string= (hunchentoot:request-method hunchentoot:*request*) "POST"))
      (progn
        (setf (hunchentoot:return-code*) 405)
        (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed")))
      (let ((token (hunchentoot:header-in :authorization hunchentoot:*request*))
            (message-id (hunchentoot:get-parameter "id"))
            (target-lang (hunchentoot:post-parameter "target-lang"))
            (source-lang (hunchentoot:post-parameter "source-lang")))
        (if (not token)
            (progn
              (setf (hunchentoot:return-code*) 401)
              (encode-api-response (make-api-error "UNAUTHORIZED" "Unauthorized")))
            (let ((user-id (verify-token (remove-prefix token "Bearer "))))
              (if (not user-id)
                  (progn
                    (setf (hunchentoot:return-code*) 401)
                    (encode-api-response (make-api-error "UNAUTHORIZED" "Unauthorized")))
                  (progn
                    (unless target-lang
                      (setf (hunchentoot:return-code*) 400)
                      (return-from api-translate-message-v1
                        (encode-api-response (make-api-error "MISSING_FIELDS" "Missing target-lang parameter"))))
                    (let ((lang-keyword (keywordify target-lang))
                          (source-keyword (when source-lang (keywordify source-lang))))
                      (handler-case
                          (multiple-value-bind (success translated-text error)
                              (translate-message (parse-integer message-id) lang-keyword :source-lang source-keyword)
                            (if success
                                (encode-api-response (make-api-response (list :translatedText translated-text
                                                                              :targetLang target-lang
                                                                              :sourceLang (or source-lang "auto"))))
                                (progn
                                  (setf (hunchentoot:return-code*) 400)
                                  (encode-api-response (make-api-error "TRANSLATION_FAILED" error)))))
                        (message-not-found (c)
                          (setf (hunchentoot:return-code*) 404)
                          (encode-api-response (make-api-error "NOT_FOUND" (format nil "~A" c))))
                        (error (c)
                          (setf (hunchentoot:return-code*) 500)
                          (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c)))))))))))))

;; Chat API v1 - Translate Text
(hunchentoot:define-easy-handler (api-translate-text-v1 :uri "/api/v1/chat/translate") ()
  (setf *current-handler* 'api-translate-text-v1)
  (if (not (string= (hunchentoot:request-method hunchentoot:*request*) "POST"))
      (progn
        (setf (hunchentoot:return-code*) 405)
        (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed")))
      (let ((token (hunchentoot:header-in :authorization hunchentoot:*request*))
            (text (hunchentoot:post-parameter "text"))
            (target-lang (hunchentoot:post-parameter "target-lang"))
            (source-lang (hunchentoot:post-parameter "source-lang")))
        (if (not token)
            (progn
              (setf (hunchentoot:return-code*) 401)
              (encode-api-response (make-api-error "UNAUTHORIZED" "Unauthorized")))
            (let ((user-id (verify-token (remove-prefix token "Bearer "))))
              (if (not user-id)
                  (progn
                    (setf (hunchentoot:return-code*) 401)
                    (encode-api-response (make-api-error "UNAUTHORIZED" "Unauthorized")))
                  (progn
                    (unless (and text target-lang)
                      (setf (hunchentoot:return-code*) 400)
                      (return-from api-translate-text-v1
                        (encode-api-response (make-api-error "MISSING_FIELDS" "Missing text or target-lang"))))
                    (let ((lang-keyword (keywordify target-lang))
                          (source-keyword (when source-lang (keywordify source-lang))))
                      (handler-case
                          (let ((result (translate-text text lang-keyword :source-lang source-keyword)))
                            (if (translation-result-error result)
                                (progn
                                  (setf (hunchentoot:return-code*) 400)
                                  (encode-api-response (make-api-error "TRANSLATION_FAILED" (translation-result-error result))))
                                (encode-api-response (make-api-response (list :translatedText (translation-result-translated-text result)
                                                                              :sourceLanguage (symbol-name (translation-result-source-language result))
                                                                              :targetLanguage target-lang
                                                                              :cached-p (translation-result-cached-p result)
                                                                              :confidence (translation-result-confidence result))))))
                        (error (c)
                          (setf (hunchentoot:return-code*) 500)
                          (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c)))))))))))))

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

;; DELETE /api/v1/friends/:id/delete - Delete friend
(defun api-delete-friend-handler ()
  "Delete a friend relationship"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (unless (string= (hunchentoot:request-method hunchentoot:*request*) "DELETE")
    (setf (hunchentoot:return-code*) 405)
    (return-from api-delete-friend-handler
      (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed"))))
  (let ((user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-delete-friend-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (let* ((uri (hunchentoot:request-uri hunchentoot:*request*))
           (friend-id (multiple-value-bind (match-start match-end reg-start reg-end)
                          (cl-ppcre:scan "^/api/v1/friends/([^/]+)/delete$" uri)
                        (if match-start
                            (subseq uri (aref reg-start 0) (aref reg-end 0))
                            (return-from api-delete-friend-handler
                              (encode-api-response (make-api-error "INVALID_URI" "Invalid friend ID")))))))
      (multiple-value-bind (success error)
          (delete-friend user-id friend-id)
        (if success
            (encode-api-response
             (make-api-response nil :message "Friend deleted"))
            (progn
              (setf (hunchentoot:return-code*) 400)
              (encode-api-response (make-api-error "DELETE_FAILED" error))))))))

;; GET /api/v1/users/search?q={query} - Search users
(defun api-search-users-handler ()
  "Search users by username or display name"
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

;;;; File Transfer API (Chunked Upload for Large Files)

;; POST /api/v1/files/upload/init - Initialize file transfer
(defun api-init-file-upload-handler ()
  "Initialize a chunked file upload session"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (unless (string= (hunchentoot:request-method hunchentoot:*request*) "POST")
    (setf (hunchentoot:return-code*) 405)
    (return-from api-init-file-upload-handler
      (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed"))))
  (let ((user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-init-file-upload-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (handler-case
        (let* ((json-str (get-request-body-string))
               (data (cl-json:decode-json-from-string json-str))
               (filename (cdr (assoc :filename data)))
               (file-size (cdr (assoc :fileSize data)))
               (file-type (cdr (assoc :fileType data)))
               (chunk-size (or (cdr (assoc :chunkSize data)) *chunk-size*))
               (recipient-id (cdr (assoc :recipientId data))))
          (unless (and filename file-size file-type)
            (setf (hunchentoot:return-code*) 400)
            (return-from api-init-file-upload-handler
              (encode-api-response (make-api-error "MISSING_FIELDS" "filename, fileSize, and fileType are required"))))
          (unless (<= file-size *max-file-size*)
            (setf (hunchentoot:return-code*) 413)
            (return-from api-init-file-upload-handler
              (encode-api-response (make-api-error "FILE_TOO_LARGE"
                        (format nil "File size exceeds maximum of ~a bytes" *max-file-size*)))))
          (let* ((file-id (generate-snowflake))
                 (transfer (init-file-transfer file-id filename file-size file-type user-id
                                               :chunk-size chunk-size :recipient-id recipient-id)))
            (encode-api-response
             (make-api-response
              (list :fileId file-id
                    :filename filename
                    :fileSize file-size
                    :fileType file-type
                    :chunkSize chunk-size
                    :totalChunks (file-transfer-total-chunks transfer)
                    :uploadUrl (format nil "/api/v1/files/upload/chunk?fileId=~a" file-id))
              :message "File transfer initialized"))))
      (error (c)
        (log-error "Init file upload error: ~A" c)
        (setf (hunchentoot:return-code*) 500)
        (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c)))))))

;; POST /api/v1/files/upload/chunk - Upload a file chunk
(defun api-upload-chunk-handler ()
  "Upload a single chunk of a file"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (unless (string= (hunchentoot:request-method hunchentoot:*request*) "POST")
    (setf (hunchentoot:return-code*) 405)
    (return-from api-upload-chunk-handler
      (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed"))))
  (let ((user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-upload-chunk-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (handler-case
        (let* ((json-str (get-request-body-string))
               (data (cl-json:decode-json-from-string json-str))
               (file-id (cdr (assoc :fileId data)))
               (chunk-index (cdr (assoc :chunkIndex data)))
               (chunk-data (cdr (assoc :chunkData data))) ; Base64 encoded chunk data
               (chunk-hash (cdr (assoc :chunkHash data))))
          (unless (and file-id chunk-index chunk-data)
            (setf (hunchentoot:return-code*) 400)
            (return-from api-upload-chunk-handler
              (encode-api-response (make-api-error "MISSING_FIELDS" "fileId, chunkIndex, and chunkData are required"))))
          (let* ((transfer (get-file-transfer file-id)))
            (unless transfer
              (setf (hunchentoot:return-code*) 404)
              (return-from api-upload-chunk-handler
                (encode-api-response (make-api-error "NOT_FOUND" "File transfer not found"))))
            (unless (string= (file-transfer-uploader-id transfer) user-id)
              (setf (hunchentoot:return-code*) 403)
              (return-from api-upload-chunk-handler
                (encode-api-response (make-api-error "FORBIDDEN" "Not authorized to upload to this file"))))
            ;; Decode base64 chunk data
            (let* ((chunk-bytes (cl-base64:base64-string-to-usb8-array chunk-data))
                   (chunk-size (length chunk-bytes))
                   (chunk-id (generate-chunk-id file-id chunk-index))
                   (storage-path (get-chunk-storage-path file-id chunk-index)))
              ;; Ensure directory exists
              (ensure-directories-exist storage-path)
              ;; Write chunk to disk
              (with-open-file (out storage-path :direction :output :if-exists :supersede
                                   :element-type '(unsigned-byte 8))
                (write-sequence chunk-bytes out))
              ;; Record chunk in database
              (record-file-chunk chunk-id file-id chunk-index chunk-size storage-path :chunk-hash chunk-hash)
              ;; Update Redis progress
              (update-upload-progress file-id (1+ (file-transfer-uploaded-chunks transfer))
                                     (file-transfer-total-chunks transfer))
              (encode-api-response
               (make-api-response
                (list :chunkId chunk-id
                      :chunkIndex chunk-index
                      :chunkSize chunk-size
                      :uploadedChunks (1+ (file-transfer-uploaded-chunks transfer))
                      :totalChunks (file-transfer-total-chunks transfer))
                :message (format nil "Chunk ~a uploaded" chunk-index))))))
      (error (c)
        (log-error "Upload chunk error: ~A" c)
        (setf (hunchentoot:return-code*) 500)
        (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c)))))))

;; POST /api/v1/files/upload/complete - Complete file upload
(defun api-complete-file-upload-handler ()
  "Complete file upload and merge chunks"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (unless (string= (hunchentoot:request-method hunchentoot:*request*) "POST")
    (setf (hunchentoot:return-code*) 405)
    (return-from api-complete-file-upload-handler
      (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed"))))
  (let ((user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-complete-file-upload-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (handler-case
        (let* ((json-str (get-request-body-string))
               (data (cl-json:decode-json-from-string json-str))
               (file-id (cdr (assoc :fileId data)))
               (file-hash (cdr (assoc :fileHash data))))
          (unless file-id
            (setf (hunchentoot:return-code*) 400)
            (return-from api-complete-file-upload-handler
              (encode-api-response (make-api-error "MISSING_FIELDS" "fileId is required"))))
          (let* ((transfer (get-file-transfer file-id)))
            (unless transfer
              (setf (hunchentoot:return-code*) 404)
              (return-from api-complete-file-upload-handler
                (encode-api-response (make-api-error "NOT_FOUND" "File transfer not found"))))
            (unless (= (file-transfer-uploaded-chunks transfer)
                       (file-transfer-total-chunks transfer))
              (setf (hunchentoot:return-code*) 400)
              (return-from api-complete-file-upload-handler
                (encode-api-response
                 (make-api-error "INCOMPLETE_UPLOAD"
                   (format nil "Only ~a/~a chunks uploaded"
                           (file-transfer-uploaded-chunks transfer)
                           (file-transfer-total-chunks transfer))))))
            ;; Get all chunk paths
            (let* ((uploaded-indices (get-uploaded-chunks file-id))
                   (chunk-paths (loop for idx in uploaded-indices
                                      collect (get-chunk-storage-path file-id idx)))
                   (output-path (get-file-storage-path file-id)))
              ;; Merge chunks
              (merge-file-chunks file-id chunk-paths output-path)
              ;; Calculate file hash if not provided
              (let ((final-hash (or file-hash (calculate-file-hash output-path))))
                ;; Update transfer status
                (update-file-transfer-status file-id :completed
                                            :file-hash final-hash
                                            :storage-path output-path)
                (encode-api-response
                 (make-api-response
                  (list :fileId file-id
                        :fileHash final-hash
                        :storagePath output-path
                        :downloadUrl (format nil "/api/v1/files/~a/download" file-id))
                  :message "File upload completed"))))))
      (error (c)
        (log-error "Complete file upload error: ~A" c)
        (setf (hunchentoot:return-code*) 500)
        (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c)))))))

;; GET /api/v1/files/upload/progress - Get upload progress
(defun api-get-upload-progress-handler ()
  "Get upload progress for a file"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (let* ((uri (hunchentoot:request-uri hunchentoot:*request*))
         (file-id (multiple-value-bind (match-start match-end reg-start reg-end)
                    (cl-ppcre:scan "^/api/v1/files/([^/]+)/progress$" uri)
                    (if match-start
                        (subseq uri (aref reg-start 0) (aref reg-end 0))
                        (return-from api-get-upload-progress-handler
                          (progn
                            (setf (hunchentoot:return-code*) 400)
                            (encode-api-response (make-api-error "INVALID_URI" "Invalid URI")))))))
         (user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-get-upload-progress-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (handler-case
        (let* ((transfer (get-file-transfer file-id)))
          (unless transfer
            (setf (hunchentoot:return-code*) 404)
            (return-from api-get-upload-progress-handler
              (encode-api-response (make-api-error "NOT_FOUND" "File transfer not found"))))
          (unless (string= (file-transfer-uploader-id transfer) user-id)
            (setf (hunchentoot:return-code*) 403)
            (return-from api-get-upload-progress-handler
              (encode-api-response (make-api-error "FORBIDDEN" "Not authorized"))))
          (multiple-value-bind (uploaded total)
              (get-upload-progress file-id)
            (encode-api-response
             (make-api-response
              (list :fileId file-id
                    :uploadedChunks uploaded
                    :totalChunks total
                    :progress (if (> total 0) (floor (* 100 uploaded total)) 0))))))
      (error (c)
        (log-error "Get upload progress error: ~A" c)
        (setf (hunchentoot:return-code*) 500)
        (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c)))))))

;; GET /api/v1/files/{file-id}/download - Download file
(defun api-download-file-handler ()
  "Download a file by ID"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (let* ((uri (hunchentoot:request-uri hunchentoot:*request*))
         (file-id (multiple-value-bind (match-start match-end reg-start reg-end)
                    (cl-ppcre:scan "^/api/v1/files/([^/]+)/download$" uri)
                    (if match-start
                        (subseq uri (aref reg-start 0) (aref reg-end 0))
                        (return-from api-download-file-handler
                          (progn
                            (setf (hunchentoot:return-code*) 400)
                            (encode-api-response (make-api-error "INVALID_URI" "Invalid URI")))))))
         (user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-download-file-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (handler-case
        (let* ((transfer (get-file-transfer file-id)))
          (unless transfer
            (setf (hunchentoot:return-code*) 404)
            (return-from api-download-file-handler
              (encode-api-response (make-api-error "NOT_FOUND" "File not found"))))
          (unless (eq (file-transfer-status transfer) :completed)
            (setf (hunchentoot:return-code*) 400)
            (return-from api-download-file-handler
              (encode-api-response (make-api-error "NOT_READY" "File upload not completed"))))
          (let ((storage-path (get-file-storage-path file-id)))
            (unless (probe-file storage-path)
              (setf (hunchentoot:return-code*) 404)
              (return-from api-download-file-handler
                (encode-api-response (make-api-error "NOT_FOUND" "File not found on disk"))))
            ;; Set headers for file download
            (setf (hunchentoot:content-type*) (file-transfer-file-type transfer))
            (setf (hunchentoot:header-out "Content-Disposition")
                  (format nil "attachment; filename=\"~a\"" (file-transfer-filename transfer)))
            ;; Read file data and return as binary
            (let ((file-data (with-open-file (s storage-path :direction :input :element-type '(unsigned-byte 8))
                               (let ((data (make-array (file-length s) :element-type '(unsigned-byte 8))))
                                 (read-sequence data s)
                                 data))))
              (setf (hunchentoot:header-out "Content-Length") (length file-data))
              file-data)
            nil))
      (error (c)
        (log-error "Download file error: ~A" c)
        (setf (hunchentoot:return-code*) 500)
        (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c)))))))

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

;;;; ============================================================================
;;;; Notification Preferences API (通知偏好设置)
;;;; ============================================================================

;; GET /api/v1/notifications/preferences - Get notification preferences
(defun api-get-notification-preferences-handler ()
  "Get current user's notification preferences"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (unless (string= (hunchentoot:request-method hunchentoot:*request*) "GET")
    (setf (hunchentoot:return-code*) 405)
    (return-from api-get-notification-preferences-handler
      (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed"))))
  (let ((user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-get-notification-preferences-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (handler-case
        (let ((prefs (get-notification-preferences user-id)))
          (encode-api-response
           (make-api-response
            `((:success . t)
              (:data . ((:enableDesktop . ,(notification-preferences-enable-desktop prefs))
                        (:enableSound . ,(notification-preferences-enable-sound prefs))
                        (:enableBadge . ,(notification-preferences-enable-badge prefs))
                        (:messageNotifications . ,(notification-preferences-message-notifications prefs))
                        (:callNotifications . ,(notification-preferences-call-notifications prefs))
                        (:friendRequestNotifications . ,(notification-preferences-friend-request-notifications prefs))
                        (:groupNotifications . ,(notification-preferences-group-notifications prefs))
                        (:quietMode . ,(notification-preferences-quiet-mode prefs))
                        (:quietStart . ,(notification-preferences-quiet-start prefs))
                        (:quietEnd . ,(notification-preferences-quiet-end prefs))))))))
      (error (c)
        (log-error "Get notification preferences error: ~A" c)
        (setf (hunchentoot:return-code*) 500)
        (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c)))))))

;; PUT /api/v1/notifications/preferences - Update notification preferences
(defun api-update-notification-preferences-handler ()
  "Update current user's notification preferences"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (unless (string= (hunchentoot:request-method hunchentoot:*request*) "PUT")
    (setf (hunchentoot:return-code*) 405)
    (return-from api-update-notification-preferences-handler
      (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed"))))
  (let ((user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-update-notification-preferences-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (handler-case
        (let* ((json-str (get-request-body-string))
               (data (cl-json:decode-json-from-string json-str))
               (enable-desktop (cdr (assoc :enableDesktop data)))
               (enable-sound (cdr (assoc :enableSound data)))
               (enable-badge (cdr (assoc :enableBadge data)))
               (message-notifications (cdr (assoc :messageNotifications data)))
               (call-notifications (cdr (assoc :callNotifications data)))
               (friend-request-notifications (cdr (assoc :friendRequestNotifications data)))
               (group-notifications (cdr (assoc :groupNotifications data)))
               (quiet-mode (cdr (assoc :quietMode data)))
               (quiet-start (cdr (assoc :quietStart data)))
               (quiet-end (cdr (assoc :quietEnd data))))
          (set-notification-preferences
           user-id
           :enable-desktop enable-desktop
           :enable-sound enable-sound
           :enable-badge enable-badge
           :message-notifications message-notifications
           :call-notifications call-notifications
           :friend-request-notifications friend-request-notifications
           :group-notifications group-notifications
           :quiet-mode quiet-mode
           :quiet-start quiet-start
           :quiet-end quiet-end)
          (encode-api-response
           (make-api-response `((:success . t)))))
      (error (c)
        (log-error "Update notification preferences error: ~A" c)
        (setf (hunchentoot:return-code*) 500)
        (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c)))))))

;;;; ============================================================================
;;;; User Notifications API (用户通知列表)
;;;; ============================================================================

;; GET /api/v1/notifications - Get user notifications
(defun api-get-notifications-handler ()
  "Get current user's notifications"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (unless (string= (hunchentoot:request-method hunchentoot:*request*) "GET")
    (setf (hunchentoot:return-code*) 405)
    (return-from api-get-notifications-handler
      (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed"))))
  (let ((user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-get-notifications-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (handler-case
        (let* ((limit-str (hunchentoot:get-parameter "limit"))
               (limit (if limit-str (parse-integer limit-str :junk-allowed t) 50))
               (unread-only (string= (hunchentoot:get-parameter "unread") "true"))
               (notifications (get-user-notifications user-id :limit limit :unread-only unread-only)))
          (encode-api-response
           (make-api-response
            `((:success . t)
              (:data . ,notifications)))))
      (error (c)
        (log-error "Get notifications error: ~A" c)
        (setf (hunchentoot:return-code*) 500)
        (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c)))))))

;; POST /api/v1/notifications/:id/read - Mark notification as read
(defun api-mark-notification-read-handler ()
  "Mark notification as read"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (unless (string= (hunchentoot:request-method hunchentoot:*request*) "POST")
    (setf (hunchentoot:return-code*) 405)
    (return-from api-mark-notification-read-handler
      (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed"))))
  (let ((user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-mark-notification-read-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (handler-case
        (let ((notification-id (parse-integer (hunchentoot:path-parameter 1) :junk-allowed t)))
          (mark-notification-read notification-id user-id)
          (encode-api-response
           (make-api-response `((:success . t)))))
      (error (c)
        (log-error "Mark notification read error: ~A" c)
        (setf (hunchentoot:return-code*) 500)
        (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c)))))))

;; POST /api/v1/notifications/read-all - Mark all notifications as read
(defun api-mark-all-notifications-read-handler ()
  "Mark all notifications as read"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (unless (string= (hunchentoot:request-method hunchentoot:*request*) "POST")
    (setf (hunchentoot:return-code*) 405)
    (return-from api-mark-all-notifications-read-handler
      (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed"))))
  (let ((user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-mark-all-notifications-read-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (handler-case
        (progn
          (mark-all-notifications-read user-id)
          (encode-api-response
           (make-api-response `((:success . t)))))
      (error (c)
        (log-error "Mark all notifications read error: ~A" c)
        (setf (hunchentoot:return-code*) 500)
        (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c)))))))

;;;; ============================================================================
;;;; Group Polls API (群投票)
;;;; ============================================================================

;; GET /api/v1/groups/:id/polls - Get group polls
(defun api-get-group-polls-handler ()
  "Get polls for a group"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (unless (string= (hunchentoot:request-method hunchentoot:*request*) "GET")
    (setf (hunchentoot:return-code*) 405)
    (return-from api-get-group-polls-handler
      (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed"))))
  (let ((user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-get-group-polls-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (handler-case
        (let* ((group-id (parse-integer (hunchentoot:path-parameter 1) :junk-allowed t))
               (status (or (hunchentoot:get-parameter "status") "active"))
               (polls (get-group-polls group-id :status status)))
          (encode-api-response
           (make-api-response
            `((:success . t)
              (:data . ,polls)))))
      (error (c)
        (log-error "Get group polls error: ~A" c)
        (setf (hunchentoot:return-code*) 500)
        (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c)))))))

;; POST /api/v1/groups/:id/polls - Create a new poll
(defun api-create-poll-handler ()
  "Create a new poll in a group"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (unless (string= (hunchentoot:request-method hunchentoot:*request*) "POST")
    (setf (hunchentoot:return-code*) 405)
    (return-from api-create-poll-handler
      (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed"))))
  (let ((user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-create-poll-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (handler-case
        (let* ((group-id (parse-integer (hunchentoot:path-parameter 1) :junk-allowed t))
               (json-str (get-request-body-string))
               (data (cl-json:decode-json-from-string json-str))
               (title (cdr (assoc :title data)))
               (description (cdr (assoc :description data)))
               (options (cdr (assoc :options data)))
               (multiple-choice (cdr (assoc :multipleChoice data)))
               (allow-suggestions (cdr (assoc :allowSuggestions data)))
               (anonymous-voting (cdr (assoc :anonymousVoting data)))
               (end-at (cdr (assoc :endAt data))))
          (unless title
            (setf (hunchentoot:return-code*) 400)
            (return-from api-create-poll-handler
              (encode-api-response (make-api-error "MISSING_FIELDS" "title is required"))))
          (let ((poll (create-poll group-id title user-id
                                   :description description
                                   :multiple-choice multiple-choice
                                   :allow-suggestions allow-suggestions
                                   :anonymous-voting anonymous-voting
                                   :end-at end-at
                                   :options options)))
            (encode-api-response
             (make-api-response
              `((:success . t)
                (:data . ,poll)))))
      (error (c)
        (log-error "Create poll error: ~A" c)
        (setf (hunchentoot:return-code*) 500)
        (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c)))))))

;; GET /api/v1/polls/:id - Get poll details and results
(defun api-get-poll-handler ()
  "Get poll details and results"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (unless (string= (hunchentoot:request-method hunchentoot:*request*) "GET")
    (setf (hunchentoot:return-code*) 405)
    (return-from api-get-poll-handler
      (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed"))))
  (let ((user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-get-poll-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (handler-case
        (let ((poll-id (parse-integer (hunchentoot:path-parameter 1) :junk-allowed t)))
          (let ((poll (get-poll poll-id)))
            (if poll
                (encode-api-response
                 (make-api-response
                  `((:success . t)
                    (:data . ,poll))))
                (progn
                  (setf (hunchentoot:return-code*) 404)
                  (encode-api-response (make-api-error "NOT_FOUND" "Poll not found"))))))
      (error (c)
        (log-error "Get poll error: ~A" c)
        (setf (hunchentoot:return-code*) 500)
        (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c)))))))

;; POST /api/v1/polls/:id/vote - Cast a vote
(defun api-cast-vote-handler ()
  "Cast a vote in a poll"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (unless (string= (hunchentoot:request-method hunchentoot:*request*) "POST")
    (setf (hunchentoot:return-code*) 405)
    (return-from api-cast-vote-handler
      (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed"))))
  (let ((user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-cast-vote-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (handler-case
        (let* ((poll-id (parse-integer (hunchentoot:path-parameter 1) :junk-allowed t))
               (json-str (get-request-body-string))
               (data (cl-json:decode-json-from-string json-str))
               (option-id (cdr (assoc :optionId data))))
          (unless option-id
            (setf (hunchentoot:return-code*) 400)
            (return-from api-cast-vote-handler
              (encode-api-response (make-api-error "MISSING_FIELDS" "optionId is required"))))
          (cast-vote poll-id option-id user-id)
          (encode-api-response
           (make-api-response `((:success . t))))
      (error (c)
        (log-error "Cast vote error: ~A" c)
        (setf (hunchentoot:return-code*) 500)
        (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c)))))))

;; POST /api/v1/polls/:id/end - End a poll
(defun api-end-poll-handler ()
  "End a poll"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (unless (string= (hunchentoot:request-method hunchentoot:*request*) "POST")
    (setf (hunchentoot:return-code*) 405)
    (return-from api-end-poll-handler
      (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed"))))
  (let ((user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-end-poll-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (handler-case
        (let ((poll-id (parse-integer (hunchentoot:path-parameter 1) :junk-allowed t)))
          (end-poll poll-id user-id)
          (encode-api-response
           (make-api-response `((:success . t))))
      (error (c)
        (log-error "End poll error: ~A" c)
        (setf (hunchentoot:return-code*) 500)
        (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c)))))))

;;;; ============================================================================
;;;; Group DND (Do Not Disturb) API (群消息免打扰)
;;;; ============================================================================

;; POST /api/v1/conversations/:id/mute - Mute a conversation
(defun api-mute-conversation-handler ()
  "Mute a conversation (group chat DND)"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (unless (string= (hunchentoot:request-method hunchentoot:*request*) "POST")
    (setf (hunchentoot:return-code*) 405)
    (return-from api-mute-conversation-handler
      (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed"))))
  (let ((user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-mute-conversation-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (handler-case
        (let* ((conversation-id (parse-integer (hunchentoot:path-parameter 1) :junk-allowed t))
               (json-str (get-request-body-string))
               (data (if (and json-str (not (string= json-str "")))
                         (cl-json:decode-json-from-string json-str)
                         nil))
               (duration (cdr (assoc :duration data)))
               (enabled (cdr (assoc :enabled data))))
          (if enabled
              (mute-conversation conversation-id user-id duration)
              (unmute-conversation conversation-id user-id))
          (encode-api-response
           (make-api-response `((:success . t)))))
      (error (c)
        (log-error "Mute conversation error: ~A" c)
        (setf (hunchentoot:return-code*) 500)
        (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c)))))))

;; GET /api/v1/conversations/muted - Get muted conversations
(defun api-get-muted-conversations-handler ()
  "Get list of muted conversations"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (unless (string= (hunchentoot:request-method hunchentoot:*request*) "GET")
    (setf (hunchentoot:return-code*) 405)
    (return-from api-get-muted-conversations-handler
      (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed"))))
  (let ((user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-get-muted-conversations-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (handler-case
        (let ((muted (get-muted-conversations user-id)))
          (encode-api-response
           (make-api-response
            `((:success . t)
              (:data . ,muted)))))
      (error (c)
        (log-error "Get muted conversations error: ~A" c)
        (setf (hunchentoot:return-code*) 500)
        (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c)))))))

;; GET /api/v1/conversations/:id/mute-status - Get conversation mute status
(defun api-get-conversation-mute-status-handler ()
  "Get mute status for a conversation"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (unless (string= (hunchentoot:request-method hunchentoot:*request*) "GET")
    (setf (hunchentoot:return-code*) 405)
    (return-from api-get-conversation-mute-status-handler
      (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed"))))
  (let ((user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-get-conversation-mute-status-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (handler-case
        (let ((conversation-id (parse-integer (hunchentoot:path-parameter 1) :junk-allowed t))
              (muted (is-conversation-muted conversation-id user-id)))
          (encode-api-response
           (make-api-response
            `((:success . t)
              (:data . ((:muted . ,muted))))))
      (error (c)
        (log-error "Get mute status error: ~A" c)
        (setf (hunchentoot:return-code*) 500)
        (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c)))))))

;;;; ============================================================================
;;;; Message Forwarding API (消息转发)
;;;; ============================================================================

;; POST /api/v1/messages/:id/forward - Forward a message
(defun api-forward-message-handler ()
  "Forward a message to another conversation"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (unless (string= (hunchentoot:request-method hunchentoot:*request*) "POST")
    (setf (hunchentoot:return-code*) 405)
    (return-from api-forward-message-handler
      (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed"))))
  (let ((user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-forward-message-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (handler-case
        (let* ((message-id (parse-integer (hunchentoot:path-parameter 1) :junk-allowed t))
               (json-str (get-request-body-string))
               (data (cl-json:decode-json-from-string json-str))
               (conversation-id (cdr (assoc :conversationId data)))
               (comment (cdr (assoc :comment data))))
          (unless conversation-id
            (setf (hunchentoot:return-code*) 400)
            (return-from api-forward-message-handler
              (encode-api-response (make-api-error "MISSING_FIELDS" "conversationId is required"))))
          (let ((new-id (forward-message message-id conversation-id comment)))
            (encode-api-response
             (make-api-response
              `((:success . t)
                (:data . ((:messageId . ,new-id)))))))
      (error (c)
        (log-error "Forward message error: ~A" c)
        (setf (hunchentoot:return-code*) 500)
        (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c)))))))

;; POST /api/v1/messages/forward-batch - Forward multiple messages
(defun api-forward-messages-batch-handler ()
  "Forward multiple messages to another conversation"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (unless (string= (hunchentoot:request-method hunchentoot:*request*) "POST")
    (setf (hunchentoot:return-code*) 405)
    (return-from api-forward-messages-batch-handler
      (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed"))))
  (let ((user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-forward-messages-batch-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (handler-case
        (let* ((json-str (get-request-body-string))
               (data (cl-json:decode-json-from-string json-str))
               (message-ids (cdr (assoc :messageIds data)))
               (conversation-id (cdr (assoc :conversationId data)))
               (comment (cdr (assoc :comment data))))
          (unless (and message-ids conversation-id)
            (setf (hunchentoot:return-code*) 400)
            (return-from api-forward-messages-batch-handler
              (encode-api-response (make-api-error "MISSING_FIELDS" "messageIds and conversationId are required"))))
          (let ((new-ids (forward-messages message-ids conversation-id comment)))
            (encode-api-response
             (make-api-response
              `((:success . t)
                (:data . ((:messageIds . ,new-ids)))))))
      (error (c)
        (log-error "Forward messages batch error: ~A" c)
        (setf (hunchentoot:return-code*) 500)
        (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c)))))))

;; GET /api/v1/messages/:id/forward-count - Get forward count
(defun api-get-message-forward-count-handler ()
  "Get forward count for a message"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (unless (string= (hunchentoot:request-method hunchentoot:*request*) "GET")
    (setf (hunchentoot:return-code*) 405)
    (return-from api-get-message-forward-count-handler
      (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed"))))
  (handler-case
      (let ((message-id (parse-integer (hunchentoot:path-parameter 1) :junk-allowed t))
            (count (get-message-forward-count message-id)))
        (encode-api-response
         (make-api-response
          `((:success . t)
            (:data . ((:count . ,(or count 0)))))))
    (error (c)
      (log-error "Get forward count error: ~A" c)
      (setf (hunchentoot:return-code*) 500)
      (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c)))))))

;; GET /api/v1/messages/:id/origin - Get forwarded message origin
(defun api-get-forwarded-message-origin-handler ()
  "Get origin information for a forwarded message"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (unless (string= (hunchentoot:request-method hunchentoot:*request*) "GET")
    (setf (hunchentoot:return-code*) 405)
    (return-from api-get-forwarded-message-origin-handler
      (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed"))))
  (handler-case
      (let ((message-id (parse-integer (hunchentoot:path-parameter 1) :junk-allowed t))
            (origin (get-forwarded-message-origin message-id)))
        (if origin
            (encode-api-response
             (make-api-response
              `((:success . t)
                (:data . ,origin))))
            (progn
              (setf (hunchentoot:return-code*) 404)
              (encode-api-response (make-api-error "NOT_FOUND" "Message is not forwarded")))))
    (error (c)
      (log-error "Get forwarded origin error: ~A" c)
      (setf (hunchentoot:return-code*) 500)
      (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c)))))))

;;;; ============================================================================
;;;; Highlight Messages API (群精华消息)
;;;; ============================================================================

;; POST /api/v1/conversations/:id/highlights - Add highlighted message
(defun api-add-highlighted-message-handler ()
  "Add a message to highlights"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (unless (string= (hunchentoot:request-method hunchentoot:*request*) "POST")
    (setf (hunchentoot:return-code*) 405)
    (return-from api-add-highlighted-message-handler
      (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed"))))
  (let ((user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-add-highlighted-message-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (handler-case
        (let* ((conversation-id (parse-integer (hunchentoot:path-parameter 1) :junk-allowed t))
               (json-str (get-request-body-string))
               (data (cl-json:decode-json-from-string json-str))
               (message-id (cdr (assoc :messageId data)))
               (note (cdr (assoc :note data))))
          (unless message-id
            (setf (hunchentoot:return-code*) 400)
            (return-from api-add-highlighted-message-handler
              (encode-api-response (make-api-error "MISSING_FIELDS" "messageId is required"))))
          (let ((highlight-id (add-highlighted-message message-id conversation-id user-id note)))
            (encode-api-response
             (make-api-response
              `((:success . t)
                (:data . ((:highlightId . ,highlight-id)))))))
      (error (c)
        (log-error "Add highlighted message error: ~A" c)
        (setf (hunchentoot:return-code*) 500)
        (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c)))))))

;; GET /api/v1/conversations/:id/highlights - Get highlighted messages
(defun api-get-highlighted-messages-handler ()
  "Get highlighted messages for a conversation"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (unless (string= (hunchentoot:request-method hunchentoot:*request*) "GET")
    (setf (hunchentoot:return-code*) 405)
    (return-from api-get-highlighted-messages-handler
      (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed"))))
  (handler-case
      (let ((conversation-id (parse-integer (hunchentoot:path-parameter 1) :junk-allowed t))
            (highlights (get-highlighted-messages conversation-id)))
        (encode-api-response
         (make-api-response
          `((:success . t)
            (:data . ,highlights)))))
    (error (c)
      (log-error "Get highlighted messages error: ~A" c)
      (setf (hunchentoot:return-code*) 500)
      (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c)))))))

;; DELETE /api/v1/highlights/:id - Remove highlighted message
(defun api-remove-highlighted-message-handler ()
  "Remove a message from highlights"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (unless (string= (hunchentoot:request-method hunchentoot:*request*) "DELETE")
    (setf (hunchentoot:return-code*) 405)
    (return-from api-remove-highlighted-message-handler
      (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed"))))
  (let ((user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-remove-highlighted-message-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (handler-case
        (let ((highlight-id (parse-integer (hunchentoot:path-parameter 1) :junk-allowed t)))
          (remove-highlighted-message highlight-id user-id)
          (encode-api-response
           (make-api-response `((:success . t)))))
      (error (c)
        (log-error "Remove highlighted message error: ~A" c)
        (setf (hunchentoot:return-code*) 500)
        (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c)))))))

;;;; Link Preview API (链接预览)

;; POST /api/v1/links/preview - Generate preview for a URL
(defun api-generate-link-preview-handler ()
  "Generate link preview for a URL"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (unless (string= (hunchentoot:request-method hunchentoot:*request*) "POST")
    (setf (hunchentoot:return-code*) 405)
    (return-from api-generate-link-preview-handler
      (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed"))))
  (let ((user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-generate-link-preview-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (let* ((body-str (get-request-body-string))
           (body (when body-str (cl-json:decode-json-from-string body-str))))
      (unless body
        (setf (hunchentoot:return-code*) 400)
        (return-from api-generate-link-preview-handler
          (encode-api-response (make-api-error "INVALID_JSON" "Invalid JSON body"))))
      (let* ((url (cdr (assoc :url body))))
        (unless url
          (setf (hunchentoot:return-code*) 400)
          (return-from api-generate-link-preview-handler
            (encode-api-response (make-api-error "MISSING_FIELDS" "URL is required"))))
        (handler-case
            (let ((preview (generate-link-preview url)))
              (encode-api-response (make-api-response preview)))
          (error (c)
            (log-error "Generate link preview error: ~A" c)
            (setf (hunchentoot:return-code*) 500)
            (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c)))))))))

;; GET /api/v1/links/preview?url={url} - Get link preview (cached or fetch)
(defun api-get-link-preview-handler ()
  "Get link preview (from cache or fetch)"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (let ((user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-get-link-preview-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (let* ((url (hunchentoot:get-parameter "url")))
      (unless url
        (setf (hunchentoot:return-code*) 400)
        (return-from api-get-link-preview-handler
          (encode-api-response (make-api-error "MISSING_FIELDS" "URL parameter 'url' is required"))))
      (handler-case
          (let ((preview (get-link-preview url)))
            (encode-api-response (make-api-response preview)))
          (error (c)
            (log-error "Get link preview error: ~A" c)
            (setf (hunchentoot:return-code*) 500)
            (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c))))))))

;; POST /api/v1/links/extract - Extract all link previews from text
(defun api-extract-link-previews-handler ()
  "Extract all link previews from text"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (unless (string= (hunchentoot:request-method hunchentoot:*request*) "POST")
    (setf (hunchentoot:return-code*) 405)
    (return-from api-extract-link-previews-handler
      (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed"))))
  (let ((user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-extract-link-previews-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (let* ((body-str (get-request-body-string))
           (body (when body-str (cl-json:decode-json-from-string body-str))))
      (unless body
        (setf (hunchentoot:return-code*) 400)
        (return-from api-extract-link-previews-handler
          (encode-api-response (make-api-error "INVALID_JSON" "Invalid JSON body"))))
      (let* ((text (cdr (assoc :text body))))
        (unless text
          (setf (hunchentoot:return-code*) 400)
          (return-from api-extract-link-previews-handler
            (encode-api-response (make-api-error "MISSING_FIELDS" "Text is required"))))
        (handler-case
            (let ((previews (extract-link-previews text)))
              (encode-api-response (make-api-response `((:previews . ,previews)))))
          (error (c)
            (log-error "Extract link previews error: ~A" c)
            (setf (hunchentoot:return-code*) 500)
            (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c)))))))))

;; DELETE /api/v1/links/preview?url={url} - Invalidate link preview cache
(defun api-invalidate-link-preview-handler ()
  "Invalidate link preview cache for a URL"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (unless (string= (hunchentoot:request-method hunchentoot:*request*) "DELETE")
    (setf (hunchentoot:return-code*) 405)
    (return-from api-invalidate-link-preview-handler
      (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed"))))
  (let ((user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-invalidate-link-preview-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (let* ((url (hunchentoot:get-parameter "url")))
      (unless url
        (setf (hunchentoot:return-code*) 400)
        (return-from api-invalidate-link-preview-handler
          (encode-api-response (make-api-error "MISSING_FIELDS" "URL parameter 'url' is required"))))
      (handler-case
          (let ((success (invalidate-link-preview url)))
            (encode-api-response (make-api-response `((:success . ,success)))))
          (error (c)
            (log-error "Invalidate link preview error: ~A" c)
            (setf (hunchentoot:return-code*) 500)
            (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c))))))))

;;;; Fulltext Search API

;; GET /api/v1/search?q={query}&type={type}&limit={limit} - Search messages, contacts, conversations
(defun api-search-handler ()
  "Search messages, contacts, or conversations"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (let ((user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-search-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (let* ((query (hunchentoot:get-parameter "q"))
           (type (or (hunchentoot:get-parameter "type") "all"))
           (limit (parse-integer (or (hunchentoot:get-parameter "limit") "20") :junk-allowed t))
           (conversation-id (hunchentoot:get-parameter "conversationId")))
      (unless query
        (setf (hunchentoot:return-code*) 400)
        (return-from api-search-handler
          (encode-api-response (make-api-error "MISSING_FIELDS" "Query parameter 'q' is required"))))
      (handler-case
          (let* ((search-type (keywordify type))
                 (results (fulltext-search user-id query
                                           :type search-type
                                           :limit limit
                                           :conversation-id conversation-id)))
            (encode-api-response (make-api-response results)))
        (error (c)
          (log-error "Search error: ~A" c)
          (setf (hunchentoot:return-code*) 500)
          (encode-api-response (make-api-error "SEARCH_FAILED" (format nil "~A" c))))))))

;;;; Message Reply API

;; POST /api/v1/messages/:id/reply - Send reply message
(defun api-reply-message-handler ()
  "Send reply message"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (unless (string= (hunchentoot:request-method hunchentoot:*request*) "POST")
    (setf (hunchentoot:return-code*) 405)
    (return-from api-reply-message-handler
      (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed"))))
  (let ((user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-reply-message-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (let* ((uri (hunchentoot:request-uri hunchentoot:*request*))
           (message-id (multiple-value-bind (match-start match-end reg-start reg-end)
                         (cl-ppcre:scan "^/api/v1/messages/([^/]+)/reply$" uri)
                         (if match-start
                             (subseq uri (aref reg-start 0) (aref reg-end 0))
                             (return-from api-reply-message-handler
                               (progn
                                 (setf (hunchentoot:return-code*) 400)
                                 (encode-api-response (make-api-error "INVALID_URI" "Invalid message URI")))))))
           (body-str (get-request-body-string))
           (body (cl-json:decode-json-from-string body-str)))
      (log-info "Reply body str: ~A" body-str)
      (log-info "Reply body decoded: ~A" body)
      (let* ((content (cdr (assoc :content body)))
             (conversation-id (cdr (assoc :conversation-id body)))
             (quote-content (cdr (assoc :quote-content body)))
             (quote-type (or (cdr (assoc :quote-type body)) "text"))
             (message-type (or (cdr (assoc :message-type body)) "text")))
        (log-info "Parsed content: ~A, conversation-id: ~A" content conversation-id)
        (unless (and content conversation-id)
          (setf (hunchentoot:return-code*) 400)
          (return-from api-reply-message-handler
            (encode-api-response (make-api-error "MISSING_FIELDS" "Content and conversationId are required"))))
        (handler-case
            (let* ((reply-id (create-message-reply message-id content
                                                   :sender-id user-id
                                                   :conversation-id conversation-id
                                                   :quote-content quote-content
                                                   :quote-type quote-type)))
              (encode-api-response
               (make-api-response (list :messageId reply-id)
                                  :message "Reply sent successfully")))
          (error (c)
            (log-error "Reply message error: ~A" c)
            (setf (hunchentoot:return-code*) 500)
            (encode-api-response (make-api-error "REPLY_FAILED" (format nil "~A" c)))))))))

;; GET /api/v1/messages/:id/replies?limit={limit} - Get message replies
(defun api-get-replies-handler ()
  "Get message replies"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (let ((user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-get-replies-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (let* ((uri (hunchentoot:request-uri hunchentoot:*request*))
           (message-id (multiple-value-bind (match-start match-end reg-start reg-end)
                         (cl-ppcre:scan "^/api/v1/messages/([^/]+)/replies$" uri)
                         (if match-start
                             (subseq uri (aref reg-start 0) (aref reg-end 0))
                             (return-from api-get-replies-handler
                               (progn
                                 (setf (hunchentoot:return-code*) 400)
                                 (encode-api-response (make-api-error "INVALID_URI" "Invalid message URI")))))))
           (limit (parse-integer (or (hunchentoot:get-parameter "limit") "100") :junk-allowed t)))
      (handler-case
          (let ((replies (get-message-replies message-id :limit limit)))
            (encode-api-response
             (make-api-response (list :replies replies
                                      :count (length replies)))))
        (error (c)
          (log-error "Get replies error: ~A" c)
          (setf (hunchentoot:return-code*) 500)
          (encode-api-response (make-api-error "GET_REPLIES_FAILED" (format nil "~A" c))))))))

;; GET /api/v1/messages/:id/reply-chain - Get reply chain
(defun api-get-reply-chain-handler ()
  "Get reply chain from root to message"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (let ((user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-get-reply-chain-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (let* ((uri (hunchentoot:request-uri hunchentoot:*request*))
           (message-id (multiple-value-bind (match-start match-end reg-start reg-end)
                         (cl-ppcre:scan "^/api/v1/messages/([^/]+)/reply-chain$" uri)
                         (if match-start
                             (subseq uri (aref reg-start 0) (aref reg-end 0))
                             (return-from api-get-reply-chain-handler
                               (progn
                                 (setf (hunchentoot:return-code*) 400)
                                 (encode-api-response (make-api-error "INVALID_URI" "Invalid message URI"))))))))
      (handler-case
          (let ((chain (get-reply-chain message-id)))
            (encode-api-response
             (make-api-response (list :chain chain
                                      :length (length chain)))))
        (error (c)
          (log-error "Get reply chain error: ~A" c)
          (setf (hunchentoot:return-code*) 500)
          (encode-api-response (make-api-error "GET_CHAIN_FAILED" (format nil "~A" c))))))))

;; GET /api/v1/threads/:root-id - Get thread info
(defun api-get-thread-handler ()
  "Get thread information"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (let ((user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-get-thread-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (let* ((uri (hunchentoot:request-uri hunchentoot:*request*))
           (root-id (multiple-value-bind (match-start match-end reg-start reg-end)
                      (cl-ppcre:scan "^/api/v1/threads/([^/]+)$" uri)
                      (if match-start
                          (subseq uri (aref reg-start 0) (aref reg-end 0))
                          (return-from api-get-thread-handler
                            (progn
                              (setf (hunchentoot:return-code*) 400)
                              (encode-api-response (make-api-error "INVALID_URI" "Invalid thread URI"))))))))
      (handler-case
          (let ((thread (get-reply-thread root-id)))
            (encode-api-response
             (make-api-response (list :thread thread)))))
        (error (c)
          (log-error "Get thread error: ~A" c)
          (setf (hunchentoot:return-code*) 500)
          (encode-api-response (make-api-error "GET_THREAD_FAILED" (format nil "~A" c)))))))

;;; End of gateway.lisp

;;;; QR Code API Handlers (扫一扫功能)

;; POST /api/v1/qr/generate - Generate QR code for user profile
(defun api-generate-qr-handler ()
  "Generate QR code for current user"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (unless (string= (hunchentoot:request-method hunchentoot:*request*) "POST")
    (setf (hunchentoot:return-code*) 405)
    (return-from api-generate-qr-handler
      (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed"))))
  (let ((user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-generate-qr-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (let ((user (get-user user-id)))
      (unless user
        (setf (hunchentoot:return-code*) 404)
        (return-from api-generate-qr-handler
          (encode-api-response (make-api-error "NOT_FOUND" "User not found"))))
      (let ((username (getf user :username))
            (display-name (getf user :display-name)))
        (multiple-value-bind (qr-json qr-data)
            (generate-qr-code user-id username)
          (encode-api-response
           (make-api-response
            (list :qrData qr-data
                  :qrJson qr-json
                  :username username
                  :displayName display-name))))))))

;; POST /api/v1/qr/scan - Scan and decode QR code
(defun api-scan-qr-handler ()
  "Decode and verify QR code"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (unless (string= (hunchentoot:request-method hunchentoot:*request*) "POST")
    (setf (hunchentoot:return-code*) 405)
    (return-from api-scan-qr-handler
      (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed"))))
  (let ((user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-scan-qr-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (let* ((json-str (get-request-body-string))
           (data (cl-json:decode-json-from-string json-str))
           (qr-json (cdr (assoc :qr-json data))))
      (unless qr-json
        (setf (hunchentoot:return-code*) 400)
        (return-from api-scan-qr-handler
          (encode-api-response (make-api-error "MISSING_FIELDS" "qrJson is required"))))
      (multiple-value-bind (result error)
          (decode-and-verify-qr qr-json)
        (if result
            (let* ((scanned-user-id (getf result :user-id))
                   (scanned-user (get-user scanned-user-id)))
              (if scanned-user
                  (encode-api-response
                   (make-api-response
                    (list :success t
                          :type (getf data :|type|)
                          :user (list :id (getf scanned-user :id)
                                      :username (getf scanned-user :username)
                                      :displayName (getf scanned-user :display-name)
                                      :avatar (or (getf scanned-user :avatar-url) "")))))
                  (progn
                    (setf (hunchentoot:return-code*) 404)
                    (encode-api-response (make-api-error "NOT_FOUND" "User not found")))))
            (progn
              (setf (hunchentoot:return-code*) 400)
              (encode-api-response (make-api-error "INVALID_QR" (format nil "Invalid QR code: ~A" error)))))))))

;; POST /api/v1/qr/scan-image - Scan QR code from uploaded image
(defun api-scan-qr-image-handler ()
  "Decode QR code from uploaded image URL"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (unless (string= (hunchentoot:request-method hunchentoot:*request*) "POST")
    (setf (hunchentoot:return-code*) 405)
    (return-from api-scan-qr-image-handler
      (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed"))))
  (let ((user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-scan-qr-image-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (let* ((json-str (get-request-body-string))
           (data (cl-json:decode-json-from-string json-str))
           (image-url (cdr (assoc :image-url data))))
      (unless image-url
        (setf (hunchentoot:return-code*) 400)
        (return-from api-scan-qr-image-handler
          (encode-api-response (make-api-error "MISSING_FIELDS" "imageUrl is required"))))
      ;; Download image and decode QR code using Python subprocess
      (handler-case
          (let* ((uploads-dir "D:/Claude/LispIM/lispim-core/uploads/")
                 (temp-dir "D:/Claude/LispIM/lispim-core/uploads/temp/")
                 (temp-file (format nil "~A~A-qr-scan-~A.png" temp-dir (get-universal-time) user-id))
                 (python-script "D:/Claude/LispIM/lispim-core/scripts/decode_qr.py"))
            ;; Ensure temp directory exists
            (ensure-directories-exist temp-file)
            ;; Download image
            (let ((download-success (download-image-to-file image-url temp-file)))
              (unless download-success
                (setf (hunchentoot:return-code*) 500)
                (return-from api-scan-qr-image-handler
                  (encode-api-response (make-api-error "DOWNLOAD_FAILED" "Failed to download image")))))
            ;; Call Python script to decode QR code
            (let* ((python-cmd (format nil "python \"~A\" \"~A\"" python-script temp-file))
                   (result (uiop:run-program python-cmd :output :string :ignore-error-status t)))
              ;; Clean up temp file
              (ignore-errors (uiop:delete-file-if-exists temp-file))
              (if (and result (not (string= result "")) (not (search "ERROR" result)))
                  ;; QR code decoded successfully
                  (let* ((qr-json (string-trim '(#\Newline #\Space #\Tab) result)))
                    ;; Verify the QR code content
                    (multiple-value-bind (qr-result error)
                        (decode-and-verify-qr qr-json)
                      (if qr-result
                          (let* ((scanned-user-id (getf qr-result :user-id))
                                 (scanned-user (get-user scanned-user-id)))
                            (if scanned-user
                                (encode-api-response
                                 (make-api-response
                                  (list :success t
                                        :user (list :id (getf scanned-user :id)
                                                    :username (getf scanned-user :username)
                                                    :displayName (getf scanned-user :display-name)
                                                    :avatar (or (getf scanned-user :avatar-url) "")))))
                                (progn
                                  (setf (hunchentoot:return-code*) 404)
                                  (encode-api-response (make-api-error "NOT_FOUND" "User not found")))))
                          (progn
                            (setf (hunchentoot:return-code*) 400)
                            (encode-api-response (make-api-error "INVALID_QR" (format nil "Invalid QR code: ~A" error)))))))
                  ;; No QR code found in image
                  (progn
                    (setf (hunchentoot:return-code*) 400)
                    (encode-api-response (make-api-error "NO_QR_FOUND" "No QR code found in image")))))))
        (error (c)
          (log-error "QR image scan error: ~a" c)
          (setf (hunchentoot:return-code*) 500)
          (encode-api-response (make-api-error "SCAN_FAILED" (format nil "Scan error: ~a" c)))))))))

;;;; Location-Based API Handlers (附近的人功能)

;; POST /api/v1/location/report - Report user location
(defun api-report-location-handler ()
  "Report current user location"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (unless (string= (hunchentoot:request-method hunchentoot:*request*) "POST")
    (setf (hunchentoot:return-code*) 405)
    (return-from api-report-location-handler
      (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed"))))
  (let ((user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-report-location-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (let* ((json-str (get-request-body-string))
           (data (cl-json:decode-json-from-string json-str))
           (latitude (cdr (assoc :latitude data)))
           (longitude (cdr (assoc :longitude data)))
           (accuracy (or (cdr (assoc :accuracy data)) 0.0))
           (city (or (cdr (assoc :city data)) ""))
           (district (or (cdr (assoc :district data)) "")))
      (unless (and latitude longitude)
        (setf (hunchentoot:return-code*) 400)
        (return-from api-report-location-handler
          (encode-api-response (make-api-error "MISSING_FIELDS" "latitude and longitude are required"))))
      ;; Check if user has location privacy disabled
      (unless (is-location-visible user-id)
        (setf (hunchentoot:return-code*) 403)
        (return-from api-report-location-handler
          (encode-api-response (make-api-error "LOCATION_HIDDEN" "Location sharing is disabled"))))
      (let ((success (store-user-location user-id
                                          (coerce latitude 'float)
                                          (coerce longitude 'float)
                                          (coerce accuracy 'float)
                                          city
                                          district)))
        (if success
            (encode-api-response
             (make-api-response nil :message "Location reported successfully"))
            (progn
              (setf (hunchentoot:return-code*) 500)
              (encode-api-response (make-api-error "STORE_FAILED" "Failed to store location"))))))))

;; GET /api/v1/location/nearby - Get nearby users
(defun api-get-nearby-users-handler ()
  "Get users nearby"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (let ((user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-get-nearby-users-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (let* ((latitude (hunchentoot:get-parameter "lat"))
           (longitude (hunchentoot:get-parameter "lng"))
           (radius (or (hunchentoot:get-parameter "radius") "10"))
           (city (hunchentoot:get-parameter "city"))
           (district (hunchentoot:get-parameter "district")))
      (cond
        ;; Search by coordinates
        ((and latitude longitude)
         (let* ((radius-km (parse-integer radius :junk-allowed t))
                (nearby (get-nearby-users (parse-integer latitude :junk-allowed t)
                                          (parse-integer longitude :junk-allowed t)
                                          (coerce radius-km 'float))))
           (encode-api-response
            (make-api-response
             (list :users nearby
                   :count (length nearby))))))
        ;; Search by city/district
        ((and city (or district (string= city "all")))
         (let ((nearby (get-nearby-users-by-city city (when (and district (string= city "all")) district))))
           (encode-api-response
            (make-api-response
             (list :users nearby
                   :count (length nearby))))))
        (t
         (setf (hunchentoot:return-code*) 400)
         (encode-api-response
          (make-api-error "MISSING_PARAMS" "Either lat/lng or city parameter is required")))))))

;; POST /api/v1/location/privacy - Set location privacy
(defun api-set-location-privacy-handler ()
  "Set user location privacy setting"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (unless (string= (hunchentoot:request-method hunchentoot:*request*) "POST")
    (setf (hunchentoot:return-code*) 405)
    (return-from api-set-location-privacy-handler
      (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed"))))
  (let ((user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-set-location-privacy-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (let* ((json-str (get-request-body-string))
           (data (cl-json:decode-json-from-string json-str))
           (visible (cdr (assoc :visible data))))
      (unless (or (eq visible t) (eq visible nil))
        (setf (hunchentoot:return-code*) 400)
        (return-from api-set-location-privacy-handler
          (encode-api-response (make-api-error "MISSING_FIELDS" "visible (boolean) is required"))))
      (let ((success (set-location-privacy user-id visible)))
        (if success
            (encode-api-response
             (make-api-response
              (list :visible visible)))
            (progn
              (setf (hunchentoot:return-code*) 500)
              (encode-api-response (make-api-error "UPDATE_FAILED" "Failed to update privacy setting"))))))))

;;;; Moments API Handlers (朋友圈功能)

;; Initialize moments and contacts tables on startup
(ensure-moments-table-exists)
(ensure-contacts-tables-exist)
(ensure-favorites-tables-exist)

;; GET /api/v1/moments - Get moment feed
(defun api-get-moments-handler ()
  "Get user's moment feed"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (let ((user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-get-moments-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (let* ((page (parse-integer (or (hunchentoot:get-parameter "page") "1") :junk-allowed t))
           (page-size (parse-integer (or (hunchentoot:get-parameter "page_size") "20") :junk-allowed t))
           (feed (get-moment-feed user-id :page page :page-size page-size)))
      (encode-api-response
       (make-api-response
        (list :moments feed
              :page page
              :page-size page-size
              :has-more (and (= (length feed) page-size) t)))))))

;; POST /api/v1/moments/post - Create moment post
(defun api-create-moment-handler ()
  "Create a new moment post"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (unless (string= (hunchentoot:request-method hunchentoot:*request*) "POST")
    (setf (hunchentoot:return-code*) 405)
    (return-from api-create-moment-handler
      (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed"))))
  (let ((user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-create-moment-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (let* ((json-str (get-request-body-string))
           (data (cl-json:decode-json-from-string json-str))
           (content (cdr (assoc :content data)))
           (photos (cdr (assoc :photos data)))
           (type (or (cdr (assoc :type data)) "text"))
           (location (or (cdr (assoc :location data)) ""))
           (visibility (or (cdr (assoc :visibility data)) "public")))
      (unless content
        (setf (hunchentoot:return-code*) 400)
        (return-from api-create-moment-handler
          (encode-api-response (make-api-error "MISSING_FIELDS" "content is required"))))
      ;; Check photo limit
      (when (and photos (> (length photos) *moment-max-photos*))
        (setf (hunchentoot:return-code*) 400)
        (return-from api-create-moment-handler
          (encode-api-response (make-api-error "TOO_MANY_PHOTOS" (format nil "Maximum ~a photos allowed" *moment-max-photos*)))))
      ;; Get user info
      (let ((user (get-user user-id)))
        (unless user
          (setf (hunchentoot:return-code*) 404)
          (return-from api-create-moment-handler
            (encode-api-response (make-api-error "NOT_FOUND" "User not found"))))
        (let* ((username (getf user :username))
               (display-name (getf user :display-name))
               (avatar (or (getf user :avatar-url) ""))
               (post-id (create-moment-post user-id username display-name avatar content photos type location visibility)))
          (encode-api-response
           (make-api-response
            (list :id post-id
                  :message "Moment created")))))))

;; GET /api/v1/moments/:id - Get specific moment (also handles DELETE)
(defun api-moment-detail-handler ()
  "Get or delete a specific moment post"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (let* ((uri (hunchentoot:request-uri hunchentoot:*request*))
         (method (hunchentoot:request-method hunchentoot:*request*))
         (post-id-str (multiple-value-bind (match-start match-end reg-start reg-end)
                          (cl-ppcre:scan "^/api/v1/moments/([^/]+)$" uri)
                        (if match-start
                            (subseq uri (aref reg-start 0) (aref reg-end 0))
                            (return-from api-moment-detail-handler
                              (progn
                                (setf (hunchentoot:return-code*) 400)
                                (encode-api-response (make-api-error "INVALID_URI" "Invalid moment URI")))))))
         (post-id (parse-integer post-id-str))
         (user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-moment-detail-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))

    (cond
      ((string= method "GET")
       ;; Get moment details
       (let ((post (get-moment-post post-id)))
         (if post
             ;; Check visibility
             (let ((visibility (getf post :visibility))
                   (author-id (getf post :user-id)))
               (if (moment-visibility-p visibility user-id author-id)
                   (encode-api-response
                    (make-api-response post))
                   (progn
                     (setf (hunchentoot:return-code*) 403)
                     (encode-api-response (make-api-error "ACCESS_DENIED" "This post is not visible to you")))))
             (progn
               (setf (hunchentoot:return-code*) 404)
               (encode-api-response (make-api-error "NOT_FOUND" "Moment not found"))))))

      ((string= method "DELETE")
       ;; Delete moment
       (multiple-value-bind (success error)
           (delete-moment-post post-id user-id)
         (if success
             (encode-api-response (make-api-response nil :message "Moment deleted"))
             (progn
               (setf (hunchentoot:return-code*) 400)
               (encode-api-response (make-api-error "DELETE_FAILED" error))))))

      (t
       (setf (hunchentoot:return-code*) 405)
       (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed"))))))

;; POST /api/v1/moments/:id/like - Like/unlike moment
(defun api-like-moment-handler ()
  "Like or unlike a moment post"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (unless (string= (hunchentoot:request-method hunchentoot:*request*) "POST")
    (setf (hunchentoot:return-code*) 405)
    (return-from api-like-moment-handler
      (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed"))))
  (let* ((uri (hunchentoot:request-uri hunchentoot:*request*))
         (post-id-str (multiple-value-bind (match-start match-end reg-start reg-end)
                          (cl-ppcre:scan "^/api/v1/moments/([^/]+)/like$" uri)
                        (if match-start
                            (subseq uri (aref reg-start 0) (aref reg-end 0))
                            (return-from api-like-moment-handler
                              (progn
                                (setf (hunchentoot:return-code*) 400)
                                (encode-api-response (make-api-error "INVALID_URI" "Invalid moment URI")))))))
         (post-id (parse-integer post-id-str))
         (user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-like-moment-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (let* ((json-str (get-request-body-string))
           (data (cl-json:decode-json-from-string json-str))
           (action (cdr (assoc :action data))))
      (cond
        ((string= action "like")
         (multiple-value-bind (success error)
             (like-moment-post post-id user-id)
           (if success
               (encode-api-response (make-api-response nil :message "Liked"))
               (progn
                 (setf (hunchentoot:return-code*) 400)
                 (encode-api-response (make-api-error "LIKE_FAILED" error))))))
        ((string= action "unlike")
         (multiple-value-bind (success error)
             (unlike-moment-post post-id user-id)
           (if success
               (encode-api-response (make-api-response nil :message "Unliked"))
               (progn
                 (setf (hunchentoot:return-code*) 400)
                 (encode-api-response (make-api-error "UNLIKE_FAILED" error))))))
        (t
         (setf (hunchentoot:return-code*) 400)
         (encode-api-response (make-api-error "INVALID_ACTION" "action must be 'like' or 'unlike'")))))))

;; POST /api/v1/moments/:id/comment - Add comment to moment
(defun api-comment-moment-handler ()
  "Add a comment to a moment post"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (unless (string= (hunchentoot:request-method hunchentoot:*request*) "POST")
    (setf (hunchentoot:return-code*) 405)
    (return-from api-comment-moment-handler
      (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed"))))
  (let* ((uri (hunchentoot:request-uri hunchentoot:*request*))
         (post-id-str (multiple-value-bind (match-start match-end reg-start reg-end)
                          (cl-ppcre:scan "^/api/v1/moments/([^/]+)/comment$" uri)
                        (if match-start
                            (subseq uri (aref reg-start 0) (aref reg-end 0))
                            (return-from api-comment-moment-handler
                              (progn
                                (setf (hunchentoot:return-code*) 400)
                                (encode-api-response (make-api-error "INVALID_URI" "Invalid moment URI")))))))
         (post-id (parse-integer post-id-str))
         (user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-comment-moment-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (let* ((json-str (get-request-body-string))
           (data (cl-json:decode-json-from-string json-str))
           (content (cdr (assoc :content data)))
           (reply-to-user-id (cdr (assoc :reply-to-user-id data)))
           (reply-to-username (cdr (assoc :reply-to-username data))))
      (unless content
        (setf (hunchentoot:return-code*) 400)
        (return-from api-comment-moment-handler
          (encode-api-response (make-api-error "MISSING_FIELDS" "content is required"))))
      ;; Get user info
      (let ((user (get-user user-id)))
        (unless user
          (setf (hunchentoot:return-code*) 404)
          (return-from api-comment-moment-handler
            (encode-api-response (make-api-error "NOT_FOUND" "User not found"))))
        (let* ((username (getf user :username))
               (display-name (getf user :display-name))
               (avatar (or (getf user :avatar-url) ""))
               (comment-id (add-moment-comment post-id user-id username display-name avatar content reply-to-user-id reply-to-username)))
          (encode-api-response
           (make-api-response
            (list :id comment-id
                  :message "Comment added")))))))

;; DELETE /api/v1/moments/:id/comments/:comment-id - Delete comment
(defun api-delete-comment-handler ()
  "Delete a moment comment"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (unless (string= (hunchentoot:request-method hunchentoot:*request*) "DELETE")
    (setf (hunchentoot:return-code*) 405)
    (return-from api-delete-comment-handler
      (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed"))))
  (let* ((uri (hunchentoot:request-uri hunchentoot:*request*))
         (match (cl-ppcre:scan "^/api/v1/moments/([^/]+)/comments/([^/]+)$" uri))
         (post-id (when match (parse-integer (subseq uri (aref (cl-ppcre:scan "^/api/v1/moments/([^/]+)/comments/([^/]+)$" uri) 0) (aref (cl-ppcre:scan "^/api/v1/moments/([^/]+)/comments/([^/]+)$" uri) 1)))))
         (comment-id (when match (parse-integer (subseq uri (aref (cl-ppcre:scan "^/api/v1/moments/([^/]+)/comments/([^/]+)$" uri) 1) (aref (cl-ppcre:scan "^/api/v1/moments/([^/]+)/comments/([^/]+)$" uri) 2)))))
         (user-id (require-auth)))
    (unless (and post-id comment-id)
      (setf (hunchentoot:return-code*) 400)
      (return-from api-delete-comment-handler
        (encode-api-response (make-api-error "INVALID_URI" "Invalid URI"))))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-delete-comment-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (multiple-value-bind (success error)
        (delete-moment-comment comment-id post-id user-id)
      (if success
          (encode-api-response (make-api-response nil :message "Comment deleted"))
          (progn
            (setf (hunchentoot:return-code*) 400)
            (encode-api-response (make-api-error "DELETE_FAILED" error)))))))

;;;; ============================================================================
;;;; Contacts API (通讯录)
;;;; ============================================================================

;; GET /api/v1/contacts/groups - Get contact groups
(defun api-get-contact-groups-handler ()
  "Get current user's contact groups"
  (setf (hunchentoot:content-type*) "application/json")
  (unless (string= (hunchentoot:request-method hunchentoot:*request*) "GET")
    (setf (hunchentoot:return-code*) 405)
    (return-from api-get-contact-groups-handler
      (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed"))))
  (let ((user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-get-contact-groups-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (let ((groups (get-contact-groups user-id)))
      (encode-api-response (make-api-response groups)))))

;; POST /api/v1/contacts/groups - Create contact group
(defun api-create-contact-group-handler ()
  "Create a new contact group"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (unless (string= (hunchentoot:request-method hunchentoot:*request*) "POST")
    (setf (hunchentoot:return-code*) 405)
    (return-from api-create-contact-group-handler
      (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed"))))
  (let ((user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-create-contact-group-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (let* ((json-str (get-request-body-string))
           (data (cl-json:decode-json-from-string json-str))
           (name (cdr (assoc :name data)))
           (order (or (cdr (assoc :order data)) 0)))
      (unless name
        (setf (hunchentoot:return-code*) 400)
        (return-from api-create-contact-group-handler
          (encode-api-response (make-api-error "MISSING_FIELDS" "name is required"))))
      (let ((group-id (create-contact-group user-id name order)))
        (encode-api-response
         (make-api-response (list :id group-id :message "Group created")))))))

;; GET/DELETE /api/v1/contacts/groups/:id - Group detail
(defun api-contact-group-detail-handler ()
  "Get or delete a contact group"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (let* ((uri (hunchentoot:request-uri hunchentoot:*request*))
         (method (hunchentoot:request-method hunchentoot:*request*))
         (group-id-str (multiple-value-bind (match-start match-end reg-start reg-end)
                           (cl-ppcre:scan "^/api/v1/contacts/groups/([^/]+)$" uri)
                         (if match-start
                             (subseq uri (aref reg-start 0) (aref reg-end 0))
                             (return-from api-contact-group-detail-handler
                               (progn
                                 (setf (hunchentoot:return-code*) 400)
                                 (encode-api-response (make-api-error "INVALID_URI" "Invalid group URI")))))))
         (group-id (parse-integer group-id-str))
         (user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-contact-group-detail-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (cond
      ((string= method "GET")
       ;; Get group detail - return groups and filter
       (let ((groups (get-contact-groups user-id)))
         (let ((group (find-if (lambda (g) (equal (getf g :id) group-id)) groups)))
           (if group
               (encode-api-response (make-api-response group))
               (progn
                 (setf (hunchentoot:return-code*) 404)
                 (encode-api-response (make-api-error "NOT_FOUND" "Group not found")))))))
      ((string= method "DELETE")
       (multiple-value-bind (success error)
           (delete-contact-group group-id user-id)
         (if success
             (encode-api-response (make-api-response nil :message "Group deleted"))
             (progn
               (setf (hunchentoot:return-code*) 400)
               (encode-api-response (make-api-error "DELETE_FAILED" error))))))
      (t
       (setf (hunchentoot:return-code*) 405)
       (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed"))))))

;; GET /api/v1/contacts/groups/:id/members - Get group members
(defun api-get-group-members-handler ()
  "Get members of a contact group"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (unless (string= (hunchentoot:request-method hunchentoot:*request*) "GET")
    (setf (hunchentoot:return-code*) 405)
    (return-from api-get-group-members-handler
      (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed"))))
  (let* ((uri (hunchentoot:request-uri hunchentoot:*request*))
         (group-id-str (multiple-value-bind (match-start match-end reg-start reg-end)
                           (cl-ppcre:scan "^/api/v1/contacts/groups/([^/]+)/members$" uri)
                         (if match-start
                             (subseq uri (aref reg-start 0) (aref reg-end 0))
                             (return-from api-get-group-members-handler
                               (progn
                                 (setf (hunchentoot:return-code*) 400)
                                 (encode-api-response (make-api-error "INVALID_URI" "Invalid group URI")))))))
         (group-id (parse-integer group-id-str))
         (user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-get-group-members-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (let ((members (get-group-members user-id group-id)))
      (encode-api-response (make-api-response members)))))

;; GET /api/v1/contacts/tags - Get contact tags
(defun api-get-contact-tags-handler ()
  "Get current user's contact tags"
  (setf (hunchentoot:content-type*) "application/json")
  (unless (string= (hunchentoot:request-method hunchentoot:*request*) "GET")
    (setf (hunchentoot:return-code*) 405)
    (return-from api-get-contact-tags-handler
      (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed"))))
  (let ((user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-get-contact-tags-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (let ((tags (get-contact-tags user-id)))
      (encode-api-response (make-api-response tags)))))

;; POST /api/v1/contacts/tags - Create contact tag
(defun api-create-contact-tag-handler ()
  "Create a new contact tag"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (unless (string= (hunchentoot:request-method hunchentoot:*request*) "POST")
    (setf (hunchentoot:return-code*) 405)
    (return-from api-create-contact-tag-handler
      (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed"))))
  (let ((user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-create-contact-tag-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (let* ((json-str (get-request-body-string))
           (data (cl-json:decode-json-from-string json-str))
           (name (cdr (assoc :name data)))
           (color (or (cdr (assoc :color data)) "#007bff")))
      (unless name
        (setf (hunchentoot:return-code*) 400)
        (return-from api-create-contact-tag-handler
          (encode-api-response (make-api-error "MISSING_FIELDS" "name is required"))))
      (let ((tag-id (create-contact-tag user-id name color)))
        (encode-api-response
         (make-api-response (list :id tag-id :message "Tag created")))))))

;; GET/DELETE /api/v1/contacts/tags/:id - Tag detail
(defun api-contact-tag-detail-handler ()
  "Get or delete a contact tag"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (let* ((uri (hunchentoot:request-uri hunchentoot:*request*))
         (method (hunchentoot:request-method hunchentoot:*request*))
         (tag-id-str (multiple-value-bind (match-start match-end reg-start reg-end)
                         (cl-ppcre:scan "^/api/v1/contacts/tags/([^/]+)$" uri)
                       (if match-start
                           (subseq uri (aref reg-start 0) (aref reg-end 0))
                           (return-from api-contact-tag-detail-handler
                             (progn
                               (setf (hunchentoot:return-code*) 400)
                               (encode-api-response (make-api-error "INVALID_URI" "Invalid tag URI")))))))
         (tag-id (parse-integer tag-id-str))
         (user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-contact-tag-detail-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (cond
      ((string= method "GET")
       (let ((tags (get-contact-tags user-id)))
         (let ((tag (find-if (lambda (tag-item) (equal (getf tag-item :id) tag-id)) tags)))
           (if tag
               (encode-api-response (make-api-response tag))
               (progn
                 (setf (hunchentoot:return-code*) 404)
                 (encode-api-response (make-api-error "NOT_FOUND" "Tag not found")))))))
      ((string= method "DELETE")
       (multiple-value-bind (success error)
           (delete-contact-tag tag-id user-id)
         (if success
             (encode-api-response (make-api-response nil :message "Tag deleted"))
             (progn
               (setf (hunchentoot:return-code*) 400)
               (encode-api-response (make-api-error "DELETE_FAILED" error))))))
      (t
       (setf (hunchentoot:return-code*) 405)
       (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed"))))))

;; PUT /api/v1/contacts/friends/:id/remark - Set contact remark
(defun api-set-contact-remark-handler ()
  "Set remark for a friend"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (unless (string= (hunchentoot:request-method hunchentoot:*request*) "PUT")
    (setf (hunchentoot:return-code*) 405)
    (return-from api-set-contact-remark-handler
      (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed"))))
  (let* ((uri (hunchentoot:request-uri hunchentoot:*request*))
         (friend-id-str (multiple-value-bind (match-start match-end reg-start reg-end)
                            (cl-ppcre:scan "^/api/v1/contacts/friends/([^/]+)/remark$" uri)
                          (if match-start
                              (subseq uri (aref reg-start 0) (aref reg-end 0))
                              (return-from api-set-contact-remark-handler
                                (progn
                                  (setf (hunchentoot:return-code*) 400)
                                  (encode-api-response (make-api-error "INVALID_URI" "Invalid friend URI")))))))
         (friend-id (subseq friend-id-str 1 (1- (length friend-id-str)))) ; Remove quotes
         (user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-set-contact-remark-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (let* ((json-str (get-request-body-string))
           (data (cl-json:decode-json-from-string json-str))
           (remark (cdr (assoc :remark data)))
           (description (cdr (assoc :description data)))
           (phone (cdr (assoc :phone data)))
           (email (cdr (assoc :email data)))
           (company (cdr (assoc :company data)))
           (birthday (cdr (assoc :birthday data))))
      (unless remark
        (setf (hunchentoot:return-code*) 400)
        (return-from api-set-contact-remark-handler
          (encode-api-response (make-api-error "MISSING_FIELDS" "remark is required"))))
      (set-contact-remark user-id friend-id remark :description description :phone phone :email email :company company :birthday birthday)
      (encode-api-response (make-api-response nil :message "Remark updated")))))

;; GET /api/v1/contacts/friends/:id/groups - Get friend's groups
(defun api-friend-groups-handler ()
  "Get or update groups for a friend"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (let* ((uri (hunchentoot:request-uri hunchentoot:*request*))
         (method (hunchentoot:request-method hunchentoot:*request*))
         (friend-id-str (multiple-value-bind (match-start match-end reg-start reg-end)
                            (cl-ppcre:scan "^/api/v1/contacts/friends/([^/]+)/groups$" uri)
                          (if match-start
                              (subseq uri (aref reg-start 0) (aref reg-end 0))
                              (return-from api-friend-groups-handler
                                (progn
                                  (setf (hunchentoot:return-code*) 400)
                                  (encode-api-response (make-api-error "INVALID_URI" "Invalid friend URI")))))))
         (friend-id (subseq friend-id-str 1 (1- (length friend-id-str))))
         (user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-friend-groups-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (cond
      ((string= method "GET")
       (let ((groups (get-friend-groups friend-id user-id)))
         (encode-api-response (make-api-response groups))))
      ((string= method "POST")
       ;; Add friend to group
       (let* ((json-str (get-request-body-string))
              (data (cl-json:decode-json-from-string json-str))
              (group-id (cdr (assoc :groupId data))))
         (unless group-id
           (setf (hunchentoot:return-code*) 400)
           (return-from api-friend-groups-handler
             (encode-api-response (make-api-error "MISSING_FIELDS" "groupId is required"))))
         (multiple-value-bind (success error)
             (add-friend-to-group user-id friend-id group-id)
           (if success
               (encode-api-response (make-api-response nil :message "Added to group"))
               (progn
                 (setf (hunchentoot:return-code*) 400)
                 (encode-api-response (make-api-error "ADD_FAILED" error)))))))
      (t
       (setf (hunchentoot:return-code*) 405)
       (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed"))))))

;; GET/POST /api/v1/contacts/friends/:id/tags - Get/update friend's tags
(defun api-friend-tags-handler ()
  "Get or update tags for a friend"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (let* ((uri (hunchentoot:request-uri hunchentoot:*request*))
         (method (hunchentoot:request-method hunchentoot:*request*))
         (friend-id-str (multiple-value-bind (match-start match-end reg-start reg-end)
                            (cl-ppcre:scan "^/api/v1/contacts/friends/([^/]+)/tags$" uri)
                          (if match-start
                              (subseq uri (aref reg-start 0) (aref reg-end 0))
                              (return-from api-friend-tags-handler
                                (progn
                                  (setf (hunchentoot:return-code*) 400)
                                  (encode-api-response (make-api-error "INVALID_URI" "Invalid friend URI")))))))
         (friend-id (subseq friend-id-str 1 (1- (length friend-id-str))))
         (user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-friend-tags-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (cond
      ((string= method "GET")
       (let ((tags (get-friend-tags friend-id user-id)))
         (encode-api-response (make-api-response tags))))
      ((string= method "POST")
       ;; Add/remove tag from friend
       (let* ((json-str (get-request-body-string))
              (data (cl-json:decode-json-from-string json-str))
              (tag-id (cdr (assoc :tagId data)))
              (action (cdr (assoc :action data))))
         (unless tag-id
           (setf (hunchentoot:return-code*) 400)
           (return-from api-friend-tags-handler
             (encode-api-response (make-api-error "MISSING_FIELDS" "tagId is required"))))
         (cond
           ((string= action "add")
            (multiple-value-bind (success error)
                (add-tag-to-friend user-id friend-id tag-id)
              (if success
                  (encode-api-response (make-api-response nil :message "Tag added"))
                  (progn
                    (setf (hunchentoot:return-code*) 400)
                    (encode-api-response (make-api-error "ADD_FAILED" error))))))
           ((string= action "remove")
            (multiple-value-bind (success error)
                (remove-tag-from-friend user-id friend-id tag-id)
              (if success
                  (encode-api-response (make-api-response nil :message "Tag removed"))
                  (progn
                    (setf (hunchentoot:return-code*) 400)
                    (encode-api-response (make-api-error "REMOVE_FAILED" error))))))
           (t
            (setf (hunchentoot:return-code*) 400)
            (encode-api-response (make-api-error "INVALID_ACTION" "action must be 'add' or 'remove'")))))))
      (t
       (setf (hunchentoot:return-code*) 405)
       (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed"))))))))

;; GET/POST /api/v1/contacts/blacklist - Get/manage blacklist
(defun api-blacklist-handler ()
  "Get blacklist or add/remove user"
  (setf (hunchentoot:content-type*) "application/json")
  (let ((method (hunchentoot:request-method hunchentoot:*request*))
        (user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-blacklist-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (cond
      ((string= method "GET")
       (let ((blacklist (get-blacklist user-id)))
         (encode-api-response (make-api-response blacklist))))
      ((string= method "POST")
       ;; Add user to blacklist
       (let* ((json-str (get-request-body-string))
              (data (cl-json:decode-json-from-string json-str))
              (blocked-id (cdr (assoc :blockedId data))))
         (unless blocked-id
           (setf (hunchentoot:return-code*) 400)
           (return-from api-blacklist-handler
             (encode-api-response (make-api-error "MISSING_FIELDS" "blockedId is required"))))
         (multiple-value-bind (success error)
             (add-to-blacklist user-id blocked-id)
           (if success
               (encode-api-response (make-api-response nil :message "User blocked"))
               (progn
                 (setf (hunchentoot:return-code*) 400)
                 (encode-api-response (make-api-error "BLOCK_FAILED" error)))))))
      (t
       (setf (hunchentoot:return-code*) 405)
       (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed"))))))

;; DELETE /api/v1/contacts/blacklist/:id - Remove from blacklist
(defun api-blacklist-detail-handler ()
  "Remove user from blacklist"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (unless (string= (hunchentoot:request-method hunchentoot:*request*) "DELETE")
    (setf (hunchentoot:return-code*) 405)
    (return-from api-blacklist-detail-handler
      (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed"))))
  (let* ((uri (hunchentoot:request-uri hunchentoot:*request*))
         (blocked-id-str (multiple-value-bind (match-start match-end reg-start reg-end)
                             (cl-ppcre:scan "^/api/v1/contacts/blacklist/([^/]+)$" uri)
                           (if match-start
                               (subseq uri (aref reg-start 0) (aref reg-end 0))
                               (return-from api-blacklist-detail-handler
                                 (progn
                                   (setf (hunchentoot:return-code*) 400)
                                   (encode-api-response (make-api-error "INVALID_URI" "Invalid URI")))))))
         (blocked-id (subseq blocked-id-str 1 (1- (length blocked-id-str))))
         (user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-blacklist-detail-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (multiple-value-bind (success error)
        (remove-from-blacklist user-id blocked-id)
      (if success
          (encode-api-response (make-api-response nil :message "User unblocked"))
          (progn
            (setf (hunchentoot:return-code*) 400)
            (encode-api-response (make-api-error "UNBLOCK_FAILED" error)))))))

;; GET/POST /api/v1/contacts/stars - Get star contacts or add star
(defun api-stars-handler ()
  "Get star contacts or add star contact"
  (setf (hunchentoot:content-type*) "application/json")
  (let ((method (hunchentoot:request-method hunchentoot:*request*))
        (user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-stars-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (cond
      ((string= method "GET")
       (let ((stars (get-star-contacts user-id)))
         (encode-api-response (make-api-response stars))))
      ((string= method "POST")
       ;; Add star contact
       (let* ((json-str (get-request-body-string))
              (data (cl-json:decode-json-from-string json-str))
              (starred-id (cdr (assoc :starredId data))))
         (unless starred-id
           (setf (hunchentoot:return-code*) 400)
           (return-from api-stars-handler
             (encode-api-response (make-api-error "MISSING_FIELDS" "starredId is required"))))
         (multiple-value-bind (success error)
             (add-star-contact user-id starred-id)
           (if success
               (encode-api-response (make-api-response nil :message "Contact starred"))
               (progn
                 (setf (hunchentoot:return-code*) 400)
                 (encode-api-response (make-api-error "STAR_FAILED" error)))))))
      (t
       (setf (hunchentoot:return-code*) 405)
       (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed"))))))

;; DELETE /api/v1/contacts/stars/:id - Remove star contact
(defun api-stars-detail-handler ()
  "Remove star from contact"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (unless (string= (hunchentoot:request-method hunchentoot:*request*) "DELETE")
    (setf (hunchentoot:return-code*) 405)
    (return-from api-stars-detail-handler
      (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed"))))
  (let* ((uri (hunchentoot:request-uri hunchentoot:*request*))
         (starred-id-str (multiple-value-bind (match-start match-end reg-start reg-end)
                             (cl-ppcre:scan "^/api/v1/contacts/stars/([^/]+)$" uri)
                           (if match-start
                               (subseq uri (aref reg-start 0) (aref reg-end 0))
                               (return-from api-stars-detail-handler
                                 (progn
                                   (setf (hunchentoot:return-code*) 400)
                                   (encode-api-response (make-api-error "INVALID_URI" "Invalid URI")))))))
         (starred-id (subseq starred-id-str 1 (1- (length starred-id-str))))
         (user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-stars-detail-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (multiple-value-bind (success error)
        (remove-star-contact user-id starred-id)
      (if success
          (encode-api-response (make-api-response nil :message "Star removed"))
          (progn
            (setf (hunchentoot:return-code*) 400)
            (encode-api-response (make-api-error "UNSTAR_FAILED" error)))))))

;; GET /api/v1/contacts/search - Search contacts
(defun api-search-contacts-handler ()
  "Search contacts by remark, username, or display name"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (unless (string= (hunchentoot:request-method hunchentoot:*request*) "GET")
    (setf (hunchentoot:return-code*) 405)
    (return-from api-search-contacts-handler
      (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed"))))
  (let ((user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-search-contacts-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (let* ((query (hunchentoot:get-parameter "q"))
           (limit-param (hunchentoot:get-parameter "limit"))
           (limit (if limit-param (parse-integer limit-param :junk-allowed t) 20)))
      (unless query
        (setf (hunchentoot:return-code*) 400)
        (return-from api-search-contacts-handler
          (encode-api-response (make-api-error "MISSING_FIELDS" "q parameter is required"))))
      (let ((results (search-contacts user-id query :limit limit)))
        (encode-api-response (make-api-response results))))))

;;;; ============================================================================
;;;; Group Management API (群聊管理)
;;;; ============================================================================

;; POST /api/v1/groups - Create group
(defun api-create-group-handler ()
  "Create a new group"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (unless (string= (hunchentoot:request-method hunchentoot:*request*) "POST")
    (setf (hunchentoot:return-code*) 405)
    (return-from api-create-group-handler
      (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed"))))
  (let ((user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-create-group-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (handler-case
        (let* ((json-str (get-request-body-string))
               (data (cl-json:decode-json-from-string json-str))
               (name (cdr (assoc :name data)))
               (avatar (cdr (assoc :avatar data)))
               (member-ids (cdr (assoc :memberIds data)))
               (max-members (cdr (assoc :maxMembers data)))
               (invite-privacy (cdr (assoc :invitePrivacy data))))
          (unless name
            (setf (hunchentoot:return-code*) 400)
            (return-from api-create-group-handler
              (encode-api-response (make-api-error "MISSING_FIELDS" "name is required"))))
          (let ((group (create-group name user-id
                                     :avatar avatar
                                     :max-members max-members
                                     :invite-privacy (when invite-privacy (keywordify invite-privacy)))))
            ;; Add initial members if provided
            (when member-ids
              (dolist (mid member-ids)
                (when (and (stringp mid) (not (string= mid user-id)))
                  (add-group-member (group-id group) mid))))
            (encode-api-response
             (make-api-response
              (list :id (group-id group)
                    :name (group-name group)
                    :avatar (group-avatar group)
                    :ownerId (group-owner-id group)
                    :memberCount (group-member-count group)
                    :createdAt (group-created-at group))
              :message "Group created successfully"))))
      (error (c)
        (log-error "Create group error: ~A" c)
        (setf (hunchentoot:return-code*) 500)
        (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c)))))))

;; GET /api/v1/groups - Get user's groups
(defun api-get-groups-handler ()
  "Get current user's groups"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (unless (string= (hunchentoot:request-method hunchentoot:*request*) "GET")
    (setf (hunchentoot:return-code*) 405)
    (return-from api-get-groups-handler
      (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed"))))
  (let ((user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-get-groups-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (handler-case
        (let ((groups (get-user-groups user-id)))
          (encode-api-response
           (make-api-response
            (loop for g in groups
                  collect
                  `((:id . ,(cdr (assoc :id g)))
                    (:name . ,(cdr (assoc :name g)))
                    (:avatar . ,(cdr (assoc :avatar g)))
                    (:ownerId . ,(cdr (assoc :owner_id g)))
                    (:memberCount . ,(cdr (assoc :member_count g)))
                    (:memberRole . ,(cdr (assoc :member_role g)))
                    (:memberNickname . ,(cdr (assoc :member_nickname g)))
                    (:createdAt . ,(cdr (assoc :created_at g)))
                    (:updatedAt . ,(cdr (assoc :updated_at g))))))))
      (error (c)
        (log-error "Get groups error: ~A" c)
        (setf (hunchentoot:return-code*) 500)
        (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c)))))))

;; GET/PUT/DELETE /api/v1/groups/:id - Group detail
(defun api-group-detail-handler ()
  "Get, update, or delete group by ID"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (let* ((uri (hunchentoot:request-uri hunchentoot:*request*))
         (group-id (multiple-value-bind (match-start match-end reg-start reg-end)
                     (cl-ppcre:scan "^/api/v1/groups/([0-9]+)$" uri)
                     (if match-start
                         (parse-integer (subseq uri (aref reg-start 0) (aref reg-end 0)))
                         (return-from api-group-detail-handler
                           (progn
                             (setf (hunchentoot:return-code*) 400)
                             (encode-api-response (make-api-error "INVALID_URI" "Invalid group ID")))))))
         (user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-group-detail-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (let ((group (get-group group-id)))
      (unless group
        (setf (hunchentoot:return-code*) 404)
        (return-from api-group-detail-handler
          (encode-api-response (make-api-error "NOT_FOUND" "Group not found"))))
      (case (intern (string-upcase (hunchentoot:request-method hunchentoot:*request*)) :keyword)
        (:get
         ;; Check if user is a member
         (unless (is-group-member-p group-id user-id)
           (setf (hunchentoot:return-code*) 403)
           (return-from api-group-detail-handler
             (encode-api-response (make-api-error "ACCESS_DENIED" "Not a group member"))))
         (let ((members (get-group-members group-id)))
           (encode-api-response
            (make-api-response
             (list :id (group-id group)
                   :name (group-name group)
                   :avatar (group-avatar group)
                   :ownerId (group-owner-id group)
                   :announcement (group-announcement group)
                   :announcementEditorId (group-announcement-editor-id group)
                   :announcementUpdatedAt (group-announcement-updated-at group)
                   :memberCount (group-member-count group)
                   :maxMembers (group-max-members group)
                   :isMuted (group-is-muted group)
                   :isDismissed (group-is-dismissed group)
                   :invitePrivacy (string-downcase (group-invite-privacy group))
                   :createdAt (group-created-at group)
                   :updatedAt (group-updated-at group)
                   :members (loop for m in members
                                  collect
                                  (list :userId (group-member-user-id m)
                                        :role (string-downcase (group-member-role m))
                                        :nickname (group-member-nickname m)
                                        :joinedAt (group-member-joined-at m)
                                        :isMuted (group-member-is-muted m)
                                        :isQuiet (group-member-is-quiet-p m))))))))
        (:put
         ;; Only owner or admin can update
         (unless (is-group-admin-p group-id user-id)
           (setf (hunchentoot:return-code*) 403)
           (return-from api-group-detail-handler
             (encode-api-response (make-api-error "ACCESS_DENIED" "Only owner or admin can update group"))))
         (let* ((json-str (get-request-body-string))
                (data (cl-json:decode-json-from-string json-str))
                (name (cdr (assoc :name data)))
                (avatar (cdr (assoc :avatar data)))
                (announcement (cdr (assoc :announcement data)))
                (invite-privacy (cdr (assoc :invitePrivacy data))))
           (update-group group-id
                         :name name
                         :avatar avatar
                         :announcement announcement
                         :invite-privacy (when invite-privacy (keywordify invite-privacy)))
           (when announcement
             (log-group-admin-action group-id user-id "update_announcement"))
           (encode-api-response
            (make-api-response nil :message "Group updated successfully"))))
        (:delete
         ;; Only owner can delete
         (unless (is-group-owner-p group-id user-id)
           (setf (hunchentoot:return-code*) 403)
           (return-from api-group-detail-handler
             (encode-api-response (make-api-error "ACCESS_DENIED" "Only owner can delete group"))))
         (delete-group group-id)
         (log-group-admin-action group-id user-id "delete_group")
         (encode-api-response
          (make-api-response nil :message "Group deleted successfully")))
        (t
         (setf (hunchentoot:return-code*) 405)
         (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed")))))))

;; GET/POST /api/v1/groups/:id/members - Group members
(defun api-group-members-handler ()
  "Get group members or add member"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (let* ((uri (hunchentoot:request-uri hunchentoot:*request*))
         (group-id (multiple-value-bind (match-start match-end reg-start reg-end)
                     (cl-ppcre:scan "^/api/v1/groups/([0-9]+)/members$" uri)
                     (if match-start
                         (parse-integer (subseq uri (aref reg-start 0) (aref reg-end 0)))
                         (return-from api-group-members-handler
                           (progn
                             (setf (hunchentoot:return-code*) 400)
                             (encode-api-response (make-api-error "INVALID_URI" "Invalid group ID")))))))
         (user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-group-members-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (let ((group (get-group group-id)))
      (unless group
        (setf (hunchentoot:return-code*) 404)
        (return-from api-group-members-handler
          (encode-api-response (make-api-error "NOT_FOUND" "Group not found"))))
      (case (intern (string-upcase (hunchentoot:request-method hunchentoot:*request*)) :keyword)
        (:get
         (unless (is-group-member-p group-id user-id)
           (setf (hunchentoot:return-code*) 403)
           (return-from api-group-members-handler
             (encode-api-response (make-api-error "ACCESS_DENIED" "Not a group member"))))
         (let ((members (get-group-members group-id)))
           (encode-api-response
            (make-api-response
             (loop for m in members
                   collect
                   (list :userId (group-member-user-id m)
                         :role (string-downcase (group-member-role m))
                         :nickname (group-member-nickname m)
                         :joinedAt (group-member-joined-at m)
                         :isMuted (group-member-is-muted m)
                         :isQuiet (group-member-is-quiet-p m)))))))
        (:post
         ;; Add member
         (unless (can-invite-p group-id user-id)
           (setf (hunchentoot:return-code*) 403)
           (return-from api-group-members-handler
             (encode-api-response (make-api-error "ACCESS_DENIED" "No permission to invite members"))))
         (let* ((json-str (get-request-body-string))
                (data (cl-json:decode-json-from-string json-str))
                (member-id (cdr (assoc :memberId data)))
                (role (cdr (assoc :role data)))
                (nickname (cdr (assoc :nickname data))))
           (unless member-id
             (setf (hunchentoot:return-code*) 400)
             (return-from api-group-members-handler
               (encode-api-response (make-api-error "MISSING_FIELDS" "memberId is required"))))
           (when (is-group-member-p group-id member-id)
             (setf (hunchentoot:return-code*) 409)
             (return-from api-group-members-handler
               (encode-api-response (make-api-error "ALREADY_MEMBER" "User is already a member"))))
           (add-group-member group-id member-id
                            :role (when role (keywordify role))
                            :nickname nickname)
           (log-group-admin-action group-id user-id "add_member" :target-user-id member-id)
           (encode-api-response
            (make-api-response nil :message "Member added successfully"))))
        (t
         (setf (hunchentoot:return-code*) 405)
         (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed")))))))

;; GET/PUT/DELETE /api/v1/groups/:id/members/:userId - Member detail
(defun api-group-member-detail-handler ()
  "Get, update, or remove group member"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (let* ((uri (hunchentoot:request-uri hunchentoot:*request*))
         (matches (multiple-value-list (cl-ppcre:scan "^/api/v1/groups/([0-9]+)/members/([^/]+)$" uri)))
         (group-id (when (car matches)
                     (parse-integer (subseq uri (nth 2 matches) (nth 3 matches)))))
         (target-user-id (when (car matches)
                           (subseq uri (nth 4 matches) (nth 5 matches))))
         (user-id (require-auth)))
    (unless (and group-id target-user-id)
      (setf (hunchentoot:return-code*) 400)
      (return-from api-group-member-detail-handler
        (encode-api-response (make-api-error "INVALID_URI" "Invalid URI"))))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-group-member-detail-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (let ((group (get-group group-id)))
      (unless group
        (setf (hunchentoot:return-code*) 404)
        (return-from api-group-member-detail-handler
          (encode-api-response (make-api-error "NOT_FOUND" "Group not found"))))
      (let ((member (get-group-member group-id target-user-id)))
        (unless member
          (setf (hunchentoot:return-code*) 404)
          (return-from api-group-member-detail-handler
            (encode-api-response (make-api-error "NOT_FOUND" "Member not found"))))
        (case (intern (string-upcase (hunchentoot:request-method hunchentoot:*request*)) :keyword)
          (:get
           (unless (is-group-member-p group-id user-id)
             (setf (hunchentoot:return-code*) 403)
             (return-from api-group-member-detail-handler
               (encode-api-response (make-api-error "ACCESS_DENIED" "Not a group member"))))
           (encode-api-response
            (make-api-response
             (list :userId (group-member-user-id member)
                   :role (string-downcase (group-member-role member))
                   :nickname (group-member-nickname member)
                   :joinedAt (group-member-joined-at member)
                   :isMuted (group-member-is-muted member)
                   :isQuiet (group-member-is-quiet-p member)))))
          (:put
           ;; Only owner/admin can update others
           (unless (is-group-admin-p group-id user-id)
             (setf (hunchentoot:return-code*) 403)
             (return-from api-group-member-detail-handler
               (encode-api-response (make-api-error "ACCESS_DENIED" "Only owner or admin can update members"))))
           (let* ((json-str (get-request-body-string))
                  (data (cl-json:decode-json-from-string json-str))
                  (role (cdr (assoc :role data)))
                  (nickname (cdr (assoc :nickname data)))
                  (is-muted (cdr (assoc :isMuted data)))
                  (is-quiet (cdr (assoc :isQuiet data))))
             (when role
               (update-group-member-role group-id target-user-id role))
             (when nickname
               (set-member-nickname group-id target-user-id nickname))
             (when (booleanp is-muted)
               (setf (group-member-is-muted member) is-muted))
             (when (booleanp is-quiet)
               (set-member-quiet group-id target-user-id is-quiet))
             (log-group-admin-action group-id user-id "update_member" :target-user-id target-user-id)
             (encode-api-response
              (make-api-response nil :message "Member updated successfully"))))
          (:delete
           ;; Remove member - only owner/admin can remove others, users can remove themselves
           (unless (or (string= user-id target-user-id)
                       (is-group-admin-p group-id user-id))
             (setf (hunchentoot:return-code*) 403)
             (return-from api-group-member-detail-handler
               (encode-api-response (make-api-error "ACCESS_DENIED" "No permission to remove this member"))))
           ;; Cannot remove owner
           (when (and (eq (group-member-role member) :owner)
                      (string= target-user-id (group-owner-id group)))
             (setf (hunchentoot:return-code*) 403)
             (return-from api-group-member-detail-handler
               (encode-api-response (make-api-error "ACCESS_DENIED" "Cannot remove group owner"))))
           (remove-group-member group-id target-user-id)
           (log-group-admin-action group-id user-id "remove_member" :target-user-id target-user-id)
           (encode-api-response
            (make-api-response nil :message "Member removed successfully")))))))

;; PUT /api/v1/groups/:id/announcement - Update group announcement
(defun api-group-announcement-handler ()
  "Update group announcement"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (let* ((uri (hunchentoot:request-uri hunchentoot:*request*))
         (group-id (multiple-value-bind (match-start match-end reg-start reg-end)
                     (cl-ppcre:scan "^/api/v1/groups/([0-9]+)/announcement$" uri)
                     (if match-start
                         (parse-integer (subseq uri (aref reg-start 0) (aref reg-end 0)))
                         (return-from api-group-announcement-handler
                           (progn
                             (setf (hunchentoot:return-code*) 400)
                             (encode-api-response (make-api-error "INVALID_URI" "Invalid group ID")))))))
         (user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-group-announcement-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (unless (string= (hunchentoot:request-method hunchentoot:*request*) "PUT")
      (setf (hunchentoot:return-code*) 405)
      (return-from api-group-announcement-handler
        (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed"))))
    (let ((group (get-group group-id)))
      (unless group
        (setf (hunchentoot:return-code*) 404)
        (return-from api-group-announcement-handler
          (encode-api-response (make-api-error "NOT_FOUND" "Group not found"))))
      (unless (is-group-member-p group-id user-id)
        (setf (hunchentoot:return-code*) 403)
        (return-from api-group-announcement-handler
          (encode-api-response (make-api-error "ACCESS_DENIED" "Not a group member"))))
      (let* ((json-str (get-request-body-string))
             (data (cl-json:decode-json-from-string json-str))
             (announcement (cdr (assoc :announcement data))))
        (update-group group-id :announcement announcement)
        (log-group-admin-action group-id user-id "update_announcement")
        (encode-api-response
         (make-api-response nil :message "Announcement updated"))))))

;; GET /api/v1/groups/:id/announcement - Get group announcement
(defun api-group-announcement-detail-handler ()
  "Get group announcement details"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (let* ((uri (hunchentoot:request-uri hunchentoot:*request*))
         (group-id (multiple-value-bind (match-start match-end reg-start reg-end)
                     (cl-ppcre:scan "^/api/v1/groups/([0-9]+)/announcement$" uri)
                     (if match-start
                         (parse-integer (subseq uri (aref reg-start 0) (aref reg-end 0)))
                         (return-from api-group-announcement-detail-handler
                           (progn
                             (setf (hunchentoot:return-code*) 400)
                             (encode-api-response (make-api-error "INVALID_URI" "Invalid group ID")))))))
         (user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-group-announcement-detail-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (unless (string= (hunchentoot:request-method hunchentoot:*request*) "GET")
      (setf (hunchentoot:return-code*) 405)
      (return-from api-group-announcement-detail-handler
        (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed"))))
    (handler-case
        (let ((group (get-group group-id)))
          (unless group
            (setf (hunchentoot:return-code*) 404)
            (return-from api-group-announcement-detail-handler
              (encode-api-response (make-api-error "NOT_FOUND" "Group not found"))))
          (encode-api-response
           (make-api-response
            `((:success . t)
              (:data . ((:announcement . ,(group-announcement group))
                        (:announcementEditorId . ,(group-announcement-editor-id group))
                        (:announcementUpdatedAt . ,(when (group-announcement-updated-at group)
                                                     (storage-universal-to-unix-ms (group-announcement-updated-at group)))))))))
      (error (c)
        (log-error "Get group announcement error: ~A" c)
        (setf (hunchentoot:return-code*) 500)
        (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c)))))))

;; GET /api/v1/groups/:id/announcement/history - Get announcement history
(defun api-group-announcement-history-handler ()
  "Get group announcement update history"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (let* ((uri (hunchentoot:request-uri hunchentoot:*request*))
         (group-id (multiple-value-bind (match-start match-end reg-start reg-end)
                     (cl-ppcre:scan "^/api/v1/groups/([0-9]+)/announcement/history$" uri)
                     (if match-start
                         (parse-integer (subseq uri (aref reg-start 0) (aref reg-end 0)))
                         (return-from api-group-announcement-history-handler
                           (progn
                             (setf (hunchentoot:return-code*) 400)
                             (encode-api-response (make-api-error "INVALID_URI" "Invalid group ID")))))))
         (user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-group-announcement-history-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (unless (string= (hunchentoot:request-method hunchentoot:*request*) "GET")
      (setf (hunchentoot:return-code*) 405)
      (return-from api-group-announcement-history-handler
        (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed"))))
    (handler-case
        (let ((history (get-group-admin-logs group-id :action "update_announcement" :limit 20)))
          (encode-api-response
           (make-api-response `((:success . t)
                                (:data . ,history))))
      (error (c)
        (log-error "Get announcement history error: ~A" c)
        (setf (hunchentoot:return-code*) 500)
        (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c)))))))

;;;; Group Invite Links API (群邀请链接)

;; GET /api/v1/groups/:id/invite-links - Get group invite links
(defun api-group-invite-links-handler ()
  "Get all invite links for a group"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (let* ((uri (hunchentoot:request-uri hunchentoot:*request*))
         (group-id (multiple-value-bind (match-start match-end reg-start reg-end)
                     (cl-ppcre:scan "^/api/v1/groups/([0-9]+)/invite-links$" uri)
                     (if match-start
                         (parse-integer (subseq uri (aref reg-start 0) (aref reg-end 0)))
                         (return-from api-group-invite-links-handler
                           (progn
                             (setf (hunchentoot:return-code*) 400)
                             (encode-api-response (make-api-error "INVALID_URI" "Invalid group ID")))))))
         (user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-group-invite-links-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (unless (string= (hunchentoot:request-method hunchentoot:*request*) "GET")
      (setf (hunchentoot:return-code*) 405)
      (return-from api-group-invite-links-handler
        (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed"))))
    (handler-case
        (let ((group (get-group group-id)))
          (unless group
            (setf (hunchentoot:return-code*) 404)
            (return-from api-group-invite-links-handler
              (encode-api-response (make-api-error "NOT_FOUND" "Group not found"))))
          ;; Check permission
          (unless (is-group-admin-p group-id user-id)
            (setf (hunchentoot:return-code*) 403)
            (return-from api-group-invite-links-handler
              (encode-api-response (make-api-error "FORBIDDEN" "Admin permission required"))))
          (let ((links (get-group-invite-links group-id)))
            (encode-api-response
             (make-api-response
              `((:success . t)
                (:data . ,(mapcar (lambda (link)
                                    `((:id . ,(group-invite-link-id link))
                                      (:code . ,(group-invite-link-code link))
                                      (:maxUses . ,(group-invite-link-max-uses link))
                                      (:usedCount . ,(group-invite-link-used-count link))
                                      (:expiresAt . ,(when (plusp (group-invite-link-expires-at link))
                                                       (storage-universal-to-unix-ms (group-invite-link-expires-at link))))
                                      (:revokedAt . ,(when (plusp (group-invite-link-revoked-at link))
                                                       (storage-universal-to-unix-ms (group-invite-link-revoked-at link))))
                                      (:createdAt . ,(storage-universal-to-unix-ms (group-invite-link-created-at link)))))
                                  links)))))))
      (error (c)
        (log-error "Get group invite links error: ~A" c)
        (setf (hunchentoot:return-code*) 500)
        (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c)))))))

;; POST /api/v1/groups/:id/invite-links/create - Create invite link
(defun api-create-group-invite-link-handler ()
  "Create a new invite link for a group"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (let ((user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-create-group-invite-link-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (unless (string= (hunchentoot:request-method hunchentoot:*request*) "POST")
      (setf (hunchentoot:return-code*) 405)
      (return-from api-create-group-invite-link-handler
        (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed"))))
    (handler-case
        (let* ((uri (hunchentoot:request-uri hunchentoot:*request*))
               (group-id (multiple-value-bind (match-start match-end reg-start reg-end)
                           (cl-ppcre:scan "^/api/v1/groups/([0-9]+)/invite-links/create$" uri)
                           (if match-start
                               (parse-integer (subseq uri (aref reg-start 0) (aref reg-end 0)))
                               (return-from api-create-group-invite-link-handler
                                 (progn
                                   (setf (hunchentoot:return-code*) 400)
                                   (encode-api-response (make-api-error "INVALID_URI" "Invalid group ID")))))))
               (json-str (get-request-body-string))
               (data (if (and json-str (not (string= json-str "")))
                         (cl-json:decode-json-from-string json-str)
                         nil))
               (max-uses (cdr (assoc :maxUses data)))
               (expires-in (cdr (assoc :expiresIn data))))
          (let ((group (get-group group-id)))
            (unless group
              (setf (hunchentoot:return-code*) 404)
              (return-from api-create-group-invite-link-handler
                (encode-api-response (make-api-error "NOT_FOUND" "Group not found"))))
            ;; Check permission
            (unless (is-group-admin-p group-id user-id)
              (setf (hunchentoot:return-code*) 403)
              (return-from api-create-group-invite-link-handler
                (encode-api-response (make-api-error "FORBIDDEN" "Admin permission required"))))
            (let ((link (create-group-invite-link group-id user-id
                                                  :max-uses max-uses
                                                  :expires-in (when expires-in (* expires-in 60)))))
              (encode-api-response
               (make-api-response
                `((:success . t)
                  (:data . ((:id . ,(group-invite-link-id link))
                            (:code . ,(group-invite-link-code link))
                            (:inviteLink . ,(format nil "/api/v1/groups/invite/~A" (group-invite-link-code link)))
                            (:maxUses . ,(group-invite-link-max-uses link))
                            (:expiresIn . ,(when expires-in expires-in))))))))))
      (error (c)
        (log-error "Create group invite link error: ~A" c)
        (setf (hunchentoot:return-code*) 500)
        (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c)))))))

;; POST /api/v1/groups/invite/:code - Join group via invite link
(defun api-join-via-invite-handler ()
  "Join a group using an invite link"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (let ((user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-join-via-invite-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (unless (string= (hunchentoot:request-method hunchentoot:*request*) "POST")
      (setf (hunchentoot:return-code*) 405)
      (return-from api-join-via-invite-handler
        (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed"))))
    (handler-case
        (let* ((uri (hunchentoot:request-uri hunchentoot:*request*))
               (code (multiple-value-bind (match-start match-end reg-start reg-end)
                       (cl-ppcre:scan "^/api/v1/groups/invite/([A-Za-z0-9]+)$" uri)
                       (if match-start
                           (subseq uri (aref reg-start 0) (aref reg-end 0))
                           (return-from api-join-via-invite-handler
                             (progn
                               (setf (hunchentoot:return-code*) 400)
                               (encode-api-response (make-api-error "INVALID_URI" "Invalid invite code"))))))))
          (multiple-value-bind (success group-id error-msg)
              (join-group-via-invite code user-id)
            (if success
                (encode-api-response
                 (make-api-response
                  `((:success . t)
                    (:groupId . ,group-id))))
                (progn
                  (setf (hunchentoot:return-code*) 400)
                  (encode-api-response (make-api-error "INVITE_ERROR" error-msg)))))))
      (error (c)
        (log-error "Join via invite error: ~A" c)
        (setf (hunchentoot:return-code*) 500)
        (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c))))))))

;; POST /api/v1/groups/invite-links/:id/revoke - Revoke invite link
(defun api-revoke-invite-link-handler ()
  "Revoke an invite link"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (let ((user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-revoke-invite-link-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (unless (string= (hunchentoot:request-method hunchentoot:*request*) "POST")
      (setf (hunchentoot:return-code*) 405)
      (return-from api-revoke-invite-link-handler
        (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed"))))
    (handler-case
        (let* ((uri (hunchentoot:request-uri hunchentoot:*request*))
               (link-id (multiple-value-bind (match-start match-end reg-start reg-end)
                          (cl-ppcre:scan "^/api/v1/groups/invite-links/([0-9]+)/revoke$" uri)
                          (if match-start
                              (parse-integer (subseq uri (aref reg-start 0) (aref reg-end 0)))
                              (return-from api-revoke-invite-link-handler
                                (progn
                                  (setf (hunchentoot:return-code*) 400)
                                  (encode-api-response (make-api-error "INVALID_URI" "Invalid link ID"))))))))
          (multiple-value-bind (success error-code error-msg)
              (revoke-invite-link link-id user-id)
            (if success
                (encode-api-response
                 (make-api-response `((:success . t))))
                (progn
                  (setf (hunchentoot:return-code*) 400)
                  (encode-api-response (make-api-error error-code error-msg)))))))
      (error (c)
        (log-error "Revoke invite link error: ~A" c)
        (setf (hunchentoot:return-code*) 500)
        (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c))))))))

;;;; ============================================================================
;;;; Favorites API (收藏管理)
;;;; ============================================================================

;; GET /api/v1/favorites - Get favorites list
;; POST /api/v1/favorites - Add favorite
(defun api-favorites-handler ()
  "Get or add favorites"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (let ((user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-favorites-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (cond
      ((string= (hunchentoot:request-method hunchentoot:*request*) "GET")
       (handler-case
           (let* ((category-id (hunchentoot:get-parameter "category"))
                  (limit (let ((l (hunchentoot:get-parameter "limit")))
                           (when l (parse-integer l))))
                  (offset (let ((o (hunchentoot:get-parameter "offset")))
                            (when o (parse-integer o))))
                  (search-query (hunchentoot:get-parameter "q"))
                  (category-id (when category-id (parse-integer category-id)))
                  (favorites (get-favorites user-id :category-id category-id :limit limit :offset offset :search-query search-query)))
             (encode-api-response
              (make-api-response `((:success . t)
                                   (:data . ,favorites)))))
         (error (c)
           (log-error "Get favorites error: ~A" c)
           (setf (hunchentoot:return-code*) 500)
           (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c))))))
      ((string= (hunchentoot:request-method hunchentoot:*request*) "POST")
       (handler-case
           (let* ((json-str (get-request-body-string))
                  (data (cl-json:decode-json-from-string json-str))
                  (message-id (cdr (assoc :messageId data)))
                  (content (cdr (assoc :content data)))
                  (message-type (cdr (assoc :messageType data)))
                  (conversation-id (cdr (assoc :conversationId data)))
                  (category-id (cdr (assoc :categoryId data)))
                  (tags (cdr (assoc :tags data)))
                  (note (cdr (assoc :note data))))
             (unless message-id
               (setf (hunchentoot:return-code*) 400)
               (return-from api-favorites-handler
                 (encode-api-response (make-api-error "MISSING_FIELDS" "messageId is required"))))
             (let ((fav-id (add-favorite user-id message-id
                                         :content content
                                         :message-type (keywordify message-type)
                                         :conversation-id conversation-id
                                         :category-id category-id
                                         :tags tags
                                         :note note)))
               (encode-api-response
                (make-api-response `((:success . t)
                                     (:favoriteId . ,fav-id))))))
         (error (c)
           (log-error "Add favorite error: ~A" c)
           (setf (hunchentoot:return-code*) 500)
           (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c))))))
      (t
       (setf (hunchentoot:return-code*) 405)
       (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed"))))))

;; GET/PUT/DELETE /api/v1/favorites/:id
(defun api-favorite-handler ()
  "Get, update, or delete a specific favorite"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (let ((user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-favorite-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (handler-case
        (let* ((uri (hunchentoot:request-uri hunchentoot:*request*))
               (favorite-id (multiple-value-bind (match-start match-end reg-start reg-end)
                              (cl-ppcre:scan "^/api/v1/favorites/([0-9]+)$" uri)
                              (if match-start
                                  (parse-integer (subseq uri (aref reg-start 0) (aref reg-end 0)))
                                  (return-from api-favorite-handler
                                    (progn
                                      (setf (hunchentoot:return-code*) 400)
                                      (encode-api-response (make-api-error "INVALID_URI" "Invalid favorite ID"))))))))
          (cond
            ((string= (hunchentoot:request-method hunchentoot:*request*) "GET")
             (let ((favorite (get-favorite favorite-id user-id)))
               (if favorite
                   (encode-api-response
                    (make-api-response `((:success . t)
                                         (:data . ,favorite))))
                   (progn
                     (setf (hunchentoot:return-code*) 404)
                     (encode-api-response (make-api-error "NOT_FOUND" "Favorite not found"))))))
            ((string= (hunchentoot:request-method hunchentoot:*request*) "PUT")
             (let* ((json-str (get-request-body-string))
                    (data (cl-json:decode-json-from-string json-str))
                    (content (cdr (assoc :content data)))
                    (category-id (cdr (assoc :categoryId data)))
                    (tags (cdr (assoc :tags data)))
                    (note (cdr (assoc :note data)))
                    (is-starred (cdr (assoc :isStarred data))))
               (update-favorite favorite-id user-id
                                :content content
                                :category-id category-id
                                :tags tags
                                :note note
                                :is-starred is-starred)
               (encode-api-response
                (make-api-response `((:success . t))))))
            ((string= (hunchentoot:request-method hunchentoot:*request*) "DELETE")
             (remove-favorite favorite-id user-id)
             (encode-api-response
              (make-api-response `((:success . t)))))
            (t
             (setf (hunchentoot:return-code*) 405)
             (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed")))))))
      (error (c)
        (log-error "Favorite operation error: ~A" c)
        (setf (hunchentoot:return-code*) 500)
        (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c))))))

;; GET /api/v1/favorites/categories - Get favorite categories
;; POST /api/v1/favorites/categories - Create category
(defun api-favorite-categories-handler ()
  "Get or create favorite categories"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (let ((user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-favorite-categories-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (cond
      ((string= (hunchentoot:request-method hunchentoot:*request*) "GET")
       (handler-case
           (let ((categories (get-favorite-categories user-id)))
             (encode-api-response
              (make-api-response `((:success . t)
                                   (:data . ,categories)))))
         (error (c)
           (log-error "Get categories error: ~A" c)
           (setf (hunchentoot:return-code*) 500)
           (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c))))))
      ((string= (hunchentoot:request-method hunchentoot:*request*) "POST")
       (handler-case
           (let* ((json-str (get-request-body-string))
                  (data (cl-json:decode-json-from-string json-str))
                  (name (cdr (assoc :name data)))
                  (color (cdr (assoc :color data)))
                  (icon (cdr (assoc :icon data)))
                  (sort-order (cdr (assoc :sortOrder data))))
             (unless name
               (setf (hunchentoot:return-code*) 400)
               (return-from api-favorite-categories-handler
                 (encode-api-response (make-api-error "MISSING_FIELDS" "name is required"))))
             (let ((cat-id (create-favorite-category user-id name
                                                     :color color
                                                     :icon icon
                                                     :sort-order sort-order)))
               (encode-api-response
                (make-api-response `((:success . t)
                                     (:categoryId . ,cat-id))))))
         (error (c)
           (log-error "Create category error: ~A" c)
           (setf (hunchentoot:return-code*) 500)
           (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c))))))
      (t
       (setf (hunchentoot:return-code*) 405)
       (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed"))))))

;; PUT/DELETE /api/v1/favorites/categories/:id
(defun api-favorite-category-handler ()
  "Update or delete a specific category"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (let ((user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-favorite-category-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (handler-case
        (let* ((uri (hunchentoot:request-uri hunchentoot:*request*))
               (category-id (multiple-value-bind (match-start match-end reg-start reg-end)
                              (cl-ppcre:scan "^/api/v1/favorites/categories/([0-9]+)$" uri)
                              (if match-start
                                  (parse-integer (subseq uri (aref reg-start 0) (aref reg-end 0)))
                                  (return-from api-favorite-category-handler
                                    (progn
                                      (setf (hunchentoot:return-code*) 400)
                                      (encode-api-response (make-api-error "INVALID_URI" "Invalid category ID"))))))))
          (cond
            ((string= (hunchentoot:request-method hunchentoot:*request*) "PUT")
             (let* ((json-str (get-request-body-string))
                    (data (cl-json:decode-json-from-string json-str))
                    (name (cdr (assoc :name data)))
                    (color (cdr (assoc :color data)))
                    (icon (cdr (assoc :icon data)))
                    (sort-order (cdr (assoc :sortOrder data))))
               (update-favorite-category category-id user-id
                                         :name name
                                         :color color
                                         :icon icon
                                         :sort-order sort-order)
               (encode-api-response
                (make-api-response `((:success . t))))))
            ((string= (hunchentoot:request-method hunchentoot:*request*) "DELETE")
             (delete-favorite-category category-id user-id)
             (encode-api-response
              (make-api-response `((:success . t)))))
            (t
             (setf (hunchentoot:return-code*) 405)
             (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed")))))))
      (error (c)
        (log-error "Category operation error: ~A" c)
        (setf (hunchentoot:return-code*) 500)
        (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c)))))

;;;; ============================================================================
;;;; Call Management API (语音/视频通话)
;;;; ============================================================================

;; POST /api/v1/calls - Create call
(defun api-create-call-handler ()
  "Create a new call (voice/video)"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (unless (string= (hunchentoot:request-method hunchentoot:*request*) "POST")
    (setf (hunchentoot:return-code*) 405)
    (return-from api-create-call-handler
      (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed"))))
  (let ((user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-create-call-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (handler-case
        (let* ((json-str (get-request-body-string))
               (data (cl-json:decode-json-from-string json-str))
               (callee-id (cdr (assoc :calleeId data)))
               (call-type (keywordify (or (cdr (assoc :type data)) "voice")))
               (conversation-id (cdr (assoc :conversationId data))))
          (unless callee-id
            (setf (hunchentoot:return-code*) 400)
            (return-from api-create-call-handler
              (encode-api-response (make-api-error "MISSING_FIELDS" "calleeId is required"))))
          (let ((call (create-call user-id callee-id call-type :conversation-id conversation-id)))
            ;; Notify callee via WebSocket
            (notify-incoming-call call)
            (encode-api-response
             (make-api-response
              (list :id (call-id call)
                    :callerId (call-caller-id call)
                    :calleeId (call-callee-id call)
                    :type (string-downcase (call-type call))
                    :status (string-downcase (call-status call)))
              :message "Call created"))))
      (error (c)
        (log-error "Create call error: ~A" c)
        (setf (hunchentoot:return-code*) 500)
        (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c)))))))

;; GET /api/v1/calls/:id - Get call info
(defun api-get-call-handler ()
  "Get call information"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (let* ((uri (hunchentoot:request-uri hunchentoot:*request*))
         (call-id (multiple-value-bind (match-start match-end reg-start reg-end)
                    (cl-ppcre:scan "^/api/v1/calls/([^/]+)$" uri)
                    (if match-start
                        (subseq uri (aref reg-start 0) (aref reg-end 0))
                        (return-from api-get-call-handler
                          (progn
                            (setf (hunchentoot:return-code*) 400)
                            (encode-api-response (make-api-error "INVALID_URI" "Invalid URI")))))))
         (user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-get-call-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (let ((call (get-call call-id)))
      (unless call
        (setf (hunchentoot:return-code*) 404)
        (return-from api-get-call-handler
          (encode-api-response (make-api-error "NOT_FOUND" "Call not found"))))
      (unless (or (string= (call-caller-id call) user-id)
                  (string= (call-callee-id call) user-id))
        (setf (hunchentoot:return-code*) 403)
        (return-from api-get-call-handler
          (encode-api-response (make-api-error "ACCESS_DENIED" "Not authorized"))))
      (encode-api-response
       (make-api-response
        (list :id (call-id call)
              :callerId (call-caller-id call)
              :calleeId (call-callee-id call)
              :conversationId (call-conversation-id call)
              :type (string-downcase (call-type call))
              :status (string-downcase (call-status call))
              :duration (call-duration call)
              :startedAt (call-started-at call)
              :endedAt (call-ended-at call)
              :createdAt (call-created-at call)))))))

;; POST /api/v1/calls/:id/answer - Answer call
(defun api-answer-call-handler ()
  "Answer an incoming call"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (unless (string= (hunchentoot:request-method hunchentoot:*request*) "POST")
    (setf (hunchentoot:return-code*) 405)
    (return-from api-answer-call-handler
      (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed"))))
  (let* ((uri (hunchentoot:request-uri hunchentoot:*request*))
         (call-id (multiple-value-bind (match-start match-end reg-start reg-end)
                    (cl-ppcre:scan "^/api/v1/calls/([^/]+)/answer$" uri)
                    (if match-start
                        (subseq uri (aref reg-start 0) (aref reg-end 0))
                        (return-from api-answer-call-handler
                          (progn
                            (setf (hunchentoot:return-code*) 400)
                            (encode-api-response (make-api-error "INVALID_URI" "Invalid URI")))))))
         (user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-answer-call-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (let ((call (get-call call-id)))
      (unless call
        (setf (hunchentoot:return-code*) 404)
        (return-from api-answer-call-handler
          (encode-api-response (make-api-error "NOT_FOUND" "Call not found"))))
      (unless (string= (call-callee-id call) user-id)
        (setf (hunchentoot:return-code*) 403)
        (return-from api-answer-call-handler
          (encode-api-response (make-api-error "ACCESS_DENIED" "Only callee can answer"))))
      (update-call-status call-id "answered")
      ;; Notify caller
      (notify-call-answered call)
      (encode-api-response
       (make-api-response nil :message "Call answered")))))

;; POST /api/v1/calls/:id/reject - Reject call
(defun api-reject-call-handler ()
  "Reject an incoming call"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (unless (string= (hunchentoot:request-method hunchentoot:*request*) "POST")
    (setf (hunchentoot:return-code*) 405)
    (return-from api-reject-call-handler
      (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed"))))
  (let* ((uri (hunchentoot:request-uri hunchentoot:*request*))
         (call-id (multiple-value-bind (match-start match-end reg-start reg-end)
                    (cl-ppcre:scan "^/api/v1/calls/([^/]+)/reject$" uri)
                    (if match-start
                        (subseq uri (aref reg-start 0) (aref reg-end 0))
                        (return-from api-reject-call-handler
                          (progn
                            (setf (hunchentoot:return-code*) 400)
                            (encode-api-response (make-api-error "INVALID_URI" "Invalid URI")))))))
         (user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-reject-call-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (let ((call (get-call call-id)))
      (unless call
        (setf (hunchentoot:return-code*) 404)
        (return-from api-reject-call-handler
          (encode-api-response (make-api-error "NOT_FOUND" "Call not found"))))
      (unless (string= (call-callee-id call) user-id)
        (setf (hunchentoot:return-code*) 403)
        (return-from api-reject-call-handler
          (encode-api-response (make-api-error "ACCESS_DENIED" "Only callee can reject"))))
      (update-call-status call-id "rejected")
      ;; Notify caller
      (notify-call-rejected call)
      (encode-api-response
       (make-api-response nil :message "Call rejected")))))

;; POST /api/v1/calls/:id/end - End call
(defun api-end-call-handler ()
  "End an ongoing call"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (unless (string= (hunchentoot:request-method hunchentoot:*request*) "POST")
    (setf (hunchentoot:return-code*) 405)
    (return-from api-end-call-handler
      (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed"))))
  (let* ((uri (hunchentoot:request-uri hunchentoot:*request*))
         (call-id (multiple-value-bind (match-start match-end reg-start reg-end)
                    (cl-ppcre:scan "^/api/v1/calls/([^/]+)/end$" uri)
                    (if match-start
                        (subseq uri (aref reg-start 0) (aref reg-end 0))
                        (return-from api-end-call-handler
                          (progn
                            (setf (hunchentoot:return-code*) 400)
                            (encode-api-response (make-api-error "INVALID_URI" "Invalid URI")))))))
         (user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-end-call-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (let ((call (get-call call-id)))
      (unless call
        (setf (hunchentoot:return-code*) 404)
        (return-from api-end-call-handler
          (encode-api-response (make-api-error "NOT_FOUND" "Call not found"))))
      (unless (or (string= (call-caller-id call) user-id)
                  (string= (call-callee-id call) user-id))
        (setf (hunchentoot:return-code*) 403)
        (return-from api-end-call-handler
          (encode-api-response (make-api-error "ACCESS_DENIED" "Not authorized"))))
      (update-call-status call-id "ended")
      ;; Notify both parties
      (notify-call-ended call)
      (encode-api-response
       (make-api-response nil :message "Call ended")))))

;; POST /api/v1/calls/:id/offer - Send SDP offer
(defun api-send-offer-handler ()
  "Send SDP offer for WebRTC"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (unless (string= (hunchentoot:request-method hunchentoot:*request*) "POST")
    (setf (hunchentoot:return-code*) 405)
    (return-from api-send-offer-handler
      (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed"))))
  (let* ((uri (hunchentoot:request-uri hunchentoot:*request*))
         (call-id (multiple-value-bind (match-start match-end reg-start reg-end)
                    (cl-ppcre:scan "^/api/v1/calls/([^/]+)/offer$" uri)
                    (if match-start
                        (subseq uri (aref reg-start 0) (aref reg-end 0))
                        (return-from api-send-offer-handler
                          (progn
                            (setf (hunchentoot:return-code*) 400)
                            (encode-api-response (make-api-error "INVALID_URI" "Invalid URI")))))))
         (user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-send-offer-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (handler-case
        (let* ((json-str (get-request-body-string))
               (data (cl-json:decode-json-from-string json-str))
               (offer (cdr (assoc :offer data))))
          (unless offer
            (setf (hunchentoot:return-code*) 400)
            (return-from api-send-offer-handler
              (encode-api-response (make-api-error "MISSING_FIELDS" "offer is required"))))
          (publish-call-offer call-id user-id offer)
          (encode-api-response
           (make-api-response nil :message "Offer sent"))))
      (error (c)
        (log-error "Send offer error: ~A" c)
        (setf (hunchentoot:return-code*) 500)
        (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c))))))

;; POST /api/v1/calls/:id/answer - Send SDP answer
(defun api-send-answer-handler ()
  "Send SDP answer for WebRTC"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (unless (string= (hunchentoot:request-method hunchentoot:*request*) "POST")
    (setf (hunchentoot:return-code*) 405)
    (return-from api-send-answer-handler
      (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed"))))
  (let* ((uri (hunchentoot:request-uri hunchentoot:*request*))
         (call-id (multiple-value-bind (match-start match-end reg-start reg-end)
                    (cl-ppcre:scan "^/api/v1/calls/([^/]+)/answer$" uri)
                    (if match-start
                        (subseq uri (aref reg-start 0) (aref reg-end 0))
                        (return-from api-send-answer-handler
                          (progn
                            (setf (hunchentoot:return-code*) 400)
                            (encode-api-response (make-api-error "INVALID_URI" "Invalid URI")))))))
         (user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-send-answer-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (handler-case
        (let* ((json-str (get-request-body-string))
               (data (cl-json:decode-json-from-string json-str))
               (answer (cdr (assoc :answer data))))
          (unless answer
            (setf (hunchentoot:return-code*) 400)
            (return-from api-send-answer-handler
              (encode-api-response (make-api-error "MISSING_FIELDS" "answer is required"))))
          (publish-call-answer call-id user-id answer)
          (encode-api-response
           (make-api-response nil :message "Answer sent"))))
      (error (c)
        (log-error "Send answer error: ~A" c)
        (setf (hunchentoot:return-code*) 500)
        (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c))))))

;; POST /api/v1/calls/:id/ice - Send ICE candidate
(defun api-send-ice-candidate-handler ()
  "Send ICE candidate for WebRTC"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (unless (string= (hunchentoot:request-method hunchentoot:*request*) "POST")
    (setf (hunchentoot:return-code*) 405)
    (return-from api-send-ice-candidate-handler
      (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed"))))
  (let* ((uri (hunchentoot:request-uri hunchentoot:*request*))
         (call-id (multiple-value-bind (match-start match-end reg-start reg-end)
                    (cl-ppcre:scan "^/api/v1/calls/([^/]+)/ice$" uri)
                    (if match-start
                        (subseq uri (aref reg-start 0) (aref reg-end 0))
                        (return-from api-send-ice-candidate-handler
                          (progn
                            (setf (hunchentoot:return-code*) 400)
                            (encode-api-response (make-api-error "INVALID_URI" "Invalid URI")))))))
         (user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-send-ice-candidate-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (handler-case
        (let* ((json-str (get-request-body-string))
               (data (cl-json:decode-json-from-string json-str))
               (candidate (cdr (assoc :candidate data))))
          (unless candidate
            (setf (hunchentoot:return-code*) 400)
            (return-from api-send-ice-candidate-handler
              (encode-api-response (make-api-error "MISSING_FIELDS" "candidate is required"))))
          (publish-ice-candidate call-id user-id candidate)
          (encode-api-response
           (make-api-response nil :message "ICE candidate sent"))))
      (error (c)
        (log-error "Send ICE candidate error: ~A" c)
        (setf (hunchentoot:return-code*) 500)
        (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c))))))

;; GET /api/v1/calls/history - Get call history
(defun api-get-call-history-handler ()
  "Get user's call history"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (unless (string= (hunchentoot:request-method hunchentoot:*request*) "GET")
    (setf (hunchentoot:return-code*) 405)
    (return-from api-get-call-history-handler
      (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed"))))
  (let ((user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-get-call-history-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (handler-case
        (let* ((limit-param (hunchentoot:get-parameter "limit"))
               (offset-param (hunchentoot:get-parameter "offset"))
               (limit (if limit-param (parse-integer limit-param :junk-allowed t) 20))
               (offset (if offset-param (parse-integer offset-param :junk-allowed t) 0))
               (calls (get-user-calls user-id :limit limit :offset offset)))
          (encode-api-response
           (make-api-response calls)))
      (error (c)
        (log-error "Get call history error: ~A" c)
        (setf (hunchentoot:return-code*) 500)
        (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c)))))))

;;;; Notification helpers for calls

(defun notify-incoming-call (call)
  "Notify callee of incoming call"
  (let ((message `((:type . :incoming-call)
                   (:callId . ,(call-id call))
                   (:callerId . ,(call-caller-id call))
                   (:calleeId . ,(call-callee-id call))
                   (:callType . ,(string-downcase (call-type call)))
                   (:ts . ,(lispim-universal-to-unix-ms (get-universal-time))))))
    (push-to-online-user (call-callee-id call) message)))

(defun notify-call-answered (call)
  "Notify caller that call was answered"
  (let ((message `((:type . :call-answered)
                   (:callId . ,(call-id call))
                   (:ts . ,(lispim-universal-to-unix-ms (get-universal-time))))))
    (push-to-online-user (call-caller-id call) message)))

(defun notify-call-rejected (call)
  "Notify caller that call was rejected"
  (let ((message `((:type . :call-rejected)
                   (:callId . ,(call-id call))
                   (:ts . ,(lispim-universal-to-unix-ms (get-universal-time))))))
    (push-to-online-user (call-caller-id call) message)))

;;;; ============================================================================
;;;; Privacy API (隐私增强)
;;;; ============================================================================

;; PUT /api/v1/conversations/:id/disappearing - Set disappearing messages
(defun api-disappearing-settings-handler ()
  "Set or get disappearing messages settings for a conversation"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (let ((user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-disappearing-settings-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (let* ((conversation-id (parse-integer (hunchentoot:path-parameter 1) :junk-allowed t)))
      (cond
        ((string= (hunchentoot:request-method hunchentoot:*request*) "PUT")
         ;; Update settings
         (handler-case
             (let* ((json-str (get-request-body-string))
                    (data (cl-json:decode-json-from-string json-str))
                    (enabled (cdr (assoc :enabled data)))
                    (timer-seconds (or (cdr (assoc :timerSeconds data)) 86400)))
               (unless (member enabled '(t nil))
                 (setf (hunchentoot:return-code*) 400)
                 (return-from api-disappearing-settings-handler
                   (encode-api-response (make-api-error "INVALID_ENABLED" "enabled must be boolean"))))
               (set-conversation-disappearing-messages conversation-id enabled :timer-seconds timer-seconds)
               (encode-api-response
                (make-api-response `((:success . t)
                                     (:enabled . ,enabled)
                                     (:timerSeconds . ,timer-seconds)))))
           (error (c)
             (log-error "Set disappearing settings error: ~A" c)
             (setf (hunchentoot:return-code*) 500)
             (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c))))))
        ((string= (hunchentoot:request-method hunchentoot:*request*) "GET")
         ;; Get settings
         (handler-case
             (let ((config (get-conversation-disappearing-config conversation-id)))
               (encode-api-response
                (make-api-response
                 `((:success . t)
                   (:enabled . ,(disappearing-message-config-enabled config))
                   (:timerSeconds . ,(disappearing-message-config-timer-seconds config))
                   (:timerStart . ,(symbol-name (disappearing-message-config-timer-start config)))))))
           (error (c)
             (log-error "Get disappearing settings error: ~A" c)
             (setf (hunchentoot:return-code*) 500)
             (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c))))))
        (t
         (setf (hunchentoot:return-code*) 405)
         (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed")))))))

;; POST /api/v1/messages/:id/delete-all - Delete message for everyone
(defun api-delete-message-for-all-handler ()
  "Delete message for everyone (bidirectional delete)"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (unless (string= (hunchentoot:request-method hunchentoot:*request*) "POST")
    (setf (hunchentoot:return-code*) 405)
    (return-from api-delete-message-for-all-handler
      (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed"))))
  (let ((user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-delete-message-for-all-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (handler-case
        (let* ((message-id (parse-integer (hunchentoot:path-parameter 1) :junk-allowed t))
               (json-str (get-request-body-string))
               (data (if (plusp (length json-str))
                         (cl-json:decode-json-from-string json-str)
                         nil))
               (reason (or (cdr (assoc :reason data)) "")))
          (delete-message-for-all message-id reason)
          (encode-api-response
           (make-api-response `((:success . t)
                                (:messageId . ,message-id)))))
      (message-not-found ()
        (setf (hunchentoot:return-code*) 404)
        (encode-api-response (make-api-error "MESSAGE_NOT_FOUND" "Message not found")))
      (auth-error ()
        (setf (hunchentoot:return-code*) 403)
        (encode-api-response (make-api-error "PERMISSION_DENIED" "No permission to delete this message")))
      (message-recall-timeout ()
        (setf (hunchentoot:return-code*) 400)
        (encode-api-response (make-api-error "TIMEOUT" "Message deletion timeout exceeded")))
      (error (c)
        (log-error "Delete message for all error: ~A" c)
        (setf (hunchentoot:return-code*) 500)
        (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c)))))))

;; POST /api/v1/messages/:id/delete-self - Delete message for self only
(defun api-delete-message-for-self-handler ()
  "Delete message for self only (unilateral delete)"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (unless (string= (hunchentoot:request-method hunchentoot:*request*) "POST")
    (setf (hunchentoot:return-code*) 405)
    (return-from api-delete-message-for-self-handler
      (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed"))))
  (let ((user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-delete-message-for-self-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (handler-case
        (let ((message-id (parse-integer (hunchentoot:path-parameter 1) :junk-allowed t)))
          (delete-message-for-self message-id)
          (encode-api-response
           (make-api-response `((:success . t)
                                (:messageId . ,message-id)))))
      (message-not-found ()
        (setf (hunchentoot:return-code*) 404)
        (encode-api-response (make-api-error "MESSAGE_NOT_FOUND" "Message not found")))
      (conversation-access-denied ()
        (setf (hunchentoot:return-code*) 403)
        (encode-api-response (make-api-error "PERMISSION_DENIED" "No access to this conversation")))
      (error (c)
        (log-error "Delete message for self error: ~A" c)
        (setf (hunchentoot:return-code*) 500)
        (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c)))))))

;; GET /api/v1/privacy/settings - Get privacy settings
;; GET /api/v1/privacy/stats - Get privacy statistics
(defun api-privacy-stats-handler ()
  "Get privacy feature statistics"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (unless (string= (hunchentoot:request-method hunchentoot:*request*) "GET")
    (setf (hunchentoot:return-code*) 405)
    (return-from api-privacy-stats-handler
      (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed"))))
  (handler-case
      (let ((stats (get-privacy-stats)))
        (encode-api-response
         (make-api-response `((:success . t)
                              (:stats . ,stats)))))
    (error (c)
      (log-error "Get privacy stats error: ~A" c)
      (setf (hunchentoot:return-code*) 500)
      (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c))))))

;;;; ============================================================================
;;;; Contact Management API (联系人管理)
;;;; ============================================================================

;; GET /api/v1/contacts/friends - Get friend list
(defun api-friend-list-handler ()
  "Get user's friend list"
  (when (handle-options-if-needed)
    (return-from api-friend-list-handler ""))
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (unless (string= (hunchentoot:request-method hunchentoot:*request*) "GET")
    (setf (hunchentoot:return-code*) 405)
    (return-from api-friend-list-handler
      (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed"))))
  (let ((user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-friend-list-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (handler-case
        (let* ((status-param (hunchentoot:get-parameter "status"))
               (status (or status-param "accepted"))
               (friends (get-friends user-id status)))
          (encode-api-response
           (make-api-response `((:success . t)
                                (:data . ,friends)))))
      (error (c)
        (log-error "Get friend list error: ~A" c)
        (setf (hunchentoot:return-code*) 500)
        (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c)))))))

;; GET /api/v1/contacts/friend-requests - Get friend requests
(defun api-friend-requests-handler ()
  "Get user's friend requests"
  (setf (hunchentoot:content-type*) "application/json")
  (unless (string= (hunchentoot:request-method hunchentoot:*request*) "GET")
    (setf (hunchentoot:return-code*) 405)
    (return-from api-friend-requests-handler
      (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed"))))
  (let ((user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-friend-requests-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (handler-case
        (let* ((status-param (hunchentoot:get-parameter "status"))
               (status (or status-param "pending"))
               (requests (get-friend-requests user-id status)))
          (encode-api-response
           (make-api-response `((:success . t)
                                (:data . ,requests)))))
      (error (c)
        (log-error "Get friend requests error: ~A" c)
        (setf (hunchentoot:return-code*) 500)
        (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c)))))))

;; POST /api/v1/contacts/friend-request/send - Send friend request
(defun api-send-friend-request-handler ()
  "Send a friend request"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (unless (string= (hunchentoot:request-method hunchentoot:*request*) "POST")
    (setf (hunchentoot:return-code*) 405)
    (return-from api-send-friend-request-handler
      (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed"))))
  (let ((user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-send-friend-request-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (handler-case
        (let* ((json-str (get-request-body-string))
               (data (cl-json:decode-json-from-string json-str))
               receiver-id
               message)
          ;; Debug logging
          (log-info "Friend request - json-str: ~A, data: ~A, type-of: ~A" json-str data (type-of data))
          ;; Validate that data is an alist (JSON object)
          ;; cl-json returns: object -> alist, array -> list, true/false -> T/NIL, null -> NIL, number/string -> atom
          (when (or (null data)        ; null or empty
                    (symbolp data)     ; boolean true/false
                    (numberp data)     ; number
                    (stringp data)     ; string
                    (vectorp data))    ; array
            (log-error "INVALID_JSON: data is not an alist, type: ~A" (type-of data))
            (setf (hunchentoot:return-code*) 400)
            (return-from api-send-friend-request-handler
              (encode-api-response (make-api-error "INVALID_JSON" "Request body must be a JSON object"))))
          ;; cl-json converts camelCase to kebab-case: receiverId -> :receiver-id
          (log-info "Before assoc - data type: ~A, data: ~A" (type-of data) data)
          (setf receiver-id (cdr (assoc :receiver-id data))
                message (cdr (assoc :message data)))
          (log-info "After assoc - receiver-id: ~A, message: ~A" receiver-id message)
          (unless receiver-id
            (setf (hunchentoot:return-code*) 400)
            (return-from api-send-friend-request-handler
              (encode-api-response (make-api-error "MISSING_FIELDS" "receiverId is required"))))
          (multiple-value-bind (success request-id error)
              (add-friend-request user-id receiver-id message)
            (log-info "add-friend-request returned: success=~A, request-id=~A, error=~A" success request-id error)
            (if success
                (encode-api-response
                 (make-api-response `((:success . t)
                                      (:requestId . ,request-id))))
                (progn
                  (setf (hunchentoot:return-code*) 400)
                  (encode-api-response (make-api-error "SEND_FAILED" error))))))
      (error (c)
        (log-error "Send friend request error: ~A" c)
        (setf (hunchentoot:return-code*) 500)
        (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c)))))))

;; POST /api/v1/contacts/friend-request/:id/accept - Accept friend request
(defun api-accept-friend-request-handler ()
  "Accept a friend request"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (let* ((uri (hunchentoot:request-uri hunchentoot:*request*))
         (method (hunchentoot:request-method hunchentoot:*request*)))
    (log-info "Accept handler: method=~A, uri=~A" method uri)
    (unless (string= method "POST")
      (setf (hunchentoot:return-code*) 405)
      (return-from api-accept-friend-request-handler
        (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed"))))
    (let ((user-id (require-auth)))
      (unless user-id
        (setf (hunchentoot:return-code*) 401)
        (return-from api-accept-friend-request-handler
          (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
      (handler-case
          (let* ((request-id-str (multiple-value-bind (match-start match-end reg-start reg-end)
                                     (cl-ppcre:scan "^/api/v1/contacts/friend-request/([^/]+)/accept$" uri)
                                   (if match-start
                                       (subseq uri (aref reg-start 0) (aref reg-end 0))
                                       (return-from api-accept-friend-request-handler
                                         (progn
                                           (setf (hunchentoot:return-code*) 400)
                                           (encode-api-response (make-api-error "INVALID_URI" "Invalid URI")))))))
                 (request-id (parse-integer request-id-str :junk-allowed t)))
            (log-info "Accept request: request-id-str=~A, request-id=~A (type: ~A)" request-id-str request-id (type-of request-id))
            (unless (and request-id (integerp request-id))
              (setf (hunchentoot:return-code*) 400)
              (return-from api-accept-friend-request-handler
                (encode-api-response (make-api-error "INVALID_ID" "Invalid request ID"))))
            (multiple-value-bind (success error)
                (accept-friend-request request-id)
              (if success
                  (encode-api-response
                   (make-api-response `((:success . t))))
                  (progn
                    (setf (hunchentoot:return-code*) 400)
                    (encode-api-response (make-api-error "ACCEPT_FAILED" error))))))
        (error (c)
          (log-error "Accept friend request error: ~A" c)
          (setf (hunchentoot:return-code*) 500)
          (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c))))))))

;; POST /api/v1/contacts/friend-request/:id/reject - Reject friend request
(defun api-reject-friend-request-handler ()
  "Reject a friend request"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (unless (string= (hunchentoot:request-method hunchentoot:*request*) "POST")
    (setf (hunchentoot:return-code*) 405)
    (return-from api-reject-friend-request-handler
      (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed"))))
  (let ((user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-reject-friend-request-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (handler-case
        (let ((request-id (parse-integer (hunchentoot:path-parameter 1) :junk-allowed t)))
          (multiple-value-bind (success error)
              (reject-friend-request request-id)
            (if success
                (encode-api-response
                 (make-api-response `((:success . t))))
                (progn
                  (setf (hunchentoot:return-code*) 400)
                  (encode-api-response (make-api-error "REJECT_FAILED" error))))))
      (error (c)
        (log-error "Reject friend request error: ~A" c)
        (setf (hunchentoot:return-code*) 500)
        (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c)))))))

;; GET /api/v1/contacts/blacklist - Get blacklist
(defun api-blacklist-handler ()
  "Get user's blacklist"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (unless (string= (hunchentoot:request-method hunchentoot:*request*) "GET")
    (setf (hunchentoot:return-code*) 405)
    (return-from api-blacklist-handler
      (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed"))))
  (let ((user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-blacklist-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (handler-case
        (let ((blacklist (get-blacklist user-id)))
          (encode-api-response
           (make-api-response `((:success . t)
                                (:data . ,blacklist)))))
      (error (c)
        (log-error "Get blacklist error: ~A" c)
        (setf (hunchentoot:return-code*) 500)
        (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c)))))))

;; POST /api/v1/contacts/blacklist/:user-id - Add to blacklist
(defun api-blacklist-user-handler ()
  "Add user to blacklist or remove from blacklist"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (let ((user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-blacklist-user-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (let ((blocked-user-id (hunchentoot:path-parameter 1)))
      (cond
        ((string= (hunchentoot:request-method hunchentoot:*request*) "POST")
         ;; Add to blacklist
         (handler-case
             (progn
               (add-to-blacklist user-id blocked-user-id)
               (encode-api-response
                (make-api-response `((:success . t)))))
           (error (c)
             (log-error "Add to blacklist error: ~A" c)
             (setf (hunchentoot:return-code*) 500)
             (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c))))))
        ((string= (hunchentoot:request-method hunchentoot:*request*) "DELETE")
         ;; Remove from blacklist
         (handler-case
             (progn
               (remove-from-blacklist user-id blocked-user-id)
               (encode-api-response
                (make-api-response `((:success . t)))))
           (error (c)
             (log-error "Remove from blacklist error: ~A" c)
             (setf (hunchentoot:return-code*) 500)
             (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c))))))
        (t
         (setf (hunchentoot:return-code*) 405)
         (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed")))))))

;;;; Privacy Settings API

;; GET/PUT /api/v1/privacy/settings - Get/update privacy settings
(defun api-privacy-settings-handler ()
  "Get or update user privacy settings"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (let ((user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-privacy-settings-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (cond
      ((string= (hunchentoot:request-method hunchentoot:*request*) "GET")
       ;; Get privacy settings
       (handler-case
           (let* ((settings (get-user-privacy-settings user-id))
                  (result (list :hide-online-status (user-privacy-settings-hide-online-status settings)
                                :hide-read-receipt (user-privacy-settings-hide-read-receipt settings)
                                :show-profile-photo (user-privacy-settings-show-profile-photo settings)
                                :show-last-seen (user-privacy-settings-show-last-seen settings))))
             (encode-api-response (make-api-response result)))
         (error (c)
           (log-error "Get privacy settings error: ~A" c)
           (setf (hunchentoot:return-code*) 500)
           (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c))))))
      ((string= (hunchentoot:request-method hunchentoot:*request*) "PUT")
       ;; Update privacy settings
       (handler-case
           (let* ((json-str (get-request-body-string))
                  (data (cl-json:decode-json-from-string json-str))
                  ;; Use assoc to check if key exists, then get value
                  (hide-online-status-cell (assoc :hide-online-status data))
                  (hide-read-receipt-cell (assoc :hide-read-receipt data))
                  (show-profile-photo-cell (assoc :show-profile-photo data))
                  (show-last-seen-cell (assoc :show-last-seen data)))
             (log-info "PUT /api/v1/privacy/settings - user=~A, json=~A, data=~A" user-id json-str data)
             (log-info "Cells: hide-online=~A, hide-read=~A, show-photo=~A, show-seen=~A"
                       hide-online-status-cell
                       hide-read-receipt-cell
                       show-profile-photo-cell
                       show-last-seen-cell)
             ;; Use cell to distinguish missing key from false value
             (set-user-privacy-settings
              user-id
              :hide-online-status (if hide-online-status-cell (cdr hide-online-status-cell) :unset)
              :hide-read-receipt (if hide-read-receipt-cell (cdr hide-read-receipt-cell) :unset)
              :show-profile-photo (if show-profile-photo-cell (cdr show-profile-photo-cell) :unset)
              :show-last-seen (if show-last-seen-cell (cdr show-last-seen-cell) :unset))
             (let ((response (make-api-response (list :success t))))
               (log-info "API response: ~A" response)
               (encode-api-response response)))
         (error (c)
           (log-error "Update privacy settings error: ~A" c)
           (setf (hunchentoot:return-code*) 500)
           (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c))))))
      (t
       (setf (hunchentoot:return-code*) 405)
       (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed"))))))

;; GET /api/v1/privacy/user/:id - Check user's privacy settings
(defun api-privacy-user-settings-handler ()
  "Check another user's privacy settings (what we're allowed to see)"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (let ((user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-privacy-user-settings-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (let ((target-user-id (hunchentoot:path-parameter 1)))
      (unless target-user-id
        (setf (hunchentoot:return-code*) 400)
        (return-from api-privacy-user-settings-handler
          (encode-api-response (make-api-error "MISSING_FIELDS" "User ID required"))))
      (handler-case
          (let* ((settings (get-user-privacy-settings target-user-id))
                 (result (list :canShowProfilePhoto (user-privacy-settings-show-profile-photo settings)
                               :canShowLastSeen (user-privacy-settings-show-last-seen settings))))
            (encode-api-response (make-api-response result)))
        (error (c)
          (log-error "Get user privacy settings error: ~A" c)
          (setf (hunchentoot:return-code*) 500)
          (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c))))))))

;; GET /api/v1/contacts/star - Get star contacts
(defun api-star-contacts-handler ()
  "Get user's star contacts"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (unless (string= (hunchentoot:request-method hunchentoot:*request*) "GET")
    (setf (hunchentoot:return-code*) 405)
    (return-from api-star-contacts-handler
      (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed"))))
  (let ((user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-star-contacts-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (handler-case
        (let ((star-contacts (get-star-contacts user-id)))
          (encode-api-response
           (make-api-response `((:success . t)
                                (:data . ,star-contacts)))))
      (error (c)
        (log-error "Get star contacts error: ~A" c)
        (setf (hunchentoot:return-code*) 500)
        (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c)))))))

;; POST /api/v1/contacts/star/:user-id - Add/remove star contact
(defun api-star-user-handler ()
  "Add or remove star contact"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (let ((user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-star-user-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (let ((star-user-id (hunchentoot:path-parameter 1)))
      (cond
        ((string= (hunchentoot:request-method hunchentoot:*request*) "POST")
         ;; Add star contact
         (handler-case
             (progn
               (add-star-contact user-id star-user-id)
               (encode-api-response
                (make-api-response `((:success . t)))))
           (error (c)
             (log-error "Add star contact error: ~A" c)
             (setf (hunchentoot:return-code*) 500)
             (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c))))))
        ((string= (hunchentoot:request-method hunchentoot:*request*) "DELETE")
         ;; Remove star contact
         (handler-case
             (progn
               (remove-star-contact user-id star-user-id)
               (encode-api-response
                (make-api-response `((:success . t)))))
           (error (c)
             (log-error "Remove star contact error: ~A" c)
             (setf (hunchentoot:return-code*) 500)
             (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c))))))
        (t
         (setf (hunchentoot:return-code*) 405)
         (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed")))))))

;;;; ============================================================================
;;;; Message Reactions API (消息表情回应)
;;;; ============================================================================

;; GET /api/v1/messages/:id/reactions - Get message reactions
(defun api-message-reactions-handler ()
  "Get reactions for a message"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (unless (string= (hunchentoot:request-method hunchentoot:*request*) "GET")
    (setf (hunchentoot:return-code*) 405)
    (return-from api-message-reactions-handler
      (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed"))))
  (handler-case
      (let ((message-id (parse-integer (hunchentoot:path-parameter 1) :junk-allowed t)))
        (let ((reactions (get-message-reactions message-id)))
          (encode-api-response
           (make-api-response `((:success . t)
                                (:data . ,reactions)))))
    (error (c)
      (log-error "Get message reactions error: ~A" c)
      (setf (hunchentoot:return-code*) 500)
      (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c)))))))

;; POST/DELETE /api/v1/messages/:id/reactions/:emoji - Add/remove reaction
(defun api-message-reaction-user-handler ()
  "Add or remove a reaction from a message"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (let ((user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-message-reaction-user-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (let* ((message-id (parse-integer (hunchentoot:path-parameter 1) :junk-allowed t))
           (emoji (hunchentoot:path-parameter 2)))
      (cond
        ((string= (hunchentoot:request-method hunchentoot:*request*) "POST")
         ;; Add reaction
         (handler-case
             (multiple-value-bind (success reaction)
                 (add-reaction message-id emoji user-id)
               (if success
                   (progn
                     ;; Broadcast reaction update via WebSocket
                     (let* ((msg (get-message message-id))
                            (conversation-id (when msg (message-conversation-id msg)))
                            (reactions (get-message-reactions message-id)))
                       (when (and msg conversation-id)
                         (broadcast-to-conversation
                          conversation-id
                          (encode-ws-message
                           `(:type "message-reaction"
                             :message-id ,message-id
                             :reactions ,reactions)))))
                     (encode-api-response
                      (make-api-response `((:success . t)
                                           (:reaction . ,reaction)))))
                   (progn
                     (setf (hunchentoot:return-code*) 400)
                     (encode-api-response (make-api-error "ALREADY_REACTED" "You already reacted with this emoji")))))
           (error (c)
             (log-error "Add reaction error: ~A" c)
             (setf (hunchentoot:return-code*) 500)
             (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c))))))
        ((string= (hunchentoot:request-method hunchentoot:*request*) "DELETE")
         ;; Remove reaction
         (handler-case
             (progn
               (remove-reaction message-id emoji user-id)
               ;; Broadcast reaction update via WebSocket
               (let* ((msg (get-message message-id))
                      (conversation-id (when msg (message-conversation-id msg)))
                      (reactions (get-message-reactions message-id)))
                 (when (and msg conversation-id)
                   (broadcast-to-conversation
                    conversation-id
                    (encode-ws-message
                     `(:type "message-reaction"
                       :message-id ,message-id
                       :reactions ,reactions)))))
               (encode-api-response
                (make-api-response `((:success . t)))))
           (error (c)
             (log-error "Remove reaction error: ~A" c)
             (setf (hunchentoot:return-code*) 500)
             (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c))))))
        (t
         (setf (hunchentoot:return-code*) 405)
         (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed")))))))

;;;; ============================================================================
;;;; Message Pinning API (消息置顶)
;;;; ============================================================================

;; GET /api/v1/conversations/:id/pinned-messages - Get pinned messages
(defun api-get-pinned-messages-handler ()
  "Get pinned messages for a conversation"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (unless (string= (hunchentoot:request-method hunchentoot:*request*) "GET")
    (setf (hunchentoot:return-code*) 405)
    (return-from api-get-pinned-messages-handler
      (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed"))))
  (handler-case
      (let ((conversation-id (parse-integer (hunchentoot:path-parameter 1) :junk-allowed t)))
        (let ((pinned-messages (get-pinned-messages conversation-id)))
          (encode-api-response
           (make-api-response `((:success . t)
                                (:data . ,pinned-messages)))))
      (error (c)
        (log-error "Get pinned messages error: ~A" c)
        (setf (hunchentoot:return-code*) 500)
        (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c)))))))

;; POST /api/v1/messages/:id/pin - Pin a message
(defun api-pin-message-handler ()
  "Pin a message in a conversation"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (let ((user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-pin-message-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (let* ((message-id (parse-integer (hunchentoot:path-parameter 1) :junk-allowed t))
           (json-str (get-request-body-string))
           (data (if (and json-str (not (string= json-str "")))
                     (cl-json:decode-json-from-string json-str)
                     nil))
           (conversation-id (cdr (assoc :conversationId data))))
      (unless conversation-id
        (setf (hunchentoot:return-code*) 400)
        (return-from api-pin-message-handler
          (encode-api-response (make-api-error "MISSING_FIELDS" "conversationId is required"))))
      (handler-case
          (progn
            (let ((*current-user-id* user-id))
              (pin-message message-id conversation-id user-id))
            (encode-api-response
             (make-api-response `((:success . t)))))
        (error (c)
          (log-error "Pin message error: ~A" c)
          (setf (hunchentoot:return-code*) 500)
          (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c))))))))

;; POST /api/v1/messages/:id/unpin - Unpin a message
(defun api-unpin-message-handler ()
  "Unpin a message in a conversation"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (let ((user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-unpin-message-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (let* ((message-id (parse-integer (hunchentoot:path-parameter 1) :junk-allowed t))
           (json-str (get-request-body-string))
           (data (if (and json-str (not (string= json-str "")))
                     (cl-json:decode-json-from-string json-str)
                     nil))
           (conversation-id (cdr (assoc :conversationId data))))
      (unless conversation-id
        (setf (hunchentoot:return-code*) 400)
        (return-from api-unpin-message-handler
          (encode-api-response (make-api-error "MISSING_FIELDS" "conversationId is required"))))
      (handler-case
          (progn
            (let ((*current-user-id* user-id))
              (unpin-message message-id conversation-id user-id))
            (encode-api-response
             (make-api-response `((:success . t)))))
        (error (c)
          (log-error "Unpin message error: ~A" c)
          (setf (hunchentoot:return-code*) 500)
          (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c))))))))

(defun notify-call-ended (call)
  "Notify both parties that call ended"
  (let ((message `((:type . :call-ended)
                   (:callId . ,(call-id call))
                   (:duration . ,(call-duration call))
                   (:ts . ,(lispim-universal-to-unix-ms (get-universal-time))))))
    (push-to-online-user (call-caller-id call) message)
    (push-to-online-user (call-callee-id call) message)))

;;;; ============================================================================
;;;; Account Management API (账号管理)
;;;; ============================================================================

;; POST /api/v1/account/change-password - Change password
(defun api-change-password-handler ()
  "Change current user's password"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (unless (string= (hunchentoot:request-method hunchentoot:*request*) "POST")
    (setf (hunchentoot:return-code*) 405)
    (return-from api-change-password-handler
      (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed"))))
  (let ((user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-change-password-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (let* ((json-str (get-request-body-string))
           (data (cl-json:decode-json-from-string json-str))
           (current-password (cdr (assoc :currentPassword data)))
           (new-password (cdr (assoc :newPassword data))))
      (unless (and current-password new-password)
        (setf (hunchentoot:return-code*) 400)
        (return-from api-change-password-handler
          (encode-api-response (make-api-error "MISSING_FIELDS" "currentPassword and newPassword are required"))))
      (unless (>= (length new-password) 6)
        (setf (hunchentoot:return-code*) 400)
        (return-from api-change-password-handler
          (encode-api-response (make-api-error "INVALID_PASSWORD" "Password must be at least 6 characters"))))
      ;; Verify current password
      (let ((user (get-user user-id)))
        (unless user
          (setf (hunchentoot:return-code*) 404)
          (return-from api-change-password-handler
            (encode-api-response (make-api-error "NOT_FOUND" "User not found"))))
        (let ((stored-hash (getf user :password-hash))
              (salt (getf user :password-salt)))
          (unless (verify-password current-password stored-hash salt)
            (setf (hunchentoot:return-code*) 401)
            (return-from api-change-password-handler
              (encode-api-response (make-api-error "INVALID_CREDENTIALS" "Current password is incorrect"))))
          ;; Update password using proper PBKDF2 hash
          (multiple-value-bind (new-hash new-salt)
              (hash-password new-password)
            (declare (ignore new-salt))
            (update-user user-id :password-hash new-hash)
            (encode-api-response (make-api-response nil :message "Password changed successfully")))))))

;; POST /api/v1/account/bind-phone - Bind phone number
(defun api-bind-phone-handler ()
  "Bind phone number to current user"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (unless (string= (hunchentoot:request-method hunchentoot:*request*) "POST")
    (setf (hunchentoot:return-code*) 405)
    (return-from api-bind-phone-handler
      (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed"))))
  (let ((user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-bind-phone-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (let* ((json-str (get-request-body-string))
           (data (cl-json:decode-json-from-string json-str))
           (phone (cdr (assoc :phone data)))
           (code (cdr (assoc :code data))))
      (unless (and phone code)
        (setf (hunchentoot:return-code*) 400)
        (return-from api-bind-phone-handler
          (encode-api-response (make-api-error "MISSING_FIELDS" "phone and code are required"))))
      ;; Verify phone code (implement verification logic)
      (unless (verify-phone-code phone code)
        (setf (hunchentoot:return-code*) 400)
        (return-from api-bind-phone-handler
          (encode-api-response (make-api-error "INVALID_CODE" "Verification code is incorrect"))))
      ;; Update user phone
      (update-user user-id :phone phone)
      (encode-api-response (make-api-response nil :message "Phone bound successfully")))))

;; POST /api/v1/account/bind-email - Bind email
(defun api-bind-email-handler ()
  "Bind email to current user"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (unless (string= (hunchentoot:request-method hunchentoot:*request*) "POST")
    (setf (hunchentoot:return-code*) 405)
    (return-from api-bind-email-handler
      (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed"))))
  (let ((user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-bind-email-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (let* ((json-str (get-request-body-string))
           (data (cl-json:decode-json-from-string json-str))
           (email (cdr (assoc :email data)))
           (code (cdr (assoc :code data))))
      (unless (and email code)
        (setf (hunchentoot:return-code*) 400)
        (return-from api-bind-email-handler
          (encode-api-response (make-api-error "MISSING_FIELDS" "email and code are required"))))
      ;; Verify email code
      (unless (verify-email-code email code)
        (setf (hunchentoot:return-code*) 400)
        (return-from api-bind-email-handler
          (encode-api-response (make-api-error "INVALID_CODE" "Verification code is incorrect"))))
      ;; Update user email
      (update-user user-id :email email)
      (encode-api-response (make-api-response nil :message "Email bound successfully"))))))

;; POST /api/v1/account/unbind-phone - Unbind phone number
(defun api-unbind-phone-handler ()
  "Unbind phone number from current user"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (unless (string= (hunchentoot:request-method hunchentoot:*request*) "POST")
    (setf (hunchentoot:return-code*) 405)
    (return-from api-unbind-phone-handler
      (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed"))))
  (let ((user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-unbind-phone-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (update-user user-id :phone nil)
    (encode-api-response (make-api-response nil :message "Phone unbound successfully"))))

;; POST /api/v1/account/unbind-email - Unbind email
(defun api-unbind-email-handler ()
  "Unbind email from current user"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (unless (string= (hunchentoot:request-method hunchentoot:*request*) "POST")
    (setf (hunchentoot:return-code*) 405)
    (return-from api-unbind-email-handler
      (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed"))))
  (let ((user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-unbind-email-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (update-user user-id :email nil)
    (encode-api-response (make-api-response nil :message "Email unbound successfully"))))

;; GET /api/v1/account/sessions - Get active sessions
(defun api-get-sessions-handler ()
  "Get current user's active sessions"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (unless (string= (hunchentoot:request-method hunchentoot:*request*) "GET")
    (setf (hunchentoot:return-code*) 405)
    (return-from api-get-sessions-handler
      (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed"))))
  (let ((user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-get-sessions-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (let ((sessions (get-user-sessions user-id)))
      (encode-api-response (make-api-response sessions)))))

;; DELETE /api/v1/account/sessions/:sessionId - Revoke session
(defun api-revoke-session-handler ()
  "Revoke a specific session"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (unless (string= (hunchentoot:request-method hunchentoot:*request*) "DELETE")
    (setf (hunchentoot:return-code*) 405)
    (return-from api-revoke-session-handler
      (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed"))))
  (let* ((uri (hunchentoot:request-uri hunchentoot:*request*))
         (session-id-str (multiple-value-bind (match-start match-end reg-start reg-end)
                             (cl-ppcre:scan "^/api/v1/account/sessions/([^/]+)$" uri)
                           (if match-start
                               (subseq uri (aref reg-start 0) (aref reg-end 0))
                               (return-from api-revoke-session-handler
                                 (progn
                                   (setf (hunchentoot:return-code*) 400)
                                   (encode-api-response (make-api-error "INVALID_URI" "Invalid URI")))))))
         (user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-revoke-session-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (invalidate-session session-id-str)
    (encode-api-response (make-api-response nil :message "Session revoked"))))

;; POST /api/v1/account/delete - Delete account
(defun api-delete-account-handler ()
  "Delete current user's account"
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (unless (string= (hunchentoot:request-method hunchentoot:*request*) "POST")
    (setf (hunchentoot:return-code*) 405)
    (return-from api-delete-account-handler
      (encode-api-response (make-api-error "METHOD_NOT_ALLOWED" "Method not allowed"))))
  (let ((user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-delete-account-handler
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (let* ((json-str (get-request-body-string))
           (data (cl-json:decode-json-from-string json-str))
           (password (cdr (assoc :password data))))
      (unless password
        (setf (hunchentoot:return-code*) 400)
        (return-from api-delete-account-handler
          (encode-api-response (make-api-error "MISSING_FIELDS" "password is required"))))
      ;; Verify password
      (let ((user (get-user user-id)))
        (unless user
          (setf (hunchentoot:return-code*) 404)
          (return-from api-delete-account-handler
            (encode-api-response (make-api-error "NOT_FOUND" "User not found"))))
        (let ((stored-hash (getf user :password-hash))
              (salt (getf user :password-salt)))
          (unless (verify-password password stored-hash salt)
            (setf (hunchentoot:return-code*) 401)
            (return-from api-delete-account-handler
              (encode-api-response (make-api-error "INVALID_CREDENTIALS" "Password is incorrect"))))
          ;; Delete account (soft delete or hard delete)
          (delete-user user-id)
          ;; Invalidate all sessions
          (invalidate-all-user-sessions user-id)
          (encode-api-response (make-api-response nil :message "Account deleted successfully")))))))

;; Helper functions (need to be implemented in auth.lisp or storage.lisp)
;; Removed duplicate verify-password function - now defined in auth.lisp
;; Original gateway.lisp version was: (defun verify-password (password hash) ...)
;; Use verify-password from auth.lisp which takes (password stored-hash salt)

(defun verify-phone-code (phone code)
  "Verify phone verification code"
  ;; TODO: Implement Redis-based code verification
  (declare (ignore phone code))
  t)

(defun verify-email-code (email code)
  "Verify email verification code"
  ;; TODO: Implement Redis-based code verification
  (declare (ignore email code))
  t)

(defun delete-user (user-id)
  "Delete user account"
  (declare (type string user-id))
  ;; Soft delete - mark user as deleted
  (postmodern:query
   "UPDATE users SET status = 'deleted' WHERE id = $1"
   user-id)
  (values t nil))

(defun invalidate-all-user-sessions (user-id)
  "Invalidate all user sessions"
  (declare (type string user-id))
  (postmodern:query
   "DELETE FROM sessions WHERE user_id = $1"
   user-id)
  (values t nil))

;;;; ============================================================================
;;;; New Features API (新功能 API - 2026-04-04)
;;;; ============================================================================

;;;; ---- Voice Messages API (语音消息) ----

;; POST /api/v1/upload/voice - Upload voice message
(hunchentoot:define-easy-handler (api-upload-voice :uri "/api/v1/upload/voice") ()
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (let ((user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-upload-voice
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (handler-case
        (let* ((content-type (hunchentoot:header-in "content-type")))
          (unless (and content-type (search "multipart/form-data" content-type))
            (setf (hunchentoot:return-code*) 400)
            (return-from api-upload-voice
              (encode-api-response (make-api-error "INVALID_CONTENT_TYPE" "Expected multipart/form-data"))))
          (let* ((file (hunchentoot:post-parameter "file"))
                 (duration (hunchentoot:post-parameter "duration")))
            (unless (and file duration)
              (setf (hunchentoot:return-code*) 400)
              (return-from api-upload-voice
                (encode-api-response (make-api-error "MISSING_FIELDS" "file and duration are required"))))
            (let* ((duration-num (parse-integer duration :junk-allowed t))
                   (filename (format nil "voice_~A_~A.wav" user-id (get-universal-time)))
                   (url (format nil "/api/v1/files/voice/~A" filename)))
              ;; TODO: Save voice file to storage
              (let ((waveform (generate-simplified-waveform duration-num)))
                (encode-api-response
                 (make-api-response `(:url ,url :waveform ,waveform))))))
      (error (c)
        (log-error "Upload voice error: ~A" c)
        (setf (hunchentoot:return-code*) 500)
        (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c))))))))

(defun generate-simplified-waveform (duration)
  "Generate simplified waveform data"
  (declare (type number duration))
  (let ((points 50)
        (waveform nil))
    (dotimes (i points (nreverse waveform))
      (push (random 1.0) waveform))))

;;;; ---- User Status API (用户状态/动态) ----

;; GET /api/v1/status/friends - Get friends' status updates
(hunchentoot:define-easy-handler (api-get-status-updates :uri "/api/v1/status/friends") ()
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (let ((user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-get-status-updates
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (handler-case
        (let ((statuses (get-friends-statuses user-id)))
          (encode-api-response
           (make-api-response
            (mapcar #'user-status-to-plist statuses))))
      (error (c)
        (log-error "Get status updates error: ~A" c)
        (setf (hunchentoot:return-code*) 500)
        (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c)))))))

;; GET /api/v1/status/:id - Get status detail
(hunchentoot:define-easy-handler (api-get-status :uri "/api/v1/status/:id") ()
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (let ((user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-get-status
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (handler-case
        (let* ((status-id (parse-integer (hunchentoot:path-parameter 1) :junk-allowed t))
               (status (get-user-status status-id)))
          (unless status
            (setf (hunchentoot:return-code*) 404)
            (return-from api-get-status
              (encode-api-response (make-api-error "NOT_FOUND" "Status not found"))))
          ;; Mark as viewed
          (view-status status-id user-id)
          (encode-api-response
           (make-api-response (user-status-to-plist status))))
      (error (c)
        (log-error "Get status error: ~A" c)
        (setf (hunchentoot:return-code*) 500)
        (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c)))))))

;; POST /api/v1/status - Create status
(hunchentoot:define-easy-handler (api-create-status :uri "/api/v1/status") ()
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (let ((user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-create-status
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (handler-case
        (let* ((content-type (hunchentoot:header-in "content-type")))
          (if (and content-type (search "multipart/form-data" content-type))
              ;; Multipart form data
              (let* ((content (hunchentoot:post-parameter "content"))
                     (media-type (hunchentoot:post-parameter "mediaType"))
                     (media-file (hunchentoot:post-parameter "mediaFile"))
                     (expires-in (or (hunchentoot:post-parameter "expiresIn") "86400")))
                (create-status-response user-id content media-type media-file expires-in))
              ;; JSON body
              (let* ((json-str (get-request-body-string))
                     (data (cl-json:decode-json-from-string json-str))
                     (content (cdr (assoc :content data)))
                     (media-type (cdr (assoc :mediaType data)))
                     (expires-in (cdr (assoc :expiresIn data))))
                (create-status-response user-id content (or media-type :text) nil (or expires-in "86400")))))
      (error (c)
        (log-error "Create status error: ~A" c)
        (setf (hunchentoot:return-code*) 500)
        (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c))))))

(defun create-status-response (user-id content media-type media-file expires-in)
  "Create status and return response"
  (let* ((user (get-user user-id))
         (status (create-user-status user-id content
                                     :username (getf user :username)
                                     :user-avatar (getf user :avatar)
                                     :media-type (or (and media-type (intern (string media-type) :keyword)) :text)
                                     :media-file media-file
                                     :expires-in (parse-integer expires-in :junk-allowed t))))
    (encode-api-response
     (make-api-response (user-status-to-plist status)))))

;; DELETE /api/v1/status/:id - Delete status
(hunchentoot:define-easy-handler (api-delete-status :uri "/api/v1/status/:id") ()
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (let ((user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-delete-status
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (handler-case
        (let* ((status-id (parse-integer (hunchentoot:path-parameter 1) :junk-allowed t)))
          (delete-user-status user-id status-id)
          (encode-api-response (make-api-response nil :message "Status deleted")))
      (error (c)
        (log-error "Delete status error: ~A" c)
        (setf (hunchentoot:return-code*) 500)
        (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c))))))))

;; POST /api/v1/status/:id/view - View status
(hunchentoot:define-easy-handler (api-view-status :uri "/api/v1/status/:id/view") ()
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (let ((user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-view-status
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (handler-case
        (let* ((status-id (parse-integer (hunchentoot:path-parameter 1) :junk-allowed t)))
          (view-status status-id user-id)
          (encode-api-response (make-api-response nil)))
      (error (c)
        (log-error "View status error: ~A" c)
        (setf (hunchentoot:return-code*) 500)
        (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c))))))

;;;; ---- Chat Folders API (聊天文件夹) ----

;; GET /api/v1/chat-folders - Get chat folders
(hunchentoot:define-easy-handler (api-get-chat-folders :uri "/api/v1/chat-folders") ()
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (let ((user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-get-chat-folders
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (handler-case
        (let ((folders (get-chat-folders user-id)))
          (encode-api-response
           (make-api-response
            (mapcar #'chat-folder-to-plist folders))))
      (error (c)
        (log-error "Get chat folders error: ~A" c)
        (setf (hunchentoot:return-code*) 500)
        (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c))))))))

;; POST /api/v1/chat-folders - Create chat folder
(hunchentoot:define-easy-handler (api-create-chat-folder :uri "/api/v1/chat-folders") ()
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (let ((user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-create-chat-folder
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (handler-case
        (let* ((json-str (get-request-body-string))
               (data (cl-json:decode-json-from-string json-str))
               (name (cdr (assoc :name data)))
               (icon (cdr (assoc :icon data)))
               (conversation-ids (cdr (assoc :conversationIds data))))
          (unless name
            (setf (hunchentoot:return-code*) 400)
            (return-from api-create-chat-folder
              (encode-api-response (make-api-error "MISSING_FIELDS" "name is required"))))
          (let ((folder (create-chat-folder user-id name
                                            :icon (or icon "📁")
                                            :conversation-ids (or conversation-ids nil)
                                            :is-default nil)))
            (encode-api-response
             (make-api-response (chat-folder-to-plist folder)))))
      (error (c)
        (log-error "Create chat folder error: ~A" c)
        (setf (hunchentoot:return-code*) 500)
        (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c))))))

;; PUT /api/v1/chat-folders/:id - Update chat folder
(hunchentoot:define-easy-handler (api-update-chat-folder :uri "/api/v1/chat-folders/:id") ()
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (let ((user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-update-chat-folder
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (handler-case
        (let* ((folder-id (parse-integer (hunchentoot:path-parameter 1) :junk-allowed t))
               (json-str (get-request-body-string))
               (data (cl-json:decode-json-from-string json-str))
               (name (cdr (assoc :name data)))
               (icon (cdr (assoc :icon data)))
               (conversation-ids (cdr (assoc :conversationIds data))))
          (let ((folder (update-chat-folder user-id folder-id
                                            :name name
                                            :icon icon
                                            :conversation-ids conversation-ids)))
            (unless folder
              (setf (hunchentoot:return-code*) 404)
              (return-from api-update-chat-folder
                (encode-api-response (make-api-error "NOT_FOUND" "Folder not found"))))
            (encode-api-response
             (make-api-response (chat-folder-to-plist folder)))))
      (error (c)
        (log-error "Update chat folder error: ~A" c)
        (setf (hunchentoot:return-code*) 500)
        (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c))))))))

;; DELETE /api/v1/chat-folders/:id - Delete chat folder
(hunchentoot:define-easy-handler (api-delete-chat-folder :uri "/api/v1/chat-folders/:id") ()
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (let ((user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-delete-chat-folder
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (handler-case
        (let* ((folder-id (parse-integer (hunchentoot:path-parameter 1) :junk-allowed t)))
          (delete-chat-folder user-id folder-id)
          (encode-api-response (make-api-response nil :message "Folder deleted")))
      (error (c)
        (log-error "Delete chat folder error: ~A" c)
        (setf (hunchentoot:return-code*) 500)
        (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c))))))

;; GET /api/v1/chat-folders/:id/conversations - Get folder conversations
(hunchentoot:define-easy-handler (api-get-folder-conversations :uri "/api/v1/chat-folders/:id/conversations") ()
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (let ((user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-get-folder-conversations
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (handler-case
        (let* ((folder-id (parse-integer (hunchentoot:path-parameter 1) :junk-allowed t))
               (conversations (get-folder-conversations user-id folder-id)))
          (encode-api-response
           (make-api-response conversations)))
      (error (c)
        (log-error "Get folder conversations error: ~A" c)
        (setf (hunchentoot:return-code*) 500)
        (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c))))))))

;;;; ---- Group Channels API (群组频道) ----

;; GET /api/v1/groups/:id/channels - Get group channels
(hunchentoot:define-easy-handler (api-get-group-channels :uri "/api/v1/groups/:id/channels") ()
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (let ((user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-get-group-channels
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (handler-case
        (let* ((group-id (parse-integer (hunchentoot:path-parameter 1) :junk-allowed t))
               (channels (get-group-channels group-id)))
          (encode-api-response
           (make-api-response
            (mapcar #'group-channel-to-plist channels))))
      (error (c)
        (log-error "Get group channels error: ~A" c)
        (setf (hunchentoot:return-code*) 500)
        (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c))))))

;; POST /api/v1/groups/:id/channels - Create group channel
(hunchentoot:define-easy-handler (api-create-group-channel :uri "/api/v1/groups/:id/channels") ()
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (let ((user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-create-group-channel
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (handler-case
        (let* ((group-id (parse-integer (hunchentoot:path-parameter 1) :junk-allowed t))
               (json-str (get-request-body-string))
               (data (cl-json:decode-json-from-string json-str))
               (name (cdr (assoc :name data)))
               (type (cdr (assoc :type data)))
               (parent-id (cdr (assoc :parentId data))))
          (unless name
            (setf (hunchentoot:return-code*) 400)
            (return-from api-create-group-channel
              (encode-api-response (make-api-error "MISSING_FIELDS" "name is required"))))
          (let ((channel (create-group-channel group-id name
                                               (or (and type (intern (string type) :keyword)) :text)
                                               :parent-id parent-id)))
            (encode-api-response
             (make-api-response (group-channel-to-plist channel)))))
      (error (c)
        (log-error "Create group channel error: ~A" c)
        (setf (hunchentoot:return-code*) 500)
        (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c))))))))

;; PUT /api/v1/groups/:groupId/channels/:id - Update group channel
(hunchentoot:define-easy-handler (api-update-group-channel :uri "/api/v1/groups/:groupId/channels/:id") ()
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (let ((user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-update-group-channel
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (handler-case
        (let* ((group-id (parse-integer (hunchentoot:path-parameter 1) :junk-allowed t))
               (channel-id (parse-integer (hunchentoot:path-parameter 2) :junk-allowed t))
               (json-str (get-request-body-string))
               (data (cl-json:decode-json-from-string json-str))
               (name (cdr (assoc :name data)))
               (description (cdr (assoc :description data)))
               (type (cdr (assoc :type data)))
               (is-muted (cdr (assoc :isMuted data))))
          (let ((channel (update-group-channel group-id channel-id
                                               :name name
                                               :description description
                                               :type (and type (intern (string type) :keyword))
                                               :is-muted is-muted)))
            (unless channel
              (setf (hunchentoot:return-code*) 404)
              (return-from api-update-group-channel
                (encode-api-response (make-api-error "NOT_FOUND" "Channel not found"))))
            (encode-api-response
             (make-api-response (group-channel-to-plist channel)))))
      (error (c)
        (log-error "Update group channel error: ~A" c)
        (setf (hunchentoot:return-code*) 500)
        (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c))))))

;; DELETE /api/v1/groups/:groupId/channels/:id - Delete group channel
(hunchentoot:define-easy-handler (api-delete-group-channel :uri "/api/v1/groups/:groupId/channels/:id") ()
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (let ((user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-delete-group-channel
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (handler-case
        (let* ((group-id (parse-integer (hunchentoot:path-parameter 1) :junk-allowed t))
               (channel-id (parse-integer (hunchentoot:path-parameter 2) :junk-allowed t)))
          (delete-group-channel group-id channel-id)
          (encode-api-response (make-api-response nil :message "Channel deleted")))
      (error (c)
        (log-error "Delete group channel error: ~A" c)
        (setf (hunchentoot:return-code*) 500)
        (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c))))))))

;; POST /api/v1/channels/:id/switch - Switch to channel
(hunchentoot:define-easy-handler (api-switch-channel :uri "/api/v1/channels/:id/switch") ()
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (let ((user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-switch-channel
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (handler-case
        (let* ((channel-id (parse-integer (hunchentoot:path-parameter 1) :junk-allowed t))
               (channel (switch-channel channel-id user-id)))
          (unless channel
            (setf (hunchentoot:return-code*) 404)
            (return-from api-switch-channel
              (encode-api-response (make-api-error "NOT_FOUND" "Channel not found"))))
          (encode-api-response
           (make-api-response (group-channel-to-plist channel))))
      (error (c)
        (log-error "Switch channel error: ~A" c)
        (setf (hunchentoot:return-code*) 500)
        (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c))))))

;;;; ---- Message Search API (消息搜索) ----

;; GET /api/v1/messages/search - Search messages (global)
(hunchentoot:define-easy-handler (api-search-messages :uri "/api/v1/messages/search") ()
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (let ((user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-search-messages
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (handler-case
        (let* ((query (hunchentoot:get-parameter "q"))
               (conversation-id (hunchentoot:get-parameter "conversationId"))
               (sender-id (hunchentoot:get-parameter "senderId"))
               (message-type (hunchentoot:get-parameter "messageType"))
               (limit (or (hunchentoot:get-parameter "limit") "20"))
               (offset (or (hunchentoot:get-parameter "offset") "0")))
          (unless query
            (setf (hunchentoot:return-code*) 400)
            (return-from api-search-messages
              (encode-api-response (make-api-error "MISSING_FIELDS" "q is required"))))
          (let* ((limit-num (parse-integer limit :junk-allowed t))
                 (offset-num (parse-integer offset :junk-allowed t))
                 (conversation-id-num (when conversation-id (parse-integer conversation-id :junk-allowed t)))
                 (results (search-messages user-id query
                                           :conversation-id conversation-id-num
                                           :limit limit-num)))
            (encode-api-response
             (make-api-response
              (mapcar (lambda (r)
                        `(:messageId ,(elt r 0)
                          :conversationId ,(elt r 1)
                          :senderId ,(elt r 2)
                          :content ,(elt r 3)
                          :createdAt ,(elt r 4)
                          :conversationName ,(elt r 5)))
                      results)))))
      (error (c)
        (log-error "Search messages error: ~A" c)
        (setf (hunchentoot:return-code*) 500)
        (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c))))))))

;; GET /api/v1/conversations/:id/messages/search - Search in conversation
(hunchentoot:define-easy-handler (api-search-in-conversation :uri "/api/v1/conversations/:id/messages/search") ()
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (let ((user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-search-in-conversation
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (handler-case
        (let* ((conversation-id (parse-integer (hunchentoot:path-parameter 1) :junk-allowed t))
               (query (hunchentoot:get-parameter "q"))
               (limit (or (hunchentoot:get-parameter "limit") "20"))
               (offset (or (hunchentoot:get-parameter "offset") "0")))
          (unless query
            (setf (hunchentoot:return-code*) 400)
            (return-from api-search-in-conversation
              (encode-api-response (make-api-error "MISSING_FIELDS" "q is required"))))
          (let* ((limit-num (parse-integer limit :junk-allowed t))
                 (offset-num (parse-integer offset :junk-allowed t))
                 (results (search-messages user-id query
                                           :conversation-id conversation-id
                                           :limit limit-num)))
            (encode-api-response
             (make-api-response
              (mapcar (lambda (r)
                        `(:messageId ,(elt r 0)
                          :conversationId ,(elt r 1)
                          :senderId ,(elt r 2)
                          :content ,(elt r 3)
                          :createdAt ,(elt r 4)))
                      results)))))
      (error (c)
        (log-error "Search in conversation error: ~A" c)
        (setf (hunchentoot:return-code*) 500)
        (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c))))))

;; GET /api/v1/conversations/:id/media - Get conversation media
(hunchentoot:define-easy-handler (api-get-conversation-media :uri "/api/v1/conversations/:id/media") ()
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (let ((user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-get-conversation-media
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (handler-case
        (let* ((conversation-id (parse-integer (hunchentoot:path-parameter 1) :junk-allowed t))
               (type (hunchentoot:get-parameter "type"))
               (limit (or (hunchentoot:get-parameter "limit") "20"))
               (offset (or (hunchentoot:get-parameter "offset") "0")))
          ;; TODO: Implement get-conversation-media in storage.lisp
          (declare (ignore type limit offset))
          (encode-api-response
           (make-api-response nil :message "Not implemented yet")))
      (error (c)
        (log-error "Get conversation media error: ~A" c)
        (setf (hunchentoot:return-code*) 500)
        (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c))))))))

;; GET /api/v1/conversations/:id/links - Get conversation links
(hunchentoot:define-easy-handler (api-get-conversation-links :uri "/api/v1/conversations/:id/links") ()
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (let ((user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-get-conversation-links
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (handler-case
        (let* ((conversation-id (parse-integer (hunchentoot:path-parameter 1) :junk-allowed t))
               (limit (or (hunchentoot:get-parameter "limit") "20")))
          ;; TODO: Implement get-conversation-links in storage.lisp
          (declare (ignore limit))
          (encode-api-response
           (make-api-response nil :message "Not implemented yet")))
      (error (c)
        (log-error "Get conversation links error: ~A" c)
        (setf (hunchentoot:return-code*) 500)
        (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c))))))

;;;; ---- Extended Reactions API (表情回应扩展) ----

;; GET /api/v1/messages/:id/reactions/detail - Get message reactions with user details
(hunchentoot:define-easy-handler (api-get-message-reactions-detail :uri "/api/v1/messages/:id/reactions/detail") ()
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (let ((user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-get-message-reactions-detail
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (handler-case
        (let* ((message-id (parse-integer (hunchentoot:path-parameter 1) :junk-allowed t))
               (reactions (get-message-reactions message-id)))
          ;; Format reactions with user details
          (let ((formatted-reactions
                 (mapcan (lambda (reaction)
                           (mapcar (lambda (user-id-in)
                                     `(:id ,(incf (random 1000000))
                                       :messageId ,message-id
                                       :emoji ,(getf reaction :emoji)
                                       :userId ,user-id-in
                                       :username ,(getf (get-user user-id-in) :username)
                                       :userAvatar ,(getf (get-user user-id-in) :avatar)
                                       :createdAt ,(get-universal-time)))
                                   (getf reaction :user-ids)))
                         reactions)))
            (encode-api-response
             (make-api-response formatted-reactions))))
      (error (c)
        (log-error "Get message reactions detail error: ~A" c)
        (setf (hunchentoot:return-code*) 500)
        (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c))))))))

;; GET /api/v1/reactions/frequent - Get frequent reactions
(hunchentoot:define-easy-handler (api-get-frequent-reactions :uri "/api/v1/reactions/frequent") ()
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (handler-case
      (let ((limit-param (hunchentoot:get-parameter "limit")))
        (let ((limit (if limit-param (parse-integer limit-param :junk-allowed t) 20)))
          (let ((suggested (subseq (get-suggested-reactions) 0 (min limit 20))))
            (encode-api-response
             (make-api-response
              (mapcar (lambda (emoji) `(:emoji ,emoji :count 1)) suggested))))))
      (error (c)
        (log-error "Get frequent reactions error: ~A" c)
        (setf (hunchentoot:return-code*) 500)
        (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c))))))

;; GET /api/v1/emoji-packs - Get custom emoji packs
(hunchentoot:define-easy-handler (api-get-emoji-packs :uri "/api/v1/emoji-packs") ()
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (handler-case
      ;; TODO: Implement custom emoji packs storage
      (encode-api-response
       (make-api-response nil))
    (error (c)
      (log-error "Get emoji packs error: ~A" c)
      (setf (hunchentoot:return-code*) 500)
      (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c))))))

;; POST /api/v1/emoji - Add custom emoji
(hunchentoot:define-easy-handler (api-add-custom-emoji :uri "/api/v1/emoji") ()
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:content-type*) "application/json")
  (let ((user-id (require-auth)))
    (unless user-id
      (setf (hunchentoot:return-code*) 401)
      (return-from api-add-custom-emoji
        (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))
    (handler-case
        (let* ((content-type (hunchentoot:header-in "content-type")))
          (unless (and content-type (search "multipart/form-data" content-type))
            (setf (hunchentoot:return-code*) 400)
            (return-from api-add-custom-emoji
              (encode-api-response (make-api-error "INVALID_CONTENT_TYPE" "Expected multipart/form-data"))))
          (let* ((file (hunchentoot:post-parameter "file"))
                 (name (hunchentoot:post-parameter "name")))
            (unless (and file name)
              (setf (hunchentoot:return-code*) 400)
              (return-from api-add-custom-emoji
                (encode-api-response (make-api-error "MISSING_FIELDS" "file and name are required"))))
            ;; TODO: Save emoji file
            (encode-api-response
             (make-api-response `(:id ,(format nil "~A_~A" user-id (get-universal-time))
                              :url ,(format nil "/api/v1/files/emoji/~A_~A.png" user-id name)))))
      (error (c)
        (log-error "Add custom emoji error: ~A" c)
        (setf (hunchentoot:return-code*) 500)
        (encode-api-response (make-api-error "INTERNAL_ERROR" (format nil "~A" c))))))))
