;; Check ASDF system source location
(ql:quickload :lispim-core)

(let ((system (asdf:find-system :lispim-core)))
  (format t "~%~%ASDF System info:~%")
  (format t "System: ~a~%" system)
  (format t "Source location: ~a~%" (asdf:component-pathname system))
  (format t "Source registry: ~a~%" (asdf:system-source-directory system)))

;; Check gateway component
(let ((gw (asdf:find-component :lispim-core '("src" "gateway"))))
  (when gw
    (format t "~%~%Gateway component:~%")
    (format t "Component: ~a~%" gw)
    (format t "Path: ~a~%" (asdf:component-pathname gw))))

(sb-ext:quit)
