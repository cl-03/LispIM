;; Test reading and checking each form
(format t "Reading all forms from gateway.lisp...~%")
(require "asdf")
(require "cl-fad")

;; First read the file and check structure
(let ((form-count 0)
      (all-forms nil)
      (error-info nil))
  (with-open-file (s "C:/Users/Administrator/quicklisp/local-projects/lispim-core/src/gateway.lisp" :direction :input)
    (handler-case
        (loop
          (let ((pos (file-position s))
                (line 1)
                (col 1))
            ;; Get line/column
            (file-position s 0)
            (dotimes (i (- pos 0))
              (let ((c (read-char s)))
                (if (char= c #\Newline)
                    (progn (incf line) (setf col 1))
                    (incf col))))
            (file-position s pos)

            (let ((form (read s nil :eof)))
              (when (eq form :eof)
                (return))
              (incf form-count)
              (push form all-forms)
              (when (zerop (mod form-count 50))
                (format t "Read ~a forms (line ~a, col ~a)~%" form-count line col)))))
      (error (c)
        (let ((pos (file-position s)))
          (setf error-info (list :message (princ-to-string c) :position pos))
          (format t "~%~%Error at position ~a:~%  ~a~%" pos c)))))

  (format t "~%Total forms read: ~a~%" form-count)
  (when error-info
    (format t "Error info: ~a~%" error-info)))

(sb-ext:quit)
