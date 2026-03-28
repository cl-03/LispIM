;; Compile and check for warnings
(format t "~%~%Loading lispim-core...~%")
(ql:quickload :lispim-core :force t)

(in-package :lispim-core)

(format t "~%~%Compilation result:~%")
(format t "start-gateway fbound: ~a~%" (fboundp 'start-gateway))
(format t "stop-gateway fbound: ~a~%" (fboundp 'stop-gateway))
(format t "start-heartbeat-monitor fbound: ~a~%" (fboundp 'start-heartbeat-monitor))
(format t "check-heartbeats fbound: ~a~%" (fboundp 'check-heartbeats))

;; Try to call start-gateway
(format t "~%~%Trying to call start-gateway (will fail if undefined)...~%")
(handler-case
    (progn
      ;; Just check if we can reference the function
      (symbol-function 'start-gateway)
      (format t "start-gateway function exists!~%"))
  (undefined-function (c)
    (format t "UNDEFINED-FUNCTION: ~a~%" c)))

(sb-ext:quit)
