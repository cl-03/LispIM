;;;; test-gateway.lisp - Test if start-gateway is defined

(load "lispim-core/lispim-core.asd")
(asdf:make :lispim-core)

(format t "~%~%================================~%")
(format t "Gateway function exists: ~a~%" (fboundp 'lispim-core:start-gateway))
(format t "================================~%~%")

(when (fboundp 'lispim-core:start-gateway)
  (format t "Starting server...~%")
  (lispim-core:start-server))
