;; Direct compilation test - compile gateway.lisp directly
(format t "~%~%Loading dependencies...~%")
(ql:quickload :hunchentoot)
(ql:quickload :bordeaux-threads)
(ql:quickload :cl-json)
(ql:quickload :flexi-streams)
(ql:quickload :cl-base64)
(ql:quickload :ironclad)

(format t "~%~%Loading lispim-core package...~%")
(ql:quickload :lispim-core :force t)

(in-package :lispim-core)

;; Now compile gateway.lisp directly
(format t "~%~%Compiling gateway.lisp directly...~%")
(let ((out-file "D:/Claude/LispIM/lispim-core/tmp/gateway-direct.fasl"))
  (handler-case
      (progn
        (compile-file "D:/Claude/LispIM/lispim-core/src/gateway.lisp"
                      :output-file out-file
                      :print t
                      :verbose t)
        (format t "~%~%Compilation succeeded, loading FASL...~%")
        (load out-file)
        (format t "~%~%After loading FASL:~%")
        (format t "start-gateway fbound: ~a~%" (fboundp 'start-gateway)))
    (error (c)
      (format t "~%~%COMPILE/LOAD ERROR: ~a~%" c)
      (format t "Type: ~a~%" (type-of c)))))

(sb-ext:quit)
