;;;; online-cache.lisp - 在线用户缓存优化
;;;;
;;;; 参考 Fiora 的 GroupOnlineMembersCache 设计
;;;; 使用多级缓存减少数据库查询
;;;;
;;;; 设计原则：
;;;; - 纯 Common Lisp 实现
;;;; - 基于 Redis 的分布式缓存
;;;; - 支持缓存失效和刷新

(in-package :lispim-core)

;;;; 依赖声明

(eval-when (:compile-toplevel :load-toplevel :execute)
  (ql:quickload '(:bordeaux-threads :cl-redis :cl-json)))

;;;; 类型定义

(deftype cache-key ()
  "缓存键类型"
  'string)

;; 缓存条目类型（不再使用 deftype，直接使用 list 描述）
;; cache-entry 是一个列表：(list cache-key members expire-time)

;;;; 在线缓存配置

(defparameter *online-cache-config*
  '((:expire-time . 60)        ; 缓存过期时间（秒）
    (:max-entries . 10000)     ; 最大缓存条目数
    (:cleanup-interval . 300)) ; 清理间隔（秒）
  "在线缓存配置")

;;;; 在线缓存结构

(defstruct online-cache
  "在线用户缓存
   参考 Fiora 的 GroupOnlineMembersCacheExpireTime 设计"
  (entries (make-hash-table :test 'equal) :type hash-table)
  (lock (bordeaux-threads:make-lock "online-cache-lock"))
  (hits 0 :type integer)
  (misses 0 :type integer)
  (updates 0 :type integer))

;;;; 全局缓存实例

(defvar *online-cache* (make-online-cache)
  "全局在线用户缓存")

(defvar *online-cache-worker* nil
  "缓存清理工作线程")

(defvar *online-cache-running* nil
  "缓存清理线程运行标志")

;;;; 缓存操作

(defun online-cache-get (room-id)
  "获取房间在线缓存

   Parameters:
     room-id - 房间 ID

   Returns:
     (values members cache-key expire-time)"
  (declare (type string room-id))
  (let ((cache *online-cache*))
    (bordeaux-threads:with-lock-held ((online-cache-lock cache))
      (let ((entry (gethash room-id (online-cache-entries cache))))
        (when entry
          (let ((key (first entry))
                (members (second entry))
                (expire (third entry)))
            (when (> expire (get-universal-time))
              (incf (online-cache-hits cache))
              (values members key expire)))))))

(defun online-cache-put (room-id members cache-key)
  "设置房间在线缓存

   Parameters:
     room-id   - 房间 ID
     members   - 在线成员列表
     cache-key - 缓存键（用于检测变化）

   Returns:
     t"
  (declare (type string room-id)
           (type list members)
           (type (or null cache-key) cache-key))
  (let ((cache *online-cache*))
    (bordeaux-threads:with-lock-held ((online-cache-lock cache))
      (setf (gethash room-id (online-cache-entries cache))
            (list cache-key
                  members
                  (+ (get-universal-time)
                     (cdr (assoc :expire-time *online-cache-config*)))))
      (incf (online-cache-updates cache))
      (log-debug "Online cache put: ~a (~a members)" room-id (length members)))
    t))

(defun online-cache-invalidate (room-id)
  "使房间缓存失效"
  (declare (type string room-id))
  (let ((cache *online-cache*))
    (bordeaux-threads:with-lock-held ((online-cache-lock cache))
      (remhash room-id (online-cache-entries cache)))
    (log-debug "Online cache invalidated: ~a" room-id)))

(defun online-cache-clear ()
  "清空所有缓存"
  (let ((cache *online-cache*))
    (bordeaux-threads:with-lock-held ((online-cache-lock cache))
      (clrhash (online-cache-entries cache)))
    (log-info "Online cache cleared")))

;;;; 辅助函数

(defun string-hash (str)
  "计算字符串哈希值"
  (declare (type string str))
  (sxhash str))

(defun compute-members-cache-key (members)
  "计算成员列表的缓存键

   通过成员列表的哈希值判断是否发生变化"
  (declare (type list members))
  (let ((sorted (sort (copy-list members) #'string<)))
    (write-to-string (string-hash (format nil "~{~a~^,~}" sorted)))))

;;;; 带缓存的在线查询（参考 Fiora）

(defun get-room-online-members-wrapper (room-id &optional cache-key)
  "获取房间在线成员（带缓存）

   参考 Fiora 的 getGroupOnlineMembersWrapperV2 实现

   Parameters:
     room-id   - 房间 ID
     cache-key - 可选缓存键，如果匹配则返回空（无变化）

   Returns:
     (values members new-cache-key)
     - members 为 nil 且 new-cache-key 等于 cache-key 表示无变化
     - members 为非 nil 表示有新数据"
  (declare (type string room-id))

  ;; 1. 检查缓存
  (multiple-value-bind (cached-members cached-key cached-expire)
      (online-cache-get room-id)
    (if (and cached-key
             cache-key
             (string= cached-key cache-key)
             (> cached-expire (get-universal-time)))
        ;; 缓存命中且无变化
        (progn
          (log-debug "Cache hit (unchanged): ~a" room-id)
          (values nil cache-key))
        ;; 需要刷新
        (let* ((members (get-room-online-members room-id))
               (new-key (compute-members-cache-key members)))
          ;; 检查缓存是否仍然有效（数据无变化）
          (if (and cached-key (string= new-key cached-key))
              ;; 数据无变化，只刷新过期时间
              (progn
                (online-cache-put room-id members new-key)
                (values nil cache-key))
              ;; 数据有变化
              (progn
                (online-cache-put room-id members new-key)
                (values members new-key))))))))

;;;; Redis 缓存（分布式场景）

(defun redis-get-online-cache (room-id)
  "从 Redis 获取在线缓存

   用于多实例部署场景"
  (declare (type string room-id))
  (when (and *redis-connected*)
    (handler-case
        (let ((key (format nil "online:~a" room-id)))
          (let ((data (redis:red-get key)))
            (when data
              (let ((decoded (cl-json:decode-json-from-string data)))
                (list :members (getf decoded :members)
                      :key (getf decoded :key)
                      :expire (getf decoded :expire))))))
      (error (c)
        (log-error "Redis get online cache failed: ~a" c)
        nil))))

(defun redis-set-online-cache (room-id members cache-key expire-seconds)
  "设置 Redis 在线缓存"
  (declare (type string room-id)
           (type list members)
           (type (or null cache-key) cache-key)
           (type integer expire-seconds))
  (when (and *redis-connected*)
    (handler-case
        (let ((key (format nil "online:~a" room-id))
              (data (cl-json:encode-json-to-string
                     (list :members members
                           :key cache-key
                           :expire (+ (get-universal-time) expire-seconds)))))
          (redis:red-setex key expire-seconds data))
      (error (c)
        (log-error "Redis set online cache failed: ~a" c)))))

;;;; 清理工作线程

(defun start-online-cache-cleanup ()
  "启动缓存清理工作线程"
  (unless *online-cache-running*
    (setf *online-cache-running* t)
    (setf *online-cache-worker*
          (bordeaux-threads:make-thread
           (lambda ()
             (log-info "Online cache cleanup worker started")
             (loop while *online-cache-running*
                   do (sleep (cdr (assoc :cleanup-interval *online-cache-config*)))
                   do (cleanup-expired-cache)))))))

(defun stop-online-cache-cleanup ()
  "停止缓存清理工作线程"
  (setf *online-cache-running* nil)
  (when *online-cache-worker*
    (bordeaux-threads:destroy-thread *online-cache-worker*)
    (setf *online-cache-worker* nil))
  (log-info "Online cache cleanup worker stopped"))

(defun cleanup-expired-cache ()
  "清理过期的缓存条目"
  (let ((cache *online-cache*)
        (now (get-universal-time))
        (count 0))
    (with-lock-held ((online-cache-lock cache))
      (do-hash (room-id entry (online-cache-entries cache))
        (declare (ignore room-id))
        (when (<= (third entry) now)
          (remhash room-id (online-cache-entries cache))
          (incf count))))
    (when (> count 0)
      (log-debug "Cleaned up ~a expired cache entries" count))))

;;;; 统计

(defun get-online-cache-stats ()
  "获取在线缓存统计"
  (let ((cache *online-cache*))
    (let ((entries (hash-table-count (online-cache-entries cache)))
          (hits (online-cache-hits cache))
          (misses (online-cache-misses cache))
          (updates (online-cache-updates cache)))
      (list :entries entries
            :hits hits
            :misses misses
            :updates updates
            :hit-rate (if (> (+ hits misses) 0)
                          (/ hits (+ hits misses))
                          0)))))

(defun reset-online-cache-stats ()
  "重置缓存统计"
  (let ((cache *online-cache*))
    (bordeaux-threads:with-lock-held ((online-cache-lock cache))
      (setf (online-cache-hits cache) 0
            (online-cache-misses cache) 0
            (online-cache-updates cache) 0))))

;;;; 内存管理

(defun shrink-online-cache (max-entries)
  "收缩缓存到指定大小（LRU 策略简化版）"
  (declare (type integer max-entries))
  (let ((cache *online-cache*))
    (bordeaux-threads:with-lock-held ((online-cache-lock cache))
      (let ((current (hash-table-count (online-cache-entries cache))))
        (when (> current max-entries)
          ;; 简单策略：清空一半
          (let ((to-remove (- current (/ max-entries 2)))
                (removed 0))
            (do-hash (room-id entry (online-cache-entries cache))
              (declare (ignore entry))
              (when (< removed to-remove)
                (remhash room-id (online-cache-entries cache))
                (incf removed)))
            (log-info "Shrunk online cache: ~a -> ~a"
                      current (hash-table-count (online-cache-entries cache)))))))))

;;;; 初始化

(defun init-online-cache (&key (max-entries 10000) (expire-time 60))
  "初始化在线缓存系统

   Parameters:
     max-entries  - 最大缓存条目数
     expire-time  - 过期时间（秒）"
  (setf (cdr (assoc :max-entries *online-cache-config*)) max-entries)
  (setf (cdr (assoc :expire-time *online-cache-config*)) expire-time)
  (start-online-cache-cleanup)
  (log-info "Online cache initialized: max=~a, expire=~as"
            max-entries expire-time))

;;;; 导出

(export '(;; Online cache operations
          get-online-users
          get-online-user-count
          is-user-online
          push-to-online-user
          get-user-connection
          get-room-online-users

          ;; Statistics
          get-online-cache-stats

          ;; Initialization
          init-online-cache
          start-online-cache-cleanup)
        :lispim-core)

;;;; End of online-cache.lisp
