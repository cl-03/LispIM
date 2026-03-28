(ql:quickload :lispim-core)
(in-package :lispim-core)

;; Check if multi-level-cache.lisp is loaded
(format t "~%~%Checking package symbols...~%")
(do-external-symbols (sym :lispim-core)
  (when (search "MLC" (symbol-name sym))
    (format t "Found: ~a~%" sym)))

;; Check if init-multi-level-cache exists
(if (fboundp 'init-multi-level-cache)
    (format t "init-multi-level-cache is FBOUNDP~%")
    (format t "init-multi-level-cache is NOT FBOUNDP~%"))

;; Check multi-level-cache variable
(if (boundp '*multi-level-cache*)
    (format t "*multi-level-cache* is BOUNDP~%")
    (format t "*multi-level-cache* is NOT BOUNDP~%"))

(sb-ext:quit)
