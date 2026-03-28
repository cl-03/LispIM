;; Test reading all forms from gateway.lisp
(format t "Reading all forms from gateway.lisp...~%")
(let ((form-count 0)
      (error-pos nil))
  (with-open-file (s "C:/Users/Administrator/quicklisp/local-projects/lispim-core/src/gateway.lisp" :direction :input)
    (handler-case
        (loop
          (let ((form (read s nil :eof)))
            (when (eq form :eof)
              (return))
            (incf form-count)
            (when (zerop (mod form-count 100))
              (format t "Read ~a forms...~%" form-count))))
      (error (c)
        (setf error-pos (file-position s))
        (format t "Error at position ~a: ~a~%" error-pos c))))
  (format t "~%Total forms read: ~a~%" form-count))
(sb-ext:quit)
