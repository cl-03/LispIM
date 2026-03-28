;;;; db-replica.lisp - 数据库读写分离模块
;;;;
;;;; 实现主从数据库配置，读写自动路由
;;;; 支持 1 主多从，从库轮询
;;;;
;;;; 架构：
;;;; - 写操作：主库
;;;; - 读操作：从库（轮询）
;;;; - 健康检查：自动剔除故障从库
;;;; - 故障转移：从库全部故障时降级到主库
;;;;
;;;; 参考：
;;;; - PostgreSQL 流复制
;;;; - MySQL 主从复制

(in-package :lispim-core)

;;;; 依赖声明

(eval-when (:compile-toplevel :load-toplevel :execute)
  (ql:quickload '(:postmodern :cl-redis :bordeaux-threads)))

;;;; 配置

(defparameter *db-replica-config*
  '((:master (:host . "localhost")
             (:port . 5432)
             (:database . "lispim")
             (:user . "lispim")
             (:password . "Clsper03"))
    (:slaves :connections
             ((:host . "localhost")
              (:port . 5433)
              (:database . "lispim")
              (:user . "lispim")
              (:password . "Clsper03"))
             ((:host . "localhost")
              (:port . 5434)
              (:database . "lispim")
              (:user . "lispim")
              (:password . "Clsper03")))
    (:health-check-interval . 30)    ; 健康检查间隔（秒）
    (:health-check-timeout . 5)      ; 健康检查超时（秒）
    (:failover-threshold . 3)        ; 故障转移阈值
    (:use-read-from-master . nil))   ; 是否允许从主库读取（从库故障时）
  "数据库读写分离配置")

;;;; 类型定义

(defstruct db-replica
  "数据库读写分离实例"
  (master nil)
  (slaves nil :type list)
  (slave-index 0 :type integer)
  (health-check-interval 30 :type integer)
  (health-check-timeout 5 :type integer)
  (failover-threshold 3 :type integer)
  (use-read-from-master nil :type boolean)
  (read-count 0 :type integer)
  (write-count 0 :type integer)
  (failover-count 0 :type integer)
  (lock (bordeaux-threads:make-lock "db-replica-lock")))

(defstruct slave-connection
  "从库连接"
  (connection nil)
  (host "" :type string)
  (port 0 :type integer)
  (database "" :type string)
  (user "" :type string)
  (password "" :type string)
  (healthy-p t :type boolean)
  (fail-count 0 :type integer)
  (last-check 0 :type integer))

;;;; 初始化

