;; Clear ASDF cache and reload
(format t "~%~%Clearing ASDF cache...~%")

;; Delete compiled FASLs
(let ((cache-dir "C:/Users/Administrator/.cache/common-lisp/"))
  (when (probe-file cache-dir)
    (format t "Cache dir exists: ~a~%" cache-dir)
    ;; We can't easily delete from Lisp, but we can note it
    ))

;; Force reload
(format t "~%~%Forcing reload...~%")
(asdf:oos 'asdf:load-op :lispim-core :force t)

(in-package :lispim-core)

(format t "~%~%After force reload:~%")
(format t "start-gateway fbound: ~a~%" (fboundp 'start-gateway))
(format t "*gateway-port* bound: ~a~%" (boundp '*gateway-port*))

(sb-ext:quit)
