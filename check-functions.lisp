;;;; check-functions.lisp - Check which functions are defined

(load "lispim-core/lispim-core.asd")

;; Suppress warnings during compilation
(let ((*standard-output* (make-broadcast-stream))
      (*error-output* (make-broadcast-stream)))
  (asdf:make :lispim-core))

(format t "~%Checking gateway.lisp functions...~%")

(dolist (fn '(start-gateway stop-gateway get-metrics make-api-response encode-api-response))
  (let ((sym (find-symbol (symbol-name fn) (find-package 'lispim-core))))
    (if sym
        (format t "~a: ~a~%" fn (fboundp sym))
        (format t "~a: NOT-FOUND~%" fn))))

(uiop:quit 0)
