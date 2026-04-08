;;;; lispim-auto.lisp - Complete Auto-Login Client
;;;;
;;;; A fully functional pure Common Lisp client for LispIM
;;;;
;;;; Usage:
;;;;   sbcl --load lispim-auto.lisp
;;;;
;;;; Requires:
;;;;   - Quicklisp installed at ~/quicklisp/
;;;;   - LispIM server running on localhost:3000

#+sbcl
(setf sb-impl::*default-external-format* :utf-8)

;;;; ============================================================================
;;;; Configuration
;;;; ============================================================================

(defparameter *config*
  '(:host "localhost"
    :port 3000
    :username "admin"
    :password "password")
  "Client configuration")

;;;; ============================================================================
;;;; Load Dependencies
;;;; ============================================================================

(format t "~%~%========================================~%")
(format t "  LispIM Pure Common Lisp Client~%")
(format t "  Version 0.1.0~%")
(format t "========================================~%")

(format t "~%; Loading Quicklisp...~%")
(handler-case
    (load "C:/Users/Administrator/quicklisp/setup.lisp")
  (error (c)
    (format t "~%ERROR: Failed to load Quicklisp: ~a~%" c)
    (format t "Please ensure Quicklisp is installed.~%")
    (sb-ext:quit :unix-status 1)))

