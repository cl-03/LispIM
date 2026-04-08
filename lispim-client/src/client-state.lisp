;;;; client-state.lisp - Client State Management

(in-package :lispim-client)

;; ============================================================================
;; Client State class
;; ============================================================================

(defclass client-state ()
  ((current-conversation :accessor state-current-conversation
                         :initform nil
                         :documentation "Currently selected conversation ID")
   (conversations :accessor state-conversations
                  :initform nil
                  :documentation "List of all conversations")
   (messages :accessor state-messages
             :initform (make-hash-table :test 'equal)
             :documentation "Hash table of messages by conversation ID")
   (users :accessor state-users
          :initform (make-hash-table :test 'equal)
          :documentation "Hash table of user info by user ID")
   (friends :accessor state-friends
            :initform nil
            :documentation "List of friends"))
  (:documentation "Client state management"))

(defun make-client-state ()
  "Create a new client state instance"
  (make-instance 'client-state))

;; ============================================================================
;; Conversation state
;; ============================================================================

(defun state-add-conversation (state conversation)
  "Add or update a conversation in state"
  (let* ((conv-id (getf conversation :id))
         (existing (position conv-id (state-conversations state) :key #'(lambda (c) (getf c :id)) :test #'=)))
    (if existing
        (setf (nth existing (state-conversations state)) conversation)
        (push conversation (state-conversations state)))
    (state-conversations state)))

(defun state-set-conversations (state conversations)
  "Set the full list of conversations"
  (setf (state-conversations state) conversations)
  conversations)

(defun state-get-conversation (state conv-id)
  "Get a conversation by ID"
  (find conv-id (state-conversations state) :key #'(lambda (c) (getf c :id)) :test #'=))

;; ============================================================================
;; Message state
;; ============================================================================

(defun state-add-message (state conversation-id message)
  "Add a message to a conversation"
  (let ((messages (gethash (format nil "~A" conversation-id)
                           (state-messages state))))
    (if messages
        (push message messages)
        (setf (gethash (format nil "~A" conversation-id)
                       (state-messages state))
              (list message)))))

(defun state-set-messages (state conversation-id messages)
  "Set messages for a conversation"
  (setf (gethash (format nil "~A" conversation-id)
                 (state-messages state))
        messages)
  messages)

(defun state-get-messages (state conversation-id)
  "Get messages for a conversation"
  (gethash (format nil "~A" conversation-id)
           (state-messages state)
           nil))

(defun state-clear-messages (state conversation-id)
  "Clear messages for a conversation"
  (remhash (format nil "~A" conversation-id)
           (state-messages state)))

;; ============================================================================
;; User state
;; ============================================================================

(defun state-add-user (state user)
  "Add or update a user in state"
  (let ((user-id (getf user :id)))
    (setf (gethash (format nil "~A" user-id)
                   (state-users state))
          user)
    user))

(defun state-get-user (state user-id)
  "Get user by ID"
  (gethash (format nil "~A" user-id)
           (state-users state)
           nil))

(defun state-set-friends (state friends)
  "Set the list of friends"
  (setf (state-friends state) friends)
  friends)

(defun state-add-friend (state friend)
  "Add a friend to the list"
  (pushnew friend (state-friends state))
  (state-friends state))
