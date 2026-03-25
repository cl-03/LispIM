;;;; start-server.lisp - Start the server

;; Register the system path
(pushnew #P"D:/Claude/LispIM/lispim-core/" asdf:*central-registry* :test #'equal)

;; Force recompilation by deleting FASL files
(let ((fasl-dir #P"C:/Users/Administrator/AppData/Local/cache/common-lisp/sbcl-2.5.8-win-x64/D/Claude/LispIM/lispim-core/src/"))
  (when (probe-file fasl-dir)
    (dolist (file (directory (merge-pathnames "*.fasl" fasl-dir)))
      (ignore-errors (delete-file file)))))

;; Clear ASDF cache
(let ((asdf-cache #P"C:/Users/Administrator/AppData/Local/cache/common-lisp/asdf/"))
  (when (probe-file asdf-cache)
    (dolist (file (directory (merge-pathnames "*.cache" asdf-cache)))
      (ignore-errors (delete-file file)))))

;; Force reload of lispim-core system
(asdf:clear-system :lispim-core)

;; Load and compile the system with :force t
(asdf:load-system :lispim-core :force t)

(format t "~%Starting LispIM server...~%")

;; Start the gateway
(lispim-core:start-server)

(format t "~%Server started! Press Ctrl+C to stop.~%")

;; Keep running
(loop do (sleep 1))