(format t "; Loading libraries...~%")
(dolist (lib '(:usocket :cl+ssl :cl-json :bordeaux-threads :alexandria :log4cl :split-sequence :cl-base64 :ironclad :flexi-streams))
  (format t "  - ~a... " lib)
  (ql:quickload lib :silent t)
  (format t "OK~%"))

;;;; ============================================================================
;;;; Load Client Modules
;;;; ============================================================================

(format t "~%; Loading client modules...~%")

;; Define package first
(eval
 (read-from-string
  "(defpackage :lispim-client
     (:use :cl :alexandria)
     (:export
      ;; Client
      #:make-client #:client #:client-host #:client-port #:client-socket
      #:client-stream #:client-connected #:client-token #:client-user-id
      #:client-username #:client-message-callback #:client-presence-callback
      #:client-notification-callback #:client-receiver-thread
      #:client-heartbeat-thread #:client-heartbeat-interval
      ;; Conditions
      #:client-error #:client-connection-error #:client-auth-error
      ;; Functions
      #:connect #:disconnect #:client-connected-p #:send-message
      #:make-message #:read-message #:login #:register #:logout
      #:send-chat-message #:get-conversations #:get-messages
      #:get-online-users #:get-user-status))"))

;; Load source files
(dolist (file '("utils.lisp" "websocket-client.lisp" "auth.lisp" "chat-client.lisp"))
  (format t "  - ~a... " file)
  (load file)
  (format t "OK~%"))

(use-package :lispim-client)

(format t "~%✓ Client loaded successfully~%")

;;;; ============================================================================
;;;; Global State
;;;; ============================================================================

(defvar *client* nil "Current client instance")
(defvar *running* t "Client running flag")

;;;; ============================================================================
;;;; Callbacks
;;;; ============================================================================

(defun setup-callbacks (client)
  "Set up message callbacks"
  (setf (client-message-callback client)
        (lambda (msg)
          (let ((type (getf msg :type))
                (sender (getf msg :senderId))
                (content (getf msg :content))
                (conv-id (getf msg :conversationId)))
            (cond
              ((string= type "MESSAGE_RECEIVED")
               (format t "~%~%📨 [MESSAGE] ~a: ~a~%" sender content))
              ((string= type "MESSAGE_STATUS")
               (format t "~%📬 [STATUS] ~a~%" content))
              (t
               (format t "~%📨 [~a] ~a: ~a~%" type sender content))))
          (format t "> ")
          (finish-output)))

  (setf (client-presence-callback client)
        (lambda (msg)
          (format t "~%👤 [PRESENCE] ~a~%" msg)
          (format t "> ")
          (finish-output)))

  (setf (client-notification-callback client)
        (lambda (msg)
          (format t "~%🔔 [NOTIFICATION] ~a~%" msg)
          (format t "> ")
          (finish-output))))

;;;; ============================================================================
;;;; Connect and Login
;;;; ============================================================================

(defun connect-and-login (host port username password)
  "Connect to server and login"
  (format t "~%Server: ~a:~a~%" host port)
  (format t "User: ~a~%" username)

  ;; Create client
  (setf *client* (make-client :host host :port port))

  ;; Connect
  (format t "~%; Connecting...~%")
  (handler-case
      (connect *client*)
    (client-connection-error (c)
      (format t "~%ERROR: Connection failed: ~a~%" c)
      (format t "Please ensure the server is running.~%")
      (return-from connect-and-login nil)))

  (format t "✓ Connected~%")

  ;; Setup callbacks
  (setup-callbacks *client*)

  ;; Login
  (format t "; Logging in...~%")
  (handler-case
      (progn
        (login *client* username password)
        (setf (client-user-id *client*) username
              (client-username *client*) username)
        (format t "✓ Logged in successfully~%")
        t)
    (error (c)
      (format t "~%ERROR: Login failed: ~a~%" c)
      nil)))

;;;; ============================================================================
;;;; REPL
;;;; ============================================================================

(defun print-help ()
  "Print help message"
  (format t "~%~%Available commands:~%")
  (format t "  (send <conv-id> <message>)  - Send a message~%")
  (format t "  (conversations)             - List conversations~%")
  (format t "  (messages <conv-id>)        - Get messages~%")
  (format t "  (online)                    - Get online users~%")
  (format t "  (status <user-id>)          - Get user status~%")
  (format t "  (help)                      - Show this help~%")
  (format t "  (quit)                      - Exit the client~%")
  (format t "~%Or use low-level functions:~%")
  (format t "  (send-chat-message *client* <conv-id> <message>)~%")
  (format t "  (get-conversations *client*)~%")
  (format t "  (get-online-users *client*)~%")
  (format t "~%"))

(defun send (conv-id content)
  "Send a message (convenience function)"
  (send-chat-message *client* conv-id content)
  (format t "✓ Message sent to ~a~%" conv-id))

(defun conversations ()
  "List conversations"
  (get-conversations *client*)
  (format t "✓ Request sent (check callback for response)~%"))

(defun messages (conv-id)
  "Get messages for a conversation"
  (get-messages *client* conv-id)
  (format t "✓ Request sent (check callback for response)~%"))

(defun online ()
  "Get online users"
  (get-online-users *client*)
  (format t "✓ Request sent (check callback for response)~%"))

(defun status (user-id)
  "Get user status"
  (get-user-status *client* user-id)
  (format t "✓ Request sent (check callback for response)~%"))

(defun repl ()
  "Interactive REPL"
  (print-help)
  (format t "~%Enter commands at the prompt:~%")
  (loop while *running*
    do (progn
         (format t "~%> ")
         (finish-output)
         (let ((input (read-line *standard-input* nil nil)))
           (cond
             ((or (null input) (string= input "quit") (string= input "exit"))
              (setf *running* nil))
             ((string= input "help")
              (print-help))
             (t
              (handler-case
                  (let ((result (eval (read-from-string input))))
                    (when (and result (not (eq result :no-value)))
                      (format t "=> ~a~%" result)))
                (error (e)
                  (format t "ERROR: ~a~%" e)))))))))

;;;; ============================================================================
;;;; Cleanup
;;;; ============================================================================

(defun cleanup ()
  "Cleanup on exit"
  (format t "~%~%; Cleaning up...~%")
  (when *client*
    (disconnect *client*))
  (format t "✓ Goodbye!~%"))

;;;; ============================================================================
;;;; Main Entry Point
;;;; ============================================================================

(format t "~%~%; Starting client...~%")

;; Get config
(let ((host (getf *config* :host))
      (port (getf *config* :port))
      (username (getf *config* :username))
      (password (getf *config* :password)))

  ;; Connect and login
  (when (connect-and-login host port username password)
    (format t "~%========================================~%")
    (format t "  Ready!~%")
    (format t "========================================~%")

    ;; Start REPL
    (handler-case
        (repl)
      (sb-sys:interactive-interrupt ()
        (format t "~%Interrupted~%"))
      (error ()
        (format t "~%Exiting...~%")))

    ;; Cleanup
    (cleanup)))

(format t "~%Client terminated.~%")
