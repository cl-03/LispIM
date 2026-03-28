;; Check for package/shadowing issues
(ql:quickload :lispim-core :force t)

(in-package :lispim-core)

;; Check if start-gateway is shadowed
(format t "~%~%Package info:~%")
(format t "Package: ~a~%" *package*)
(format t "start-gateway in package: ~a~%" (find-symbol "START-GATEWAY" :lispim-core))

;; Check shadows
(format t "~%Shadows: ~a~%" (package-shadowing-symbols :lispim-core))

;; Check what start-gateway is
(let ((sym (find-symbol "START-GATEWAY" :lispim-core)))
  (when sym
    (format t "~%~%Symbol ~a info:~%" sym)
    (format t "  symbol-package: ~a~%" (symbol-package sym))
    (format t "  fboundp: ~a~%" (fboundp sym))
    (format t "  boundp: ~a~%" (boundp sym))
    (format t "  constantp: ~a~%" (constantp sym))))

;; Try to compile and eval the defun directly
(format t "~%~%Trying to eval defun directly...~%")
(handler-case
    (progn
      (eval '(defun test-gateway-fn () "test" 42))
      (format t "test-gateway-fn fbound: ~a~%" (fboundp 'test-gateway-fn))
      (format t "test-gateway-fn result: ~a~%" (test-gateway-fn)))
  (error (c)
    (format t "Error: ~a~%" c)))

(sb-ext:quit)
