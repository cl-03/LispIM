;; Test compiling gateway.lisp directly
(ql:quickload :lispim-core :force t)

(in-package :lispim-core)

;; Check if gateway.lisp was compiled
(format t "~%~%Gateway status:~%")
(format t "  *gateway-port* bound: ~a~%" (boundp '*gateway-port*))
(format t "  *gateway-host* bound: ~a~%" (boundp '*gateway-host*))
(format t "  start-gateway fbound: ~a~%" (fboundp 'start-gateway))
(format t "  stop-gateway fbound: ~a~%" (fboundp 'stop-gateway))

;; List all symbols with "gateway" in the name
(format t "~%~%Gateway symbols:~%")
(do-all-symbols (sym :lispim-core)
  (when (search "GATEWAY" (symbol-name sym))
    (format t "  ~a: function=~a, variable=~a~%"
            sym
            (fboundp sym)
            (boundp sym))))

(sb-ext:quit)
