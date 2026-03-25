;;;; check-start-gateway.lisp - Check start-gateway definition

(load "lispim-core/lispim-core.asd")

;; Compile up to gateway
(asdf:make :lispim-core)

;; Try to compile just start-gateway
(in-package :lispim-core)

;; Check if *acceptor* is defined
(format t "~%*acceptor* bound: ~a~%" (boundp '*acceptor*))
(format t "*gateway-host* bound: ~a~%" (boundp '*gateway-host*))
(format t "*gateway-port* bound: ~a~%" (boundp '*gateway-port*))

;; Try to manually define start-gateway
(defun test-start-gateway (&key (host "0.0.0.0") (port 8443))
  "Test function"
  (format t "Starting on ~a:~a~%" host port))

(format t "test-start-gateway fbound: ~a~%" (fboundp 'test-start-gateway))

(uiop:quit 0)
