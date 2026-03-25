;;;; test-all.lisp - Test all functions

(load "lispim-core/lispim-core.asd")
(asdf:make :lispim-core)

(let ((pkg (find-package 'lispim-core)))
  (when pkg
    (format t "~%Function Status:~%")
    (format t "================~%")
    (dolist (sym-name '("START-GATEWAY" "STOP-GATEWAY" "HEALTHZ" "READYZ" "METRICS"
                        "API-LOGIN-V1" "API-REGISTER-V1" "API-SEND-CODE-V1"))
      (let ((sym (find-symbol sym-name pkg)))
        (if sym
            (format t "~a: ~a~%" sym-name (if (fboundp sym) "DEFINED" "NOT-DEFINED"))
            (format t "~a: NOT-FOUND~%" sym-name))))))

(format t "~%Done!~%")
(uiop:quit 0)
