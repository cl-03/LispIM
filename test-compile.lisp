;;;; test-compile.lisp - Test compile gateway

(load "lispim-core/lispim-core.asd")

;; First compile the whole system
(asdf:make :lispim-core)

;; Now check what's in the package
(let ((pkg (find-package 'lispim-core)))
  (if pkg
      (progn
        (format t "~%Package exists~%")
        ;; Check if symbol exists
        (let ((sym (find-symbol "START-GATEWAY" pkg)))
          (if sym
              (progn
                (format t "Symbol START-GATEWAY found: ~a~%" sym)
                (format t "Is it fbound? ~a~%" (fboundp sym)))
              (format t "Symbol START-GATEWAY not found~%"))))
      (format t "~%Package does not exist~%")))

(uiop:quit 0)
