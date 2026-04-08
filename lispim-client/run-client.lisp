;;;; run-client.lisp - Run the LispIM Client with McCLIM

;; Load Quicklisp if not already loaded
(unless (find-package :quicklisp)
  (load (merge-pathnames "quicklisp.lisp" *load-truename*)))

(quicklisp:quickload :lispim-client)

(in-package :lispim-client)

(format t "~%~%========================================~%")
(format t "LispIM Pure Common Lisp Client~%")
(format t "========================================~%~%")

;; Create client
(defvar *client* (make-lispim-client
                  :server-url "http://127.0.0.1:3000"
                  :websocket-url "ws://127.0.0.1:3000/ws"))

(format t "Client created.~%")
(format t "~%To login and start the GUI:~%")
(format t "  (lispim-client/ui:open-login-frame *client*)~%~%")

;; Auto-start GUI if desired
;; (lispim-client/ui:open-login-frame *client*)
