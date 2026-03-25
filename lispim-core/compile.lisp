;; Load ASDF system and compile lispim-core
;; 使用 *load-pathname* 获取当前文件所在目录
(let* ((base-path (or *load-pathname* *default-pathname-defaults*))
       (base-dir (pathname (directory-namestring base-path))))
  (pushnew base-dir asdf:*central-registry* :test 'equal))

(format t "~&;;; Loading lispim-core.asd...~%")
(load (merge-pathnames "lispim-core.asd" (or *load-pathname* *default-pathname-defaults*)))

(format t "~&;;; Compiling lispim-core...~%")
(asdf:load-system :lispim-core :verbose t)

(format t "~&;;; Compilation complete!~%")
(sb-ext:quit)
