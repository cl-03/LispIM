;;;; check-gateway-syntax.lisp - Check gateway.lisp syntax

(load "lispim-core/lispim-core.asd")

;; Read and parse gateway.lisp without compiling
(with-open-file (stream "lispim-core/src/gateway.lisp" :direction :input)
  (let ((content (make-string (file-length stream))))
    (read-sequence content stream)
    (format t "~%File size: ~a characters~%" (length content))

    ;; Count parentheses
    (let ((open-parens 0)
          (close-parens 0))
      (dotimes (i (length content))
        (let ((char (char content i)))
          (when (char= char #\() (incf open-parens))
          (when (char= char #\)) (incf close-parens))))
      (format t "Open parens: ~a~%" open-parens)
      (format t "Close parens: ~a~%" close-parens)
      (format t "Balance: ~a~%" (- open-parens close-parens)))))

(uiop:quit 0)
