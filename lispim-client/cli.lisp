;;;; cli.lisp - Command Line Interface

(in-package :lispim-client)

;;;; CLI Main Loop

(defun run-cli (&key (host "localhost") (port 3000))
  "Run the interactive command-line client"
  (declare (type string host)
           (type integer port))

  (format t "~%========================================~%")
  (format t "  LispIM Command Line Client~%")
  (format t "========================================~%~%")
  (force-output)

  ;; Create and connect client
  (let ((client (make-client :host host :port port)))

    ;; Connect
    (handler-case
        (connect client)
      (client-connection-error (c)
        (format t "Connection failed: ~a~%" c)
        (return-from run-cli nil)))

    ;; Set up callbacks
    (setf (client-message-callback client)
          (lambda (msg)
            (let ((sender (getf msg :senderId))
                  (content (getf msg :content))
                  (type (getf msg :type)))
              (format t "~%[~a] ~a: ~a~%" type sender content)
              (format t "> "))))

    (setf (client-presence-callback client)
          (lambda (msg)
            (format t "~%[PRESENCE] ~a~%" msg)
            (format t "> "))))

    (setf (client-notification-callback client)
          (lambda (msg)
            (format t "~%[NOTIFICATION] ~a~%" msg)
            (format t "> "))))

    ;; Connected
    (let ((host (client-host client))
          (port (client-port client)))
      (format t "~%Connected to ~a:~a~%" host port)
      (format t "~%Type 'help' for available commands.~%~%")
      (force-output))

    ;; Main loop
    (loop for line = (progn
                       (format t "> ")
                       (force-output)
                       (read-line *standard-input* nil nil))
          while line
          do (handler-case
                 (let ((result (process-command client line)))
                   (when result
                     (format t "~a~%" result)))
               (error (c)
                 (format t "Error: ~a~%" c)))

    ;; Disconnect on exit
    (disconnect client))

  (values)

;;;; Command Processing

(defun process-command (client line)
  "Process a CLI command"
  (declare (type client client)
           (type string line))

  (let* ((parts (split-sequence:split-sequence #\Space line :remove-empty-subseqs t))
         (cmd (when parts (string-downcase (first parts))))
         (args (rest parts)))

    (case (intern (string-upcase cmd) "KEYWORD")
      (:help (cmd-help))
      (:login (cmd-login client args))
      (:register (cmd-register client args))
      (:send (cmd-send client args))
      (:conversations (cmd-conversations client))
      (:messages (cmd-messages client args))
      (:online (cmd-online client))
      (:status (cmd-status client args))
      (:typing (cmd-typing client args))
      (:read (cmd-read client args))
      (:logout (cmd-logout client))
      (:quit (cmd-quit client))
      (:exit (cmd-quit client))
      (t (format nil "Unknown command: ~a. Type 'help' for commands." cmd)))))

;;;; Commands

(defun cmd-help ()
  "Show help"
  (format nil "~%Available commands:
  login <username> <password>     - Login to account
  register <username> <password>  - Register new account
  send <conv_id> <message>        - Send message
  conversations                   - List conversations
  messages <conv_id>              - Get messages
  online                          - Show online users
  status <user_id>                - Get user status
  typing <conv_id>                - Send typing indicator
  read <conv_id>                  - Mark as read
  logout                          - Logout
  quit/exit                       - Exit client"))

(defun cmd-login (client args)
  "Login command"
  (when (< (length args) 2)
    (return-from cmd-login "Usage: login <username> <password>"))

  (let ((username (first args))
        (password (second args)))
    (login client username password)
    (setf (client-user-id client) username)
    "Logged in. Use 'send <conv_id> <message>' to chat."))

(defun cmd-register (client args)
  "Register command"
  (when (< (length args) 2)
    (return-from cmd-register "Usage: register <username> <password>"))

  (let ((username (first args))
        (password (second args)))
    (register client username password)
    "Registration request sent. Check for confirmation."))

(defun cmd-send (client args)
  "Send message command"
  (when (< (length args) 2)
    (return-from cmd-send "Usage: send <conversation_id> <message>"))

  (let ((conv-id (first args))
        (content (format nil "~{~a~^ ~}" (rest args))))
    (send-chat-message client conv-id content)
    "Message sent."))

(defun cmd-conversations (client)
  "List conversations command"
  (get-conversations client)
  "Loading conversations... (check callback for results)")

(defun cmd-messages (client args)
  "Get messages command"
  (when (null args)
    (return-from cmd-messages "Usage: messages <conversation_id>"))

  (let ((conv-id (first args)))
    (get-messages client conv-id)
    "Loading messages... (check callback for results)"))

(defun cmd-online (client)
  "Show online users command"
  (get-online-users client)
  "Loading online users... (check callback for results)")

(defun cmd-status (client args)
  "Get user status command"
  (when (null args)
    (return-from cmd-status "Usage: status <user_id>"))

  (get-user-status client (first args))
  "Loading status... (check callback for results)")

(defun cmd-typing (client args)
  "Send typing indicator command"
  (when (null args)
    (return-from cmd-typing "Usage: typing <conversation_id>"))

  (send-typing client (first args))
  "Typing indicator sent.")

(defun cmd-read (client args)
  "Mark as read command"
  (when (null args)
    (return-from cmd-read "Usage: read <conversation_id>"))

  (mark-as-read client (first args))
  "Marked as read.")

(defun cmd-logout (client)
  "Logout command"
  (logout client)
  "Logged out.")

(defun cmd-quit (client)
  "Quit command"
  (disconnect client)
  (format t "Goodbye!~%")
  (sb-ext:quit))

;;;; Utility

(defun split-sequence (seq &key (remove-empty-subseqs nil))
  "Split a sequence by a delimiter"
  ;; Simplified implementation - use split-sequence library in production
  (declare (ignore remove-empty-subseqs))
  seq)
