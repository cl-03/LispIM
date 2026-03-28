;; Test redis package symbols
(load (merge-pathnames #P"quicklisp/setup.lisp" (user-homedir-pathname)))
(quicklisp:quickload '(:cl-redis) :silent t)

(format t "~%Redis package symbols:~%")
(do-external-symbols (s :redis)
  (format t "  ~a~%" s))

(format t "~%All redis package symbols:~%")
(in-package :redis)
(do-symbols (s)
  (when (eq (symbol-package s) (find-package :redis))
    (format t "  ~a~%" s)))

(sb-ext:quit)
