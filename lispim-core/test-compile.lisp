(ql:quickload :lispim-core)
(in-package :lispim-core)

;; Try to compile init-multi-level-cache
(format t "~%~%Compiling init-multi-level-cache...~%")
(handler-case
    (progn
      (compile 'init-multi-level-cache)
      (format t "Compilation succeeded~%"))
  (error (c)
    (format t "Compilation failed: ~a~%" c)))

(sb-ext:quit)
