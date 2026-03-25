;;;; snowflake.lisp - 分布式 ID 生成器
;;;;
;;;; 使用 Snowflake 算法生成全局唯一、有序 ID

(in-package :lispim-core)

;;;; Snowflake 配置 - 使用常量声明优化

;; 类型声明
(declaim (type (unsigned-byte 5) *snowflake-datacenter-id* *snowflake-worker-id*))
(declaim (type (unsigned-byte 12) *snowflake-sequence*))
(declaim (type (signed-byte 64) *snowflake-last-timestamp*))

;; Define variables - defparameter ensures value is always set
(defparameter *snowflake-datacenter-id* 0
  "数据中心 ID (0-31)")
(defparameter *snowflake-worker-id* 0
  "工作节点 ID (0-31)")
(defparameter *snowflake-sequence* 0
  "序列号 (0-4095)")
(defparameter *snowflake-last-timestamp* -1
  "最后时间戳（毫秒）")
(defparameter *snowflake-epoch-ms* nil
  "自定义纪元毫秒基准（用于测试时钟回拨）")
(defparameter *snowflake-lock* nil
  "Snowflake 生成锁")
(defparameter *snowflake-epoch* (+ 1735689600 2208988800)
  "自定义纪元 (2025-01-01 00:00:00 UTC in Lisp universal time)")

;; Initialize lock at load time - moved before use
(eval-when (:load-toplevel :execute)
  (setf *snowflake-lock* (bordeaux-threads:make-lock "snowflake-lock")))

;;;; 位掩码常量 - 使用 defconstant 优化

(defconstant +timestamp-bits+ 41)
(defconstant +datacenter-bits+ 5)
(defconstant +worker-bits+ 5)
(defconstant +sequence-bits+ 12)

(defconstant +max-sequence+ (ash 1 +sequence-bits+)) ; 4096
(defconstant +max-datacenter+ (ash 1 +datacenter-bits+)) ; 32
(defconstant +max-worker+ (ash 1 +worker-bits+)) ; 32

(defconstant +timestamp-mask+ (1- (ash 1 +timestamp-bits+)))
(defconstant +sequence-mask+ (1- (ash 1 +sequence-bits+)))
(defconstant +worker-shift+ +sequence-bits+)
(defconstant +datacenter-shift+ (+ +worker-bits+ +sequence-bits+))
(defconstant +timestamp-shift+ (+ +datacenter-bits+ +worker-bits+ +sequence-bits+))

;;;; Snowflake ID 生成 - 优化版本

(declaim (ftype (function () (unsigned-byte 64)) get-epoch-ms))
(declaim (inline get-epoch-ms))

(defun get-epoch-ms ()
  "获取从自定义纪元开始的毫秒数"
  (declare (optimize (speed 3) (safety 1)))
  (the (unsigned-byte 64)
    (* (- (get-universal-time) *snowflake-epoch*) 1000)))

(declaim (ftype (function ((unsigned-byte 64)) (unsigned-byte 64)) wait-next-millis))

(defun wait-next-millis (last-timestamp)
  "等待到下一毫秒"
  (declare (type (unsigned-byte 64) last-timestamp)
           (optimize (speed 3) (safety 1)))
  (loop
    (let ((ts (get-epoch-ms)))
      (when (> ts last-timestamp)
        (return (the (unsigned-byte 64) ts))))
    (sleep 0.001)))

(declaim (ftype (function (&optional (unsigned-byte 5) (unsigned-byte 5)) (unsigned-byte 64)) generate-snowflake-id))