(defun init-db-replica (&key master-host master-port master-database master-user master-password
                              slaves-config health-check-interval health-check-timeout
                              failover-threshold use-read-from-master)
  "初始化数据库读写分离"
  (let* ((master-cfg (or (cdr (assoc :master *db-replica-config*))
                         `((:host . ,master-host)
                           (:port . ,master-port)
                           (:database . ,master-database)
                           (:user . ,master-user)
                           (:password . ,master-password))))
         (slaves-cfg (or (cdr (assoc :slaves *db-replica-config*)) slaves-config))
         (replica (make-db-replica
                   :master nil
                   :slaves nil
                   :slave-index 0
                   :health-check-interval (or health-check-interval
                                              (cdr (assoc :health-check-interval *db-replica-config*))
                                              30)
                   :health-check-timeout (or health-check-timeout
                                             (cdr (assoc :health-check-timeout *db-replica-config*))
                                             5)
                   :failover-threshold (or failover-threshold
                                           (cdr (assoc :failover-threshold *db-replica-config*))
                                           3)
                   :use-read-from-master (or use-read-from-master
                                             (cdr (assoc :use-read-from-master *db-replica-config*))
                                             nil))))

    ;; 连接主库
    (setf (db-replica-master replica)
          (connect-to-database
           (cdr (assoc :host master-cfg))
           (cdr (assoc :port master-cfg))
           (cdr (assoc :database master-cfg))
           (cdr (assoc :user master-cfg))
           (cdr (assoc :password master-cfg))))

    ;; 连接从库
    (when slaves-cfg
      (let ((slave-connections (cdr slaves-cfg)))
        (setf (db-replica-slaves replica)
              (loop for cfg in slave-connections
                    collect (make-slave-connection
                             :connection (connect-to-database
                                          (cdr (assoc :host cfg))
                                          (cdr (assoc :port cfg))
                                          (cdr (assoc :database cfg))
                                          (cdr (assoc :user cfg))
                                          (cdr (assoc :password cfg)))
                             :host (cdr (assoc :host cfg))
                             :port (cdr (assoc :port cfg))
                             :database (cdr (assoc :database cfg))
                             :user (cdr (assoc :user cfg))
                             :password (cdr (assoc :password cfg))
                             :healthy-p t
                             :fail-count 0
                             :last-check (get-universal-time)))))))

    (log-info "DB replica initialized: master=~a:~a, ~a slaves"
              (cdr (assoc :host master-cfg))
              (cdr (assoc :port master-cfg))
              (length (db-replica-slaves replica)))
    replica)

(defun connect-to-database (host port database user password)
  "连接到数据库"
  (let ((conn (postmodern:connect-toplevel
               :hostname host
               :port port
               :database database
               :user user
               :password password
               :pool-size 1)))
    (log-debug "Connected to database ~a@~a:~a" user host port)
    conn))

;;;; 全局实例

(defvar *db-replica* nil
  "全局数据库读写分离实例")

;;;; 读写路由

(defmacro with-master-db (&body body)
  "使用主库执行写操作"
  `(let ((conn (get-master-connection *db-replica*)))
     (when conn
       (incf (db-replica-write-count *db-replica*))
       (postmodern:with-connection conn
         ,@body))))

(defmacro with-slave-db (&body body)
  "使用从库执行读操作"
  `(let ((conn (get-slave-connection *db-replica*)))
     (when conn
       (incf (db-replica-read-count *db-replica*))
       (postmodern:with-connection conn
         ,@body))))

(defun get-master-connection (replica)
  "获取主库连接"
  (declare (type db-replica replica))
  (db-replica-master replica))

(defun get-slave-connection (replica)
  "获取从库连接（轮询）"
  (declare (type db-replica replica))
  (bordeaux-threads:with-lock-held ((db-replica-lock replica))
    (let* ((slaves (db-replica-slaves replica))
           (healthy-slaves (remove-if-not #'slave-connection-healthy-p slaves)))

      (cond
        ;; 有健康从库，轮询
        ((and healthy-slaves (> (length healthy-slaves) 0))
         (let* ((index (mod (db-replica-slave-index replica) (length healthy-slaves)))
                (slave (nth index healthy-slaves)))
           (incf (db-replica-slave-index replica))
           (slave-connection-connection slave)))

        ;; 无健康从库，是否允许主库读取
        ((db-replica-use-read-from-master replica)
         (incf (db-replica-failover-count replica))
         (log-warning "All slaves unhealthy, failing over to master")
         (db-replica-master replica))

        (t
         (log-error "No healthy database available")
         nil)))))

;;;; 查询执行

(defun db-write (query &rest args)
  "执行写操作"
  (apply 'postmodern:query query args))

(defun db-read (query &rest args)
  "执行读操作"
  (apply 'postmodern:query query args))

;;;; 健康检查

(defun start-health-check-worker (replica)
  "启动健康检查工作线程"
  (declare (type db-replica replica))
  (bordeaux-threads:make-thread
   (lambda ()
     (loop while t
           do (progn
                (check-slave-health replica)
                (sleep (db-replica-health-check-interval replica)))))
   :name "db-replica-health-check"))

(defun check-slave-health (replica)
  "检查从库健康状态"
  (declare (type db-replica replica))
  (dolist (slave (db-replica-slaves replica))
    (let ((healthy (check-single-slave slave (db-replica-health-check-timeout replica))))
      (unless healthy
        (incf (slave-connection-fail-count slave))
        (when (>= (slave-connection-fail-count slave)
                  (db-replica-failover-threshold replica))
          (setf (slave-connection-healthy-p slave) nil)
          (log-error "Slave ~a:~a marked as unhealthy"
                     (slave-connection-host slave)
                     (slave-connection-port slave))))
      (setf (slave-connection-last-check slave) (get-universal-time)))))

(defun check-single-slave (slave timeout)
  "检查单个从库健康"
  (declare (type slave-connection slave)
           (type integer timeout))
  (handler-case
      (progn
        ;; 简单健康检查：执行 SELECT 1
        (postmodern:with-connection (slave-connection-connection slave)
          (postmodern:query "SELECT 1"))
        ;; 重置失败计数
        (setf (slave-connection-fail-count slave) 0)
        t)
    (error (c)
      (log-warning "Slave health check failed: ~a" c)
      nil)))

;;;; 故障恢复

(defun recover-slave (replica host port)
  "尝试恢复故障从库"
  (declare (type db-replica replica)
           (type string host port))
  (let ((slave (find-if (lambda (s)
                          (and (string= (slave-connection-host s) host)
                               (= (slave-connection-port s) port)))
                        (db-replica-slaves replica))))
    (when slave
      (handler-case
          (progn
            ;; 重新连接
            (setf (slave-connection-connection slave)
                  (connect-to-database (slave-connection-host slave)
                                       (slave-connection-port slave)
                                       (slave-connection-database slave)
                                       (slave-connection-user slave)
                                       (slave-connection-password slave)))
            ;; 健康检查
            (when (check-single-slave slave (db-replica-health-check-timeout replica))
              (setf (slave-connection-healthy-p slave) t)
              (setf (slave-connection-fail-count slave) 0)
              (log-info "Slave ~a:~a recovered" host port)
              t))
        (error (c)
          (log-error "Failed to recover slave ~a:~a: ~a" host port c)
          nil)))))

;;;; 统计

(defun get-db-replica-stats (replica)
  "获取数据库读写分离统计"
  (declare (type db-replica replica))
  (list :master-connected (if (db-replica-master replica) t nil)
        :slave-count (length (db-replica-slaves replica))
        :healthy-slave-count (length (remove-if-not #'slave-connection-healthy-p
                                                     (db-replica-slaves replica)))
        :read-count (db-replica-read-count replica)
        :write-count (db-replica-write-count replica)
        :failover-count (db-replica-failover-count replica)
        :slave-index (db-replica-slave-index replica)))

;;;; 高层 API

(defun db-init-replica (&key master-host master-port master-database master-user master-password
                              slaves health-check-interval)
  "高层初始化 API"
  (setf *db-replica*
        (init-db-replica :master-host master-host
                         :master-port master-port
                         :master-database master-database
                         :master-user master-user
                         :master-password master-password
                         :slaves-config slaves
                         :health-check-interval health-check-interval)))

(defun db-write-row (table columns values &key (returning nil))
  "高层写操作 API"
  (let ((query (format nil "INSERT INTO ~a (~{~a~^, ~}) VALUES (~{~a~^, ~})~@[ RETURNING ~a~]"
                       table columns
                       (mapcar (lambda (v) (typecase v
                                            (string (format nil "'~a'" v))
                                            (null "NULL")
                                            (otherwise (format nil "~a" v))))
                               values)
                       returning)))
    (with-master-db
      (db-write query))))

(defun db-read-row (table columns &key (where nil) (limit 1))
  "高层读操作 API"
  (let ((query (format nil "SELECT ~{~a~^, ~} FROM ~a~@[ WHERE ~a~]~@[ LIMIT ~a~]"
                       columns table where limit)))
    (with-slave-db
      (db-read query))))

(defun db-update-row (table columns values where &key (returning nil))
  "高层更新操作 API"
  (let ((set-clause (loop for col in columns
                          for val in values
                          collect (format nil "~a = '~a'" col val)))
        (query nil))
    (setf query (format nil "UPDATE ~a SET ~{~a~^, ~} WHERE ~a~@[ RETURNING ~a~]"
                        table set-clause where returning))
    (with-master-db
      (db-write query))))

(defun db-delete-row (table where)
  "高层删除操作 API"
  (let ((query (format nil "DELETE FROM ~a WHERE ~a" table where)))
    (with-master-db
      (db-write query))))

;;;; 清理

(defun shutdown-db-replica (replica)
  "关闭数据库读写分离"
  (declare (type db-replica replica))
  ;; 关闭主库连接
  (when (db-replica-master replica)
    (postmodern:disconnect-toplevel (db-replica-master replica))
    (log-info "Master database connection closed"))
  ;; 关闭从库连接
  (dolist (slave (db-replica-slaves replica))
    (when (slave-connection-connection slave)
      (postmodern:disconnect-toplevel (slave-connection-connection slave))))
  (log-info "All slave database connections closed")
  (log-info "DB replica shutdown complete"))

;;;; 导出

(export '(;; Initialization
          init-db-replica
          *db-replica*

          ;; Macros
          with-master-db
          with-slave-db

          ;; Connection access
          get-master-connection
          get-slave-connection

          ;; Query execution
          db-write
          db-read

          ;; Health check
          start-health-check-worker
          check-slave-health
          recover-slave

          ;; Statistics
          get-db-replica-stats

          ;; High-level API
          db-init-replica
          db-write-row
          db-read-row
          db-update-row
          db-delete-row

          ;; Cleanup
          shutdown-db-replica)
        :lispim-core)
