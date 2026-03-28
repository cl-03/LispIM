;; Force reload of the system
(ql:quickload :lispim-core :force t)
(in-package :lispim-core)
(format t "~%~%Starting LispIM server...~%")
(start-server)
(format t "~%~%Server started successfully~%")
(format t "~%Press Ctrl+C to stop the server~%")
;; Keep running
(loop while *server-running*
      do (sleep 1))
