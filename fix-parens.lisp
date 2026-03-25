;;;; fix-parens.lisp - Fix missing parens

;; Read the file
(with-open-file (in "lispim-core/src/gateway.lisp" :direction :input)
  (let* ((content (make-string (file-length in)))
         (result (make-string-output-stream)))
    (read-sequence content in)

    ;; Find start-gateway function and count parens
    (let ((depth 0)
          (in-start-gateway nil)
          (start-gateway-start 0)
          (pos 0))

      ;; First, find where start-gateway starts and ends
      (loop for i from 0 below (length content)
            for char = (char content i)
            do
            (when (and (not in-start-gateway)
                       (search "(defun start-gateway" content :start2 i :end2 (+ i 20)))
              (setf in-start-gateway t
                    start-gateway-start i))

            (when in-start-gateway
              (if (char= char #\()
                  (incf depth)
                  (when (char= char #\))
                    (decf depth)
                    (when (and (> depth 0) (= depth 1))
                      ;; This might be the end of start-gateway
                      ))))

            (incf pos))

      (format t "start-gateway starts at: ~a~%" start-gateway-start)
      (format t "Final depth in start-gateway: ~a~%" depth)))

  (format t "~%Analysis complete~%"))

(uiop:quit 0)
