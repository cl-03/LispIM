;;;; room.lisp - 房间管理系统
;;;;
;;;; 参考 Fiora/Tailchat 的房间管理设计
;;;; 支持群组房间、私聊房间、频道房间等
;;;;
;;;; 设计原则：
;;;; - 纯 Common Lisp 实现
;;;; - 高效的房间查找和广播
;;;; - 支持嵌套房间（用户可同时属于多个房间）

(in-package :lispim-core)

;;;; 依赖声明

(eval-when (:compile-toplevel :load-toplevel :execute)
  (ql:quickload '(:bordeaux-threads :cl-json)))

;;;; 类型定义

(deftype room-id ()
  "房间 ID 类型"
  'string)

(deftype room-type ()
  "房间类型"
  '(member :user      ; 用户私聊房间
           :group     ; 群组房间
           :channel   ; 频道房间
           :system    ; 系统房间
           :temporary)) ; 临时房间

;;;; 房间结构

(defstruct room
  "房间
   参考 Tailchat 的房间概念，支持多种房间类型"
  (id "" :type room-id)
  (type :user :type room-type)
  (members (make-hash-table :test 'equal) :type hash-table)
  (created-at (get-universal-time) :type integer)
  (metadata (make-hash-table :test 'equal) :type hash-table)
  (lock (bordeaux-threads:make-lock "room-lock")))

(defstruct room-membership
  "房间成员资格"
  (user-id "" :type string)
  (joined-at (get-universal-time) :type integer)
  (role :member :type keyword)
  (muted-p nil :type boolean))

;;;; 全局房间表

(defvar *rooms* (make-hash-table :test 'equal)
  "房间表：room-id -> room")

(defvar *rooms-lock* (bordeaux-threads:make-lock "rooms-lock")
  "房间表锁")

(defvar *user-rooms* (make-hash-table :test 'equal)
  "用户房间索引：user-id -> (room-id*)")

(defvar *user-rooms-lock* (bordeaux-threads:make-lock "user-rooms-lock")
  "用户房间索引锁")

;;;; 房间统计

(defvar *rooms-created-counter* 0
  "创建的房间总数")

(defvar *rooms-active-gauge* 0
  "活跃房间数")

;;;; 房间操作

(defun create-room (room-id &key (type :user) (metadata nil))
  "创建房间

   Parameters:
     room-id  - 房间 ID
     type     - 房间类型（:user/:group/:channel/:system/:temporary）
     metadata - 元数据 plist

   Returns:
     room 对象"
  (declare (type room-id room-id)
           (type room-type type))
  (bordeaux-threads:with-lock-held (*rooms-lock*)
    (when (gethash room-id *rooms*)
      (return-from create-room nil))
    (let ((room (make-room
                 :id room-id
                 :type type
                 :metadata (or metadata (make-hash-table :test 'equal)))))
      (setf (gethash room-id *rooms*) room)
      (incf *rooms-created-counter*)
      (incf *rooms-active-gauge*)
      (log-info "Room created: ~a (type=~a)" room-id type)
      room)))

(defun destroy-room (room-id)
  "销毁房间"
  (declare (type room-id room-id))
  (let ((room (gethash room-id *rooms*)))
    (when room
      ;; 移除所有成员
      (maphash (lambda (user-id membership)
                 (declare (ignore membership))
                 (remove-from-room room-id user-id))
               (room-members room))
      ;; 从全局表移除
      (bordeaux-threads:with-lock-held (*rooms-lock*)
        (remhash room-id *rooms*)
        (decf *rooms-active-gauge*))
      (log-info "Room destroyed: ~a" room-id)
      t)))

(defun get-room (room-id)
  "获取房间对象"
  (declare (type room-id room-id))
  (gethash room-id *rooms*))

(defun room-exists-p (room-id)
  "检查房间是否存在"
  (declare (type room-id room-id))
  (nth-value 1 (gethash room-id *rooms*)))

;;;; 成员操作

(defun join-room (room-id user-id &key (role :member))
  "加入房间

   Parameters:
     room-id - 房间 ID
     user-id - 用户 ID
     role    - 角色（:owner/:admin/:member/:guest）

   Returns:
     t 成功，nil 失败"
  (declare (type room-id room-id)
           (type string user-id))
  (let ((room (gethash room-id *rooms*)))
    (unless room
      (log-warn "Join room failed: room ~a not found" room-id)
      (return-from join-room nil))
    (bordeaux-threads:with-lock-held ((room-lock room))
      ;; 检查是否已在房间中
      (when (gethash user-id (room-members room))
        (return-from join-room t))
      ;; 添加成员
      (setf (gethash user-id (room-members room))
            (make-room-membership
             :user-id user-id
             :role role))
      ;; 更新用户房间索引
      (bordeaux-threads:with-lock-held (*user-rooms-lock*)
        (pushnew room-id (gethash user-id *user-rooms*) :test 'string=))
      (log-info "User ~a joined room ~a" user-id room-id)
      t)))

(defun leave-room (room-id user-id)
  "离开房间"
  (declare (type room-id room-id)
           (type string user-id))
  (let ((room (gethash room-id *rooms*)))
    (unless room
      (return-from leave-room nil))
    (bordeaux-threads:with-lock-held ((room-lock room))
      ;; 移除成员
      (remhash user-id (room-members room))
      ;; 更新用户房间索引
      (bordeaux-threads:with-lock-held (*user-rooms-lock*)
        (let ((rooms (gethash user-id *user-rooms*)))
          (when rooms
            (setf (gethash user-id *user-rooms*)
                  (remove room-id rooms :test 'string=)))))
      (log-info "User ~a left room ~a" user-id room-id)
      t)))

(defun remove-from-room (room-id user-id)
  "从房间移除（与 leave-room 相同，语义不同）"
  (leave-room room-id user-id))

(defun get-room-members (room-id)
  "获取房间所有成员"
  (declare (type room-id room-id))
  (let ((room (gethash room-id *rooms*)))
    (when room
      (let ((members nil))
        (maphash (lambda (uid membership)
                   (declare (ignore membership))
                   (push uid members))
                 (room-members room))
        members))))

(defun get-room-member-count (room-id)
  "获取房间成员数量"
  (declare (type room-id room-id))
  (let ((room (gethash room-id *rooms*)))
    (if room
        (hash-table-count (room-members room))
        0)))

(defun get-user-rooms (user-id)
  "获取用户加入的所有房间"
  (declare (type string user-id))
  (bordeaux-threads:with-lock-held (*user-rooms-lock*)
    (copy-list (gethash user-id *user-rooms*))))

(defun is-member-of-room-p (room-id user-id)
  "检查用户是否是房间成员"
  (declare (type room-id room-id)
           (type string user-id))
  (let ((room (gethash room-id *rooms*)))
    (when room
      (nth-value 1 (gethash user-id (room-members room))))))

(defun get-user-room-role (room-id user-id)
  "获取用户在房间中的角色"
  (declare (type room-id room-id)
           (type string user-id))
  (let ((room (gethash room-id *rooms*)))
    (when room
      (let ((membership (gethash user-id (room-members room))))
        (when membership
          (room-membership-role membership))))))

(defun set-room-member-role (room-id user-id role)
  "设置用户在房间中的角色"
  (declare (type room-id room-id)
           (type string user-id)
           (type keyword role))
  (let ((room (gethash room-id *rooms*)))
    (unless room
      (return-from set-room-member-role nil))
    (bordeaux-threads:with-lock-held ((room-lock room))
      (let ((membership (gethash user-id (room-members room))))
        (unless membership
          (return-from set-room-member-role nil))
        (setf (room-membership-role membership) role)))
    (log-info "User ~a role set to ~a in room ~a" user-id role room-id)
    t))

;;;; 房间广播

(defun broadcast-to-room (room-id message &optional exclude-user-id)
  "广播消息到房间所有成员

   Parameters:
     room-id        - 房间 ID
     message        - 消息（plist 或 JSON 字符串）
     exclude-user-id - 排除的用户 ID（可选）

   参考 Fiora 的 socket.to(roomId).emit() 模式"
  (declare (type room-id room-id)
           (type (or string list vector) message))
  (let ((room (gethash room-id *rooms*)))
    (unless room
      (log-warn "Broadcast failed: room ~a not found" room-id)
      (return-from broadcast-to-room nil))
    (let ((count 0))
      (maphash (lambda (user-id membership)
                 (declare (ignore membership))
                 (unless (and exclude-user-id
                              (string= user-id exclude-user-id))
                   (broadcast-to-user user-id message)
                   (incf count)))
               (room-members room))
      (log-debug "Broadcast to room ~a: ~a members" room-id count)
      count)))

(defun broadcast-to-room-except-sender (room-id message sender-id)
  "广播消息到房间（排除发送者）"
  (declare (type room-id room-id)
           (type string sender-id)
           (type (or string list vector) message))
  (broadcast-to-room room-id message sender-id))

;;;; 在线状态

(defun get-room-online-members (room-id)
  "获取房间在线成员列表

   参考 Fiora 的 getGroupOnlineMembers 实现"
  (declare (type room-id room-id))
  (let ((room (gethash room-id *rooms*)))
    (unless room
      (return-from get-room-online-members nil))
    (let ((online nil))
      (maphash (lambda (user-id membership)
                 (declare (ignore membership))
                 (let ((conns (get-user-connections user-id)))
                   (when conns
                     (push user-id online))))
               (room-members room))
      online)))

(defun get-room-online-count (room-id)
  "获取房间在线成员数量"
  (declare (type room-id room-id))
  (length (get-room-online-members room-id)))

;;;; 房间缓存（参考 Fiora 性能优化）

(defvar *room-online-cache* (make-hash-table :test 'equal)
  "房间在线缓存：room-id -> (key value expire-time)")

(defvar *room-online-cache-expire* 60
  "房间在线缓存过期时间（秒）
   参考 Fiora 的 GroupOnlineMembersCacheExpireTime = 1000 * 60")

(defun get-room-online-members-cached (room-id &optional cache-key)
  "获取房间在线成员（带缓存）

   参考 Fiora 的 getGroupOnlineMembersWrapperV2 实现

   Parameters:
     room-id   - 房间 ID
     cache-key - 可选缓存键，如果匹配则返回空结果（无变化）

   Returns:
     (values members new-cache-key)"
  (declare (type room-id room-id))
  (let ((cached (gethash room-id *room-online-cache*)))
    (if (and cached
             cache-key
             (string= cache-key (getf cached :key))
             (> (getf cached :expire-time) (get-universal-time)))
        ;; 缓存命中且无变化
        (values nil cache-key)
        ;; 需要刷新
        (let ((members (get-room-online-members room-id)))
          (let ((new-key (format nil "~x"
                                 (sxhash (format nil "~{~a~}" (sort (copy-list members) #'string<))))))
            (if (and cached (string= new-key (getf cached :key)))
                ;; 数据无变化，只刷新过期时间
                (progn
                  (setf (getf (gethash room-id *room-online-cache*) :expire-time)
                        (+ (get-universal-time) *room-online-cache-expire*))
                  (values nil cache-key))
                ;; 数据有变化
                (progn
                  (setf (gethash room-id *room-online-cache*)
                        (list :key new-key
                              :members members
                              :expire-time (+ (get-universal-time) *room-online-cache-expire*)))
                  (values members new-key))))))))

;;;; 房间权限

(defun can-send-message-p (room-id user-id)
  "检查用户是否可以在房间发送消息"
  (declare (type room-id room-id)
           (type string user-id))
  (let ((room (gethash room-id *rooms*)))
    (unless room
      (return-from can-send-message-p nil))
    (let ((membership (gethash user-id (room-members room))))
      (unless membership
        (return-from can-send-message-p nil))
      ;; 检查是否被禁言
      (if (room-membership-muted-p membership)
          nil
          t))))

(defun can-kick-member-p (room-id operator-id target-id)
  "检查是否可以踢出成员"
  (declare (type room-id room-id)
           (type string operator-id target-id))
  (let ((room (gethash room-id *rooms*)))
    (unless room
      (return-from can-kick-member-p nil))
    (let ((operator-role (get-user-room-role room-id operator-id))
          (target-role (get-user-room-role room-id target-id)))
      ;; 只有 owner 和 admin 可以踢人
      (unless (member operator-role '(:owner :admin))
        (return-from can-kick-member-p nil))
      ;; 不能踢比自己角色大的
      (let ((operator-level (cdr (assoc operator-role *room-roles*)))
            (target-level (cdr (assoc target-role *room-roles*))))
        (and operator-level target-level
             (> operator-level target-level))))))

(defparameter *room-roles*
  '((:owner . 100)
    (:admin . 50)
    (:member . 10)
    (:guest . 1))
  "房间角色权限等级")

;;;; 临时房间

(defun create-temporary-room (&key (prefix "temp-"))
  "创建临时房间（自动过期）"
  (let ((room-id (format nil "~a~a-~a" prefix (get-universal-time) (random 10000))))
    (create-room room-id :type :temporary)
    (log-info "Temporary room created: ~a" room-id)
    room-id))

(defun temporary-room-p (room-id)
  "检查是否是临时房间"
  (let ((room (gethash room-id *rooms*)))
    (when room
      (eq (room-type room) :temporary))))

;;;; 房间统计

(defun get-room-stats ()
  "获取房间统计信息"
  (let ((total (hash-table-count *rooms*))
        (temporary 0)
        (group 0)
        (channel 0)
        (user 0))
    (maphash (lambda (id room)
               (declare (ignore id))
               (case (room-type room)
                 (:temporary (incf temporary))
                 (:group (incf group))
                 (:channel (incf channel))
                 (:user (incf user))
                 (:system nil)))
             *rooms*)
    (list :total total
          :created *rooms-created-counter*
          :active-gauge *rooms-active-gauge*
          :by-type (list :temporary temporary
                         :group group
                         :channel channel
                         :user user))))

;;;; 房间清理

(defun cleanup-temporary-rooms ()
  "清理临时房间（可定时调用）"
  (let ((to-remove nil))
    (maphash (lambda (id room)
               (when (eq (room-type room) :temporary)
                 ;; 临时房间 1 小时后自动清理
                 (when (> (- (get-universal-time) (room-created-at room)) 3600)
                   (push id to-remove))))
             *rooms*)
    (dolist (id to-remove)
      (destroy-room id))
    (when to-remove
      (log-info "Cleaned up ~a temporary rooms" (length to-remove)))))

;;;; 导出公共 API
;;;; (Symbols are exported via package.lisp)
