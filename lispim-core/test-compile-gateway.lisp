;; Compile gateway.lisp and capture all output
(format t "~%~%Compiling gateway.lisp...~%")

;; First load the package
(ql:quickload :lispim-core :force t)

(in-package :lispim-core)

;; Now compile the file to a temp location
(let ((tmp-file "D:/Claude/LispIM/lispim-core/tmp/gateway-test.fasl"))
  (handler-case
      (multiple-value-list (compile-file "D:/Claude/LispIM/lispim-core/src/gateway.lisp"
                                          :output-file tmp-file
                                          :print t
                                          :verbose t))
    (error (c)
      (format t "~%COMPILE ERROR: ~a~%" c)
      (format t "Type: ~a~%" (type-of c)))))

(format t "~%~%Checking functions after compile:~%")
(format t "start-gateway fbound: ~a~%" (fboundp 'start-gateway))

(sb-ext:quit)
