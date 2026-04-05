;;;; group.lisp - 群组聊天模块
;;;;
;;;; 提供群组创建、管理、成员角色等功能
;;;; Features: 群组 CRUD, 成员管理，角色权限，群组公告

(in-package :lispim-core)

;;;; 依赖声明

(eval-when (:compile-toplevel :load-toplevel :execute)
  (ql:quickload '(:postmodern :cl-redis :cl-json :uuid)))

;;;; 群组结构定义

(defstruct group
  "群组记录"
  (id 0 :type integer)
  (name "" :type string)
  (avatar "" :type string)
  (owner-id "" :type string)
  (announcement "" :type string)
  (announcement-editor-id "" :type string)
  (announcement-updated-at 0 :type integer)
  (member-count 0 :type integer)
  (max-members 500 :type integer)
  (is-muted nil :type boolean)
  (is-dismissed nil :type boolean)
  (invite-privacy :all :type keyword) ; :all / :owner / :admin
  (created-at 0 :type integer)
  (updated-at 0 :type integer))

(defstruct group-member
  "群组成员记录"
  (group-id 0 :type integer)
  (user-id "" :type string)
  (role :member :type keyword) ; :owner / :admin / :member
  (nickname "" :type string)
  (joined-at 0 :type integer)
  (is-muted nil :type boolean)
  (is-quiet-p nil :type boolean)) ; 是否设置了消息免打扰

;;;; 数据库表初始化

(defun ensure-group-tables-exist ()
  "创建群组相关数据库表"
  (ensure-pg-connected)

  ;; 群组表
  (postmodern:query
   "CREATE TABLE IF NOT EXISTS `groups` (
      id BIGSERIAL PRIMARY KEY,
      name VARCHAR(255) NOT NULL,
      avatar VARCHAR(512) DEFAULT '',
      owner_id VARCHAR(255) NOT NULL,
      announcement TEXT DEFAULT '',
      announcement_editor_id VARCHAR(255) DEFAULT '',
      announcement_updated_at TIMESTAMPTZ DEFAULT NOW(),
      member_count INTEGER DEFAULT 1,
      max_members INTEGER DEFAULT 500,
      is_muted BOOLEAN DEFAULT FALSE,
      is_dismissed BOOLEAN DEFAULT FALSE,
      invite_privacy VARCHAR(20) DEFAULT 'all',
      created_at TIMESTAMPTZ DEFAULT NOW(),
      updated_at TIMESTAMPTZ DEFAULT NOW()
    )")

  (postmodern:query
   "CREATE INDEX IF NOT EXISTS idx_groups_owner ON `groups`(owner_id)")

  ;; 群组成员表
  (postmodern:query
   "CREATE TABLE IF NOT EXISTS group_members (
      id BIGSERIAL PRIMARY KEY,
      group_id BIGINT REFERENCES `groups`(id) ON DELETE CASCADE,
      user_id VARCHAR(255) NOT NULL,
      role VARCHAR(20) DEFAULT 'member',
      nickname VARCHAR(255) DEFAULT '',
      joined_at TIMESTAMPTZ DEFAULT NOW(),
      is_muted BOOLEAN DEFAULT FALSE,
      is_quiet BOOLEAN DEFAULT FALSE,
      UNIQUE(group_id, user_id)
    )")

  (postmodern:query
   "CREATE INDEX IF NOT EXISTS idx_group_members_group ON group_members(group_id)")
  (postmodern:query
   "CREATE INDEX IF NOT EXISTS idx_group_members_user ON group_members(user_id)")

  ;; 群组管理员操作日志表
  (postmodern:query
   "CREATE TABLE IF NOT EXISTS group_admin_logs (
      id BIGSERIAL PRIMARY KEY,
      group_id BIGINT REFERENCES `groups`(id) ON DELETE CASCADE,
      operator_id VARCHAR(255) NOT NULL,
      action VARCHAR(50) NOT NULL,
      target_user_id VARCHAR(255) DEFAULT '',
      details JSONB DEFAULT '{}',
      created_at TIMESTAMPTZ DEFAULT NOW()
    )")

  (postmodern:query
   "CREATE INDEX IF NOT EXISTS idx_group_admin_logs_group ON group_admin_logs(group_id)")

  ;; 群邀请链接表
  (postmodern:query
   "CREATE TABLE IF NOT EXISTS group_invite_links (
      id BIGSERIAL PRIMARY KEY,
      group_id BIGINT REFERENCES `groups`(id) ON DELETE CASCADE,
      code VARCHAR(50) UNIQUE NOT NULL,
      created_by VARCHAR(255) NOT NULL,
      max_uses INTEGER DEFAULT 0,
      used_count INTEGER DEFAULT 0,
      expires_at TIMESTAMPTZ,
      revoked_at TIMESTAMPTZ DEFAULT NULL,
      created_at TIMESTAMPTZ DEFAULT NOW(),
      UNIQUE(code)
    )")

  (postmodern:query
   "CREATE INDEX IF NOT EXISTS idx_group_invite_links_code ON group_invite_links(code)")
  (postmodern:query
   "CREATE INDEX IF NOT EXISTS idx_group_invite_links_group ON group_invite_links(group_id)")

  ;; 群邀请链接使用记录
  (postmodern:query
   "CREATE TABLE IF NOT EXISTS group_invite_link_uses (
      id BIGSERIAL PRIMARY KEY,
      link_id BIGINT REFERENCES group_invite_links(id) ON DELETE CASCADE,
      user_id VARCHAR(255) NOT NULL,
      joined_at TIMESTAMPTZ DEFAULT NOW()
    )")

  (postmodern:query
   "CREATE INDEX IF NOT EXISTS idx_group_invite_uses_link ON group_invite_link_uses(link_id)")

  (log-info "Group tables initialized"))

;;;; 群组 CRUD 操作

(defun create-group (name owner-id &key avatar max-members invite-privacy)
  "创建群组"
  (declare (type string name owner-id)
           (type (or null string) avatar)
           (type (or null integer) max-members)
           (type (or null keyword) invite-privacy))

  (ensure-pg-connected)

  (let* ((now (get-universal-time))
         (group-id (postmodern:query
                    "INSERT INTO `groups`
                     (name, avatar, owner_id, max_members, invite_privacy, created_at, updated_at)
                     VALUES ($1, $2, $3, $4, $5, to_timestamp($6), to_timestamp($7))
                     RETURNING id"
                    name (or avatar "") owner-id (or max-members 500)
                    (case invite-privacy
                      ((:owner :admin) (string-downcase invite-privacy))
                      (otherwise "all"))
                    (storage-universal-to-unix now)
                    (storage-universal-to-unix now)
                    :alists))
         (gid (cdr (assoc :|id| (car group-id)))))

    ;; 创建者自动成为群主并加入群组
    (add-group-member gid owner-id :role :owner)

    ;; 创建对应的会话
    (let ((conv-id (create-conversation :group (list owner-id)
                                        :name name
                                        :avatar avatar
                                        :metadata `((:group-id . ,gid)))))
      ;; 更新群组的会话 ID
      (postmodern:query
       "UPDATE `groups` SET metadata = $2 WHERE id = $1"
       gid (cl-json:encode-json-to-string `(("conversation_id" . ,conv-id))))

      (log-info "Group created: ~a (~a) by ~a" gid name owner-id)

      (make-group
       :id gid
       :name name
       :avatar (or avatar "")
       :owner-id owner-id
       :member-count 1
       :max-members (or max-members 500)
       :invite-privacy (or invite-privacy :all)
       :created-at now
       :updated-at now))))

(defun get-group (group-id)
  "获取群组信息"
  (declare (type integer group-id))

  (let ((result (postmodern:query
                 "SELECT * FROM `groups` WHERE id = $1"
                 group-id :alists)))

    (when result
      (let ((row (car result)))
        (flet ((get-val (name)
                 (let ((cell (find name row :key #'car :test #'string=)))
                   (when cell (cdr cell)))))
          (make-group
           :id (parse-integer (get-val "ID"))
           :name (get-val "NAME")
           :avatar (get-val "AVATAR")
           :owner-id (get-val "OWNER_ID")
           :announcement (or (get-val "ANNOUNCEMENT") "")
           :announcement-editor-id (or (get-val "ANNOUNCEMENT_EDITOR_ID") "")
           :announcement-updated-at (storage-universal-to-unix (get-val "ANNOUNCEMENT_UPDATED_AT"))
           :member-count (parse-integer (get-val "MEMBER_COUNT"))
           :max-members (parse-integer (get-val "MAX_MEMBERS"))
           :is-muted (string= (get-val "IS_MUTED") "t")
           :is-dismissed (string= (get-val "IS_DISMISSED") "t")
           :invite-privacy (keywordify (get-val "INVITE_PRIVACY"))
           :created-at (storage-universal-to-unix (get-val "CREATED_AT"))
           :updated-at (storage-universal-to-unix (get-val "UPDATED_AT"))))))))

(defun update-group (group-id &key name avatar announcement invite-privacy)
  "更新群组信息"
  (declare (type integer group-id)
           (type (or null string) name avatar announcement)
           (type (or null keyword) invite-privacy))

  (let ((updates nil)
        (params nil)
        (param-idx 1))

    (when name
      (push (format nil "name = $~a" param-idx) updates)
      (push name params)
      (incf param-idx))

    (when avatar
      (push (format nil "avatar = $~a" param-idx) updates)
      (push avatar params)
      (incf param-idx))

    (when announcement
      (push (format nil "announcement = $~a" param-idx) updates)
      (push announcement params)
      (push (get-universal-time) params) ; announcement_updated_at
      (push (format nil "announcement_updated_at = to_timestamp($~a)" param-idx) updates)
      (incf param-idx)
      (incf param-idx))

    (when invite-privacy
      (push (format nil "invite_privacy = $~a" param-idx) updates)
      (push (string-downcase invite-privacy) params)
      (incf param-idx))

    (when updates
      (push group-id params)
      (let ((sql (format nil "UPDATE `groups` SET ~a WHERE id = $~a"
                         (format nil "~{~a~^, ~}" updates) param-idx)))
        (apply (function (lambda (s p) (postmodern:query s p :alists))) (list sql params))))

    (log-info "Group ~a updated" group-id)))

(defun delete-group (group-id)
  "删除群组"
  (declare (type integer group-id))

  (postmodern:query
   "DELETE FROM `groups` WHERE id = $1"
   group-id)

  (log-info "Group ~a deleted" group-id)
  t)

;;;; 群组成员管理

(defun add-group-member (group-id user-id &key role nickname)
  "添加群组成员"
  (declare (type integer group-id)
           (type string user-id)
           (type (or null keyword) role)
           (type (or null string) nickname))

  (handler-case
      (postmodern:query
       "INSERT INTO group_members (group_id, user_id, role, nickname)
        VALUES ($1, $2, $3, $4)
        ON CONFLICT (group_id, user_id) DO NOTHING"
       group-id user-id (string-downcase (or role :member)) (or nickname ""))

    (postmodern:database-error (c)
      (declare (ignore c))
      (return-from add-group-member nil)))

  ;; 更新群组成员数
  (postmodern:query
   "UPDATE `groups` SET member_count = member_count + 1, updated_at = NOW()
    WHERE id = $1 AND NOT EXISTS
      (SELECT 1 FROM group_members WHERE group_id = $1 AND user_id = $2)"
   group-id user-id)

  (log-info "User ~a added to group ~a" user-id group-id)
  t)

(defun remove-group-member (group-id user-id)
  "移除群组成员"
  (declare (type integer group-id)
           (type string user-id))

  (postmodern:query
   "DELETE FROM group_members WHERE group_id = $1 AND user_id = $2"
   group-id user-id)

  ;; 更新群组成员数
  (postmodern:query
   "UPDATE `groups` SET member_count = member_count - 1, updated_at = NOW()
    WHERE id = $1"
   group-id)

  (log-info "User ~a removed from group ~a" user-id group-id)
  t)

(defun get-group-members (group-id)
  "获取群组成员列表"
  (declare (type integer group-id))

  (let ((result (postmodern:query
                 "SELECT * FROM group_members
                  WHERE group_id = $1
                  ORDER BY
                    CASE role
                      WHEN 'owner' THEN 1
                      WHEN 'admin' THEN 2
                      ELSE 3
                    END,
                    joined_at ASC"
                 group-id :alists)))

    (when result
      (loop for row in result
            collect
            (flet ((get-val (name)
                     (let ((cell (find name row :key #'car :test #'string=)))
                       (when cell (cdr cell)))))
              (make-group-member
               :group-id group-id
               :user-id (get-val "USER_ID")
               :role (keywordify (get-val "ROLE"))
               :nickname (get-val "NICKNAME")
               :joined-at (storage-universal-to-unix (get-val "JOINED_AT"))
               :is-muted (string= (get-val "IS_MUTED") "t")
               :is-quiet-p (string= (get-val "IS_QUIET") "t")))))))

(defun get-user-groups (user-id)
  "获取用户加入的所有群组"
  (declare (type string user-id))

  (let ((result (postmodern:query
                 "SELECT g.*, gm.role as member_role, gm.nickname as member_nickname
                  FROM `groups` g
                  JOIN group_members gm ON g.id = gm.group_id
                  WHERE gm.user_id = $1
                  ORDER BY g.updated_at DESC"
                 user-id :alists)))

    (when result
      (loop for row in result
            collect
            (flet ((get-val (name)
                     (let ((cell (find name row :key #'car :test #'string=)))
                       (when cell (cdr cell)))))
              `((:id . ,(parse-integer (get-val "ID")))
                (:name . ,(get-val "NAME"))
                (:avatar . ,(get-val "AVATAR"))
                (:owner_id . ,(get-val "OWNER_ID"))
                (:member_count . ,(parse-integer (get-val "MEMBER_COUNT")))
                (:member_role . ,(keywordify (get-val "MEMBER_ROLE")))
                (:member_nickname . ,(get-val "MEMBER_NICKNAME"))
                (:created_at . ,(storage-universal-to-unix (get-val "CREATED_AT")))
                (:updated_at . ,(storage-universal-to-unix (get-val "UPDATED_AT")))))))))

(defun get-group-member (group-id user-id)
  "获取群组成员信息"
  (declare (type integer group-id)
           (type string user-id))

  (let ((result (postmodern:query
                 "SELECT * FROM group_members
                  WHERE group_id = $1 AND user_id = $2"
                 group-id user-id :alists)))

    (when result
      (let ((row (car result)))
        (flet ((get-val (name)
                 (let ((cell (find name row :key #'car :test #'string=)))
                   (when cell (cdr cell)))))
          (make-group-member
           :group-id group-id
           :user-id (get-val "USER_ID")
           :role (keywordify (get-val "ROLE"))
           :nickname (get-val "NICKNAME")
           :joined-at (storage-universal-to-unix (get-val "JOINED_AT"))
           :is-muted (string= (get-val "IS_MUTED") "t")
           :is-quiet-p (string= (get-val "IS_QUIET") "t")))))))

(defun update-group-member-role (group-id user-id new-role)
  "更新群组成员角色"
  (declare (type integer group-id)
           (type string user-id new-role))

  (postmodern:query
   "UPDATE group_members SET role = $3
    WHERE group_id = $1 AND user_id = $2"
   group-id user-id (string-downcase new-role))

  (log-info "User ~a role changed to ~a in group ~a" user-id new-role group-id)
  t)

(defun set-member-nickname (group-id user-id nickname)
  "设置群组成员昵称"
  (declare (type integer group-id)
           (type string user-id nickname))

  (postmodern:query
   "UPDATE group_members SET nickname = $3
    WHERE group_id = $1 AND user_id = $2"
   group-id user-id nickname)

  (log-info "User ~a nickname set to ~a in group ~a" user-id nickname group-id)
  t)

(defun set-member-quiet (group-id user-id quiet-p)
  "设置群组成员消息免打扰"
  (declare (type integer group-id)
           (type string user-id)
           (type boolean quiet-p))

  (postmodern:query
   "UPDATE group_members SET is_quiet = $3
    WHERE group_id = $1 AND user_id = $2"
   group-id user-id quiet-p)

  (log-info "User ~a quiet mode set to ~a in group ~a" user-id quiet-p group-id)
  t)

;;;; 群组管理员操作日志

(defun log-group-admin-action (group-id operator-id action &key target-user-id details)
  "记录群组管理员操作日志"
  (declare (type integer group-id)
           (type string operator-id action)
           (type (or null string) target-user-id)
           (type (or null string) details))

  (postmodern:query
   "INSERT INTO group_admin_logs (group_id, operator_id, action, target_user_id, details)
    VALUES ($1, $2, $3, $4, $5)"
   group-id operator-id action (or target-user-id "") (or details "{}")))

;;;; 群组权限检查

(defun is-group-owner-p (group-id user-id)
  "检查用户是否是群主"
  (declare (type integer group-id)
           (type string user-id))

  (let ((member (get-group-member group-id user-id)))
    (and member (eq (group-member-role member) :owner))))

(defun is-group-admin-p (group-id user-id)
  "检查用户是否是管理员"
  (declare (type integer group-id)
           (type string user-id))

  (let ((member (get-group-member group-id user-id)))
    (member (group-member-role member) '(:owner :admin))))

(defun is-group-member-p (group-id user-id)
  "检查用户是否是群组成员"
  (declare (type integer group-id)
           (type string user-id))

  (let ((member (get-group-member group-id user-id)))
    (and member t)))

(defun can-invite-p (group-id user-id)
  "检查用户是否可以邀请成员"
  (declare (type integer group-id)
           (type string user-id))

  (let ((group (get-group group-id)))
    (unless group
      (return-from can-invite-p nil))

    (let ((member (get-group-member group-id user-id)))
      (unless member
        (return-from can-invite-p nil))

      (case (group-invite-privacy group)
        (:all t)
        (:owner (eq (group-member-role member) :owner))
        (:admin (member (group-member-role member) '(:owner :admin)))
        (otherwise t)))))

;;;; 群邀请链接

(defstruct group-invite-link
  "群邀请链接"
  (id 0 :type integer)
  (group-id 0 :type integer)
  (code "" :type string)
  (created-by "" :type string)
  (max-uses 0 :type integer)  ; 0 = 无限
  (used-count 0 :type integer)
  (expires-at 0 :type integer)  ; 0 = 永不过期
  (revoked-at 0 :type integer)  ; 0 = 未撤销
  (created-at 0 :type integer))

(defun generate-invite-code ()
  "生成唯一的邀请码"
  (let ((chars "ABCDEFGHJKLMNPQRSTUVWXYZ23456789")  ; 去掉易混淆的字符
        (code-length 8)
        (code ""))
    (dotimes (i code-length code)
      (setf code (concatenate 'string code
                              (string (char chars (random (length chars)))))))))

(defun create-group-invite-link (group-id user-id &key max-uses expires-in)
  "创建群邀请链接
   参数:
   - group-id: 群组 ID
   - user-id: 创建者用户 ID
   - max-uses: 最大使用次数 (0 = 无限)
   - expires-in: 过期时间（秒），nil = 永不过期"
  (declare (type integer group-id)
           (type string user-id)
           (type (or null integer) max-uses)
           (type (or null integer) expires-in))

  (ensure-pg-connected)

  (let* ((now (get-universal-time))
         (code (generate-invite-code))
         (expires-at (if expires-in (+ now expires-in) 0))
         (link-id (postmodern:query
                   "INSERT INTO group_invite_links
                    (group_id, code, created_by, max_uses, expires_at, created_at)
                    VALUES ($1, $2, $3, $4, to_timestamp($5), to_timestamp($6))
                    RETURNING id"
                   group-id code user-id (or max-uses 0)
                   (if expires-at (storage-universal-to-unix expires-at) nil)
                   (storage-universal-to-unix now)
                   :alists)))
    (log-info "Invite link created: ~a for group ~a by ~a" code group-id user-id)
    (make-group-invite-link
     :id (cdr (assoc :|id| (car link-id)))
     :group-id group-id
     :code code
     :created-by user-id
     :max-uses (or max-uses 0)
     :used-count 0
     :expires-at expires-at
     :revoked-at 0
     :created-at now)))

(defun get-invite-link-by-code (code)
  "通过邀请码获取邀请链接"
  (declare (type string code))

  (ensure-pg-connected)

  (let ((row (postmodern:query
              "SELECT id, group_id, code, created_by, max_uses, used_count,
                      COALESCE(EXTRACT(EPOCH FROM expires_at), 0) AS expires_at,
                      COALESCE(EXTRACT(EPOCH FROM revoked_at), 0) AS revoked_at,
                      EXTRACT(EPOCH FROM created_at) AS created_at
               FROM group_invite_links
               WHERE code = $1"
              code)))
    (if row
        (let ((data (car row)))
          (make-group-invite-link
           :id (cdr (assoc :|id| data))
           :group-id (cdr (assoc :|group_id| data))
           :code (cdr (assoc :|code| data))
           :created-by (cdr (assoc :|created_by| data))
           :max-uses (cdr (assoc :|max_uses| data))
           :used-count (cdr (assoc :|used_count| data))
           :expires-at (floor (cdr (assoc :|expires_at| data)))
           :revoked-at (floor (or (cdr (assoc :|revoked_at| data)) 0))
           :created-at (floor (cdr (assoc :|created_at| data)))))
        nil)))

(defun validate-invite-link (link)
  "验证邀请链接是否有效"
  (declare (type group-invite-link link))

  (let ((now (get-universal-time)))
    (cond
      ;; 检查是否被撤销
      ((plusp (group-invite-link-revoked-at link))
       (values nil "INVITE_REVOKED" "邀请链接已被撤销"))
      ;; 检查是否过期
      ((and (plusp (group-invite-link-expires-at link))
            (> now (group-invite-link-expires-at link)))
       (values nil "INVITE_EXPIRED" "邀请链接已过期"))
      ;; 检查使用次数
      ((and (plusp (group-invite-link-max-uses link))
            (>= (group-invite-link-used-count link) (group-invite-link-max-uses link)))
       (values nil "INVITE_FULL" "邀请链接使用次数已达上限"))
      (t (values t nil nil)))))

(defun join-group-via-invite (code user-id)
  "通过邀请链接加入群组"
  (declare (type string code)
           (type string user-id))

  (let ((link (get-invite-link-by-code code)))
    (unless link
      (return-from join-group-via-invite
        (values nil "INVALID_CODE" "无效的邀请链接")))

    ;; 验证链接
    (multiple-value-bind (valid error-code error-msg)
        (validate-invite-link link)
      (unless valid
        (return-from join-group-via-invite
          (values nil error-code error-msg)))

      (let ((group-id (group-invite-link-group-id link)))
        ;; 检查用户是否已是成员
        (when (get-group-member group-id user-id)
          (return-from join-group-via-invite
            (values nil "ALREADY_MEMBER" "你已是群组成员")))

        ;; 加入群组
        (add-group-member group-id user-id :role :member)

        ;; 更新使用计数
        (postmodern:query
         "UPDATE group_invite_links
          SET used_count = used_count + 1
          WHERE id = $1"
         (group-invite-link-id link))

        ;; 记录使用
        (postmodern:query
         "INSERT INTO group_invite_link_uses (link_id, user_id)
          VALUES ($1, $2)"
         (group-invite-link-id link) user-id)

        ;; 通知群组成员有新成员加入
        (notify-group-member-joined group-id user-id)

        (log-info "User ~a joined group ~a via invite ~a" user-id group-id code)
        (values t group-id nil)))))

(defun revoke-invite-link (link-id user-id)
  "撤销邀请链接"
  (declare (type integer link-id)
           (type string user-id))

  (ensure-pg-connected)

  (let ((link (get-invite-link-by-id link-id)))
    (unless link
      (return-from revoke-invite-link
        (values nil "NOT_FOUND" "邀请链接不存在")))

    ;; 检查权限
    (unless (or (string= (group-invite-link-created-by link) user-id)
                (is-group-admin-p (group-invite-link-group-id link) user-id))
      (return-from revoke-invite-link
        (values nil "NO_PERMISSION" "没有权限撤销此邀请链接")))

    (let ((now (get-universal-time)))
      (postmodern:query
       "UPDATE group_invite_links
        SET revoked_at = to_timestamp($1)
        WHERE id = $2"
       (storage-universal-to-unix now) link-id)

      (log-info "Invite link ~a revoked by ~a" link-id user-id)
      (values t nil nil))))

(defun get-invite-link-by-id (link-id)
  "通过 ID 获取邀请链接"
  (declare (type integer link-id))

  (ensure-pg-connected)

  (let ((row (postmodern:query
              "SELECT id, group_id, code, created_by, max_uses, used_count,
                      COALESCE(EXTRACT(EPOCH FROM expires_at), 0) AS expires_at,
                      COALESCE(EXTRACT(EPOCH FROM revoked_at), 0) AS revoked_at,
                      EXTRACT(EPOCH FROM created_at) AS created_at
               FROM group_invite_links
               WHERE id = $1"
              link-id)))
    (if row
        (let ((data (car row)))
          (make-group-invite-link
           :id (cdr (assoc :|id| data))
           :group-id (cdr (assoc :|group_id| data))
           :code (cdr (assoc :|code| data))
           :created-by (cdr (assoc :|created_by| data))
           :max-uses (cdr (assoc :|max_uses| data))
           :used-count (cdr (assoc :|used_count| data))
           :expires-at (floor (cdr (assoc :|expires_at| data)))
           :revoked-at (floor (or (cdr (assoc :|revoked_at| data)) 0))
           :created-at (floor (cdr (assoc :|created_at| data)))))
        nil)))

(defun get-group-invite-links (group-id)
  "获取群组的所有邀请链接"
  (declare (type integer group-id))

  (ensure-pg-connected)

  (let ((rows (postmodern:query
               "SELECT id, code, created_by, max_uses, used_count,
                       COALESCE(EXTRACT(EPOCH FROM expires_at), 0) AS expires_at,
                       COALESCE(EXTRACT(EPOCH FROM revoked_at), 0) AS revoked_at,
                       EXTRACT(EPOCH FROM created_at) AS created_at
                FROM group_invite_links
                WHERE group_id = $1
                ORDER BY created_at DESC"
               group-id)))
    (mapcar (lambda (data)
              (make-group-invite-link
               :id (cdr (assoc :|id| data))
               :group-id group-id
               :code (cdr (assoc :|code| data))
               :created-by (cdr (assoc :|created_by| data))
               :max-uses (cdr (assoc :|max_uses| data))
               :used-count (cdr (assoc :|used_count| data))
               :expires-at (floor (cdr (assoc :|expires_at| data)))
               :revoked-at (floor (or (cdr (assoc :|revoked_at| data)) 0))
               :created-at (floor (cdr (assoc :|created_at| data)))))
            rows)))

(defun notify-group-member-joined (group-id user-id)
  "通知群组成员加入"
  (declare (type integer group-id)
           (type string user-id))

  (let ((conv-id (get-conversation-id-by-group-id group-id)))
    (when conv-id
      (let ((notification `((:type . :member-joined)
                            (:group-id . ,group-id)
                            (:user-id . ,user-id)
                            (:ts . ,(lispim-universal-to-unix-ms (get-universal-time))))))
        (push-to-online-users conv-id notification)))))

(defun get-conversation-id-by-group-id (group-id)
  "通过群组 ID 获取会话 ID"
  (declare (type integer group-id))

  (ensure-pg-connected)

  (let ((row (postmodern:query
              "SELECT id FROM conversations
               WHERE metadata->>'group-id' = $1"
              (princ-to-string group-id))))
    (if row
        (cdr (assoc :|id| (car row)))
        nil)))

;;;; 导出函数

(export '(ensure-group-tables-exist
          create-group
          get-group
          update-group
          delete-group
          add-group-member
          remove-group-member
          get-group-members
          get-user-groups
          get-group-member
          update-group-member-role
          set-member-nickname
          set-member-quiet
          log-group-admin-action
          is-group-owner-p
          is-group-admin-p
          is-group-member-p
          can-invite-p
          ;; Group invite links
          group-invite-link
          make-group-invite-link
          group-invite-link-id
          group-invite-link-group-id
          group-invite-link-code
          group-invite-link-created-by
          group-invite-link-max-uses
          group-invite-link-used-count
          group-invite-link-expires-at
          group-invite-link-revoked-at
          group-invite-link-created-at
          generate-invite-code
          create-group-invite-link
          get-invite-link-by-code
          get-invite-link-by-id
          validate-invite-link
          join-group-via-invite
          revoke-invite-link
          get-group-invite-links
          notify-group-member-joined
          get-conversation-id-by-group-id))
