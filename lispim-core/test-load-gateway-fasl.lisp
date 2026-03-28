;; Load the compiled FASL and check functions
(format t "~%~%Loading compiled gateway FASL...~%")

;; First load the package
(ql:quickload :lispim-core :force t)

(in-package :lispim-core)

;; Load the compiled FASL
(handler-case
    (load "D:/Claude/LispIM/lispim-core/tmp/gateway-test.fasl")
  (error (c)
    (format t "~%LOAD ERROR: ~a~%" c)
    (format t "Type: ~a~%" (type-of c))))

(format t "~%~%Checking functions after loading FASL:~%")
(format t "start-gateway fbound: ~a~%" (fboundp 'start-gateway))
(format t "stop-gateway fbound: ~a~%" (fboundp 'stop-gateway))
(format t "*gateway-port* bound: ~a~%" (boundp '*gateway-port*))
(format t "*acceptor* bound: ~a~%" (boundp '*acceptor*))

(sb-ext:quit)
