;; Test loading gateway.lisp
(asdf:clear-source-registry)
(ql:quickload :lispim-core :force t)

(in-package :lispim-core)

(format t "~%~%Gateway status:~%")
(format t "  *gateway-port* bound: ~a~%" (boundp '*gateway-port*))
(format t "  *gateway-host* bound: ~a~%" (boundp '*gateway-host*))
(format t "  *gateway-start-time* bound: ~a~%" (boundp '*gateway-start-time*))
(format t "  start-gateway fbound: ~a~%" (fboundp 'start-gateway))
(format t "  stop-gateway fbound: ~a~%" (fboundp 'stop-gateway))

;; List all gateway-related symbols
(format t "~%~%Gateway symbols:~%")
(do-all-symbols (sym :lispim-core)
  (when (search "GATEWAY" (symbol-name sym))
    (format t "  ~a: function=~a, variable=~a~%"
            sym
            (if (fboundp sym) 'YES 'NO)
            (if (boundp sym) 'YES 'NO))))

(sb-ext:quit)
