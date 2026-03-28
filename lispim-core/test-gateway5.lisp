;; Detailed compilation test
(format t "~%~%Loading lispim-core...~%")
(handler-case
    (ql:quickload :lispim-core :force t)
  (error (c)
    (format t "ERROR during quickload: ~a~%" c)
    (format t "Condition: ~a~%" (type-of c))))

(in-package :lispim-core)

;; Check each component
(format t "~%~%Checking gateway.lisp components:~%")

;; Check if the file was loaded
(format t "  package lispim-core exists: ~a~%" (find-package :lispim-core))

;; Check specific symbols
(dolist (sym-name '("*ACCEPTOR*" "*GATEWAY-HOST*" "*GATEWAY-PORT*" "*GATEWAY-START-TIME*"
                    "START-GATEWAY" "STOP-GATEWAY"))
  (let ((sym (find-symbol sym-name :lispim-core)))
    (if sym
        (format t "  ~a: exists=~a, fbound=~a, bound=~a~%"
                sym-name
                T
                (if (fboundp sym) 'YES 'NO)
                (if (boundp sym) 'YES 'NO))
        (format t "  ~a: NOT FOUND in package~%" sym-name))))

(sb-ext:quit)
