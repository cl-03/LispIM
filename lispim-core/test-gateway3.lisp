;; Test loading gateway.lisp step by step
(ql:quickload :lispim-core :force t)

(in-package :lispim-core)

;; Try to call start-gateway
(format t "~%~%Trying to call start-gateway...~%")
(handler-case
    (progn
      (funcall #'start-gateway :port 9999)
      (format t "start-gateway called successfully~%"))
  (undefined-function (c)
    (format t "UNDEFINED-FUNCTION: ~a~%" c))
  (error (c)
    (format t "ERROR: ~a~%" c)))

;; Check if the function exists now
(format t "~%~%After call attempt:~%")
(format t "start-gateway fbound: ~a~%" (fboundp 'start-gateway))

(sb-ext:quit)
