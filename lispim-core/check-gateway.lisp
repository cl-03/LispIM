;; check-gateway.lisp - Check gateway.lisp for syntax errors

;; Load Quicklisp and dependencies
(load (merge-pathnames #P"quicklisp/setup.lisp" (user-homedir-pathname)))
(format t "~%Quicklisp loaded~%")
(quicklisp:quickload '(:hunchentoot :cl-ppcre :cl-json :postmodern :cl-redis
                       :bordeaux-threads :uuid :babel :salza2 :local-time
                       :log4cl :ironclad :trivia :alexandria :serapeum
                       :flexi-streams :str :drakma) :silent t)
(format t "~%Dependencies loaded~%")

;; Load lispim-core source files in order
(load "src/package.lisp")
(load "src/conditions.lisp")
(load "src/utils.lisp")
(load "src/snowflake.lisp")
(load "src/db-migration.lisp")
(load "src/storage.lisp")
(load "src/auth.lisp")
(load "src/message-status.lisp")
(load "src/message-encoding.lisp")
(load "src/message-compression.lisp")
(load "src/connection-pool.lisp")
(load "src/multi-level-cache.lisp")
(load "src/offline-queue.lisp")
(load "src/sync.lisp")
(load "src/message-queue.lisp")
(load "src/cluster.lisp")
(load "src/double-ratchet.lisp")
(load "src/cdn-storage.lisp")
(load "src/db-replica.lisp")
(load "src/message-dedup.lisp")
(load "src/rate-limiter.lisp")
(load "src/fulltext-search.lisp")
(load "src/message-reply.lisp")

(format t "~&;;; Compiling gateway.lisp...~%")

(handler-case
    (progn
      (compile-file "src/gateway.lisp"
                    :output-file "tmp/gateway.fasl"
                    :print t
                    :verbose t)
      (format t "~%=== Compilation successful! ===~%"))
  (error (c)
    (format t "~%=== Compilation failed: ~A ===~%" c)))

(sb-ext:quit)
