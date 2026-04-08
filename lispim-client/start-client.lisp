;;;; start-client.lisp - Start the LispIM Client

;; Load the system
(load "load-system.lisp")

(in-package :lispim-client)

(format t "~%~%LispIM Pure Common Lisp Client~%")
(format t "================================~%~%")

;; Create client instance
(defvar *client* (make-lispim-client
                  :server-url "http://127.0.0.1:3000"
                  :websocket-url "ws://127.0.0.1:3000/ws"))

(format t "Client created.~%")
(format t "Server: http://127.0.0.1:3000~%")
(format t "WebSocket: ws://127.0.0.1:3000/ws~%~%")

(format t "To login, use: (client-login *client* \"username\" \"password\")~%")
(format t "To start the GUI, use: (lispim-client/ui:open-login-frame *client*)~%~%")

;; Start REPL
(sb-ext:repl)
