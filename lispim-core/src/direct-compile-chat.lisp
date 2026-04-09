;;; Direct compile test for chat.lisp
(load "/c/Users/Administrator/quicklisp/setup.lisp")
(ql:quickload '(:cl-json :bordeaux-threads :uuid :babel :dexador :alexandria) :silent t)

(format t "~%Compiling chat.lisp directly...~%")
(finish-output)

(handler-case
    (progn
      (compile-file "chat.lisp" :output-file "/tmp/chat-test.fasl")
      (format t "~%Direct compilation successful!~%")
      (sb-ext:quit :unix-status 0))
  (error (e)
    (format t "~%Direct compilation failed: ~A~%" e)
    (finish-output)
    (sb-ext:quit :unix-status 1)))
