;;;; start-minimal.lisp - Start LispIM Server (minimal, no prompts)

(format t "~&================================~%")
(format t "~&  LispIM Enterprise Server v0.1.0~%")
(format t "~&================================~%~%")

(require 'asdf)
;; 使用 *load-pathname* 获取当前文件所在目录，添加相对路径到 ASDF
(let* ((base-path (or *load-pathname* *default-pathname-defaults*))
       (base-dir (pathname (directory-namestring base-path))))
  (pushnew base-dir asdf:*central-registry* :test 'equal)
  (pushnew (merge-pathnames "src/" base-dir) asdf:*central-registry* :test 'equal))

(format t "~&Loading Quicklisp systems...~%")
(ql:quickload '(:hunchentoot :cl-json :bordeaux-threads :uuid :babel :log4cl :ironclad :alexandria :postmodern :cl-redis :salza2 :local-time :trivia :serapeum :flexi-streams) :prompt nil)

(format t "~&Loading lispim-core system...~%")
(asdf:load-system :lispim-core :verbose nil)

(format t "~&Starting server on port 8443...~%~%")

(in-package :lispim-core)

;; Create test user
(handler-case
    (auth:create-user "test-user-001" "test" "test123456" "test@example.com" :display-name "Test User")
  (condition (e)
    (format t "~&Note: ~a~%" e)))

(format t "~&~%Server starting...~%")
(format t "~&API Endpoints:~%")
(format t "~&  POST /api/v1/auth/login     - User login~%")
(format t "~&  POST /api/v1/auth/logout    - User logout~%")
(format t "~&  GET  /healthz               - Health check~%")
(format t "~&~%Press Ctrl+C to stop~%~%")

(start-server)
