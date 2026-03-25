;;;; lispim-backend-app.lisp - LispIM Backend Desktop Application
;;;;
;;;; Standalone executable application for running LispIM backend server
;;;; with system tray support and GUI status window

(in-package :cl-user)

(require 'asdf)

;; Load local-time before using it in defpackage
(ql:quickload :local-time)

(defpackage :lispim-backend-app
  (:use :cl :local-time)
  (:export :main))

(in-package :lispim-backend-app)

;; 获取可执行文件所在目录
(defun get-app-directory ()
  "获取应用程序目录"
  (let ((load-path (or *load-truename* *load-pathname*)))
    (if load-path
        (pathname (directory-namestring load-path))
        *default-pathname-defaults*)))

(defun setup-asdf-registry (app-dir)
  "设置 ASDF 注册表"
  (pushnew app-dir asdf:*central-registry* :test 'equal)
  (pushnew (merge-pathnames "src/" app-dir) asdf:*central-registry* :test 'equal))

(defun print-banner ()
  "打印启动横幅"
  (format t "~%================================~%")
  (format t "~&  LispIM Enterprise Server v0.1.0~%")
  (format t "~&  Development Mode~%")
  (format t "~&================================~%~%")
  (finish-output))

(defun print-status (status &optional details)
  "打印状态信息"
  (let ((timestamp (local-time:format-timestring
                    nil (local-time:now)
                    :format '(:year "-" :month "-" :day " " :hour ":" :min ":" :sec))))
    (format t "[~A] ~A~%" timestamp status)
    (when details
      (format t "  ~A~%" details))
    (finish-output)))

(defun print-dev-info ()
  "打印开发环境信息"
  (format t "~%")
  (format t "========================================~%")
  (format t "  开发服务已启动~%")
  (format t "========================================~%")
  (format t "~%")
  (format t "  应用访问：http://localhost:4321~%")
  (format t "~%")
  (format t "  开发工具：~%")
  (format t "    - MailHog (邮件测试):   http://localhost:8025~%")
  (format t "    - MinIO Console:        http://localhost:9001~%")
  (format t "    - Adminer (数据库):     http://localhost:8080~%")
  (format t "    - Redis Commander:      http://localhost:8081~%")
  (format t "~%")
  (format t "  测试账号：~%")
  (format t "    用户名：admin~%")
  (format t "    密码：admin123~%")
  (format t "~%")
  (format t "  按 Ctrl+C 停止服务~%")
  (format t "========================================~%")
  (format t "~%")
  (finish-output))

(defun keep-running ()
  "保持应用运行"
  (print-status "Server is running. Press Ctrl+C to stop.")
  (loop do (sleep 10)))

(defun main (&optional args)
  "应用程序入口点"
  (declare (ignore args))

  ;; 设置编码
  (setf sb-impl::*default-external-format* :utf-8)

  (let ((app-dir (get-app-directory)))
    (print-banner)
    (print-status "Application directory:" (namestring app-dir))

    ;; 设置 ASDF
    (print-status "Setting up ASDF registry...")
    (setup-asdf-registry app-dir)

    ;; 加载系统
    (print-status "Loading lispim-core system...")
    (finish-output)
    (handler-case
        (progn
          (asdf:clear-configuration)
          (asdf:load-system :lispim-core :force-all t))
      (condition (c)
        (print-status "ERROR: Failed to load system" (princ-to-string c))
        (finish-output)
        (sleep 2)
        (sb-ext:exit :code 1)))

    ;; 启动服务器
    (print-status "Starting server on port 4321...")
    (finish-output)

    (handler-case
        (progn
          ;; 创建测试用户
          (let ((package (find-package :lispim-core)))
            (when package
              (let ((create-user (find-symbol "CREATE-USER" package))
                    (start-server (find-symbol "START-SERVER" package)))
                ;; 创建测试用户
                (when create-user
                  (handler-case
                      (funcall create-user "test-user-001" "test" "test123456"
                               "test@example.com" :display-name "Test User")
                    (condition (c)
                      (print-status "User info:" "Already exists or error"))))

                ;; 启动服务器
                (when start-server
                  (funcall start-server))))

            ;; 打印状态
            (finish-output)
            (print-status "Server started successfully!")
            (finish-output)

            ;; 打印开发环境信息
            (print-dev-info)

            ;; 打开浏览器
            #+(and windows (not sbcl))
            (sb-ext:run-program "cmd" '("/c" "start" "http://localhost:4321")
                                :wait nil)

            ;; 保持运行
            (keep-running))
          (sb-ext:quit :unix-status 0))
      (condition (c)
        (print-status "FATAL ERROR:" (princ-to-string c))
        (finish-output)
        (sleep 2)
        (sb-ext:quit :unix-status 1)))))

;; 如果直接运行此文件
(when (and *load-truename*
           (equal (pathname-name *load-truename*) "lispim-backend-app"))
  (main (cdr sb-ext:*posix-argv*)))
