;;;; start-auto-login-simple.lisp - Simple Auto Login
;;;;
;;;; Usage: sbcl --non-interactive --load start-auto-login-simple.lisp

#+sbcl
(setf sb-impl::*default-external-format* :utf-8)

(format t "~%========================================~%")
(format t "  LispIM Auto-Login Client~%")
(format t "========================================~%")

;;;; Configuration
(defparameter *al-server-host* "localhost"
  "LispIM server host")

(defparameter *al-server-port* 3000
  "LispIM server port")

(defparameter *al-username* "admin"
  "Username for auto-login")

(defparameter *al-password* "password"
  "Password for auto-login")

;;;; Load Quicklisp and dependencies
(format t "~%; Loading Quicklisp...~%")
(load "C:/Users/Administrator/quicklisp/setup.lisp")

(format t "; Loading dependencies...~%")
(ql:quickload :usocket :silent t)
(ql:quickload :cl+ssl :silent t)
(ql:quickload :cl-json :silent t)
(ql:quickload :bordeaux-threads :silent t)
(ql:quickload :alexandria :silent t)
(ql:quickload :log4cl :silent t)
(ql:quickload :split-sequence :silent t)

(format t "; Loading client...~%")
(load "package.lisp")
(load "utils.lisp")
(load "websocket-client.lisp")
(load "auth.lisp")
(load "chat-client.lisp")
(load "repl-client.lisp")
;; cli.lisp has compile errors, skip it for now
;; (load "cli.fasl")

(format t "✓ Client loaded (core modules)~%")

;;;; Import package
(use-package :lispim-client)

;;;; Global client variable
(defvar *auto-client* nil
  "Auto-login client instance")

;;;; Auto Login Function
(defun al-connect-and-login (&key (host *al-server-host*)
                                  (port *al-server-port*)
                                  (username *al-username*)
                                  (password *al-password))
  "Connect and login automatically"
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
            (format t "~%> "))))

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
        (format t "========================================~%~%")

        ;; Start interactive REPL
        (al-repl))
    (error (c)
      (format t "~%ERROR: Login failed: ~a~%" c)
      (format t "Please check your credentials.~%")
      (sb-ext:quit :unix-status 1))))

;;;; Simple REPL Loop
(defun al-repl ()
  "Simple REPL for user input"
  (format t "~%Enter 'quit' to exit~%")
  (loop
    (format t "~%> ")
    (finish-output)
    (let ((input (read-line *standard-input* nil nil)))
      (when (or (null input) (string= input "quit") (string= input "exit"))
        (disconnect)
        (format t "~%Goodbye!~%")
        (return))
      (handler-case
          (let ((result (eval (read-from-string input))))
            (when result
              (format t "~%~a~%" result)))
        (error (e)
          (format t "~%ERROR: ~a~%" e))))))

;;;; Command-line argument parsing
(defun parse-args (args)
  "Parse command line arguments: [username] [password] [host] [port]"
  (when (>= (length args) 1)
    (setf *al-username* (nth 0 args)))
  (when (>= (length args) 2)
    (setf *al-password* (nth 1 args)))
  (when (>= (length args) 3)
    (setf *al-server-host* (nth 2 args)))
  (when (>= (length args) 4)
    (setf *al-server-port* (parse-integer (nth 3 args)))))

;;;; Main Entry Point
(format t "~%~%Starting auto-login client...~%")

;; Note: Command-line args disabled for Windows compatibility
;; Use hardcoded values or modify *al-username*, *al-password*, etc. above

(al-connect-and-login)