(defun generate-snowflake-id (&optional (datacenter-id *snowflake-datacenter-id*)
                                        (worker-id *snowflake-worker-id*))
  "生成 Snowflake ID

   返回 64 位整数，结构：
   - 41 bits: 时间戳（毫秒）
   - 5 bits: 数据中心 ID
   - 5 bits: 工作节点 ID
   - 12 bits: 序列号"
  (declare (type (unsigned-byte 5) datacenter-id worker-id)
           (optimize (speed 3) (safety 1)))

  ;; 验证参数
  (when (>= datacenter-id +max-datacenter+)
    (error "Datacenter ID must be < ~a" +max-datacenter+))
  (when (>= worker-id +max-worker+)
    (error "Worker ID must be < ~a" +max-worker+))

  (bordeaux-threads:with-lock-held (*snowflake-lock*)
    (let ((timestamp (get-epoch-ms)))
      (declare (type (unsigned-byte 64) timestamp))

      ;; 检查时钟回拨
      (when (< timestamp *snowflake-last-timestamp*)
        (error 'lispim-error
               :message (format nil "Clock moved backwards: ~a < ~a"
                                timestamp *snowflake-last-timestamp)))

      ;; 处理同一毫秒内的序列号
      (if (= timestamp *snowflake-last-timestamp*)
          (setf *snowflake-sequence*
                (the (unsigned-byte 12) (logand (1+ *snowflake-sequence*) +sequence-mask+)))
          (setf *snowflake-sequence* 0))

      ;; 序列号溢出时等待下一毫秒
      (when (zerop *snowflake-sequence*)
        (setf timestamp (wait-next-millis timestamp)))

      (setf *snowflake-last-timestamp* timestamp)

      ;; 组合 ID
      (the (unsigned-byte 64)
        (logior (ash (logand timestamp +timestamp-mask+)
                     +timestamp-shift+)
                (ash datacenter-id +datacenter-shift+)
                (ash worker-id +worker-shift+)
                (logand *snowflake-sequence* +sequence-mask+))))))

;;;; 解析函数 - 优化版本

(declaim (ftype (function ((unsigned-byte 64)) (values (unsigned-byte 64) (unsigned-byte 5) (unsigned-byte 5) (unsigned-byte 12))) parse-snowflake-id))
(declaim (inline parse-snowflake-id))

(defun parse-snowflake-id (id)
  "解析 Snowflake ID，返回时间戳、数据中心 ID、工作节点 ID、序列号"
  (declare (type (unsigned-byte 64) id)
           (optimize (speed 3) (safety 1)))
  (values (the (unsigned-byte 64) (logand (ash id (- +timestamp-shift+)) +timestamp-mask+))
          (the (unsigned-byte 5) (logand (ash id (- +datacenter-shift+)) +max-datacenter+))
          (the (unsigned-byte 5) (logand (ash id (- +worker-shift+)) +max-worker+))
          (the (unsigned-byte 12) (logand id +sequence-mask+))))

(declaim (inline snowflake-to-string string-to-snowflake))

(defun snowflake-to-string (id)
  "将 Snowflake ID 转换为字符串"
  (declare (type (unsigned-byte 64) id)
           (optimize (speed 3) (safety 1)))
  (write-to-string id))

(defun string-to-snowflake (str)
  "将字符串转换为 Snowflake ID"
  (declare (type string str)
           (optimize (speed 3) (safety 1)))
  (parse-integer str))

;;;; ID 生成辅助函数 - 使用 inline 声明优化

(define-symbol-macro generate-message-id (generate-snowflake-id))
(define-symbol-macro generate-user-id (generate-snowflake-id))
(define-symbol-macro generate-conversation-id (generate-snowflake-id))

;; 保留函数版本用于显式调用
(declaim (inline generate-message-id generate-user-id generate-conversation-id))

(defun generate-message-id ()
  "生成消息 ID"
  (generate-snowflake-id))

(defun generate-user-id ()
  "生成用户 ID"
  (generate-snowflake-id))

(defun generate-conversation-id ()
  "生成会话 ID"
  (generate-snowflake-id))

;;;; 测试辅助

(defun reset-snowflake ()
  "重置 Snowflake 生成器（仅用于测试）"
  (setf *snowflake-sequence* 0
        *snowflake-last-timestamp* -1
        *snowflake-epoch-ms* nil))
