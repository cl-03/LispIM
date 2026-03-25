;;;; test-gateway.lisp - Gateway 模块测试

(in-package :lispim-core/test)

(eval-when (:compile-toplevel :load-toplevel :execute)
  (ql:quickload '(:fiveam :lispim-core)))

(in-package :lispim-core/test)

(def-suite :test-gateway
  :description "Gateway 模块测试套件")

(in-suite :test-gateway)

;;;; 测试：连接创建

(test test-connection-create
  "测试连接创建"
  (let ((conn (lispim-core::make-connection)))
    (is (typep (lispim-core::connection-id conn) 'uuid:uuid))
    (is (eq (lispim-core::connection-state conn) :connecting))
    (is (null (lispim-core::connection-user-id conn)))
    (is (null (lispim-core::connection-socket conn)))))

;;;; 测试：连接注册

(test test-connection-register
  "测试连接注册"
  (let ((conn (lispim-core::make-connection)))
    (lispim-core::register-connection conn)
    (let ((retrieved (lispim-core::get-connection (lispim-core::connection-id conn))))
      (is (not (null retrieved)))
      (is (eq retrieved conn)))))

;;;; 测试：连接注销

(test test-connection-unregister
  "测试连接注销"
  (let ((conn (lispim-core::make-connection)))
    (lispim-core::register-connection conn)
    (lispim-core::unregister-connection (lispim-core::connection-id conn))
    (let ((retrieved (lispim-core::get-connection (lispim-core::connection-id conn))))
      (is (null retrieved)))))

;;;; 测试：多端登录

(test test-user-multiple-connections
  "测试用户多端登录"
  (let* ((user-id "test-user-123")
         (conn1 (lispim-core::make-connection :user-id user-id))
         (conn2 (lispim-core::make-connection :user-id user-id))
         (conn3 (lispim-core::make-connection :user-id "other-user")))
    (lispim-core::register-connection conn1)
    (lispim-core::register-connection conn2)
    (lispim-core::register-connection conn3)

    (let ((user-conns (lispim-core::get-user-connections user-id)))
      (is (= 2 (length user-conns)))
      (is (member conn1 user-conns))
      (is (member conn2 user-conns))
      (is (not (member conn3 user-conns))))))

;;;; 测试：连接状态转换

(test test-connection-state-transition
  "测试连接状态转换"
  (let ((conn (lispim-core::make-connection)))
    ;; 先注册连接，否则 set-connection-state 不会生效
    (lispim-core::register-connection conn)

    ;; 初始状态应该是 :connecting
    (is (eq (lispim-core::connection-state conn) :connecting))

    ;; 转换到 :authenticated
    (lispim-core::set-connection-state (lispim-core::connection-id conn) :authenticated)
    (is (eq (lispim-core::connection-state conn) :authenticated))

    ;; 转换到 :active
    (lispim-core::set-connection-state (lispim-core::connection-id conn) :active)
    (is (eq (lispim-core::connection-state conn) :active))

    ;; 转换到 :closing
    (lispim-core::set-connection-state (lispim-core::connection-id conn) :closing)
    (is (eq (lispim-core::connection-state conn) :closing))))

;;;; 测试：心跳更新

(test test-heartbeat-update
  "测试心跳更新"
  (let ((conn (lispim-core::make-connection))
        (before (get-universal-time)))
    (lispim-core::register-connection conn)
    (sleep 0.1)

    (lispim-core::update-connection-heartbeat (lispim-core::connection-id conn))
    (let ((after (lispim-core::connection-last-heartbeat
                  (lispim-core::get-connection (lispim-core::connection-id conn)))))
      (is (>= after before)))))

;;;; 运行所有测试

(defun run-gateway-tests ()
  "运行所有 Gateway 测试"
  (fiveam:run! :test-gateway))
