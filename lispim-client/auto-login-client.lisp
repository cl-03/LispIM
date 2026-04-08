;;;; auto-login-client.lisp - Auto Login Client
;;;;
;;;; Usage: sbcl --load auto-login-client.lisp
;;;;
;;;; This script will:
;;;; 1. Connect to LispIM server
;;;; 2. Automatically login with configured credentials
;;;; 3. Start interactive REPL with logged-in session

#+sbcl
(setf sb-impl::*default-external-format* :utf-8)

;; Configuration - Edit these values
(defparameter *server-host* "localhost"
  "LispIM server host")

(defparameter *server-port* 3000
  "LispIM server port")

(defparameter *username* "admin"
  "Username for auto-login")

(defparameter *password* "password"
  "Password for auto-login")

;; Load Quicklisp
(handler-case
    (progn
      (load (merge-pathnames "quicklisp.lisp" (user-homedir-pathname)))
      (quicklisp:setup))
  (error (c)
    (format t "~%ERROR: Failed to load Quicklisp: ~a~%" c)
    (format t "Please ensure quicklisp.lisp is installed in your home directory.~%")
    (sb-ext:quit :unix-status 1)))

;; Load client system
(format t "~%~%; Loading LispIM Client...~%")
(handler-case
    (asdf:load-system :lispim-client)
  (error (c)
    (format t "~%ERROR: Failed to load lispim-client: ~a~%" c)
    (format t "Make sure you are in the lispim-client directory.~%")
    (sb-ext:quit :unix-status 1)))

;; Import package
(use-package :lispim-client)

;; Global client variable
(defvar *auto-client* nil
  "Auto-login client instance")

;;;; Auto Login Function

(defun auto-connect-and-login (&key (host *server-host*)
                                    (port *server-port*)
                                    (username *username*)
                                    (password *password))
  "Connect and login automatically"
  (format t "~%========================================~%")
  (format t "  LispIM Auto-Login Client~%")
  (format t "========================================~%")
  (format t "~%Server: ~a:~a~%" host port)
  (format t "User: ~a~%" username)
  (format t "~%; Connecting...~%")

  ;; Create client
  (setf *auto-client* (make-client :host host :port port))

  ;; Connect
  (handler-case
      (connect *auto-client*)
    (client-connection-error (c)
      (format t "~%ERROR: Connection failed: ~a~%" c)
      (format t "Please ensure the server is running at ~a:~a~%" host port)
      (sb-ext:quit :unix-status 1)))

  (format t "✓ Connected to server~%")

  ;; Set up callbacks
  (setf (client-message-callback *auto-client*)
        (lambda (msg)
          (let ((sender (getf msg :senderId))
                (content (getf msg :content))
                (type (getf msg :type))
                (conv-id (getf msg :conversationId)))
            (format t "~%📨 [~a] ~a: ~a~%" type sender content)
            (format t "~%> ")))

  (setf (client-presence-callback *auto-client*)
        (lambda (msg)
          (format t "~%👤 [PRESENCE] ~a~%" msg)
          (format t "~%> ")))

  (setf (client-notification-callback *auto-client*)
        (lambda (msg)
          (format t "~%🔔 [NOTIFICATION] ~a~%" msg)
          (format t "~%> ")))

  ;; Login
  (format t "~%; Logging in as ~a...~%" username)
  (handler-case
      (progn
        (login *auto-client* username password)
        (setf (client-user-id *auto-client*) username
              (client-username *auto-client*) username)
        (format t "✓ Logged in successfully!~%")
        (format t "~%========================================~%")
        (format t "  Commands:~%")
        (format t "========================================~%")
        (format t "  (send \"conv-id\" \"message\") - Send message~%")
        (format t "  (conversations)              - List conversations~%")
        (format t "  (messages \"conv-id\")       - Get messages~%")
        (format t "  (online-users)               - Get online users~%")
        (format t "  (status \"user-id\")         - Get user status~%")
        (format t "  (disconnect)                 - Disconnect~%")
        (format t "~%Type commands at the > prompt~%")
        (format t "========================================~%~%"))
    (error (c)
      (format t "~%ERROR: Login failed: ~a~%" c)
      (format t "Please check your credentials.~%")
      (sb-ext:quit :unix-status 1))))

;;;; Convenience Functions

(defun send (conv-id content)
  "Send a message"
  (if *auto-client*
      (progn
        (send-chat-message *auto-client* conv-id content)
        (format t "✓ Message sent to ~a~%" conv-id))
      (format t "ERROR: Not connected. Use (auto-connect-and-login) first.")))

(defun conversations ()
  "Get conversations list"
  (if *auto-client*
      (progn
        (get-conversations *auto-client*)
        (format t "✓ Request sent. Check callback for response."))
      (format t "ERROR: Not connected.")))

(defun messages (conv-id)
  "Get messages for a conversation"
  (if *auto-client*
      (progn
        (get-messages *auto-client* conv-id)
        (format t "✓ Request sent. Check callback for response."))
      (format t "ERROR: Not connected.")))

(defun online-users ()
  "Get online users"
  (if *auto-client*
      (progn
        (get-online-users *auto-client*)
        (format t "✓ Request sent. Check callback for response."))
      (format t "ERROR: Not connected.")))

(defun status (user-id)
  "Get user status"
  (if *auto-client*
      (progn
        (get-user-status *auto-client* user-id)
        (format t "✓ Request sent. Check callback for response."))
      (format t "ERROR: Not connected.")))

(defun disconnect ()
  "Disconnect from server"
  (when *auto-client*
    (lispim-client:disconnect *auto-client*)
    (setf *auto-client* nil)
    (format t "~%✓ Disconnected.~%")))

;;;; Main Entry Point

(format t "~%~%Starting auto-login client...~%")
(auto-connect-and-login)
