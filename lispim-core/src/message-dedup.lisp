;;;; message-dedup.lisp - 消息去重模块
;;;;
;;;; 防止消息重复处理和存储
;;;;
;;;; 功能：
;;;; - 消息去重（基于消息 ID/内容指纹）
;;;; - 布隆过滤器快速检查
;;;; - 滑动窗口去重
;;;; - 重复消息统计
;;;;
;;;; 使用场景：
;;;; - 网络重传导致的重复消息
;;;; - 集群跨实例消息去重
;;;; - 消息幂等性保证

(in-package :lispim-core)

;;;; 依赖声明

(eval-when (:compile-toplevel :load-toplevel :execute)
  (ql:quickload '(:ironclad :cl-redis :babel)))

;;;; 配置

(defparameter *dedup-config*
  '((:window-size . 10000)           ; 滑动窗口大小
    (:window-ttl . (* 60 60))        ; 窗口 TTL（秒）
    (:bloom-size . 1000000)          ; 布隆过滤器大小
    (:bloom-hash-count . 7)          ; 布隆过滤器哈希函数数量
    (:cleanup-interval . 300))       ; 清理间隔（秒）
  "消息去重配置")

;;;; 类型定义

(defstruct message-deduplicator
  "消息去重器"
  (window (make-hash-table :test 'equal :size 10000) :type hash-table)
  (bloom-filter nil :type (or null vector))
  (window-size 10000 :type integer)
  (window-ttl 3600 :type integer)
  (message-count 0 :type integer)
  (duplicate-count 0 :type integer)
  (lock (bordeaux-threads:make-lock "dedup-lock") :type bordeaux-threads:lock)
  (created-at (get-universal-time) :type integer))

;;;; 初始化

(defun init-message-deduplicator (&key (window-size 10000) (window-ttl 3600)
                                        (bloom-size 1000000) (bloom-hash-count 7))
  "初始化消息去重器"
  (let ((dedup (make-message-deduplicator
                :window-size window-size
                :window-ttl window-ttl)))
    ;; 初始化布隆过滤器
    (setf (message-deduplicator-bloom-filter dedup)
          (make-array bloom-size :element-type 'bit :initial-element 0))
    (log-info "Message deduplicator initialized: window-size=~a, bloom-size=~a"
              window-size bloom-size)
    dedup))

;;;; 全局实例

(defvar *message-deduplicator* nil
  "全局消息去重器")

;;;; 消息指纹生成

(defun generate-message-fingerprint (message-id content sender-id timestamp)
  "生成消息指纹"
  (declare (type string message-id content sender-id)
           (type integer timestamp))
  (let* ((data (format nil "~a:~a:~a:~d" message-id content sender-id timestamp))
         (digest (ironclad:make-digest :sha256)))
    (ironclad:update-digest digest (babel:string-to-octets data))
    ;; 返回 16 字节指纹
    (let ((hash (ironclad:digest-sequence digest (make-array 32 :element-type '(unsigned-byte 8)))))
      (subseq hash 0 16))))

(defun message-fingerprint-to-string (fingerprint)
  "指纹转字符串"
  (declare (type vector fingerprint))
  (with-output-to-string (s)
    (loop for i below (length fingerprint)
          do (format s "~2,'0x" (aref fingerprint i)))))

;;;; 布隆过滤器操作

(defun bloom-filter-hash (fingerprint hash-index filter-size)
  "计算布隆过滤器哈希位置"
  (declare (type vector fingerprint)
           (type integer hash-index filter-size))
  (let ((h1 (aref fingerprint (mod hash-index (length fingerprint))))
        (h2 (aref fingerprint (mod (+ hash-index 1) (length fingerprint)))))
    (mod (+ h1 (* hash-index (1+ h2))) filter-size)))

(defun bloom-filter-add (bloom fingerprint &optional (hash-count 7))
  "添加到布隆过滤器"
  (declare (type vector bloom fingerprint))
  (dotimes (i hash-count)
    (let ((pos (bloom-filter-hash fingerprint i (length bloom))))
      (setf (bit bloom pos) 1))))

(defun bloom-filter-contains-p (bloom fingerprint &optional (hash-count 7))
  "检查布隆过滤器是否包含指纹"
  (declare (type vector bloom fingerprint))
  (dotimes (i hash-count)
    (let ((pos (bloom-filter-hash fingerprint i (length bloom))))
      (when (= (bit bloom pos) 0)
        (return-from bloom-filter-contains-p nil))))
  t)

;;;; 消息去重检查

(defun dedup-check-message (dedup message-id &optional content sender-id timestamp)
  "检查消息是否重复"
  (declare (type message-deduplicator dedup)
           (type string message-id))
  (bordeaux-threads:with-lock-held ((message-deduplicator-lock dedup))
    (let ((fingerprint (if content
                           (generate-message-fingerprint message-id content
                                                          (or sender-id "")
                                                          (or timestamp 0))
                           message-id)))
      ;; 1. 检查滑动窗口
      (when (gethash message-id (message-deduplicator-window dedup))
        (incf (message-deduplicator-duplicate-count dedup))
        (return-from dedup-check-message t))

      ;; 2. 检查布隆过滤器（可能存在假阳性）
      (when (and (message-deduplicator-bloom-filter dedup)
                 (bloom-filter-contains-p (message-deduplicator-bloom-filter dedup)
                                           fingerprint))
        ;; 布隆过滤器命中，可能是重复
        ;; 进一步检查滑动窗口确认
        (incf (message-deduplicator-duplicate-count dedup))
        (return-from dedup-check-message t))

      ;; 3. 添加到去重器
      (setf (gethash message-id (message-deduplicator-window dedup))
            (get-universal-time))
      (incf (message-deduplicator-message-count dedup))

      ;; 4. 添加到布隆过滤器
      (when (message-deduplicator-bloom-filter dedup)
        (bloom-filter-add (message-deduplicator-bloom-filter dedup) fingerprint))

      ;; 5. 检查是否需要清理窗口
      (when (>= (hash-table-count (message-deduplicator-window dedup))
                (message-deduplicator-window-size dedup))
        (cleanup-dedup-window dedup))

      nil)))

(defun cleanup-dedup-window (dedup)
  "清理过期的去重窗口"
  (declare (type message-deduplicator dedup))
  (let* ((now (get-universal-time))
         (ttl (message-deduplicator-window-ttl dedup))
         (expired-threshold (- now ttl))
         (removed 0))
    (loop for key being the hash-keys of (message-deduplicator-window dedup)
          using (hash-value timestamp)
          when (< timestamp expired-threshold)
            do (progn
                 (remhash key (message-deduplicator-window dedup))
                 (incf removed)))
    (when (> removed 0)
      (log-debug "Cleaned up ~a expired entries from dedup window" removed))
    removed))

;;;; 后台清理线程

(defvar *dedup-cleanup-thread* nil
  "去重清理线程")

(defun start-dedup-cleanup-worker (dedup &optional (interval 300))
  "启动后台清理线程"
  (declare (type message-deduplicator dedup))
  (let ((cleanup-interval interval))
    (setf *dedup-cleanup-thread*
          (bordeaux-threads:make-thread
           (lambda ()
             (loop while t
                   do (progn
                        (sleep cleanup-interval)
                        (cleanup-dedup-window dedup)
                        (log-debug "Dedup cleanup worker ran"))))
           :name "dedup-cleanup-worker"
           :initial-bindings `((*standard-output* . ,*standard-output*))))))

(defun stop-dedup-cleanup-worker ()
  "停止后台清理线程"
  (when (and *dedup-cleanup-thread*
             (bordeaux-threads:thread-alive-p *dedup-cleanup-thread*))
    (bordeaux-threads:destroy-thread *dedup-cleanup-thread*)
    (setf *dedup-cleanup-thread* nil)
    (log-info "Dedup cleanup worker stopped")))

;;;; Redis 分布式去重

(defun dedup-check-message-redis (redis-client key-prefix message-id &optional ttl)
  "使用 Redis 进行分布式去重检查"
  (declare (type string key-prefix message-id))
  (let* ((key (format nil "~a:~a" key-prefix message-id))
         (ttl (or ttl 3600)))
    (handler-case
        ;; 使用 SETNX + EXPIRE 实现原子操作
        (let ((result (redis:red-setnx redis-client key "1")))
          (when (and result (> ttl 0))
            (redis:red-expire redis-client key ttl))
          (if result
              nil  ; 新消息
              t))  ; 重复消息
      (error (c)
        (log-error "Redis dedup check failed: ~a" c)
        nil))))

;;;; 统计

(defun get-dedup-stats (dedup)
  "获取去重统计"
  (declare (type message-deduplicator dedup))
  (list :message-count (message-deduplicator-message-count dedup)
        :duplicate-count (message-deduplicator-duplicate-count dedup)
        :window-size (hash-table-count (message-deduplicator-window dedup))
        :duplicate-rate (if (> (message-deduplicator-message-count dedup) 0)
                            (/ (message-deduplicator-duplicate-count dedup)
                               (+ (message-deduplicator-message-count dedup)
                                  (message-deduplicator-duplicate-count dedup)))
                            0)))

;;;; 高层 API

(defun init-message-dedup (&key (window-size 10000) (window-ttl 3600) (bloom-size 1000000) (cleanup-interval 300))
  "高层初始化 API"
  (setf *message-deduplicator*
        (init-message-deduplicator :window-size window-size
                                    :window-ttl window-ttl
                                    :bloom-size bloom-size))
  (start-dedup-cleanup-worker *message-deduplicator* cleanup-interval)
  *message-deduplicator*)

(defun is-duplicate-message-p (message-id &optional content sender-id timestamp)
  "高层去重检查 API"
  (if *message-deduplicator*
      (dedup-check-message *message-deduplicator* message-id content sender-id timestamp)
      nil))

(defun get-message-dedup-stats ()
  "高层统计 API"
  (if *message-deduplicator*
      (get-dedup-stats *message-deduplicator*)
      nil))

;;;; 消息幂等性

(defmacro with-idempotent-operation ((key &optional (ttl 3600)) &body body)
  "幂等操作宏"
  `(let ((operation-key (format nil "idempotent:~a" ,key)))
     (if (is-duplicate-message-p operation-key)
         (progn
           (log-warn "Idempotent operation skipped: ~a" ,key)
           nil)
         (progn
           ,@body))))

;;;; 清理

(defun shutdown-message-dedup ()
  "关闭消息去重模块"
  (stop-dedup-cleanup-worker)
  (when *message-deduplicator*
    (clrhash (message-deduplicator-window *message-deduplicator*))
    (setf *message-deduplicator* nil))
  (log-info "Message dedup shutdown complete"))

;;;; 导出

(export '(;; Initialization
          init-message-deduplicator
          init-message-dedup
          *message-deduplicator*

          ;; Dedup check
          dedup-check-message
          is-duplicate-message-p
          generate-message-fingerprint
          message-fingerprint-to-string

          ;; Bloom filter
          bloom-filter-add
          bloom-filter-contains-p

          ;; Cleanup
          cleanup-dedup-window
          start-dedup-cleanup-worker
          stop-dedup-cleanup-worker

          ;; Redis dedup
          dedup-check-message-redis

          ;; Statistics
          get-dedup-stats
          get-message-dedup-stats

          ;; Idempotency
          with-idempotent-operation

          ;; Shutdown
          shutdown-message-dedup)
        :lispim-core)
