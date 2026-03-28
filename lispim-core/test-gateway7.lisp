;; Test compiling gateway.lisp directly with the package already set up
(ql:quickload :lispim-core :force t)

(in-package :lispim-core)

;; Now try to load the gateway.lisp file directly
(format t "~%~%Loading gateway.lisp directly...~%")
(handler-case
    (progn
      (load "D:/Claude/LispIM/lispim-core/src/gateway.lisp")
      (format t "gateway.lisp loaded successfully~%"))
  (error (c)
    (format t "ERROR loading gateway.lisp: ~a~%" c)
    (format t "Type: ~a~%" (type-of c))))

;; Check if functions are now available
(format t "~%~%After loading gateway.lisp:~%")
(format t "  start-gateway fbound: ~a~%" (fboundp 'start-gateway))
(format t "  stop-gateway fbound: ~a~%" (fboundp 'stop-gateway))

(sb-ext:quit)
