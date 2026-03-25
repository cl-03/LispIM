;;;; check-parens.lisp - Check parentheses balance

(with-open-file (stream "D:/Claude/LispIM/lispim-core/src/gateway.lisp" :direction :input)
  (let ((content (make-string (file-length stream))))
    (read-sequence content stream)

    ;; Count parentheses
    (let ((open-parens 0)
          (close-parens 0)
            (open-brackets 0)
            (close-brackets 0))
      (dotimes (i (length content))
        (let ((char (char content i)))
          (when (char= char #\() (incf open-parens))
          (when (char= char #\)) (incf close-parens))
          (when (char= char #\[) (incf open-brackets))
          (when (char= char #\]) (incf close-brackets))))
      (format t "Open parens: ~a~%" open-parens)
      (format t "Close parens: ~a~%" close-parens)
      (format t "Paren balance: ~a~%" (- open-parens close-parens))
      (format t "Open brackets: ~a~%" open-brackets)
      (format t "Close brackets: ~a~%" close-brackets)
      (format t "Bracket balance: ~a~%" (- open-brackets close-brackets))
      (if (and (= open-parens close-parens) (= open-brackets close-brackets))
          (format t "~%ALL BALANCED!~%")
          (format t "~%UNBALANCED!~%")))))

(uiop:quit 0)
