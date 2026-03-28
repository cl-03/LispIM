;; Test loading gateway.lisp directly
(format t "~%~%Loading dependencies...~%")
(ql:quickload :hunchentoot)
(ql:quickload :bordeaux-threads)
(ql:quickload :cl-json)
(ql:quickload :flexi-streams)
(ql:quickload :cl-base64)
(ql:quickload :ironclad)
(ql:quickload :uuid)
(ql:quickload :cl-ppcre)
(ql:quickload :cl-fad)

(format t "~%~%Loading package...~%")
(load "D:/Claude/LispIM/lispim-core/src/package.lisp")

(in-package :lispim-core)

(format t "~%~%Loading gateway.lisp directly (no compilation)...~%")
(handler-case
    (progn
      (load "D:/Claude/LispIM/lispim-core/src/gateway.lisp" :verbose t)
      (format t "~%~%After loading gateway.lisp:~%")
      (format t "start-gateway fbound: ~a~%" (fboundp 'start-gateway))
      (format t "stop-gateway fbound: ~a~%" (fboundp 'stop-gateway))
      (format t "start-heartbeat-monitor fbound: ~a~%" (fboundp 'start-heartbeat-monitor)))
  (error (c)
    (format t "~%~%LOAD ERROR: ~a~%" c)
    (format t "Type: ~a~%" (type-of c))))

(sb-ext:quit)
