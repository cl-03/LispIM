;;;; build-app.lisp - Compile LispIM Backend as Standalone Executable

(format t "~&Compiling LispIM Backend Desktop Application...~%~%")

;; 设置应用目录
(pushnew *default-pathname-defaults* asdf:*central-registry* :test 'equal)
(pushnew (merge-pathnames "src/" *default-pathname-defaults*) asdf:*central-registry* :test 'equal)

(format t "~&Loading lispim-core...~%")
(finish-output)

;; 预加载所有依赖
(asdf:load-system :lispim-core)

(format t "~&Loading lispim-backend-app...~%")
(finish-output)

;; 加载应用代码
(load "lispim-backend-app.lisp")

(format t "~&Creating executable...~%")
(finish-output)

;; 创建可执行文件
(sb-ext:save-lisp-and-die "build/LispIM_backend.exe"
                          :toplevel #'lispim-backend-app::main
                          :executable t
                          :purify t
                          :compression t)

(format t "~&Executable created successfully!~%")
(finish-output)
