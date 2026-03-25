;;;; module.lisp - 热更新引擎
;;;;
;;;; 负责模块加载、卸载、热更新、健康检查

(in-package :lispim-core)

;;;; 依赖声明

(eval-when (:compile-toplevel :load-toplevel :execute)
  (ql:quickload '(:bordeaux-threads :cl-fad)))

;;;; 类型定义

(deftype module-status ()
  '(member :healthy :degraded :unhealthy :loading :stopped))

(deftype module-name ()
  'keyword)

;;;; 模块元数据

(defstruct module-info
  "模块元数据"
  (name nil :type module-name)
  (version "0.0.0" :type string)
  (fasl-path nil :type (or null pathname))
  (source-path nil :type (or null pathname))
  (load-time 0 :type integer)
  (health-status :healthy :type module-status)
  (dependencies nil :type list)
  (cleanup-hook nil :type (or null function))
  (init-hook nil :type (or null function))
  (state-store nil :type (or null hash-table))
  (reload-count 0 :type integer))

;;;; 模块管理器

(defvar *lispim-modules* (make-hash-table :test 'eq)
  "已加载模块表：module-name -> module-info")

(defvar *lispim-modules-lock* (bordeaux-threads:make-lock "modules-lock")
  "模块表读写锁")

(defvar *module-load-order* nil
  "模块加载顺序")

;;;; 模块协议（CLOS 泛化函数）

(defgeneric module-init (module config)
  (:documentation "初始化模块")
  (:method (module config)
    (declare (ignore module config))
    t))

(defgeneric module-cleanup (module)
  (:documentation "清理模块资源")
  (:method (module)
    (declare (ignore module))
    t))

(defgeneric module-health-check (module)
  (:documentation "健康检查")
  (:method (module)
    (declare (ignore module))
    t))

(defgeneric module-migrate-state (module old-state new-version)
  (:documentation "状态迁移")
  (:method (module old-state new-version)
    (declare (ignore module old-state new-version))
    nil))

;;;; 模块加载

(defun load-module (module-name source-path &key (config nil) (dependencies nil))
  "加载模块"
  (declare (type module-name module-name)
           (type (or string pathname) source-path))

  (log-info "Loading module: ~a from ~a" module-name source-path)

  (handler-case
      (let* ((path (pathname source-path))
             (fasl-path (compile-file path))
             (module (make-module-info
                      :name module-name
                      :version "0.1.0"
                      :source-path path
                      :fasl-path fasl-path
                      :load-time (get-universal-time)
                      :dependencies dependencies
                      :state-store (make-hash-table :test 'equal))))

        ;; 检查依赖
        (unless (check-dependencies module)
          (error 'module-load-failed
                 :module-name module-name
                 :reason "Dependencies not satisfied"))

        ;; 编译并加载
        (load fasl-path)

        ;; 注册模块
        (bordeaux-threads:with-lock-held (*lispim-modules-lock*)
          (setf (gethash module-name *lispim-modules*) module)
          (push module-name *module-load-order*))

        ;; 初始化
        (let ((pkg (find-package :lispim-core))
              (init-sym nil))
          (multiple-value-bind (sym status) (find-symbol "MODULE-INIT" (or (find-package module-name) pkg))
            (when status
              (setf init-sym sym)))
          (when init-sym
            (funcall init-sym module config)))

        ;; 健康检查
        (let ((pkg (find-package :lispim-core))
              (health-sym nil))
          (multiple-value-bind (sym status) (find-symbol "MODULE-HEALTH-CHECK" (or (find-package module-name) pkg))
            (when status
              (setf health-sym sym)))
          (when health-sym
            (unless (funcall health-sym module)
              (setf (module-info-health-status module) :degraded))))

        (log-info "Module ~a loaded successfully" module-name)
        module)

    (error (c)
      (log-error "Failed to load module ~a: ~a" module-name c)
      (error 'module-load-failed
             :module-name module-name
             :reason (format nil "~a" c)))))

(defun unload-module (module-name)
  "卸载模块"
  (declare (type module-name module-name))

  (log-info "Unloading module: ~a" module-name)

  (bordeaux-threads:with-lock-held (*lispim-modules-lock*)
    (let ((module (gethash module-name *lispim-modules*)))
      (unless module
        (error 'module-not-found :module-name module-name))

      ;; 调用清理钩子
      (when (module-info-cleanup-hook module)
        (funcall (module-info-cleanup-hook module)))

      ;; 调用模块 cleanup
      (let ((pkg (find-package :lispim-core))
            (cleanup-sym nil))
        (multiple-value-bind (sym status) (find-symbol "MODULE-CLEANUP" (or (find-package module-name) pkg))
          (when status
            (setf cleanup-sym sym)))
        (when cleanup-sym
          (funcall cleanup-sym module)))

      ;; 从表中移除
      (remhash module-name *lispim-modules*)
      (setf *module-load-order*
            (remove module-name *module-load-order*)))

    (log-info "Module ~a unloaded" module-name)))

;;;; 热更新

(defun reload-module (module-name source-path &key (config nil))
  "热更新模块（支持自动回滚）"
  (declare (type module-name module-name)
           (type (or string pathname) source-path))

  (log-info "Reloading module: ~a" module-name)

  (let ((old-module (bordeaux-threads:with-lock-held (*lispim-modules-lock*)
                      (gethash module-name *lispim-modules*)))
        (old-state (save-module-state module-name)))

    (handler-case
        (progn
          ;; 保存状态
          (when old-module
            (setf (module-info-cleanup-hook old-module)
                  (lambda ()
                    (let ((pkg (find-package :lispim-core))
                          (cleanup-sym nil))
                      (multiple-value-bind (sym status) (find-symbol "MODULE-CLEANUP" (or (find-package module-name) pkg))
                        (when status
                          (setf cleanup-sym sym)))
                      (when cleanup-sym
                        (funcall cleanup-sym old-module))))))

          ;; 卸载旧模块
          (unload-module module-name)

          ;; 加载新模块
          (let ((new-module (load-module module-name source-path :config config)))
            (setf (module-info-reload-count new-module)
                  (1+ (module-info-reload-count old-module)))

            ;; 状态迁移
            (when old-state
              (let ((pkg (find-package :lispim-core))
                    (migrate-sym nil))
                (multiple-value-bind (sym status) (find-symbol "MODULE-MIGRATE-STATE" (or (find-package module-name) pkg))
                  (when status
                    (setf migrate-sym sym)))
                (when migrate-sym
                  (funcall migrate-sym new-module old-state
                           (module-info-version new-module)))))

            ;; 健康检查
            (let ((pkg (find-package :lispim-core))
                  (health-sym nil))
              (multiple-value-bind (sym status) (find-symbol "MODULE-HEALTH-CHECK" (or (find-package module-name) pkg))
                (when status
                  (setf health-sym sym)))
              (when health-sym
                (unless (funcall health-sym new-module)
                  (error 'module-health-check-failed
                         :module-name module-name))))

            (log-info "Module ~a reloaded successfully (reload #~a)"
                      module-name
                      (module-info-reload-count new-module)))
          t)

      (error (c)
        (log-error "Module reload failed: ~a" c)
        ;; 回滚
        (when old-state
          (log-info "Rolling back module ~a" module-name)
          (rollback-module module-name old-state old-module))
        nil))))

(defun save-module-state (module-name)
  "保存模块状态用于回滚"
  (declare (type module-name module-name))
  (let ((module (bordeaux-threads:with-lock-held (*lispim-modules-lock*)
                  (gethash module-name *lispim-modules*))))
    (when module
      (lispim-copy-hash-table (module-info-state-store module)))))

(defun rollback-module (module-name old-state old-module)
  "回滚模块到旧版本"
  (declare (type module-name module-name)
           (type hash-table old-state)
           (type (or null module-info) old-module))

  (handler-case
      (progn
        ;; 重新加载旧版本
        (when (module-info-source-path old-module)
          (load-module module-name (module-info-source-path old-module)))

        ;; 恢复状态
        (let ((module (bordeaux-threads:with-lock-held (*lispim-modules-lock*)
                    (gethash module-name *lispim-modules*))))
          (when module
            (setf (module-info-state-store module) old-state)))

        (log-info "Module ~a rolled back successfully" module-name)
        t)

    (error (c)
      (log-error "Rollback failed: ~a" c)
      nil)))

;;;; 辅助函数

;; alexandria 提供有用的哈希表工具：
;; - alexandria:hash-table-keys - 获取所有键
;; - alexandria:hash-table-values - 获取所有值
;; - alexandria:hash-table-alist - 转为关联列表

(defun check-dependencies (module)
  "检查模块依赖 - 使用 alexandria 工具"
  (declare (type module-info module))
  (every (lambda (dep)
           (bordeaux-threads:with-lock-held (*lispim-modules-lock*)
             (gethash dep *lispim-modules*)))
         (module-info-dependencies module)))

(defun list-modules ()
  "列出所有已加载模块 - 使用 alexandria:hash-table-values"
  (bordeaux-threads:with-lock-held (*lispim-modules-lock*)
    (alexandria:hash-table-values *lispim-modules*)))

(defun get-module-status (module-name)
  "获取模块状态"
  (declare (type module-name module-name))
  (bordeaux-threads:with-lock-held (*lispim-modules-lock*)
    (gethash module-name *lispim-modules*)))

(defun get-healthy-modules ()
  "获取所有健康模块"
  (bordeaux-threads:with-lock-held (*lispim-modules-lock*)
    (remove-if-not (lambda (module)
                     (eq (module-info-health-status module) :healthy))
                   (alexandria:hash-table-values *lispim-modules*))))

;;;; 模块健康检查

(defun check-all-modules-health ()
  "检查所有模块健康状态"
  (bordeaux-threads:with-lock-held (*lispim-modules-lock*)
    (loop for module being the hash-values of *lispim-modules*
          collect (cons (module-info-name module)
                        (handler-case
                            (module-health-check module)
                          (error () nil))))))

;;;; 导出

(export '(;; Module management
          load-module
          unload-module
          reload-module
          list-modules
          get-module-status
          get-healthy-modules
          check-all-modules-health

          ;; Module info
          module-info
          make-module-info
          module-info-name
          module-info-version
          module-info-fasl-path
          module-info-source-path
          module-info-load-time
          module-info-health-status
          module-info-dependencies
          module-info-cleanup-hook
          module-info-init-hook
          module-info-state-store
          module-info-reload-count

          ;; Module protocol
          module-init
          module-cleanup
          module-health-check
          module-migrate-state

          ;; Variables
          *lispim-modules*
          *module-load-order*))
