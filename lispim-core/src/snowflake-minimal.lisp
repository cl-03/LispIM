;;;; snowflake.lisp - 分布式 ID 生成器

(in-package :lispim-core)

;;;; Snowflake 配置

;; Global variables - using defparameter for reliable initialization
(defparameter *snowflake-datacenter-id* 0)
(defparameter *snowflake-worker-id* 0)
(defparameter *snowflake-sequence* 0)
(defparameter *snowflake-last-timestamp* -1)
(defparameter *snowflake-lock* nil)
(defparameter *snowflake-epoch* (+ 1735689600 2208988800)
  "自定义纪元 (2025-01-01 00:00:00 UTC in Lisp universal time)")

;; Initialize lock at load time
(setf *snowflake-lock* (bordeaux-threads:make-lock "snowflake-lock"))

;; Constants
(defparameter +sequence-bits+ 12)
(defparameter +max-sequence+ (ash 1 +sequence-bits+))
(defparameter +sequence-mask+ (1- (ash 1 +sequence-bits+)))

(defun get-epoch-ms ()
  "获取从自定义纪元开始的毫秒数"
  (let* ((now (get-universal-time))
         (epoch-ms (* (- now *snowflake-epoch*) 1000)))
    epoch-ms))

(defun wait-next-millis (last-timestamp)
  "等待到下一毫秒"
  (loop
    (let ((ts (get-epoch-ms)))
      (when (> ts last-timestamp)
        (return ts)))
    (sleep 0.001)))

(defun generate-snowflake-id (&optional (datacenter-id *snowflake-datacenter-id*)
                                        (worker-id *snowflake-worker-id*))
  "生成 Snowflake ID"
  (bordeaux-threads:with-lock-held (*snowflake-lock*)
    (let ((timestamp (get-epoch-ms)))
      ;; Check clock rollback
      (when (< timestamp *snowflake-last-timestamp*)
        (error "Clock moved backwards"))

      ;; Handle sequence within same millisecond
      (if (= timestamp *snowflake-last-timestamp*)
          (setf *snowflake-sequence* (logand (1+ *snowflake-sequence*) +sequence-mask+))
          (setf *snowflake-sequence* 0))

      ;; Wait for next ms if sequence overflows
      (when (zerop *snowflake-sequence*)
        (setf timestamp (wait-next-millis timestamp)))

      (setf *snowflake-last-timestamp* timestamp)

      ;; Generate ID
      (logior (ash timestamp (+ 5 5 +sequence-bits+))
              (ash datacenter-id (+ 5 +sequence-bits+))
              (ash worker-id +sequence-bits+)
              (logand *snowflake-sequence* +sequence-mask+)))))

(defun reset-snowflake ()
  "Reset Snowflake generator"
  (setf *snowflake-sequence* 0
        *snowflake-last-timestamp* -1))
