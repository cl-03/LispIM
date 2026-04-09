;;;; role.lisp - 角色与权限系统
;;;;
;;;; 基于角色的访问控制（RBAC）
;;;; 内置角色：群主、管理员、成员、访客
;;;; 支持自定义角色和权限粒度控制

(in-package :lispim-core)

;;;; 依赖声明

(eval-when (:compile-toplevel :load-toplevel :execute)
  (ql:quickload '(::bordeaux-threads :cl-json)))

;;;; 权限定义

(defconstant +permissions+
  '(:all                      ; 所有权限（仅群主）
    :manage-group             ; 管理群组（解散、转让）
    :manage-roles             ; 管理角色
    :manage-panels            ; 管理面板
    :manage-members           ; 管理成员（踢人、禁言）
    :invite-members           ; 邀请成员
    :send-message             ; 发送消息
    :view-panels              ; 查看面板
    :view-history             ; 查看历史记录
    :recall-message           ; 撤回消息
    :pin-message              ; 置顶消息
    :create-panel             ; 创建面板
    :delete-others-message    ; 删除他人消息
    :manage-webhooks)         ; 管理 Webhook
  "所有可用权限")

;;;; 内置角色定义

(defstruct built-in-role
  "内置角色定义"
  (id nil :type string)
  (name nil :type string)
  (name-zh nil :type string)
  (permissions nil :type list)
  (color nil :type string)
  (position 0 :type integer)
  (is-default nil :type boolean))

(defparameter *built-in-roles*
  (list
   (make-built-in-role
    :id "owner"
    :name "Owner"
    :name-zh "群主"
    :permissions (list :all)
    :color "#FF0000"
    :position 100
    :is-default nil)

   (make-built-in-role
    :id "admin"
    :name "Admin"
    :name-zh "管理员"
    :permissions (list :manage-panels :manage-members :kick-member :mute-member :invite-members :send-message :view-panels :view-history :recall-message :pin-message)
    :color "#FFA500"
    :position 90
    :is-default nil)

   (make-built-in-role
    :id "member"
    :name "Member"
    :name-zh "成员"
    :permissions (list :send-message :view-panels :view-history :recall-message :create-panel)
    :color "#00AA00"
    :position 50
    :is-default t)

   (make-built-in-role
    :id "guest"
    :name "Guest"
    :name-zh "访客"
    :permissions (list :view-panels)
    :color "#888888"
    :position 10
    :is-default nil))
  "内置角色列表")

;;;; 角色数据结构

(defstruct role
  "角色定义"
  (id nil :type string)                 ; 角色 ID
  (name nil :type string)               ; 角色名称
  (name-zh nil :type (or null string))  ; 中文名称
  (group-id nil :type string)           ; 所属群组 ID
  (permissions nil :type list)          ; 权限列表
  (color "#888888" :type string)        ; 角色颜色
  (position 0 :type integer)            ; 角色等级（数字越大越高）
  (is-default nil :type boolean)        ; 是否为默认角色
  (is-built-in nil :type boolean)       ; 是否为内置角色
  (created-at nil :type integer)        ; 创建时间
  (updated-at nil :type integer))       ; 更新时间

;;;; 成员角色关联

(defstruct member-role
  "成员角色关联"
  (user-id nil :type string)
  (group-id nil :type string)
  (role-id nil :type string)
  (assigned-at nil :type integer)
  (assigned-by nil :type string))

;;;; 数据库初始化

(defun ensure-role-tables-exist ()
  "确保角色数据表存在"
  (handler-case
      (progn
        ;; 角色表
        (postmodern:execute
         "CREATE TABLE IF NOT EXISTS lispim_roles (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            name_zh TEXT,
            group_id TEXT,
            permissions JSONB,
            color TEXT DEFAULT '#888888',
            position INTEGER DEFAULT 0,
            is_default BOOLEAN DEFAULT FALSE,
            is_builtin BOOLEAN DEFAULT FALSE,
            created_at BIGINT,
            updated_at BIGINT,
            UNIQUE(group_id, id)
          )")

        ;; 成员角色关联表
        (postmodern:execute
         "CREATE TABLE IF NOT EXISTS lispim_member_roles (
            user_id TEXT NOT NULL,
            group_id TEXT NOT NULL,
            role_id TEXT NOT NULL,
            assigned_at BIGINT,
            assigned_by TEXT,
            PRIMARY KEY (user_id, group_id, role_id)
          )")

        ;; 索引
        (postmodern:execute
         "CREATE INDEX IF NOT EXISTS idx_roles_group_id ON lispim_roles(group_id)")
        (postmodern:execute
         "CREATE INDEX IF NOT EXISTS idx_member_roles_user_id ON lispim_member_roles(user_id)")
        (postmodern:execute
         "CREATE INDEX IF NOT EXISTS idx_member_roles_group_id ON lispim_member_roles(group_id)")

        ;; 初始化内置角色
        (init-built-in-roles)

        (log-info "Role tables initialized"))
    (error (c)
      (log-error "Failed to initialize role tables: ~a" c))))

(defun init-built-in-roles ()
  "初始化内置角色到数据库"
  (dolist (built-in *built-in-roles*)
    (let ((exists (postmodern:query "SELECT 1 FROM lispim_roles WHERE id = $1 AND is_builtin = TRUE"
                                    (built-in-role-id built-in) :single)))
      (unless exists
        (postmodern:execute
         "INSERT INTO lispim_roles (id, name, name_zh, group_id, permissions, color, position, is_default, is_builtin, created_at, updated_at)
          VALUES ($1, $2, $3, NULL, $4::jsonb, $5, $6, $7, $8, $9, $10)"
         (built-in-role-id built-in)
         (built-in-role-name built-in)
         (built-in-role-name-zh built-in)
         (cl-json:encode-json-to-string
          (mapcar #'string-downcase (mapcar #'symbol-name (built-in-role-permissions built-in))))
         (built-in-role-color built-in)
         (built-in-role-position built-in)
         (built-in-role-is-default built-in)
         t
         (lispim-universal-to-unix-ms (get-universal-time))
         (lispim-universal-to-unix-ms (get-universal-time)))))))

;;;; 角色 CRUD

(defun create-role (group-id name &key (permissions nil) (color "#888888") (position 0))
  "创建自定义角色"
  (let* ((role-id (generate-snowflake-id))
         (role (make-role
                :id role-id
                :name name
                :group-id group-id
                :permissions permissions
                :color color
                :position position
                :created-at (get-universal-time)
                :updated-at (get-universal-time)
                :is-built-in nil)))

    (postmodern:execute
     "INSERT INTO lispim_roles (id, name, group_id, permissions, color, position, is_default, is_builtin, created_at, updated_at)
      VALUES ($1, $2, $3, $4::jsonb, $5, $6, $7, $8, $9, $10)"
     role-id name group-id
     (cl-json:encode-json-to-string
      (mapcar #'string-downcase (mapcar #'symbol-name permissions)))
     color position nil nil
     (lispim-universal-to-unix-ms (role-created-at role))
     (lispim-universal-to-unix-ms (role-updated-at role)))

    (log-info "Role created: ~a in group ~a" role-id group-id)
    role))

(defun get-role (role-id)
  "获取角色详情"
  (let ((result (postmodern:query
                 "SELECT * FROM lispim_roles WHERE id = $1"
                 role-id :alist)))
    (if result
        (row-to-role (first result))
        nil)))

(defun get-group-roles (group-id)
  "获取群组的所有角色"
  (let ((results (postmodern:query
                  "SELECT * FROM lispim_roles
                   WHERE group_id = $1 OR is_builtin = TRUE
                   ORDER BY position DESC"
                  group-id :alist)))
    (mapcar #'row-to-role results)))

(defun update-role (role-id &key (name nil) (permissions nil) (color nil) (position nil))
  "更新角色"
  (let ((role (get-role role-id)))
    (unless role
      (error 'role-not-found :role-id role-id))

    (when name (setf (role-name role) name))
    (when permissions (setf (role-permissions role) permissions))
    (when color (setf (role-color role) color))
    (when position (setf (role-position role) position))
    (setf (role-updated-at role) (get-universal-time))

    (postmodern:execute
     "UPDATE lispim_roles SET name = $2, permissions = $3::jsonb, color = $4, position = $5, updated_at = $6
      WHERE id = $1"
     role-id (role-name role)
     (cl-json:encode-json-to-string
      (mapcar #'string-downcase (mapcar #'symbol-name (role-permissions role))))
     (role-color role) (role-position role)
     (lispim-universal-to-unix-ms (role-updated-at role)))

    role))

(defun delete-role (role-id)
  "删除角色"
  (let ((role (get-role role-id)))
    (unless role
      (error 'role-not-found :role-id role-id))

    (when (role-is-built-in role)
      (error 'cannot-delete-built-in-role :role-id role-id))

    (postmodern:execute "DELETE FROM lispim_roles WHERE id = $1" role-id)
    (postmodern:execute "DELETE FROM lispim_member_roles WHERE role_id = $1" role-id)

    (log-info "Role deleted: ~a" role-id)
    t))

;;;; 成员角色管理

(defun assign-role-to-member (user-id group-id role-id &key (assigned-by nil))
  "给成员分配角色"
  (let ((role (get-role role-id)))
    (unless role
      (error 'role-not-found :role-id role-id)))

  ;; 检查用户是否在群组中
  (unless (is-group-member-p user-id group-id)
    (error 'user-not-in-group :user-id user-id :group-id group-id))

  ;; 添加角色关联
  (postmodern:execute
   "INSERT INTO lispim_member_roles (user_id, group_id, role_id, assigned_at, assigned_by)
    VALUES ($1, $2, $3, $4, $5)
    ON CONFLICT (user_id, group_id, role_id) DO NOTHING"
   user-id group-id role-id
   (lispim-universal-to-unix-ms (get-universal-time))
   assigned-by)

  ;; 清除缓存
  (clear-user-roles-cache user-id group-id)

  (log-info "Role ~a assigned to ~a in group ~a" role-id user-id group-id)
  t)

(defun remove-role-from-member (user-id group-id role-id)
  "移除成员的角色"
  (postmodern:execute
   "DELETE FROM lispim_member_roles
    WHERE user_id = $1 AND group_id = $2 AND role_id = $3"
   user-id group-id role-id)

  ;; 清除缓存
  (clear-user-roles-cache user-id group-id)

  (log-info "Role ~a removed from ~a in group ~a" role-id user-id group-id)
  t)

(defun get-user-roles (user-id group-id)
  "获取用户在群组中的角色"
  ;; 检查缓存
  (let ((cached (get-user-roles-from-cache user-id group-id)))
    (when cached
      (return-from get-user-roles cached)))

  ;; 从数据库查询
  (let ((results (postmodern:query
                  "SELECT r.* FROM lispim_roles r
                   INNER JOIN lispim_member_roles mr ON r.id = mr.role_id
                   WHERE mr.user_id = $1 AND mr.group_id = $2"
                  user-id group-id :alist)))
    (let ((roles (mapcar #'row-to-role results)))
      ;; 如果没有自定义角色，返回默认角色
      (unless roles
        (let ((default-role (find "member" *built-in-roles* :key #'built-in-role-id :test #'string=)))
          (when default-role
            (setf roles (list (built-in-role-to-role default-role))))))
      ;; 缓存结果
      (cache-user-roles user-id group-id roles)
      roles)))

;;;; 权限检查

(defun has-permission-p (user-id group-id permission)
  "检查用户是否有指定权限"
  (let ((roles (get-user-roles user-id group-id)))
    (dolist (role roles)
      (let ((perms (role-permissions role)))
        ;; 检查是否有 :all 权限
        (when (member :all perms)
          (return-from has-permission-p t))
        ;; 检查是否有具体权限
        (when (member permission perms)
          (return-from has-permission-p t)))))
  nil)

(defun guard-permission (user-id group-id permission &body body)
  "权限守卫宏"
  `(if (has-permission-p ,user-id ,group-id ,permission)
       (progn ,@body)
       (error 'permission-denied :permission ,permission :user-id ,user-id :group-id ,group-id)))

(defmacro with-permission ((user-id group-id permission) &body body)
  "权限检查宏"
  `(guard-permission ,user-id ,group-id ,permission ,@body))

;;;; 缓存

(defvar *user-roles-cache*
  (make-hash-table :test 'equal)
  "用户角色缓存")

(defvar *user-roles-cache-lock*
  (bordeaux-threads:make-lock "user-roles-cache")
  "缓存锁")

(defun cache-key (user-id group-id)
  "生成缓存键"
  (format nil "~a:~a" user-id group-id))

(defun get-user-roles-from-cache (user-id group-id)
  "从缓存获取用户角色"
  (bordeaux-threads:with-lock-held (*user-roles-cache-lock*)
    (gethash (cache-key user-id group-id) *user-roles-cache*)))

(defun cache-user-roles (user-id group-id roles)
  "缓存用户角色"
  (bordeaux-threads:with-lock-held (*user-roles-cache-lock*)
    (setf (gethash (cache-key user-id group-id) *user-roles-cache*) roles)))

(defun clear-user-roles-cache (user-id group-id)
  "清除用户角色缓存"
  (bordeaux-threads:with-lock-held (*user-roles-cache-lock*)
    (remhash (cache-key user-id group-id) *user-roles-cache*)))

;;;; 辅助函数

(defun row-to-role (row)
  "将数据库行转换为角色"
  (let* ((permissions-json (getf row :permissions))
         (permissions (when permissions-json
                        (let ((obj (cl-json:decode-json-from-string permissions-json)))
                          (mapcar #'keywordify obj)))))
    (make-role
     :id (getf row :id)
     :name (getf row :name)
     :name-zh (getf row :name_zh)
     :group-id (getf row :group_id)
     :permissions permissions
     :color (or (getf row :color) "#888888")
     :position (or (getf row :position) 0)
     :is-default (or (getf row :is_default) nil)
     :is-built-in (or (getf row :is_builtin) nil)
     :created-at (unix-ms-to-lispim-universal (getf row :created_at))
     :updated-at (unix-ms-to-lispim-universal (getf row :updated_at)))))

(defun built-in-role-to-role (built-in)
  "将内置角色转换为角色"
  (make-role
   :id (built-in-role-id built-in)
   :name (built-in-role-name built-in)
   :name-zh (built-in-role-name-zh built-in)
   :group-id nil
   :permissions (built-in-role-permissions built-in)
   :color (built-in-role-color built-in)
   :position (built-in-role-position built-in)
   :is-default (built-in-role-is-default built-in)
   :is-built-in t
   :created-at (get-universal-time)
   :updated-at (get-universal-time)))

;;;; WebSocket 消息处理

(defun handle-role-message (conn message)
  "处理角色相关的 WebSocket 消息"
  (let ((payload (getf message :payload))
        (user-id (connection-user-id conn)))
    (cond
      ((string= (getf message :type) "ROLE_CREATE")
       (let ((group-id (getf payload :groupId))
             (name (getf payload :name))
             (permissions (getf payload :permissions)))
         (handler-case
             (with-permission (user-id group-id :manage-roles)
               (let ((role (create-role group-id name :permissions permissions)))
                 (send-to-connection conn (encode-ws-message
                                           (list :type "ROLE_CREATED"
                                                 :payload (role-to-plist role)))))
           (permission-denied (c)
             (send-to-connection conn (encode-ws-message
                                       (list :type "ERROR"
                                             :payload (:message "Permission denied"))))))))

      ((string= (getf message :type) "ROLE_UPDATE")
       (let ((role-id (getf payload :roleId)))
         (handler-case
             (let ((role (update-role role-id
                                      :name (getf payload :name)
                                      :permissions (getf payload :permissions))))
               (send-to-connection conn (encode-ws-message
                                         (list :type "ROLE_UPDATED"
                                               :payload (role-to-plist role)))))
           (error (c)
             (send-to-connection conn (encode-ws-message
                                       (list :type "ERROR"
                                             :payload (:message ,(princ-to-string c)))))))))

      ((string= (getf message :type) "ROLE_DELETE")
       (let ((role-id (getf payload :roleId)))
         (handler-case
             (progn
               (delete-role role-id)
               (send-to-connection conn (encode-ws-message
                                         (list :type "ROLE_DELETED"
                                               :payload (:roleId ,role-id)))))
           (error (c)
             (send-to-connection conn (encode-ws-message
                                       (list :type "ERROR"
                                             :payload (:message ,(princ-to-string c)))))))))

      ((string= (getf message :type) "ASSIGN_ROLE")
       (let ((target-user-id (getf payload :userId))
             (group-id (getf payload :groupId))
             (role-id (getf payload :roleId)))
         (handler-case
             (with-permission (user-id group-id :manage-members)
               (assign-role-to-member target-user-id group-id role-id :assigned-by user-id)
               (send-to-connection conn (encode-ws-message
                                         (list :type "ROLE_ASSIGNED"
                                               :payload (:userId ,target-user-id :roleId ,role-id)))))
           (permission-denied (c)
             (send-to-connection conn (encode-ws-message
                                       (list :type "ERROR"
                                             :payload (:message "Permission denied"))))))))

      ((string= (getf message :type) "GET_ROLES")
       (let ((group-id (getf payload :groupId)))
         (handler-case
             (let ((roles (get-group-roles group-id)))
               (send-to-connection conn (encode-ws-message
                                         (list :type "ROLES"
                                               :payload (:groupId ,group-id
                                                        :roles ,(mapcar #'role-to-plist roles)))))
           (error (c)
             (send-to-connection conn (encode-ws-message
                                       (list :type "ERROR"
                                             :payload (:message ,(princ-to-string c)))))))))

      (t
       (log-debug "Unknown role message type: ~a" (getf message :type))))))

(defun role-to-plist (role)
  "将角色转换为 plist"
  (list :id (role-id role)
        :name (role-name role)
        :name-zh (role-name-zh role)
        :group-id (role-group-id role)
        :permissions (role-permissions role)
        :color (role-color role)
        :position (role-position role)
        :is-default (role-is-default role)
        :is-built-in (role-is-built-in role)))

;;;; 条件系统

(define-condition role-error (condition)
  ((role-id :initarg :role-id :reader role-error-role-id))
  (:report (lambda (c s)
             (format s "Role error [~a]" (role-error-role-id c)))))

(define-condition role-not-found (role-error)
  ()
  (:report (lambda (c s)
             (format s "Role not found: ~a" (role-error-role-id c)))))

(define-condition cannot-delete-built-in-role (role-error)
  ()
  (:report (lambda (c s)
             (format s "Cannot delete built-in role: ~a" (role-error-role-id c)))))

(define-condition permission-denied (condition)
  ((permission :initarg :permission :reader permission-denied-permission)
   (user-id :initarg :user-id :reader permission-denied-user-id)
   (group-id :initarg :group-id :reader permission-denied-group-id))
  (:report (lambda (c s)
             (format s "Permission denied: ~a (user: ~a, group: ~a)"
                     (permission-denied-permission c)
                     (permission-denied-user-id c)
                     (permission-denied-group-id c)))))

(define-condition user-not-in-group (condition)
  ((user-id :initarg :user-id)
   (group-id :initarg :group-id))
  (:report (lambda (c s)
             (format s "User ~a is not in group ~a"
                     (condition-user-id c)
                     (condition-group-id c)))))

;;;; 初始化

(defun init-role-system ()
  "初始化角色权限系统"
  (log-info "Initializing role system...")

  ;; 确保数据表存在
  (ensure-role-tables-exist)

  (log-info "Role system initialized"))

;;;; 导出

(export '(;; Permissions
          #:*permissions+
          ;; Built-in roles
          #:*built-in-roles*
          #:built-in-role
          #:built-in-role-id
          #:built-in-role-name
          #:built-in-role-name-zh
          #:built-in-role-permissions
          #:built-in-role-color
          #:built-in-role-position
          #:built-in-role-is-default
          ;; Role
          #:role
          #:make-role
          #:role-id
          #:role-name
          #:role-name-zh
          #:role-group-id
          #:role-permissions
          #:role-color
          #:role-position
          #:role-is-default
          #:role-is-built-in
          #:role-created-at
          #:role-updated-at
          ;; CRUD
          #:create-role
          #:get-role
          #:get-group-roles
          #:update-role
          #:delete-role
          ;; Member roles
          #:assign-role-to-member
          #:remove-role-from-member
          #:get-user-roles
          ;; Permission checks
          #:has-permission-p
          #:guard-permission
          #:with-permission
          ;; WebSocket
          #:handle-role-message
          #:role-to-plist
          ;; Initialization
          #:ensure-role-tables-exist
          #:init-role-system
          ;; Conditions
          #:role-error
          #:role-not-found
          #:cannot-delete-built-in-role
          #:permission-denied
          #:user-not-in-group)
        :lispim-core)
