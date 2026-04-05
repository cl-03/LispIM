;;;; start.lisp - Start LispIM Server
;;;;
;;;; 加载系统并启动服务器

(format t "~&================================~%")
(format t "~&  LispIM Enterprise Server v0.1.0~%")
(format t "~&================================~%~%")

;; 首先加载 ASDF
(require 'asdf)

;; 使用 *load-pathname* 获取当前文件所在目录，添加相对路径到 ASDF
(let* ((base-path (or *load-pathname* *default-pathname-defaults*))
       (base-dir (pathname (directory-namestring base-path))))
  (pushnew base-dir asdf:*central-registry* :test 'equal)
  (pushnew (merge-pathnames "src/" base-dir) asdf:*central-registry* :test 'equal))

(format t "~&Loading Quicklisp...~%")
(ql:quickload '(:hunchentoot :cl-json :bordeaux-threads :uuid :babel :log4cl :ironclad :alexandria) :prompt nil)

(format t "~&Loading lispim-core system...~%")
;; Force reload of the system
(asdf:clear-system :lispim-core)
;; Force recompilation
(handler-bind ((warning #'muffle-warning))
  (asdf:load-system :lispim-core :verbose nil :force t))
(format t "~&lispim-core loaded successfully~%")

;; 启动服务器
(in-package :lispim-core)

;; =============================================================================
;; 初始化默认用户和好友关系
;; =============================================================================

(format t "~&~%Initializing default users and friends...~%")

(ensure-pg-connected)

;; 创建 admin 用户（固定 ID=1）
(handler-case
    (multiple-value-bind (hash salt)
        (hash-password "admin123")
      (postmodern:query
       "INSERT INTO users (id, username, email, password_hash, password_salt, display_name, status)
        VALUES (1, 'admin', 'admin@lispim.com', $1, $2, 'System Administrator', 'active')
        ON CONFLICT (id) DO UPDATE SET
          password_hash = $1,
          password_salt = $2,
          username = 'admin',
          display_name = 'System Administrator',
          status = 'active'"
       hash salt)
      (format t "~&✓ Admin user: id=1, username=admin, password=admin123~%"))
  (condition (c)
    (format t "~&  Admin user setup: ~a~%" c)))

;; 创建 test 用户（固定 ID=2）
(handler-case
    (multiple-value-bind (hash salt)
        (hash-password "test123")
      (postmodern:query
       "INSERT INTO users (id, username, email, password_hash, password_salt, display_name, status)
        VALUES (2, 'test', 'test@lispim.com', $1, $2, 'Test User', 'active')
        ON CONFLICT (id) DO UPDATE SET
          password_hash = $1,
          password_salt = $2,
          username = 'test',
          display_name = 'Test User',
          status = 'active'"
       hash salt)
      (format t "~&✓ Test user: id=2, username=test, password=test123~%"))
  (condition (c)
    (format t "~&  Test user setup: ~a~%" c)))

;; 确保系统管理员用户存在
(handler-case
    (progn
      (ensure-system-admin-exists)
      (format t "~&✓ System Administrator: id=~a~%" *system-admin-user-id*))
  (condition (c)
    (format t "~&  System Administrator setup: ~a~%" c)))

;; 创建 admin 和 test 之间的好友关系
(handler-case
    (progn
      (postmodern:with-transaction ()
        (postmodern:query
         "INSERT INTO friends (user_id, friend_id, status) VALUES (1, 2, 'accepted')
          ON CONFLICT (user_id, friend_id) DO NOTHING")
        (postmodern:query
         "INSERT INTO friends (user_id, friend_id, status) VALUES (2, 1, 'accepted')
          ON CONFLICT (user_id, friend_id) DO NOTHING"))
      (format t "~&✓ Friend relationship: admin <-> test~%"))
  (condition (c)
    (format t "~&  Friend relationship admin-test: ~a~%" c)))

;; 创建 admin 与系统管理员的好友关系
(handler-case
    (let ((admin-id *system-admin-user-id*))
      (postmodern:with-transaction ()
        (postmodern:query
         "INSERT INTO friends (user_id, friend_id, status) VALUES (1, $1, 'accepted')
          ON CONFLICT (user_id, friend_id) DO NOTHING"
         admin-id)
        (postmodern:query
         "INSERT INTO friends (user_id, friend_id, status) VALUES ($1, 1, 'accepted')
          ON CONFLICT (user_id, friend_id) DO NOTHING"
         admin-id))
      (format t "~&✓ Friend relationship: admin <-> System Administrator~%"))
  (condition (c)
    (format t "~&  Friend relationship admin-sysadmin: ~a~%" c)))

;; 创建 test 与系统管理员的好友关系
(handler-case
    (let ((admin-id *system-admin-user-id*))
      (postmodern:with-transaction ()
        (postmodern:query
         "INSERT INTO friends (user_id, friend_id, status) VALUES (2, $1, 'accepted')
          ON CONFLICT (user_id, friend_id) DO NOTHING"
         admin-id)
        (postmodern:query
         "INSERT INTO friends (user_id, friend_id, status) VALUES ($1, 2, 'accepted')
          ON CONFLICT (user_id, friend_id) DO NOTHING"
         admin-id))
      (format t "~&✓ Friend relationship: test <-> System Administrator~%"))
  (condition (c)
    (format t "~&  Friend relationship test-sysadmin: ~a~%" c)))

;; 创建 admin 与系统管理员的会话
(handler-case
    (let ((conv-id (get-or-create-system-admin-conversation 1)))
      (format t "~&✓ Conversation: admin <-> System Administrator (~a)~%" conv-id))
  (condition (c)
    (format t "~&  Conversation admin-sysadmin: ~a~%" c)))

;; 创建 test 与系统管理员的会话
(handler-case
    (let ((conv-id (get-or-create-system-admin-conversation 2)))
      (format t "~&✓ Conversation: test <-> System Administrator (~a)~%" conv-id))
  (condition (c)
    (format t "~&  Conversation test-sysadmin: ~a~%" c)))

;; 创建 admin 和 test 之间的会话
(handler-case
    (let ((conv-id (get-or-create-direct-conversation 1 2)))
      (format t "~&✓ Conversation: admin <-> test (~a)~%" conv-id))
  (condition (c)
    (format t "~&  Conversation admin-test: ~a~%" c)))

(format t "~&~%Default setup complete!~%")
(format t "~&  Users:~%")
(format t "~&    - admin / admin123  (可以看到 test 和系统管理员)~%")
(format t "~&    - test / test123    (可以看到 admin 和系统管理员)~%")
(format t "~&    - 系统管理员        (所有人的默认好友)~%")

;; =============================================================================
;; 启动服务器
;; =============================================================================

(format t "~&~&Starting server on port 3000...~%")
(format t "~&API Endpoints:~%")
(format t "~&  POST /api/v1/auth/login   - User login~%")
(format t "~&  POST /api/v1/auth/register - User register~%")
(format t "~&  POST /api/v1/auth/send-code - Send verification code~%")
(format t "~&  POST /api/v1/auth/wechat  - WeChat OAuth~%")
(format t "~&  GET  /healthz             - Health check~%")
(format t "~&  GET  /readyz              - Ready check~%")
(format t "~&  GET  /metrics             - Prometheus metrics~%")
(format t "~&~&~%Press Ctrl+C to stop~%~%")

(start-server)

;; Keep main thread alive (Hunchentoot runs in background thread)
(format t "~&~%Server running. Use Ctrl+C to stop.~%")
(loop do (sleep 60))
