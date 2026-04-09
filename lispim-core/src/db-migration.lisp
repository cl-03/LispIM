;;;; db-migration.lisp - Database Migration System
;;;;
;;;; 负责数据库模式版本控制和迁移管理

(in-package :lispim-core)

;;;; 依赖声明

(eval-when (:compile-toplevel :load-toplevel :execute)
  (ql:quickload '(:postmodern :cl-fad :cl-ppcre :ironclad :babel :alexandria)))

;;;; 迁移表结构

(defvar *migrations-table* "schema_migrations"
  "存储已应用迁移的表名")

;;;; 类型定义

(deftype migration-version ()
  'integer)

;;;; 迁移状态

(defvar *current-migration-version* 0
  "当前数据库模式版本")

(defvar *migrations-dir* nil
  "迁移文件目录")

;;;; 初始化

(defun init-migration-system (&optional (migrations-dir nil))
  "初始化迁移系统"
  ;; 如果未指定目录，使用当前文件所在目录的 migrations/子目录
  (let ((base-dir (or *load-pathname* *default-pathname-defaults*)))
    (setf *migrations-dir* (or migrations-dir (merge-pathnames "migrations/" base-dir))))
  (ensure-migrations-table)
  (setf *current-migration-version* (get-current-version))
  (log-info "Migration system initialized, current version: ~a" *current-migration-version*))

(defun ensure-migrations-table ()
  "创建迁移表（如果不存在）"
  (postmodern:execute
   (format nil "CREATE TABLE IF NOT EXISTS ~a (
      version BIGINT PRIMARY KEY,
      applied_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
      checksum VARCHAR(64),
      description TEXT
    )" *migrations-table*)))

(defun get-current-version ()
  "获取当前数据库版本"
  (let ((result (postmodern:query (format nil "SELECT MAX(version) FROM ~a" *migrations-table*))))
    (or (caar result) 0)))

;;;; 迁移文件发现

(defun discover-migrations ()
  "发现所有可用的迁移文件"
  (let ((migrations nil))
    (when (and *migrations-dir* (probe-file *migrations-dir*))
      (dolist (file (directory (merge-pathnames "*.up.sql" *migrations-dir*)))
        (let* ((filename (file-namestring file))
               (match (multiple-value-list (cl-ppcre:scan-to-strings "^([0-9]+)-.*\\.up\\.sql$" filename))))
          (when (and match (> (length match) 0))
            (let ((version (parse-integer (aref (nth 0 match) 0))))
              (push (list :version version
                          :file file
                          :name (pathname-name filename))
                    migrations))))))
    ;; 按版本号排序
    (setf migrations (sort migrations #'< :key (lambda (x) (getf x :version))))
    migrations))

(defun get-pending-migrations ()
  "获取待应用的迁移"
  (let ((current (get-current-version))
        (all-migrations (discover-migrations)))
    (remove-if (lambda (m) (<= (getf m :version) current)) all-migrations)))

;;;; 迁移执行

(defun apply-migration (migration)
  "应用单个迁移"
  (let* ((version (getf migration :version))
         (file (getf migration :file))
         (sql (alexandria:read-file-into-string file))
         (digest (ironclad:make-digest :sha256))
         (checksum (with-output-to-string (out)
                     (loop for byte across (ironclad:digest-sequence digest (babel:string-to-octets sql))
                       do (format out "~2,'0x" byte))))
         (description (extract-migration-description sql)))

    (log-info "Applying migration ~a: ~a" version (getf migration :name))

    ;; 在事务中执行
    (postmodern:with-transaction ()
      ;; 执行迁移 SQL
      (postmodern:execute sql)

      ;; 记录迁移
      (postmodern:query
       (format nil "INSERT INTO ~a (version, checksum, description) VALUES ($1, $2, $3)"
               *migrations-table*)
       version checksum description))

    (log-info "Migration ~a applied successfully" version)
    t))

(defun rollback-migration (version)
  "回滚单个迁移"
  (let* ((migration (find-migration version))
         (down-file (when migration
                      (make-down-file-path (getf migration :file)))))

    (unless (and down-file (probe-file down-file))
      (error "No rollback script found for version ~a" version))

    (let ((sql (alexandria:read-file-into-string down-file)))
      (log-info "Rolling back migration ~a" version)

      (postmodern:with-transaction ()
        ;; 执行回滚 SQL
        (postmodern:execute sql)

        ;; 删除迁移记录
        (postmodern:query
         (format nil "DELETE FROM ~a WHERE version = $1" *migrations-table*)
         version))

      (log-info "Migration ~a rolled back successfully" version)
      t)))

(defun find-migration (version)
  "查找指定版本的迁移"
  (find-if (lambda (m) (= (getf m :version) version))
           (discover-migrations)))

(defun make-down-file-path (up-file)
  "从 up 文件路径生成 down 文件路径"
  (let* ((name (pathname-name up-file))
         (dir (pathname-directory up-file))
         (down-name (substitute-if #\d (lambda (c) (char= c #\u)) name)))
    (make-pathname :directory dir :name down-name :type "sql")))

(defun extract-migration-description (sql)
  "从 SQL 中提取迁移描述"
  (multiple-value-bind (match-start match-end reg-starts reg-ends)
      (cl-ppcre:scan "^-- Description: \\(.*\\)" sql)
    (if match-start
        (subseq sql (svref reg-starts 0) (svref reg-ends 0))
        "")))

;;;; 公共 API

(defun migrate (&key (target-version nil))
  "执行数据库迁移

   :target-version - 目标版本号（NIL 表示迁移到最新）"
  (let ((pending (get-pending-migrations)))
    (unless pending
      (log-info "Database is up to date")
      (return-from migrate nil))

    (when target-version
      (setf pending (remove-if (lambda (m) (> (getf m :version) target-version)) pending)))

    (dolist (migration pending)
      (apply-migration migration))

    (log-info "All migrations applied successfully")
    t))

(defun rollback (&optional (steps 1))
  "回滚数据库迁移

   :steps - 回滚的步数"
  (let ((current (get-current-version)))
    (when (zerop current)
      (log-info "Nothing to rollback")
      (return-from rollback nil))

    (let ((versions-to-rollback nil))
      (dotimes (i steps)
        (let ((v (- current i)))
          (when (>= v 0)
            (push v versions-to-rollback))))

      (dolist (version versions-to-rollback)
        (rollback-migration version))

      (log-info "Rolled back ~a migrations" (length versions-to-rollback))
      t)))

(defun migration-status ()
  "显示迁移状态"
  (let ((current (get-current-version))
        (all (discover-migrations)))
    (format t "Current database version: ~a~%" current)
    (format t "~%Available migrations:~%")
    (dolist (m all)
      (let ((v (getf m :version)))
        (format t "  [~a] ~a ~a~%"
                (if (<= v current) "X" " ")
                v
                (getf m :name))))))

;;;; 导出

(export '(init-migration-system
          migrate
          rollback
          migration-status
          get-current-version
          apply-migration
          rollback-migration)
        :lispim-core)
