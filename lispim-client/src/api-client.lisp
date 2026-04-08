;;;; api-client.lisp - HTTP API Client for LispIM Core

(in-package :lispim-client)

(defvar *default-server-url* "http://127.0.0.1:3000"
  "Default server URL for the LispIM core API")

(defvar *api-timeout* 30
  "API request timeout in seconds")

;; ============================================================================
;; API Client class
;; ============================================================================

(defclass api-client ()
  ((base-url :accessor api-client-base-url
             :initarg :base-url
             :initform *default-server-url*
             :documentation "Base URL of the API server")
   (token :accessor api-client-token
          :initarg :token
          :initform nil
          :documentation "Authentication token")
   (timeout :accessor api-client-timeout
            :initarg :timeout
            :initform *api-timeout*
            :documentation "Request timeout in seconds")
   (headers :accessor api-client-headers
            :initarg :headers
            :initform nil
            :documentation "Additional headers"))
  (:documentation "HTTP API client for LispIM core"))

(defun make-api-client (&key (base-url *default-server-url*)
                             (token nil)
                             (timeout *api-timeout*)
                             (headers nil))
  "Create a new API client instance"
  (make-instance 'api-client
                 :base-url base-url
                 :token token
                 :timeout timeout
                 :headers headers))

;; ============================================================================
;; API call helper
;; ============================================================================

(defun api-call (client method path &key body headers)
  "Make an API call to the server"
  (let* ((url (format nil "~A~A" (api-client-base-url client) path))
         (token (api-client-token client))
         (auth-header (when token
                        `(("Authorization" . ,(format nil "Bearer ~A" token)))))
         (default-headers `(("Content-Type" . "application/json")))
         (all-headers (append auth-header default-headers headers)))
    (handler-case
        (let ((response (ecase method
                          (:get (dex:get url :headers all-headers))
                          (:post (dex:post url
                                           :headers all-headers
                                           :content (when body
                                                      (cl-json:encode-json-to-string body))))
                          (:put (dex:put url
                                         :headers all-headers
                                         :content (when body
                                                    (cl-json:encode-json-to-string body))))
                          (:delete (dex:delete url :headers all-headers)))))
          (values t response))
      (error (e)
        (values nil (format nil "API call error: ~A" e))))))

;; ============================================================================
;; Authentication API
;; ============================================================================

(defun api-client-login (client username password)
  "Login to the server"
  (api-call client :post "/api/v1/auth/login"
            :body `(("username" . ,username)
                    ("password" . ,password))))

(defun api-client-logout (client)
  "Logout from the server"
  (api-call client :post "/api/v1/auth/logout"))

(defun api-client-get-me (client)
  "Get current user info"
  (api-call client :get "/api/v1/users/me"))

;; ============================================================================
;; Conversations API
;; ============================================================================

(defun api-client-get-conversations (client)
  "Get list of conversations"
  (api-call client :get "/api/v1/conversations"))

(defun api-client-get-messages (client conversation-id &key (limit 50) (before nil))
  "Get messages for a conversation"
  (let ((path (if before
                  (format nil "/api/v1/conversations/~A/messages?limit=~A&before=~A"
                          conversation-id limit before)
                  (format nil "/api/v1/conversations/~A/messages?limit=~A"
                          conversation-id limit))))
    (api-call client :get path)))

(defun api-client-send-message (client conversation-id content &key (message-type "text"))
  "Send a message to a conversation"
  (api-call client :post
            (format nil "/api/v1/conversations/~A/messages" conversation-id)
            :body `(("content" . ,content)
                    ("message-type" . ,message-type))))

(defun api-client-mark-read (client message-id)
  "Mark a message as read"
  (api-call client :post
            (format nil "/api/v1/messages/~A/read" message-id)))

;; ============================================================================
;; Friends/Contacts API
;; ============================================================================

(defun api-client-get-friends (client)
  "Get list of friends"
  (api-call client :get "/api/v1/contacts/friends"))

(defun api-client-search-users (client query)
  "Search for users"
  (api-call client :get
            (format nil "/api/v1/users/search?q=~A"
                    (quri:url-encode query))))

(defun api-client-send-friend-request (client receiver-id)
  "Send a friend request"
  (api-call client :post "/api/v1/contacts/friend-request"
            :body `(("receiverId" . ,receiver-id))))

(defun api-client-get-pending-friend-requests (client)
  "Get pending friend requests"
  (api-call client :get "/api/v1/contacts/friend-requests/pending"))

(defun api-client-accept-friend-request (client request-id)
  "Accept a friend request"
  (api-call client :post
            (format nil "/api/v1/contacts/friend-request/~A/accept" request-id)))

;; ============================================================================
;; AI Configuration API
;; ============================================================================

(defun api-client-get-ai-config (client)
  "Get AI configuration"
  (api-call client :get "/api/v1/ai/config"))

(defun api-client-update-ai-config (client &key enabled backend model personality
                                    context-length rate-limit streaming-p
                                    skills budget-limit auto-summarize language
                                    system-prompt temperature max-tokens)
  "Update AI configuration"
  (let ((body (cl-json:encode-json-to-string
               `((:enabled . ,enabled)
                 (:backend . ,backend)
                 (:model . ,model)
                 (:personality . ,personality)
                 (:context-length . ,context-length)
                 (:rate-limit . ,rate-limit)
                 (:streaming-p . ,streaming-p)
                 (:skills . ,skills)
                 (:budget-limit . ,budget-limit)
                 (:auto-summarize . ,auto-summarize)
                 (:language . ,language)
                 (:system-prompt . ,system-prompt)
                 (:temperature . ,temperature)
                 (:max-tokens . ,max-tokens)))))
    (api-call client :patch "/api/v1/ai/config" :body body)))

(defun api-client-get-ai-backends (client)
  "Get available AI backends"
  (api-call client :get "/api/v1/ai/backends"))

(defun api-client-get-ai-budget (client)
  "Get AI budget statistics"
  (api-call client :get "/api/v1/ai/budget"))

(defun api-client-chat (client messages &key model stream-p conversation-id)
  "Send chat request to AI"
  (let ((body (cl-json:encode-json-to-string
               `((:messages . ,messages)
                 (:model . ,model)
                 (:stream . ,stream-p)
                 (:conversation-id . ,conversation-id)))))
    (api-call client :post "/api/v1/ai/chat" :body body)))
