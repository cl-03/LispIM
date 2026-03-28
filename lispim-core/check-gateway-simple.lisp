;; Simple gateway compile test
(load (merge-pathnames #P"quicklisp/setup.lisp" (user-homedir-pathname)))
(format t "~%Quicklisp loaded~%")
(quicklisp:quickload '(:hunchentoot :cl-ppcre :cl-json :postmodern :cl-redis
                       :bordeaux-threads :uuid :babel :salza2 :local-time
                       :log4cl :ironclad :trivia :alexandria :serapeum
                       :flexi-streams :str :drakma) :silent t)
(format t "~%Dependencies loaded~%")

;; Connect to Redis to initialize the package
(handler-case
    (progn
      (redis:connect :host "localhost" :port 6379)
      (format t "~%Redis connected~%"))
  (error (c)
    (format t "~%Redis connection failed (expected if server not running): ~a~%" c)))

;; Load minimal dependencies for gateway
(load "src/package.lisp")
(load "src/conditions.lisp")
(load "src/utils.lisp")
(load "src/snowflake.lisp")

;; Define stubs for complex dependencies
(defparameter *multi-level-cache* nil)
(defparameter *offline-queue* nil)
(defparameter *message-queue* nil)

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
