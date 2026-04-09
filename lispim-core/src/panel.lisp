;;;; panel.lisp - 群组面板系统
;;;;
;;;; 参考 Tailchat 的面板设计，实现两层级群组空间
;;;; Group -> Panels (multiple)
;;;; 支持多种面板类型：聊天、网页、应用、文件、公告

(in-package :lispim-core)

;;;; 依赖声明

(eval-when (:compile-toplevel :load-toplevel :execute)
  (ql:quickload '(::bordeaux-threads :cl-json :uuid)))

;;;; 面板类型定义

(defparameter +panel-types+
  '(:chat      "聊天面板")
  "内置面板类型")

(defparameter +panel-type-chat+      :chat      "聊天面板")
(defparameter +panel-type-web+       :web       "网页面板")
(defparameter +panel-type-app+       :app       "应用面板")
(defparameter +panel-type-file+      :file      "文件面板")
(defparameter +panel-type-announcement+ :announcement "公告面板")
(defparameter +panel-type-calendar+  :calendar  "日历面板")
(defparameter +panel-type-vote+      :vote      "投票面板")

;;;; 面板配置结构

(defstruct panel-config
  "面板配置"
  (type nil :type keyword)              ; 面板类型
  (title nil :type (or null string))    ; 面板标题
  (url nil :type (or null string))      ; 网页面板 URL
  (app-id nil :type (or null string))   ; 应用面板 ID
  (folder-id nil :type (or null string)) ; 文件夹 ID
  (permissions nil :type list)          ; 查看权限（角色 ID 列表）
  (hidden nil :type boolean))           ; 是否隐藏

;;;; 面板数据结构

(defstruct panel
  "面板（第二层级）"
  (id nil :type string)                 ; 面板 ID（Snowflake）
  (name nil :type string)               ; 面板名称
  (group-id nil :type string)           ; 所属群组 ID
  (type :chat :type keyword)            ; 面板类型
  (config nil :type (or null panel-config)) ; 面板配置
  (position 0 :type integer)            ; 排列位置
  (created-at nil :type integer)        ; 创建时间
  (updated-at nil :type integer)        ; 更新时间
  (created-by nil :type string))        ; 创建者 ID

;;;; 群组数据结构（扩展）

(defstruct group-panel-info
  "群组中的面板信息"
  (panel-id nil :type string)
  (name nil :type string)
  (type nil :type keyword)
  (position nil :type integer)
  (hidden nil :type boolean))

;;;; 数据库初始化

(defun ensure-panel-tables-exist ()
  "确保面板数据表存在"
  (handler-case
      (progn
        ;; 创建面板表
        (postmodern:execute
         "CREATE TABLE IF NOT EXISTS lispim_panels (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            group_id TEXT NOT NULL,
            type TEXT NOT NULL,
            config JSONB,
            position INTEGER DEFAULT 0,
            created_at BIGINT,
            updated_at BIGINT,
            created_by TEXT,
            UNIQUE(group_id, id)
          )")

        ;; 创建索引
        (postmodern:execute
         "CREATE INDEX IF NOT EXISTS idx_panels_group_id ON lispim_panels(group_id)")
        (postmodern:execute
         "CREATE INDEX IF NOT EXISTS idx_panels_position ON lispim_panels(position)")

        (log-info "Panel tables initialized"))
    (error (c)
      (log-error "Failed to initialize panel tables: ~a" c))))

;;;; 面板 CRUD 操作

(defun create-panel (group-id name type &key (config nil) (created-by nil))
  "创建面板"
  (declare (type string group-id name created-by)
           (type keyword type))

  (let* ((panel-id (generate-snowflake-id))
         (panel (make-panel
                 :id panel-id
                 :name name
                 :group-id group-id
                 :type type
                 :config config
                 :position (get-next-panel-position group-id)
                 :created-at (get-universal-time)
                 :updated-at (get-universal-time)
                 :created-by created-by))
         (config-json (when config
                        (cl-json:encode-json-to-string
                         `(("type" . ,(string-downcase (symbol-name (panel-config-type config))))
                           ("title" . ,(panel-config-title config))
                           ("url" . ,(panel-config-url config))
                           ("appId" . ,(panel-config-app-id config))
                           ("folderId" . ,(panel-config-folder-id config))
                           ("hidden" . ,(panel-config-hidden config)))))))

    ;; 保存到数据库
    (postmodern:execute
     "INSERT INTO lispim_panels (id, name, group_id, type, config, position, created_at, updated_at, created_by)
      VALUES ($1, $2, $3, $4, $5::jsonb, $6, $7, $8, $9)"
     panel-id name group-id (string-downcase (symbol-name type))
     config-json (panel-position panel)
     (lispim-universal-to-unix-ms (panel-created-at panel))
     (lispim-universal-to-unix-ms (panel-updated-at panel))
     created-by)

    ;; 发送 WebSocket 通知
    (broadcast-to-group group-id
                        (list :type "PANEL_CREATED"
                              :payload (panel-to-plist panel)))

    (log-info "Panel created: ~a in group ~a" panel-id group-id)
    panel))

(defun get-panel (panel-id)
  "获取面板详情"
  (let ((result (postmodern:query
                 "SELECT id, name, group_id, type, config, position, created_at, updated_at, created_by
                  FROM lispim_panels WHERE id = $1"
                 panel-id :alist)))
    (if result
        (row-to-panel (first result))
        nil)))

(defun get-group-panels (group-id)
  "获取群组的所有面板"
  (let ((results (postmodern:query
                  "SELECT id, name, group_id, type, config, position, created_at, updated_at, created_by
                   FROM lispim_panels
                   WHERE group_id = $1
                   ORDER BY position ASC"
                  group-id :alist)))
    (mapcar #'row-to-panel results)))

(defun update-panel (panel-id &key (name nil) (config nil) (position nil) (hidden nil))
  "更新面板"
  (let ((panel (get-panel panel-id)))
    (unless panel
      (error 'panel-not-found :panel-id panel-id))

    ;; 更新字段
    (when name
      (setf (panel-name panel) name))
    (when config
      (setf (panel-config panel) config))
    (when position
      (setf (panel-position panel) position))
    (when hidden
      (setf (panel-config panel)
            (make-panel-config
             :type (panel-config-type (panel-config panel))
             :hidden hidden))))

  ;; 保存到数据库
  (let* ((config-json (when (panel-config panel)
                        (cl-json:encode-json-to-string
                         `(("type" . ,(string-downcase (symbol-name (panel-config-type (panel-config panel)))))
                           ("hidden" . ,(panel-config-hidden (panel-config panel)))))))
         (updated-at (get-universal-time)))
    (setf (panel-updated-at panel) updated-at)

    (postmodern:execute
     "UPDATE lispim_panels SET name = $2, config = $3::jsonb, position = $4, updated_at = $5
      WHERE id = $1"
     panel-id (panel-name panel) config-json (panel-position panel)
     (lispim-universal-to-unix-ms updated-at))

    ;; 发送通知
    (broadcast-to-group (panel-group-id panel)
                        (list :type "PANEL_UPDATED"
                              :payload (panel-to-plist panel)))

    (log-info "Panel updated: ~a" panel-id)
    panel))

(defun delete-panel (panel-id)
  "删除面板"
  (let ((panel (get-panel panel-id)))
    (unless panel
      (error 'panel-not-found :panel-id panel-id))

    (let ((group-id (panel-group-id panel)))
      ;; 从数据库删除
      (postmodern:execute "DELETE FROM lispim_panels WHERE id = $1" panel-id)

      ;; 重新排列位置
      (reorder-group-panels group-id)

      ;; 发送通知
      (broadcast-to-group group-id
                          `(:type "PANEL_DELETED"
                            :payload (:panel-id ,panel-id)))

      (log-info "Panel deleted: ~a" panel-id)))
  t)

;;;; 辅助函数

(defun get-next-panel-position (group-id)
  "获取下一个面板位置"
  (let ((max (postmodern:query "SELECT MAX(position) FROM lispim_panels WHERE group_id = $1"
                               group-id :single)))
    (if max (1+ max) 0)))

(defun reorder-group-panels (group-id)
  "重新排列群组面板位置"
  (let ((panels (get-group-panels group-id)))
    (loop for panel in panels
          for i from 0
          do (update-panel (panel-id panel) :position i))))

(defun row-to-panel (row)
  "将数据库行转换为面板结构"
  (let* ((config-json (getf row :config))
         (config (when config-json
                   (let ((obj (cl-json:decode-json-from-string config-json)))
                     (make-panel-config
                      :type (keywordify (cdr (assoc "type" obj :test 'equal)))
                      :title (cdr (assoc "title" obj :test 'equal))
                      :url (cdr (assoc "url" obj :test 'equal))
                      :app-id (cdr (assoc "appId" obj :test 'equal))
                      :folder-id (cdr (assoc "folderId" obj :test 'equal))
                      :hidden (or (cdr (assoc "hidden" obj :test 'equal)) nil))))))
    (make-panel
     :id (getf row :id)
     :name (getf row :name)
     :group-id (getf row :group-id)
     :type (keywordify (getf row :type))
     :config config
     :position (or (getf row :position) 0)
     :created-at (unix-ms-to-lispim-universal (getf row :created_at))
     :updated-at (unix-ms-to-lispim-universal (getf row :updated_at))
     :created-by (getf row :created_by))))

(defun panel-to-plist (panel)
  "将面板转换为 plist"
  (list :id (panel-id panel)
        :name (panel-name panel)
        :group-id (panel-group-id panel)
        :type (panel-type panel)
        :position (panel-position panel)
        :created-at (panel-created-at panel)
        :updated-at (panel-updated-at panel)
        :created-by (panel-created-by panel)
        :config (panel-config-to-plist (panel-config panel))))

(defun panel-config-to-plist (config)
  "将面板配置转换为 plist"
  (when config
    (list :type (panel-config-type config)
          :title (panel-config-title config)
          :url (panel-config-url config)
          :app-id (panel-config-app-id config)
          :folder-id (panel-config-folder-id config)
          :hidden (panel-config-hidden config))))

;;;; WebSocket 消息处理

(defun handle-panel-message (conn message)
  "处理面板相关的 WebSocket 消息"
  (let ((payload (getf message :payload))
        (msg-type (getf message :type)))
    (cond
      ((string= msg-type "PANEL_CREATE")
       (let ((group-id (getf payload :groupId))
             (name (getf payload :name))
             (type (keywordify (getf payload :type))))
         (handler-case
             (let ((panel (create-panel group-id name type
                                        :created-by (connection-user-id conn))))
               (send-to-connection conn (encode-ws-message
                                         `(:type "PANEL_CREATED"
                                           :payload ,(panel-to-plist panel)))))
           (error (c)
             (send-to-connection conn (encode-ws-message
                                       `(:type "ERROR"
                                         :payload (:message ,(princ-to-string c)))))))))

      ((string= msg-type "PANEL_UPDATE")
       (let ((panel-id (getf payload :panelId)))
         (handler-case
             (let ((panel (update-panel panel-id
                                        :name (getf payload :name)
                                        :position (getf payload :position))))
               (send-to-connection conn (encode-ws-message
                                         `(:type "PANEL_UPDATED"
                                           :payload ,(panel-to-plist panel)))))
           (error (c)
             (send-to-connection conn (encode-ws-message
                                       `(:type "ERROR"
                                         :payload (:message ,(princ-to-string c)))))))))

      ((string= msg-type "PANEL_DELETE")
       (let ((panel-id (getf payload :panelId)))
         (handler-case
             (progn
               (delete-panel panel-id)
               (send-to-connection conn (encode-ws-message
                                         `(:type "PANEL_DELETED"
                                           :payload (:panelId ,panel-id)))))
           (error (c)
             (send-to-connection conn (encode-ws-message
                                       `(:type "ERROR"
                                         :payload (:message ,(princ-to-string c)))))))))

      ((string= msg-type "GET_PANELS")
       (let ((group-id (getf payload :groupId)))
         (handler-case
             (let ((panels (get-group-panels group-id)))
               (send-to-connection conn (encode-ws-message
                                         `(:type "PANELS"
                                           :payload (:groupId ,group-id
                                                    :panels ,(mapcar #'panel-to-plist panels)))))
           (error (c)
             (send-to-connection conn (encode-ws-message
                                       `(:type "ERROR"
                                         :payload (:message ,(princ-to-string c)))))))))

      (t
       (log-debug "Unknown panel message type: ~a" msg-type))))))

;;;; 条件系统

(define-condition panel-error (condition)
  ((panel-id :initarg :panel-id :reader panel-error-panel-id))
  (:report (lambda (c s)
             (format s "Panel error [~a]" (panel-error-panel-id c)))))

(define-condition panel-not-found (panel-error)
  ()
  (:report (lambda (c s)
             (format s "Panel not found: ~a" (panel-error-panel-id c)))))

;;;; 初始化

(defun init-panel-system ()
  "初始化面板系统"
  (log-info "Initializing panel system...")

  ;; 确保数据表存在
  (ensure-panel-tables-exist)

  (log-info "Panel system initialized"))

;;;; 导出 - Removed: exports are in package.lisp