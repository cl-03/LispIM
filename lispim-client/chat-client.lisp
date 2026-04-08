;;;; chat-client.lisp - High-level Chat Client API

(in-package :lispim-client)

;;;; Chat Operations

(defun send-chat-message (client conversation-id content &key (type "text") reply-to)
  "Send a chat message"
  (declare (type client client)
           (type string conversation-id content)
           (type string type)
           (type (or null string) reply-to))

  (unless (client-connected client)
    (error 'client-error :message "Not connected"))

  (let ((msg (make-message :type "MESSAGE_SEND"
                           :conversationId conversation-id
                           :content content
                           :type type)))
    (when reply-to (setf (getf msg :replyTo) reply-to))
    (send-message client msg))

  t)

(defun get-messages (client conversation-id &key (limit 50) (before nil))
  "Get message history for a conversation"
  (declare (type client client)
           (type string conversation-id)
           (type integer limit)
           (type (or null string) before))

  (unless (client-connected client)
    (error 'client-error :message "Not connected"))

  (let ((msg (make-message :type "MESSAGE_HISTORY"
                           :conversationId conversation-id
                           :limit limit)))
    (when before (setf (getf msg :before) before))
    (send-message client msg))

  ;; Response will come via message callback
  t)

(defun get-conversations (client)
  "Get list of conversations"
  (declare (type client client))

  (unless (client-connected client)
    (error 'client-error :message "Not connected"))

  (send-message client (make-message :type "CONVERSATIONS"))

  ;; Response will come via message callback
  t)

(defun mark-as-read (client conversation-id)
  "Mark a conversation as read"
  (declare (type client client)
           (type string conversation-id))

  (unless (client-connected client)
    (error 'client-error :message "Not connected"))

  (send-message client (make-message :type "MESSAGE_READ"
                                     :conversationId conversation-id))

  t)

;;;; Presence

(defun get-online-users (client)
  "Get list of online users"
  (declare (type client client))

  (unless (client-connected client)
    (error 'client-error :message "Not connected"))

  (send-message client (make-message :type "ONLINE_USERS"))

  ;; Response will come via message callback
  t)

(defun get-user-status (client user-id)
  "Get user status/presence"
  (declare (type client client)
           (type string user-id))

  (unless (client-connected client)
    (error 'client-error :message "Not connected"))

  (send-message client (make-message :type "USER_STATUS"
                                     :userId user-id))

  ;; Response will come via message callback
  t)

;;;; User operations

(defun get-profile (client)
  "Get current user profile"
  (declare (type client client))

  (unless (client-connected client)
    (error 'client-error :message "Not connected"))

  (send-message client (make-message :type "GET_PROFILE"))

  t)

(defun update-profile (client &key display-name avatar status-message)
  "Update user profile"
  (declare (type client client)
           (type (or null string) display-name)
           (type (or null string) avatar)
           (type (or null string) status-message))

  (unless (client-connected client)
    (error 'client-error :message "Not connected"))

  (let ((msg (make-message :type "UPDATE_PROFILE")))
    (when display-name (setf (getf msg :displayName) display-name))
    (when avatar (setf (getf msg :avatar) avatar))
    (when status-message (setf (getf msg :statusMessage) status-message))
    (send-message client msg))

  t)

;;;; Typing indicators

(defun send-typing (client conversation-id &key (typing t))
  "Send typing indicator"
  (declare (type client client)
           (type string conversation-id)
           (type boolean typing))

  (unless (client-connected client)
    (error 'client-error :message "Not connected"))

  (send-message client (make-message :type "TYPING"
                                     :conversationId conversation-id
                                     :typing typing))

  t)
