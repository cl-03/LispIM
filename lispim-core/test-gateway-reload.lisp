(ql:quickload :lispim-core :force t)
(in-package :lispim-core)

(format t "~%~%Checking functions after force reload:~%")
(format t "start-gateway fbound: ~a~%" (fboundp 'start-gateway))
(format t "stop-gateway fbound: ~a~%" (fboundp 'stop-gateway))
(format t "*gateway-port* bound: ~a~%" (boundp '*gateway-port*))
(format t "*acceptor* bound: ~a~%" (boundp '*acceptor*))
(format t "*gateway-start-time* bound: ~a~%" (boundp '*gateway-start-time*))

(sb-ext:quit)
