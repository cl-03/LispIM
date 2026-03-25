;;;; simple-verify.lisp - Simple verification

(format t "~%Loading ASDF...~%")
(load "lispim-core/lispim-core.asd")

(format t "Compiling...~%")
(ignore-errors (asdf:make :lispim-core))

(format t "Done!~%")

;; Check start-gateway
(let ((pkg (find-package 'lispim-core)))
  (when pkg
    (let ((sym (find-symbol "START-GATEWAY" pkg)))
      (if sym
          (format t "START-GATEWAY fbound: ~a~%" (fboundp sym))
          (format t "START-GATEWAY not found~%")))))

(uiop:quit 0)
