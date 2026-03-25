;;;; snowflake.lisp - 分布式 ID 生成器
;;;;
;;;; 使用 Snowflake 算法生成全局唯一、有序 ID

(in-package :lispim-core)

;;;; Snowflake 配置

;; Snowflake 结构：timestamp(41) + datacenter(5) + machine(5) + sequence(12) = 64 bits

;; Define variables with provable initial values
;; Using defparameter to ensure they're always initialized
(defparameter *snowflake-datacenter-id* 0)
(defparameter *snowflake-worker-id* 0)
(defparameter *snowflake-sequence* 0)
(defparameter *snowflake-last-timestamp* -1)
(defparameter *snowflake-lock* nil)
(defparameter *snowflake-epoch* 1735689600)

;; Initialize lock at load time
(setf *snowflake-lock* (bordeaux-threads:make-lock "snowflake-lock"))
