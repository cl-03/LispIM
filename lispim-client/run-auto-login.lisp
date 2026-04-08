;;;; run-auto-login.lisp - LispIM Auto-Login Client
;;;;
;;;; A pure Common Lisp WebSocket client for LispIM
;;;; No JavaScript/TypeScript required!
;;;;
;;;; Usage: sbcl --load run-auto-login.lisp
;;;;
;;;; Or customize credentials:
;;;;   sbcl --load run-auto-login.lisp --eval "(setf *username* \"myuser\")"

#+sbcl
(setf sb-impl::*default-external-format* :utf-8)

;;;; Configuration - Edit here
(defparameter *username* "admin"
  "Username for auto-login")

(defparameter *password* "password"
  "Password for auto-login")

(defparameter *server-host* "localhost"
  "LispIM server host")

(defparameter *server-port* 3000
  "LispIM server port")

;;;; Load Quicklisp
(format t "~%========================================~%")
(format t "  LispIM Pure Lisp Auto-Login Client~%")
(format t "========================================~%")
(format t "~%; Loading Quicklisp...~%")

(load "C:/Users/Administrator/quicklisp/setup.lisp")

;;;; Load dependencies
(format t "; Loading dependencies...~%")
(ql:quickload :usocket :silent t)
(ql:quickload :cl+ssl :silent t)
(ql:quickload :cl-json :silent t)
(ql:quickload :bordeaux-threads :silent t)
(ql:quickload :alexandria :silent t)
(ql:quickload :log4cl :silent t)
(ql:quickload :split-sequence :silent t)
(ql:quickload :cl-base64 :silent t)
(ql:quickload :ironclad :silent t)
(ql:quickload :flexi-streams :silent t)

;;;; Load client modules
(format t "; Loading client modules...~%")
(load "package.lisp")
(load "utils.lisp")
(load "websocket-client.lisp")
(load "auth.lisp")
(load "chat-client.lisp")

;;;; Import package
(use-package :lispim-client)

;;;; Global state
(defvar *auto-client* nil "Auto-login client instance")

;;;; Auto Login
(format t "~%Server: ~a:~a~%" *server-host* *server-port*)
(format t "User: ~a~%" *username*)
(format t "~%; Connecting...~%")

(setf *auto-client* (make-client :host *server-host* :port *server-port*))

(handler-case
    (connect *auto-client*)
  (client-connection-error (c)
    (format t "~%ERROR: Connection failed: ~a~%" c)
    (format t "Please ensure the server is running at ~a:~a~%" *server-host* *server-port*)
    (sb-ext:quit :unix-status 1)))

(format t "✓ Connected to server~%")

;;;; Set up message callbacks
(setf (client-message-callback *auto-client*)
      (lambda (msg)
        (let ((sender (getf msg :senderId))
              (content (getf msg :content))
              (type (getf msg :type)))
          (format t "~%📨 [~a] ~a: ~a~%" type sender content)
          (format t "> "))))

(setf (client-presence-callback *auto-client*)
      (lambda (msg)
        (format t "~%👤 [PRESENCE] ~a~%" msg)
        (format t "> ")))

(setf (client-notification-callback *auto-client*)
      (lambda (msg)
        (format t "~%🔔 [NOTIFICATION] ~a~%" msg)
        (format t "> ")))

;;;; Login
(format t "~%; Logging in as ~a...~%" *username*)
(handler-case
    (progn
      (login *auto-client* *username* *password*)
      (setf (client-user-id *auto-client*) *username*
            (client-username *auto-client*) *username*)
      (format t "✓ Logged in successfully!~%")
      (format t "~%========================================~%")
      (format t "  Available Commands:~%")
      (format t "========================================~%")
      (format t "  (send-chat-message *auto-client* \"conv-id\" \"Hello\")~%")
      (format t "  (get-conversations *auto-client*)~%")
      (format t "  (get-messages *auto-client* \"conv-id\")~%")
      (format t "  (get-online-users *auto-client*)~%")
      (format t "  (get-user-status *auto-client* \"user-id\")~%")
      (format t "  (disconnect *auto-client*)~%")
      (format t "~%Type Lisp expressions at the > prompt~%")
      (format t "Enter (quit) or Ctrl+C to exit~%")
      (format t "========================================~%~%"))
  (error (c)
    (format t "~%ERROR: Login failed: ~a~%" c)
    (sb-ext:quit :unix-status 1)))

;;;; Simple REPL
(defun repl-loop ()
  "Interactive REPL loop"
  (format t "~%Enter (quit) to exit~%")
  (loop
    (format t "~%> ")
    (finish-output)
    (let ((input (read-line *standard-input* nil nil)))
      (when (or (null input) (string= input "quit") (string= input "(quit)"))
        (when *auto-client*
          (disconnect *auto-client*))
        (format t "~%Goodbye!~%")
        (return))
      (handler-case
          (let ((result (eval (read-from-string input))))
            (when (and result (not (eq result :no-value)))
              (format t "~%=> ~a~%" result)))
        (error (e)
          (format t "~%ERROR: ~a~%" e))))))

;;;; Start REPL
(format t "~%Starting interactive session...~%")
(repl-loop)
