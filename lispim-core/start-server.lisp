;; Load system from FASLs (pre-compiled) or compile from source
(load "load-system.lisp")

(in-package :lispim-core)
(format t "~%~%Starting LispIM server...~%")

;; Initialize storage and gateway
(init-storage "postgresql://lispim:Clsper03@localhost:5432/lispim" "redis://localhost:6379")

;; Initialize message sequence counters from database (if available)
(when (fboundp 'initialize-sequence-counters)
  (initialize-sequence-counters))

;; Start gateway
(start-gateway :port 3000)

(format t "~%~%Server started successfully~%")
(format t "~%Press Ctrl+C to stop the server~%")
;; Keep running
(loop do (sleep 1))
