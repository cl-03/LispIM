;; Manual compilation test
(format t "~%~%Step 1: Loading dependencies...~%")
(ql:quickload :lispim-core :force t)

(in-package :lispim-core)

(format t "~%~%Step 2: Check current state~%")
(format t "start-gateway fbound: ~a~%" (fboundp 'start-gateway))

;; Get the gateway component
(let ((system (asdf:find-system :lispim-core)))
  (format t "~%~%Step 3: ASDF system info~%")
  (format t "System: ~a~%" system)

  ;; Find gateway component
  (let ((gw-comp (asdf:find-component system '("src" "gateway"))))
    (when gw-comp
      (format t "Gateway component: ~a~%" gw-comp)
      (format t "Gateway pathname: ~a~%" (asdf:component-pathname gw-comp))

      ;; Check if it's already compiled
      (format t "~%~%Step 4: Check compilation status~%")
      (let ((fasl (compile-file-pathname (asdf:component-pathname gw-comp))))
        (format t "FASL path: ~a~%" fasl)
        (format t "FASL exists: ~a~%" (probe-file fasl))))))

(format t "~%~%Step 5: Try to compile gateway directly~%")
(let ((src "D:/Claude/LispIM/lispim-core/src/gateway.lisp")
      (fasl "D:/Claude/LispIM/lispim-core/tmp/gateway-manual.fasl"))
  (ensure-directories-exist fasl)
  (handler-case
      (progn
        (format t "Compiling ~a -> ~a~%" src fasl)
        (compile-file src :output-file fasl :print t :verbose t)
        (format t "~%Compilation succeeded!~%")

        ;; Now load it
        (format t "Loading FASL...~%")
        (load fasl :verbose t)

        (format t "~%~%After loading FASL:~%")
        (format t "start-gateway fbound: ~a~%" (fboundp 'start-gateway))
        (format t "stop-gateway fbound: ~a~%" (fboundp 'stop-gateway)))
    (error (c)
      (format t "~%~%ERROR: ~a~%" c)
      (format t "Type: ~a~%" (type-of c)))))

(sb-ext:quit)
