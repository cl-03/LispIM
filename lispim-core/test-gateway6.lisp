;; Compile gateway.lisp with full error reporting
(ql:quickload :lispim-core :force t)

(in-package :lispim-core)

;; Try to compile the start-gateway function from source
(format t "~%~%Trying to compile start-gateway from source...~%")

;; Read the source file and find the defun
(with-open-file (s "D:/Claude/LispIM/lispim-core/src/gateway.lisp" :direction :input)
  (let ((form nil)
        (found nil))
    (loop for line from 1
          for form = (ignore-errors (read s nil nil))
          while form
          do (when (and (listp form)
                        (eq (car form) 'defun)
                        (eq (cadr form) 'start-gateway))
               (setf found t)
               (format t "Found defun start-gateway at line ~a~%" line)
               (format t "Form: ~S~%" form)
               (return))))
    (unless found
      (format t "defun start-gateway NOT FOUND in file!~%"))))

(sb-ext:quit)
