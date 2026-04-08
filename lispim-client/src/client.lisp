;;;; client.lisp - Main LispIM Client

(in-package :lispim-client)

;; ============================================================================
;; Client class
;; ============================================================================

(defclass lispim-client ()
  ((api-client :accessor client-api-client
               :initarg :api-client
               :documentation "HTTP API client")
   (websocket :accessor client-websocket
              :initform nil
              :documentation "WebSocket client")
   (auth-manager :accessor client-auth-manager
                 :initarg :auth-manager
                 :documentation "Authentication manager")
   (state :accessor client-state
          :initform nil
          :documentation "Client state")
   (websocket-url :accessor client-websocket-url
                  :initarg :websocket-url
                  :initform "ws://127.0.0.1:3000/ws"
                  :documentation "WebSocket server URL"))
  (:documentation "Main LispIM client"))

(defun make-lispim-client (&key (server-url "http://127.0.0.1:3000")
                                (websocket-url "ws://127.0.0.1:3000/ws")
                                (token nil))
  "Create a new LispIM client instance"
  (let ((api-client (make-api-client :base-url server-url :token token)))
    (make-instance 'lispim-client
                   :api-client api-client
                   :auth-manager (make-auth-manager :api-client api-client)
                   :websocket-url websocket-url)))

;; ============================================================================
;; Connection management
;; ============================================================================

(defun client-connect (client)
  "Connect to the server (WebSocket)"
  (let ((websocket (make-websocket-client
                    :on-message (lambda (msg)
                                  (handle-incoming-message client msg))
                    :on-connected (lambda ()
                                    (format t "~%WebSocket connected~%")
                                    ;; Start keep-alive ping
                                    )
                    :on-disconnected (lambda ()
                                       (format t "~%WebSocket disconnected~%"))
                    :on-error (lambda (err)
                                (format t "~%WebSocket error: ~A~%" err)))))
    (multiple-value-bind (success result)
        (websocket-client-connect websocket (client-websocket-url client)
                                  :token (auth-manager-get-token
                                          (client-auth-manager client)))
      (if success
          (progn
            (setf (client-websocket client) websocket)
            ;; Start keep-alive ping (every 30 seconds)
            (websocket-client-keep-alive websocket :interval 30)
            (format t "~%WebSocket keep-alive started~%"))
          (format t "~%WebSocket connection failed: ~A~%" result))
      success)))

(defun client-disconnect (client)
  "Disconnect from the server"
  (when (client-websocket client)
    (websocket-client-disconnect (client-websocket client))
    (setf (client-websocket client) nil)))

;; ============================================================================
;; Authentication
;; ============================================================================

(defun client-login (client username password)
  "Login to the server"
  (multiple-value-bind (success result)
      (auth-manager-login (client-auth-manager client) username password)
    (if success
        (progn
          ;; Connect WebSocket with new token
          (client-connect client)
          ;; Load initial data
          (client-load-initial-data client)
          (values success result))
        (values success result))))

(defun client-logout (client)
  "Logout from the server"
  (client-disconnect client)
  (auth-manager-logout (client-auth-manager client)))

;; ============================================================================
;; Data loading
;; ============================================================================

(defun client-load-initial-data (client)
  "Load initial data after login"
  (let ((state (client-state client)))
    (when (null state)
      (setf (client-state client) (make-client-state))
      (setf state (client-state client)))
    
    ;; Load conversations
    (multiple-value-bind (success conversations)
        (api-client-get-conversations (client-api-client client))
      (when (and success conversations)
        (state-set-conversations state (json-to-plist conversations))))
    
    ;; Load friends
    (multiple-value-bind (success friends)
        (api-client-get-friends (client-api-client client))
      (when (and success friends)
        (state-set-friends state (json-to-plist friends))))))

;; ============================================================================
;; Message handling
;; ============================================================================

(defun client-send-message (client conversation-id content &key (message-type "text"))
  "Send a message"
  (api-client-send-message (client-api-client client) conversation-id content
                           :message-type message-type))

(defun client-get-messages (client conversation-id &key (limit 50))
  "Get messages for a conversation"
  (multiple-value-bind (success result)
      (api-client-get-messages (client-api-client client) conversation-id :limit limit)
    (if (and success result)
        (let ((messages (json-to-plist result)))
          (state-set-messages (client-state client) conversation-id messages)
          messages)
        nil)))

(defun client-mark-read (client message-id)
  "Mark a message as read"
  (api-client-mark-read (client-api-client client) message-id))

(defun handle-incoming-message (client message)
  "Handle an incoming WebSocket message"
  (let ((data (json-to-plist message)))
    (let ((type (getf data :type))
          (payload (getf data :payload)))
      (case (intern (string-upcase type) :keyword)
        (:new-message
         ;; Add message to state
         (let ((conv-id (getf payload :conversationId)))
           (when conv-id
             (state-add-message (client-state client) conv-id payload))))
        (:message-read
         ;; Update message status
         (let ((msg-id (getf payload :messageId)))
           (when msg-id
             ;; Update message status in UI
             )))
        (:user-status
         ;; Update user online status
         (let ((user-id (getf payload :userId))
               (status (getf payload :status)))
           (when (and user-id status)
             (state-add-user (client-state client)
                             (list :id user-id :status status)))))
        (:ai-response
         ;; AI chat response
         (let ((conv-id (getf payload :conversationId))
               (content (getf payload :content)))
           (when (and conv-id content)
             (state-add-message (client-state client) conv-id
                                (list :content content
                                      :senderName "AI"
                                      :createdAt (get-universal-time))))))
        (:notification
         ;; Server notification
         (let ((content (getf payload :content)))
           (when content
             (format t "~%Notification: ~A~%" content))))
        (otherwise
         (format t "~%Unknown message type: ~A~%" type))))))

;; ============================================================================
;; Conversations
;; ============================================================================

(defun client-get-conversations (client)
  "Get list of conversations"
  (state-conversations (client-state client)))

(defun client-select-conversation (client conversation-id)
  "Select a conversation and load its messages"
  (setf (state-current-conversation (client-state client)) conversation-id)
  (client-get-messages client conversation-id))

;; ============================================================================
;; Main entry point
;; ============================================================================

(defun start-client (&key (server-url "http://127.0.0.1:3000")
                          (websocket-url "ws://127.0.0.1:3000/ws"))
  "Start the LispIM client"
  (let ((client (make-lispim-client :server-url server-url
                                    :websocket-url websocket-url)))
    (format t "~%LispIM Client started~%")
    (format t "Server: ~A~%" server-url)
    (format t "WebSocket: ~A~%" websocket-url)
    client))

(defun stop-client (client)
  "Stop the LispIM client"
  (client-logout client)
  (format t "~%LispIM Client stopped~%"))

(defun run (client)
  "Run the client main loop"
  (declare (ignore client))
  ;; This would be replaced by the McCLIM event loop
  (format t "~%Client running. Press Ctrl+C to exit.~%")
  (loop do (sleep 1)))
