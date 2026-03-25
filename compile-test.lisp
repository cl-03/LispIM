;;;; compile-test.lisp - Compile and check for errors

(load "lispim-core/lispim-core.asd")

(format t "~%Compiling lispim-core...~%")

(handler-case
    (progn
      (asdf:make :lispim-core)
      (format t "~%Compilation complete~%"))
  (error (c)
    (format t "~%Compilation error: ~a~%" c)
    (finish-output)
    (uiop:quit 1)))

;; Check if start-gateway is fbound
(let ((pkg (find-package 'lispim-core)))
  (when pkg
    (format t "~%Package lispim-core exists~%")
    (format t "Checking start-gateway...~%")
    (format t "fboundp: ~a~%" (fboundp 'lispim-core:start-gateway))
    (if (fboundp 'lispim-core:start-gateway)
        (progn
          (format t "~%Starting server...~%")
          (lispim-core:start-server))
        (progn
          (format t "~%ERROR: start-gateway is not defined!~%")
          (uiop:quit 1)))))

(uiop:quit 0)
