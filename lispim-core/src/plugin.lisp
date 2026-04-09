;;;; plugin.lisp - 插件系统核心
;;;;
;;;; 基于 Tailchat 插件架构设计的 LispIM 插件引擎
;;;; 支持服务器端插件和客户端插件

(in-package :lispim-core)

;;;; 依赖声明

(eval-when (:compile-toplevel :load-toplevel :execute)
  (ql:quickload '(::bordeaux-threads :cl-fad :cl-json :dexador :cl-ppcre)))

;;;; 插件元数据

(defstruct plugin-manifest
  "插件清单（对应 Tailchat 的 manifest.json）"
  (name nil :type (or null string))           ; 插件唯一标识，如 "lispim.linkmeta"
  (label nil :type (or null string))          ; 显示名称
  (label-zh nil :type (or null string))       ; 中文显示名称
  (version "0.0.0" :type string)
  (author nil :type (or null string))
  (description nil :type (or null string))
  (description-zh nil :type (or null string))
  (server-entry nil :type (or null string))   ; 服务端入口文件
  (client-entry nil :type (or null string))   ; 客户端入口文件/URL
  (document-url nil :type (or null string))   ; 文档 URL
  (require-restart nil :type boolean)         ; 是否需要重启
  (apis nil :type list)                       ; 提供的 API 列表
  (permissions nil :type list))               ; 需要的权限

(defstruct plugin-instance
  "插件实例"
  (manifest nil :type plugin-manifest)
  (enabled nil :type boolean)
  (installed-at nil :type (or null integer))
  (updated-at nil :type (or null integer))
  (load-path nil :type (or null pathname))
  (package nil :type (or null package))
  (state nil :type (or null hash-table)))

;;;; 插件注册表

(defvar *lispim-plugins* (make-hash-table :test 'equal)
  "已安装插件表：plugin-name -> plugin-instance")

(defvar *lispim-plugins-lock* (bordeaux-threads:make-lock "plugins-lock")
  "插件表读写锁")

(defvar *plugin-api-registry* (make-hash-table :test 'equal)
  "插件 API 注册表：api-name -> function")

;;;; 插件协议（CLOS 泛化函数）

(defgeneric plugin-init (plugin config)
  (:documentation "初始化插件")
  (:method (plugin config)
    (declare (ignore plugin config))
    t))

(defgeneric plugin-cleanup (plugin)
  (:documentation "清理插件资源")
  (:method (plugin)
    (declare (ignore plugin))
    t))

(defgeneric plugin-health-check (plugin)
  (:documentation "插件健康检查")
  (:method (plugin)
    (declare (ignore plugin))
    t))

;;;; 插件 Manifest 解析

(defun parse-plugin-manifest (json-string)
  "从 JSON 字符串解析插件清单"
  (let* ((obj (cl-json:decode-json-from-string json-string))
         (manifest (make-plugin-manifest)))
    ;; 从 alist 提取字段（cl-json 将 camelCase 转换为 KEYWORD-NAME）
    (setf (plugin-manifest-name manifest) (or (cdr (assoc :name obj)) "")
          (plugin-manifest-label manifest) (or (cdr (assoc :label obj)) "")
          (plugin-manifest-label-zh manifest) (or (cdr (assoc :label.zh-cn obj)) "")
          (plugin-manifest-version manifest) (or (cdr (assoc :version obj)) "0.0.0")
          (plugin-manifest-author manifest) (or (cdr (assoc :author obj)) "")
          (plugin-manifest-description manifest) (or (cdr (assoc :description obj)) "")
          (plugin-manifest-description-zh manifest) (or (cdr (assoc :description.zh-cn obj)) "")
          (plugin-manifest-server-entry manifest) (or (cdr (assoc :server-entry-point obj)) "")
          (plugin-manifest-client-entry manifest) (or (cdr (assoc :client-entry-point obj)) "")
          (plugin-manifest-document-url manifest) (or (cdr (assoc :document-url obj)) "")
          (plugin-manifest-require-restart manifest) (or (cdr (assoc :require-restart obj)) nil)
          (plugin-manifest-apis manifest) (or (cdr (assoc :apis obj)) nil)
          (plugin-manifest-permissions manifest) (or (cdr (assoc :permissions obj)) nil))
    manifest))

(defun plugin-manifest-to-json (manifest)
  "将插件清单转换为 JSON"
  (cl-json:encode-json-to-string
   (list (cons "name" (plugin-manifest-name manifest))
         (cons "label" (plugin-manifest-label manifest))
         (cons "label.zh-CN" (plugin-manifest-label-zh manifest))
         (cons "version" (plugin-manifest-version manifest))
         (cons "author" (plugin-manifest-author manifest))
         (cons "description" (plugin-manifest-description manifest))
         (cons "description.zh-CN" (plugin-manifest-description-zh manifest))
         (cons "serverEntryPoint" (plugin-manifest-server-entry manifest))
         (cons "clientEntryPoint" (plugin-manifest-client-entry manifest))
         (cons "documentUrl" (plugin-manifest-document-url manifest))
         (cons "requireRestart" (plugin-manifest-require-restart manifest))
         (cons "apis" (plugin-manifest-apis manifest))
         (cons "permissions" (plugin-manifest-permissions manifest)))))

;;;; 插件安装

(defun install-plugin-from-url (manifest-url)
  "从 URL 安装插件"
  (log-info "Installing plugin from: ~a" manifest-url)

  (handler-case
      (let* ((json (dex:get manifest-url))
             (manifest (parse-plugin-manifest json))
             (plugin-name (plugin-manifest-name manifest))
             (plugin-dir (format nil "./plugins/~a/" plugin-name)))

        ;; 创建插件目录
        (ensure-directories-exist plugin-dir)

        ;; 下载服务端入口文件
        (when (plugin-manifest-server-entry manifest)
          (let ((entry-url (format nil "~a/~a" manifest-url
                                   (plugin-manifest-server-entry manifest)))
                (entry-path (merge-pathnames (plugin-manifest-server-entry manifest)
                                             (pathname plugin-dir))))
            (dex:fetch entry-url entry-path)
            (log-info "Downloaded server entry: ~a" entry-path)))

        ;; 创建插件实例
        (let ((plugin (make-plugin-instance
                       :manifest manifest
                       :enabled t
                       :installed-at (get-universal-time)
                       :updated-at (get-universal-time)
                       :load-path (pathname plugin-dir)
                       :state (make-hash-table :test 'equal))))

          ;; 注册插件
          (bordeaux-threads:with-lock-held (*lispim-plugins-lock*)
            (setf (gethash plugin-name *lispim-plugins*) plugin))

          ;; 加载插件
          (load-plugin-plugin plugin-name)

          (log-info "Plugin ~a installed successfully" plugin-name)
          plugin))

    (error (c)
      (log-error "Failed to install plugin: ~a" c)
      (error 'plugin-install-failed
             :reason (format nil "~a" c)))))

(defun install-plugin-from-manifest (manifest-json)
  "从 Manifest JSON 安装插件（手动安装）"
  (let ((manifest (parse-plugin-manifest manifest-json)))
    ;; 验证 manifest
    (unless (plugin-manifest-name manifest)
      (error "Missing required field: name"))
    (unless (plugin-manifest-version manifest)
      (error "Missing required field: version"))

    ;; 创建插件实例
    (let ((plugin (make-plugin-instance
                   :manifest manifest
                   :enabled t
                   :installed-at (get-universal-time)
                   :updated-at (get-universal-time)
                   :state (make-hash-table :test 'equal))))

      ;; 注册插件
      (bordeaux-threads:with-lock-held (*lispim-plugins-lock*)
        (setf (gethash (plugin-manifest-name manifest) *lispim-plugins*) plugin))

      ;; 保存 manifest 到 Redis（如果 Redis 不可用则跳过）
      (handler-case
          (redis:red-set (format nil "lispim:plugins:~a" (plugin-manifest-name manifest))
                     (plugin-manifest-to-json manifest))
        (redis:redis-connection-error (e)
          (log-warn "Could not save plugin manifest to Redis: ~a" e)))

      (log-info "Plugin ~a installed from manifest" (plugin-manifest-name manifest))
      plugin)))

;;;; 插件加载

(defun load-plugin-plugin (plugin-name)
  "加载插件"
  (declare (type string plugin-name))

  (log-info "Loading plugin: ~a" plugin-name)

  (bordeaux-threads:with-lock-held (*lispim-plugins-lock*)
    (let ((plugin (gethash plugin-name *lispim-plugins*)))
      (unless plugin
        (error 'plugin-not-found :plugin-name plugin-name))

      (let ((load-path (plugin-instance-load-path plugin)))
        (unless load-path
          (error "Plugin has no load path"))

        ;; 加载服务端入口
        (let ((entry-file (merge-pathnames "plugin.lisp" load-path)))
          (when (cl-fad:file-exists-p entry-file)
            (let ((fasl (compile-file entry-file)))
              (load fasl)
              (log-info "Loaded plugin entry: ~a" entry-file))))

        ;; 调用插件初始化
        (let ((pkg (find-package (string-upcase plugin-name))))
          (when pkg
            (multiple-value-bind (sym status) (find-symbol "PLUGIN-INIT" pkg)
              (when status
                (funcall sym plugin nil)))))

        ;; 注册插件 API
        (register-plugin-apis plugin)))))

(defun unload-plugin-plugin (plugin-name)
  "卸载插件"
  (declare (type string plugin-name))

  (log-info "Unloading plugin: ~a" plugin-name)

  (bordeaux-threads:with-lock-held (*lispim-plugins-lock*)
    (let ((plugin (gethash plugin-name *lispim-plugins*)))
      (unless plugin
        (error 'plugin-not-found :plugin-name plugin-name))

      ;; 调用清理钩子
      (let ((pkg (find-package (string-upcase plugin-name))))
        (when pkg
          (multiple-value-bind (sym status) (find-symbol "PLUGIN-CLEANUP" pkg)
            (when status
              (funcall sym plugin)))))

      ;; 注销 API
      (unregister-plugin-apis plugin)

      ;; 从注册表移除
      (remhash plugin-name *lispim-plugins*)
      (redis:red-del (format nil "lispim:plugins:~a" plugin-name))

      (log-info "Plugin ~a unloaded" plugin-name))))

;;;; 插件 API 注册

(defun register-plugin-api (api-name function)
  "注册插件 API"
  (setf (gethash api-name *plugin-api-registry*) function)
  (log-debug "Registered plugin API: ~a" api-name))

(defun unregister-plugin-api (api-name)
  "注销插件 API"
  (remhash api-name *plugin-api-registry*))

(defun register-plugin-apis (plugin)
  "注册插件的所有 API"
  (let ((apis (plugin-manifest-apis (plugin-instance-manifest plugin))))
    (when apis
      (dolist (api apis)
        (let ((sym (intern (string-upcase api) :lispim-core)))
          (when (fboundp sym)
            (register-plugin-api api (symbol-function sym))))))))

(defun unregister-plugin-apis (plugin)
  "注销插件的所有 API"
  (let ((apis (plugin-manifest-apis (plugin-instance-manifest plugin))))
    (when apis
      (dolist (api apis)
        (unregister-plugin-api api)))))

(defun call-plugin-api (api-name &rest args)
  "调用插件 API"
  (let ((fn (gethash api-name *plugin-api-registry*)))
    (unless fn
      (error 'plugin-api-not-found :api-name api-name))
    (apply fn args)))

;;;; 插件管理 API

(defun list-plugins ()
  "获取所有已安装插件"
  (let ((result nil))
    (bordeaux-threads:with-lock-held (*lispim-plugins-lock*)
      (maphash (lambda (name plugin)
                 (push (list :name name
                             :label (plugin-manifest-label (plugin-instance-manifest plugin))
                             :version (plugin-manifest-version (plugin-instance-manifest plugin))
                             :enabled (plugin-instance-enabled plugin)
                             :installed-at (plugin-instance-installed-at plugin))
                       result))
               *lispim-plugins*))
    result))

(defun get-plugin (plugin-name)
  "获取插件详情"
  (bordeaux-threads:with-lock-held (*lispim-plugins-lock*)
    (gethash plugin-name *lispim-plugins*)))

(defun enable-plugin (plugin-name)
  "启用插件"
  (bordeaux-threads:with-lock-held (*lispim-plugins-lock*)
    (let ((plugin (gethash plugin-name *lispim-plugins*)))
      (unless plugin
        (error 'plugin-not-found :plugin-name plugin-name))
      (unless (plugin-instance-enabled plugin)
        (setf (plugin-instance-enabled plugin) t)
        (load-plugin-plugin plugin-name)
        (log-info "Plugin ~a enabled" plugin-name))
      t)))

(defun disable-plugin (plugin-name)
  "禁用插件"
  (bordeaux-threads:with-lock-held (*lispim-plugins-lock*)
    (let ((plugin (gethash plugin-name *lispim-plugins*)))
      (unless plugin
        (error 'plugin-not-found :plugin-name plugin-name))
      (when (plugin-instance-enabled plugin)
        (setf (plugin-instance-enabled plugin) nil)
        (unload-plugin-plugin plugin-name)
        (log-info "Plugin ~a disabled" plugin-name))
      t)))

(defun uninstall-plugin (plugin-name)
  "卸载插件"
  (let ((plugin (get-plugin plugin-name)))
    (unless plugin
      (error 'plugin-not-found :plugin-name plugin-name))

    ;; 如果已启用，先禁用
    (when (plugin-instance-enabled plugin)
      (disable-plugin plugin-name))

    ;; 删除插件文件
    (let ((load-path (plugin-instance-load-path plugin)))
      (when (and load-path (cl-fad:directory-exists-p load-path))
        (cl-fad:delete-directory-and-files load-path)))

    (log-info "Plugin ~a uninstalled" plugin-name)
    t))

;;;; WebSocket 消息处理

(defun handle-plugin-message (conn message)
  "处理插件相关的 WebSocket 消息"
  (let ((msg-type (getf message :type)))
    (cond
      ((string= msg-type "PLUGIN")
       ;; Nested plugin message - extract inner type
       (let ((payload (getf message :payload))
             (inner-type (getf message :payload :type)))
         (cond
           ((string= inner-type "PLUGIN_INSTALL")
            (let ((url (getf payload :url)))
              (handler-case
                  (let ((plugin (install-plugin-from-url url)))
                    (send-to-connection conn (encode-ws-message
                                              (list :type "PLUGIN_INSTALLED"
                                                    :payload (list :name (plugin-manifest-name (plugin-instance-manifest plugin)))))))
                (error (c)
                  (send-to-connection conn (encode-ws-message
                                            (list :type "PLUGIN_ERROR"
                                                  :payload (list :message (princ-to-string c)))))))))

           ((string= inner-type "PLUGIN_UNINSTALL")
            (let ((name (getf payload :name)))
              (handler-case
                  (progn
                    (uninstall-plugin name)
                    (send-to-connection conn (encode-ws-message
                                              (list :type "PLUGIN_UNINSTALLED"
                                                    :payload (list :name name)))))
                (error (c)
                  (send-to-connection conn (encode-ws-message
                                            (list :type "PLUGIN_ERROR"
                                                  :payload (list :message (princ-to-string c)))))))))

           ((string= inner-type "PLUGIN_ENABLE")
            (let ((name (getf payload :name)))
              (handler-case
                  (progn
                    (enable-plugin name)
                    (send-to-connection conn (encode-ws-message
                                              (list :type "PLUGIN_ENABLED"
                                                    :payload (list :name name)))))
                (error (c)
                  (send-to-connection conn (encode-ws-message
                                            (list :type "PLUGIN_ERROR"
                                                  :payload (list :message (princ-to-string c)))))))))

           ((string= inner-type "PLUGIN_DISABLE")
            (let ((name (getf payload :name)))
              (handler-case
                  (progn
                    (disable-plugin name)
                    (send-to-connection conn (encode-ws-message
                                              (list :type "PLUGIN_DISABLED"
                                                    :payload (list :name name)))))
                (error (c)
                  (send-to-connection conn (encode-ws-message
                                            (list :type "PLUGIN_ERROR"
                                                  :payload (list :message (princ-to-string c)))))))))

           ((string= inner-type "LIST_PLUGINS")
            (send-to-connection conn (encode-ws-message
                                      (list :type "PLUGIN_LIST"
                                            :payload (list :plugins (list-plugins))))))

           (t
            (log-debug "Unknown plugin message type: ~a" inner-type)))))

      ((string= msg-type "PLUGIN_INSTALL")
       ;; Direct plugin message (legacy format)
       (let ((url (getf message :url)))
         (handler-case
             (let ((plugin (install-plugin-from-url url)))
               (send-to-connection conn (encode-ws-message
                                         (list :type "PLUGIN_INSTALLED"
                                               :payload (list :name (plugin-manifest-name (plugin-instance-manifest plugin)))))))
           (error (c)
             (send-to-connection conn (encode-ws-message
                                       (list :type "PLUGIN_ERROR"
                                             :payload (list :message (princ-to-string c)))))))))

      ((string= msg-type "PLUGIN_UNINSTALL")
       (let ((name (getf message :name)))
         (handler-case
             (progn
               (uninstall-plugin name)
               (send-to-connection conn (encode-ws-message
                                         (list :type "PLUGIN_UNINSTALLED"
                                               :payload (list :name name)))))
           (error (c)
             (send-to-connection conn (encode-ws-message
                                       (list :type "PLUGIN_ERROR"
                                             :payload (list :message (princ-to-string c)))))))))

      ((string= msg-type "PLUGIN_ENABLE")
       (let ((name (getf message :name)))
         (handler-case
             (progn
               (enable-plugin name)
               (send-to-connection conn (encode-ws-message
                                         (list :type "PLUGIN_ENABLED"
                                               :payload (list :name name)))))
           (error (c)
             (send-to-connection conn (encode-ws-message
                                       (list :type "PLUGIN_ERROR"
                                             :payload (list :message (princ-to-string c)))))))))

      ((string= msg-type "PLUGIN_DISABLE")
       (let ((name (getf message :name)))
         (handler-case
             (progn
               (disable-plugin name)
               (send-to-connection conn (encode-ws-message
                                         (list :type "PLUGIN_DISABLED"
                                               :payload (list :name name)))))
           (error (c)
             (send-to-connection conn (encode-ws-message
                                       (list :type "PLUGIN_ERROR"
                                             :payload (list :message (princ-to-string c)))))))))

      ((string= msg-type "LIST_PLUGINS")
       (send-to-connection conn (encode-ws-message
                                 (list :type "PLUGIN_LIST"
                                       :payload (list :plugins (list-plugins))))))

      (t
       (log-debug "Unknown plugin message type: ~a" msg-type)))))

;;;; 条件系统

(define-condition plugin-error (condition)
  ((plugin-name :initarg :plugin-name :reader plugin-error-plugin-name)
   (reason :initarg :reason :reader plugin-error-reason))
  (:report (lambda (c s)
             (format s "Plugin error [~a]: ~a"
                     (plugin-error-plugin-name c)
                     (plugin-error-reason c)))))

(define-condition plugin-not-found (plugin-error)
  ()
  (:report (lambda (c s)
             (format s "Plugin not found: ~a"
                     (plugin-error-plugin-name c)))))

(define-condition plugin-install-failed (plugin-error)
  ()
  (:report (lambda (c s)
             (format s "Failed to install plugin: ~a"
                     (plugin-error-reason c)))))

(define-condition plugin-api-not-found (condition)
  ((api-name :initarg :api-name :reader plugin-api-not-found-api-name))
  (:report (lambda (c s)
             (format s "Plugin API not found: ~a"
                     (plugin-api-not-found-api-name c)))))

;;;; 初始化

(defun init-plugin-system ()
  "初始化插件系统"
  (log-info "Initializing plugin system...")

  ;; 从 Redis 加载已安装插件
  (let ((keys (redis:red-keys "lispim:plugins:*")))
    (dolist (key keys)
      (let* ((json (redis:red-get key))
             (manifest (parse-plugin-manifest json))
             (plugin (make-plugin-instance
                      :manifest manifest
                      :enabled t
                      :installed-at (get-universal-time)
                      :state (make-hash-table :test 'equal))))
        (setf (gethash (plugin-manifest-name manifest) *lispim-plugins*) plugin)
        (log-info "Loaded plugin from Redis: ~a" (plugin-manifest-name manifest)))))

  ;; 加载本地插件目录
  (let ((plugin-dir "./plugins/"))
    (when (cl-fad:directory-exists-p plugin-dir)
      (dolist (dir (cl-fad:list-directory plugin-dir))
        (let ((manifest-file (merge-pathnames "manifest.json" dir)))
          (when (cl-fad:file-exists-p manifest-file)
            (with-open-file (s manifest-file :direction :input)
              (let ((json (make-string (file-length s))))
                (read-sequence json s)
                (install-plugin-from-manifest json))))))))

  (log-info "Plugin system initialized"))
