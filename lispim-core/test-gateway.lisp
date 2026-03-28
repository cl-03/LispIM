(ql:quickload :lispim-core :force t)
(in-package :lispim-core)

(format t "~%~%Checking functions...~%")
(format t "start-gateway: ~a~%" (fboundp 'start-gateway))
(format t "stop-gateway: ~a~%" (fboundp 'stop-gateway))
(format t "*gateway-port*: ~a~%" (boundp '*gateway-port*))

(sb-ext:quit)
