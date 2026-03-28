;; Reload lispim-core with force
(format t "~%~%Loading lispim-core with force...~%")
(ql:quickload :lispim-core :force t)

(in-package :lispim-core)

(format t "~%~%Checking functions:~%")
(format t "start-gateway fbound: ~a~%" (fboundp 'start-gateway))
(format t "stop-gateway fbound: ~a~%" (fboundp 'stop-gateway))
(format t "*acceptor* bound: ~a~%" (boundp '*acceptor*))
(format t "*gateway-start-time* bound: ~a~%" (boundp '*gateway-start-time*))

(sb-ext:quit)
