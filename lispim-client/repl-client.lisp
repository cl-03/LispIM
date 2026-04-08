;;;; repl-client.lisp - REPL Interactive Client

(in-package :lispim-client)

;;;; REPL Client

(defvar *repl-client* nil
  "Current REPL client instance")

(defun make-repl-client (&key (host "localhost") (port 3000))
  "Create a REPL client instance"
  (declare (type string host)
           (type integer port))
  (setf *repl-client*
        (make-client :host host :port port)))

(defun repl-connect (&key (host "localhost") (port 3000))
  "Connect to server from REPL"
  (declare (type string host)
           (type integer port))

  (when *repl-client*
    (disconnect *repl-client*))

  (setf *repl-client* (make-client :host host :port port))
  (connect *repl-client*)

  ;; Set up default callbacks
  (setf (client-message-callback *repl-client*)
        (lambda (msg)
          (format t "~%[MESSAGE] ~a~%" msg)
          (format t "> ")))

  (setf (client-presence-callback *repl-client*)
        (lambda (msg)
          (format t "~%[PRESENCE] ~a~%" msg)
          (format t "> ")))

  (setf (client-notification-callback *repl-client*)
        (lambda (msg)
          (format t "~%[NOTIFICATION] ~a~%" msg)
          (format t "> ")))

  (format t "~%Connected! Use (repl-login \"username\" \"password\") to authenticate.~%")
  *repl-client*)

(defun repl-login (username password)
  "Login from REPL"
  (declare (type string username password))

  (unless *repl-client*
    (error "No client. Call (repl-connect) first."))

  (login *repl-client* username password)
  (setf (client-user-id *repl-client*) username
        (client-username *repl-client*) username)

  (format t "~%Logged in as ~a!~%" username)
  (format t "~%Commands:~%")
  (format t "  (repl-send \"conversation-id\" \"message\") - Send message~%")
  (format t "  (repl-conversations) - Get conversations~%")
  (format t "  (repl-messages \"conversation-id\") - Get messages~%")
  (format t "  (repl-online-users) - Get online users~%")
  (format t "  (repl-disconnect) - Disconnect~%")

  t)

(defun repl-send (conversation-id content)
  "Send a message from REPL"
  (declare (type string conversation-id content))

  (unless *repl-client*
    (error "No client. Call (repl-connect) first."))

  (send-chat-message *repl-client* conversation-id content)
  (format t "Message sent.~%")
  t)

(defun repl-conversations ()
  "Get conversations from REPL"
  (unless *repl-client*
    (error "No client. Call (repl-connect) first."))

  (get-conversations *repl-client*)
  (format t "Request sent. Check callback for response.~%")
  t)

(defun repl-messages (conversation-id)
  "Get messages from REPL"
  (declare (type string conversation-id))

  (unless *repl-client*
    (error "No client. Call (repl-connect) first."))

  (get-messages *repl-client* conversation-id)
  (format t "Request sent. Check callback for response.~%")
  t)

(defun repl-online-users ()
  "Get online users from REPL"
  (unless *repl-client*
    (error "No client. Call (repl-connect) first."))

  (get-online-users *repl-client*)
  (format t "Request sent. Check callback for response.~%")
  t)

(defun repl-disconnect ()
  "Disconnect from REPL"
  (when *repl-client*
    (disconnect *repl-client*)
    (setf *repl-client* nil)
    (format t "Disconnected.~%"))
  t)
