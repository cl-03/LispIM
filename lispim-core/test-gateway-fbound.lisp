;; Test loading gateway.lisp directly
(format t "~%~%Loading lispim-core via ASDF...~%")
(ql:quickload :lispim-core :force t)

(in-package :lispim-core)

(format t "~%~%After loading lispim-core:~%")
(format t "start-gateway fbound: ~a~%" (fboundp 'start-gateway))
(format t "stop-gateway fbound: ~a~%" (fboundp 'stop-gateway))
(format t "start-heartbeat-monitor fbound: ~a~%" (fboundp 'start-heartbeat-monitor))

;; Check if the symbol exists
(let ((sym (find-symbol "START-GATEWAY" :lispim-core)))
  (when sym
    (format t "~%~%Symbol ~a info:~%" sym)
    (format t "  symbol-package: ~a~%" (symbol-package sym))
    (format t "  fboundp: ~a~%" (fboundp sym))
    (format t "  symbol-function: ~a~%" (ignore-errors (symbol-function sym)))))

(sb-ext:quit)
