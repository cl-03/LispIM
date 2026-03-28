;;;; run-server.lisp - Run LispIM Server (after compilation)

(format t "~&================================~%")
(format t "~&  LispIM Enterprise Server v0.1.0~%")
(format t "~&================================~%~%")

(require 'asdf)
;; 使用 *load-pathname* 获取当前文件所在目录
(let* ((base-path (or *load-pathname* *default-pathname-defaults*))
       (base-dir (pathname (directory-namestring base-path))))
  (pushnew base-dir asdf:*central-registry* :test 'equal)
  (pushnew (merge-pathnames "src/" base-dir) asdf:*central-registry* :test 'equal))

(format t "~&Loading lispim-core system...~%")
(asdf:clear-system :lispim-core)
(handler-bind ((warning #'muffle-warning))
  (asdf:load-system :lispim-core))

(format t "~&Starting server on port 3000...~%~%")

(in-package :lispim-core)

;; Create test user if not exists
(handler-case
    (create-user "test-user-001" "test" "test123456" "test@example.com" :display-name "Test User")
  (condition (e)
    (format t "~&User exists or error: ~a~%" e)))

(format t "~&~%Server starting...~%")
(format t "~&API Endpoints:~%")
(format t "~&  POST /api/v1/auth/login     - User login~%")
(format t "~&  POST /api/v1/auth/logout    - User logout~%")
(format t "~&  GET  /healthz               - Health check~%")
(format t "~&~%Press Ctrl+C to stop~%~%")

(start-server)

;; Keep SBCL running
(format t "~&Server running. Waiting for requests...~%")
(loop do (sleep 10))
