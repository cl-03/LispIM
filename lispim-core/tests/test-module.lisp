;;;; test-module.lisp - Module Manager 测试

(in-package :lispim-core/test)

(eval-when (:compile-toplevel :load-toplevel :execute)
  (ql:quickload '(:fiveam :lispim-core)))

(in-package :lispim-core/test)

(def-suite :test-module
  :description "Module Manager 测试套件")

(in-suite :test-module)

;;;; 测试：模块信息创建

(test test-module-info-create
  "测试模块信息创建"
  (let ((module (lispim-core::make-module-info
                 :name :test-module
                 :version "1.0.0")))
    (is (eq (lispim-core::module-info-name module) :test-module))
    (is (string= (lispim-core::module-info-version module) "1.0.0"))
    (is (eq (lispim-core::module-info-health-status module) :healthy))))

;;;; 测试：模块加载

(test test-module-load
  "测试模块加载"
  (let ((module (lispim-core::make-module-info :name :test-module)))
    ;; 模拟模块加载
    (setf (gethash :test-module lispim-core::*lispim-modules*) module)
    (let ((retrieved (lispim-core::get-module-status :test-module)))
      (is (not (null retrieved)))
      (is (eq (lispim-core::module-info-name retrieved) :test-module)))))

;;;; 测试：模块卸载

(test test-module-unload
  "测试模块卸载"
  (let ((module (lispim-core::make-module-info :name :test-module)))
    (setf (gethash :test-module lispim-core::*lispim-modules*) module)
    (lispim-core::unload-module :test-module)
    (let ((retrieved (lispim-core::get-module-status :test-module)))
      (is (null retrieved)))))

;;;; 测试：模块健康检查

(test test-module-health-check
  "测试模块健康检查"
  (let ((healthy-module (lispim-core::make-module-info
                         :name :healthy-module
                         :health-status :healthy))
        (degraded-module (lispim-core::make-module-info
                          :name :degraded-module
                          :health-status :degraded))
        (unhealthy-module (lispim-core::make-module-info
                           :name :unhealthy-module
                           :health-status :unhealthy)))
    (is (eq (lispim-core::module-info-health-status healthy-module) :healthy))
    (is (eq (lispim-core::module-info-health-status degraded-module) :degraded))
    (is (eq (lispim-core::module-info-health-status unhealthy-module) :unhealthy))))

;;;; 测试：模块依赖检查

(test test-module-dependencies
  "测试模块依赖检查"
  (let* ((dep1 (lispim-core::make-module-info :name :dep1))
         (dep2 (lispim-core::make-module-info :name :dep2))
         (module (lispim-core::make-module-info
                  :name :module-with-deps
                  :dependencies (list :dep1 :dep2))))
    ;; 注册依赖
    (setf (gethash :dep1 lispim-core::*lispim-modules*) dep1)
    (setf (gethash :dep2 lispim-core::*lispim-modules*) dep2)

    ;; 依赖应该满足
    (is (lispim-core::check-dependencies module))))

;;;; 测试：模块状态列表

(test test-list-modules
  "测试列出所有模块"
  ;; 清理
  (clrhash lispim-core::*lispim-modules*)

  ;; 添加模块
  (setf (gethash :mod1 lispim-core::*lispim-modules*)
        (lispim-core::make-module-info :name :mod1))
  (setf (gethash :mod2 lispim-core::*lispim-modules*)
        (lispim-core::make-module-info :name :mod2))
  (setf (gethash :mod3 lispim-core::*lispim-modules*)
        (lispim-core::make-module-info :name :mod3))

  (let ((modules (lispim-core::list-modules)))
    (is (= 3 (length modules)))))

;;;; 运行所有测试

(defun run-module-tests ()
  "运行所有 Module 测试"
  (fiveam:run! :test-module))
