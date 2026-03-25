;;;; run-server.lisp - Run the LispIM Server

;; Load Quicklisp
(load "C:/Users/Administrator/quicklisp/setup.lisp")

;; Register local projects
(ql:register-local-projects)

;; Set up ASDF registry as backup
(pushnew #P"D:/Claude/LispIM/lispim-core/" asdf:*central-registry* :test #'equal)

(format t "~%=== LispIM Enterprise Server v0.1.0 ===~%")
(format t "Loading system...~%")

;; Load the system
(handler-case
    (progn
      ;; Force recompilation
      (asdf:clear-system :lispim-core)
      (asdf:compile-system :lispim-core :force t)
      (ql:quickload :lispim-core :verbose nil)
      (format t "System loaded successfully!~%")
      (format t "Starting server on port 4321...~%~%"))
  (error (c)
    (format t "Failed to load system: ~a~%" c)
    (finish-output)
    (sb-ext:quit :unix-status 1)))

;; Start the server
(handler-case
    (progn
      (lispim-core:start-server)
      (format t "~%Server is running! Press Ctrl+C to stop.~%")
      (finish-output)
      ;; Keep running
      (loop while lispim-core::*server-running* do (sleep 1)))
  (error (c)
    (format t "Server error: ~a~%" c)
    (lispim-core:stop-server)
    (sb-ext:quit :unix-status 1)))
