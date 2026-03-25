;;;; verify-fix.lisp - Verify the fix

(load "lispim-core/lispim-core.asd")

;; Suppress warnings during compilation
(format t "~%Compiling lispim-core...~%")
(let ((*standard-output* (make-broadcast-stream))
      (*error-output* (make-broadcast-stream)))
  (asdf:make :lispim-core))

(format t "~%Compilation complete!~%")

;; Check functions
(dolist (fn '(start-gateway stop-gateway get-metrics make-api-response))
  (let ((sym (find-symbol (symbol-name fn) (find-package 'lispim-core))))
    (if sym
        (format t "~a: ~a~%" fn (fboundp sym))
        (format t "~a: NOT-FOUND~%" fn))))

(uiop:quit 0)
