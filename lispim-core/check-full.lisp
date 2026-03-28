;; check-full.lisp - Check full compilation

(pushnew #P"D:/Claude/LispIM/lispim-core/" asdf:*central-registry* :test 'equal)

(format t "~&;;; Loading lispim-core.asd...~%")
(load "lispim-core.asd")

(format t "~&;;; Compiling lispim-core...~%")

(handler-case
    (progn
      (asdf:load-system :lispim-core :verbose t)
      (format t "~&;;; Compilation complete!~%"))
  (error (c)
    (format t "~&;;; Compilation error: ~A~%" c)
    (format t ";;; Error type: ~A~%" (type-of c))))

(sb-ext:quit)
