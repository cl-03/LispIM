;;;; load-system.lisp - Load LispIM Client system

;; Load Quicklisp if not already loaded
(unless (find-package :quicklisp)
  (let ((quicklisp-init (merge-pathnames "quicklisp.lisp" *load-truename*)))
    (when (probe-file quicklisp-init)
      (load quicklisp-init))))

;; Add to ASDF source registry
(pushnew (truename ".") asdf:*central-registry* :test #'equal)

;; Load the system using ASDF
;; Dependencies are defined in lispim-client.asd
(asdf:load-system :lispim-client)

(format t "~%LispIM Client loaded successfully.~%")
