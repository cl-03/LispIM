;;;; main-frame.lisp - Main Frame using McCLIM

(in-package :lispim-client/ui)

;; ============================================================================
;; Main Frame Application
;; ============================================================================

(define-application-frame main-frame ()
  ((client :accessor frame-client
           :initarg :client
           :documentation "LispIM client instance")
   (current-conversation :accessor frame-current-conversation
                         :initform nil
                         :documentation "Currently selected conversation ID"))
  (:panes
   ;; Left pane - Conversation list
   (conversation-list :output-pane
                      :value ""
                      :label "Conversations"
                      :scroll-bars :both
                      :width 200
                      :documentation "List of conversations")
   
   ;; Middle pane - Messages
   (message-view :output-pane
                 :value ""
                 :label "Messages"
                 :scroll-bars :both
                 :documentation "Message display area")
   
   ;; Bottom - Message input
   (message-input :text-field-pane
                  :value ""
                  :label ""
                  :documentation "Message input field")
   
   ;; Right pane - User info
   (user-info :output-pane
              :value ""
              :label "User Info"
              :width 150
              :documentation "User information panel"))
   
  (:layouts
   (default
    (horizontally ()
      ;; Left: Conversation list
      (vertically ()
        (make-pane 'accepting-values-pane
                   :display-function 'draw-conversation-list
                   :scroll-bars :both
                   :width 200))
      ;; Middle: Messages and input
      (vertically ()
        (make-pane 'accepting-values-pane
                   :display-function 'draw-messages
                   :scroll-bars :both)
        message-input)
      ;; Right: User info
      (vertically ()
        user-info))))

  (:command-table (main-frame))
  
  (:top-level (main-frame-top-level)))

;; ============================================================================
;; Display functions
;; ============================================================================

(defun draw-conversation-list (frame pane)
  "Draw the conversation list"
  (let* ((client (frame-client frame))
         (state (client-state client))
         (conversations (state-conversations state))
         (current (frame-current-conversation frame)))
    (with-text-style (pane (:size :large))
      (draw-text* pane "Conversations" 10 10))
    (let ((y 40))
      (if conversations
          (dolist (conv conversations)
            (let* ((name (getf conv :name "Unknown"))
                   (id (getf conv :id))
                   (last-msg (getf conv :lastMessage ""))
                   (selected (= id current)))
              (when selected
                (draw-rectangle* pane 5 (- y 5) 195 (+ y 25)
                                 :ink +gray85+
                                 :filled t))
              (with-text-style (pane (if selected '(:weight :bold) nil))
                (draw-text* pane name 15 y))
              (with-text-style (pane (:size :small))
                (draw-text* pane (subseq last-msg 0 (min 30 (length last-msg)))
                           15 (+ y 15)))
              (incf y 35)))
          (draw-text* pane "No conversations" 15 y)))))

(defun draw-messages (frame pane)
  "Draw the message list"
  (let* ((client (frame-client frame))
         (conv-id (frame-current-conversation frame))
         (messages (if conv-id
                       (state-get-messages (client-state client) conv-id)
                       nil)))
    (with-text-style (pane (:size :large))
      (draw-text* pane "Messages" 10 10))
    (let ((y 40))
      (if messages
          (dolist (msg (nreverse messages))
            (let* ((sender (getf msg :senderName "Unknown"))
                   (content (getf msg :content ""))
                   (timestamp (getf msg :createdAt 0))
                   (formatted-time (format-timestamp timestamp)))
              (with-text-style (pane (:weight :bold))
                (draw-text* pane sender 15 y))
              (draw-text* pane content 15 (+ y 15))
              (with-text-style (pane (:size :small :slant :italic))
                (draw-text* pane formatted-time 15 (+ y 30)))
              (incf y 50)))
          (draw-text* pane "Select a conversation" 15 y)))))

(defun draw-user-info (frame pane)
  "Draw user information"
  (let* ((client (frame-client frame))
         (auth (client-auth-manager client))
         (user (auth-manager-get-current-user auth)))
    (with-text-style (pane (:size :large))
      (draw-text* pane "User Info" 10 10))
    (if user
        (let ((username (getf user :username "Unknown"))
              (status (getf user :status "online")))
          (draw-text* pane (format nil "Username: ~A" username) 15 40)
          (draw-text* pane (format nil "Status: ~A" status) 15 60))
        (draw-text* pane "Not logged in" 15 40))))

;; ============================================================================
;; Commands
;; ============================================================================

(define-command (com-send-message) ()
  "Send the typed message"
  (let* ((frame *application-frame*)
         (client (frame-client frame))
         (conv-id (frame-current-conversation frame))
         (input-pane (find-pane-from-instance frame 'message-input))
         (content (sheet-text input-pane)))
    (when (and conv-id (not (string= content "")))
      ;; Send message
      (client-send-message client conv-id content)
      ;; Clear input
      (setf (sheet-text input-pane) ""))))

(define-command (com-select-conversation (conv-id))
  "Select a conversation"
  (let ((frame *application-frame*))
    (setf (frame-current-conversation frame) conv-id)
    ;; Load messages
    (client-get-messages (frame-client frame) conv-id)
    ;; Redraw
    (redisplay-frame-panes frame)))

(define-command (com-logout) ()
  "Logout from the server"
  (let* ((frame *application-frame*)
         (client (frame-client frame)))
    (client-logout client)
    (close-main-frame)
    (open-login-frame client)))

;; ============================================================================
;; Top-level loop
;; ============================================================================

(defun main-frame-top-level (frame)
  "Main event loop for main frame"
  (with-input-context (frame)
    (keyboard)
    (do ()
        ((frame-top-level-exit-p frame))
      (handle-event frame (next-event))
      (redisplay-frame-panes frame))))

;; ============================================================================
;; Frame management
;; ============================================================================

(defvar *main-frame* nil
  "Current main frame instance")

(defun open-main-frame (client)
  "Open the main frame"
  (close-login-frame)
  (let ((frame (make-application-frame 'main-frame :client client)))
    (setf *main-frame* frame)
    ;; Load initial data
    (client-load-initial-data client)
    (run-frame-top-level frame)))

(defun close-main-frame ()
  "Close the main frame"
  (when *main-frame*
    (frame-top-level-exit *main-frame*)
    (setf *main-frame* nil)))
