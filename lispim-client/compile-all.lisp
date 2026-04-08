;;; compile-all.lisp - Compile the entire lispim-client system

;; Load Quicklisp if not already loaded
(unless (find-package :ql)
  (load (merge-pathnames "quicklisp.lisp" *load-truename*)))

(ql:quickload :lispim-client :verbose t)

(format t "~&~%========================================~%")
(format t "LispIM Client compiled successfully!~%")
(format t "========================================~%~%")
