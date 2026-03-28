;; Check symbol type
(ql:quickload :lispim-core :force t)
(in-package :lispim-core)

(format t "~%~%Symbol inspection for start-gateway:~%")
(format t "fboundp: ~a~%" (fboundp 'start-gateway))
(format t "macro-function: ~a~%" (macro-function 'start-gateway))
(format t "special-operator-p: ~a~%" (special-operator-p 'start-gateway))
(format t "symbol-function: ~a~%" (ignore-errors (symbol-function 'start-gateway)))
(format t "type: ~a~%" (type-of 'start-gateway))

;; Check if it's a generic function
(format t "~%~%Is it a generic function?~%")
(handler-case
    (progn
      (let ((fn (symbol-function 'start-gateway)))
        (format t "function type: ~a~%" (type-of fn))
        (format t "Is generic-function: ~a~%" (typep fn 'generic-function))))
  (error (c)
    (format t "Error: ~a~%" c)))

(sb-ext:quit)
