;;;; rate-limiter.lisp - 速率限制模块
;;;;
;;;; 保护系统免受滥用和 DDoS 攻击
;;;;
;;;; 功能：
;;;; - 令牌桶算法
;;;; - 漏桶算法
;;;; - 固定窗口限流
;;;; - 滑动窗口限流
;;;; - 分布式限流（Redis）
;;;; - IP/用户维度限流
;;;;
;;;; 使用场景：
;;;; - API 请求限流
;;;; - 消息发送限流
;;;; - 登录尝试限流
;;;; - 文件上传限流

(in-package :lispim-core)

;;;; 依赖声明

(eval-when (:compile-toplevel :load-toplevel :execute)
  (ql:quickload '(:cl-redis :bordeaux-threads)))

;;;; 配置

(defparameter *rate-limiter-config*
  '((:default-rate . 100)             ; 默认速率（请求/秒）
    (:default-burst . 200)            ; 默认突发量
    (:window-size . 60)               ; 窗口大小（秒）
    (:cleanup-interval . 60))         ; 清理间隔（秒）
  "速率限制器配置")

;;;; 类型定义

(defstruct token-bucket
  "令牌桶限流器"
  (capacity 0 :type integer)          ; 桶容量
  (tokens 0 :type number)             ; 当前令牌数
  (refill-rate 0 :type number)        ; 补充速率（令牌/秒）
  (last-refill 0 :type integer)       ; 上次补充时间
  (lock (bordeaux-threads:make-lock "bucket-lock") :type bordeaux-threads:lock))

(defstruct leaky-bucket
  "漏桶限流器"
  (capacity 0 :type integer)          ; 桶容量
  (leak-rate 0 :type number)          ; 泄漏速率（请求/秒）
  (water-level 0 :type number)        ; 当前水位
  (last-leak 0 :type integer)         ; 上次泄漏时间
  (lock (bordeaux-threads:make-lock "leaky-lock") :type bordeaux-threads:lock))

(defstruct sliding-window
  "滑动窗口限流器"
  (window-size 0 :type integer)       ; 窗口大小（秒）
  (max-requests 0 :type integer)      ; 最大请求数
  (requests nil :type list)           ; 请求时间戳列表
  (lock (bordeaux-threads:make-lock "window-lock") :type bordeaux-threads:lock))

(defstruct rate-limiter
  "速率限制器"
  (buckets (make-hash-table :test 'equal) :type hash-table)
  (windows (make-hash-table :test 'equal) :type hash-table)
  (default-rate 100 :type integer)
  (default-burst 200 :type integer)
  (lock (bordeaux-threads:make-lock "limiter-lock") :type bordeaux-threads:lock)
  (allowed-count 0 :type integer)
  (denied-count 0 :type integer))

;;;; 令牌桶实现

(defun make-token-bucket (capacity refill-rate)
  "创建令牌桶"
  (make-token-bucket
   :capacity capacity
   :tokens capacity
   :refill-rate refill-rate
   :last-refill (get-universal-time)))

(defun token-bucket-refill (bucket)
  "补充令牌"
  (declare (type token-bucket bucket))
  (let* ((now (get-universal-time))
         (elapsed (- now (token-bucket-last-refill bucket)))
         (refill (* elapsed (token-bucket-refill-rate bucket))))
    (setf (token-bucket-tokens bucket)
          (min (token-bucket-capacity bucket)
               (+ (token-bucket-tokens bucket) refill)))
    (setf (token-bucket-last-refill bucket) now)))

(defun token-bucket-try-acquire (bucket &optional (tokens 1))
  "尝试获取令牌"
  (declare (type token-bucket bucket)
           (type integer tokens))
  (bordeaux-threads:with-lock-held ((token-bucket-lock bucket))
    (token-bucket-refill bucket)
    (if (>= (token-bucket-tokens bucket) tokens)
        (progn
          (decf (token-bucket-tokens bucket) tokens)
          t)
        nil)))

(defun token-bucket-get-tokens (bucket)
  "获取当前令牌数"
  (declare (type token-bucket bucket))
  (bordeaux-threads:with-lock-held ((token-bucket-lock bucket))
    (token-bucket-refill bucket)
    (token-bucket-tokens bucket)))

;;;; 漏桶实现

(defun make-leaky-bucket (capacity leak-rate)
  "创建漏桶"
  (make-leaky-bucket
   :capacity capacity
   :leak-rate leak-rate
   :water-level 0
   :last-leak (get-universal-time)))

(defun leaky-bucket-leak (bucket)
  "泄漏水"
  (declare (type leaky-bucket bucket))
  (let* ((now (get-universal-time))
         (elapsed (- now (leaky-bucket-last-leak bucket)))
         (leak (* elapsed (leaky-bucket-leak-rate bucket))))
    (setf (leaky-bucket-water-level bucket)
          (max 0 (- (leaky-bucket-water-level bucket) leak)))
    (setf (leaky-bucket-last-leak bucket) now)))

(defun leaky-bucket-try-acquire (bucket &optional (water 1))
  "尝试添加水（请求）"
  (declare (type leaky-bucket bucket)
           (type number water))
  (bordeaux-threads:with-lock-held ((leaky-bucket-lock bucket))
    (leaky-bucket-leak bucket)
    (if (<= (+ (leaky-bucket-water-level bucket) water)
            (leaky-bucket-capacity bucket))
        (progn
          (incf (leaky-bucket-water-level bucket) water)
          t)
        nil)))

;;;; 滑动窗口实现

(defun make-sliding-window (window-size max-requests)
  "创建滑动窗口"
  (make-sliding-window
   :window-size window-size
   :max-requests max-requests
   :requests nil))

(defun sliding-window-cleanup (window)
  "清理过期请求"
  (declare (type sliding-window window))
  (let* ((now (get-universal-time))
         (cutoff (- now (sliding-window-window-size window))))
    (setf (sliding-window-requests window)
          (remove-if (lambda (ts) (< ts cutoff))
                     (sliding-window-requests window)))))

(defun sliding-window-try-acquire (window)
  "尝试获取请求许可"
  (declare (type sliding-window window))
  (bordeaux-threads:with-lock-held ((sliding-window-lock window))
    (sliding-window-cleanup window)
    (if (< (length (sliding-window-requests window))
           (sliding-window-max-requests window))
        (progn
          (push (get-universal-time) (sliding-window-requests window))
          t)
        nil)))

(defun sliding-window-get-count (window)
  "获取当前窗口请求数"
  (declare (type sliding-window window))
  (bordeaux-threads:with-lock-held ((sliding-window-lock window))
    (sliding-window-cleanup window)
    (length (sliding-window-requests window))))

;;;; 速率限制器主实现

(defun init-rate-limiter (&key (default-rate 100) (default-burst 200))
  "初始化速率限制器"
  (make-rate-limiter
   :default-rate default-rate
   :default-burst default-burst))

(defvar *rate-limiter* nil
  "全局速率限制器")

(defun get-or-create-bucket (limiter key &optional (rate nil) (burst nil))
  "获取或创建令牌桶"
  (declare (type rate-limiter limiter)
           (type string key))
  (or (gethash key (rate-limiter-buckets limiter))
      (let ((bucket (make-token-bucket
                      (or burst (rate-limiter-default-burst limiter))
                      (or rate (rate-limiter-default-rate limiter)))))
        (setf (gethash key (rate-limiter-buckets limiter)) bucket)
        bucket)))

(defun rate-limit-allow-p (limiter key &optional (rate nil) (burst nil))
  "检查请求是否允许"
  (declare (type rate-limiter limiter)
           (type string key))
  (let ((bucket (get-or-create-bucket limiter key rate burst)))
    (if (token-bucket-try-acquire bucket)
        (progn
          (incf (rate-limiter-allowed-count limiter))
          t)
        (progn
          (incf (rate-limiter-denied-count limiter))
          nil))))

(defun rate-limit-remaining (limiter key)
  "获取剩余请求数"
  (declare (type rate-limiter limiter)
           (type string key))
  (let ((bucket (get-or-create-bucket limiter key)))
    (floor (token-bucket-get-tokens bucket))))

;;;; 固定窗口限流

(defun make-fixed-window (window-size max-requests)
  "创建固定窗口限流器"
  (list :window-size window-size
        :max-requests max-requests
        :current-window 0
        :current-count 0
        :lock (bordeaux-threads:make-lock "fixed-window-lock")))

(defun fixed-window-try-acquire (window)
  "尝试获取请求许可"
  (declare (type list window))
  (let* ((now (get-universal-time))
         (window-size (getf window :window-size))
         (current-window (floor now window-size)))
    (bordeaux-threads:with-lock-held ((getf window :lock))
      ;; 检查是否需要重置窗口
      (when (/= current-window (getf window :current-window))
        (setf (getf window :current-window) current-window)
        (setf (getf window :current-count) 0))
      ;; 检查是否允许请求
      (if (< (getf window :current-count) (getf window :max-requests))
          (progn
            (incf (getf window :current-count))
            t)
          nil))))

;;;; Redis 分布式限流

(defun redis-rate-limit-allow-p (key-prefix key max-requests window-size)
  "使用 Redis 进行分布式限流"
  (declare (type string key-prefix key)
           (type integer max-requests window-size))
  (let* ((full-key (format nil "~a:~a" key-prefix key))
         (now (get-universal-time))
         (window (floor now window-size)))
    (handler-case
        (progn
          (redis:connect :host "localhost" :port 6379)
          (let* ((window-key (format nil "~a:~d" full-key window))
                 (count (redis:red-incr window-key))
                 (ttl (- window-size (mod now window-size))))
            ;; 设置过期时间
            (when (= count 1)
              (redis:red-expire window-key ttl))
            (<= count max-requests)))
      (error (c)
        (log-error "Redis rate limit failed: ~a" c)
        t))))

;;;; 预定义限流策略

(defparameter *preset-rate-limits*
  '((:api-default . (100 200))           ; 100 req/s, burst 200
    (:api-strict . (10 20))              ; 10 req/s, burst 20
    (:api-relaxed . (1000 2000))         ; 1000 req/s, burst 2000
    (:login . (5 10))                    ; 5 次/分钟登录尝试
    (:message . (60 120))                ; 60 消息/分钟
    (:upload . (10 20))                  ; 10 文件/分钟
    (:sms . (1 3)))                      ; 1 短信/分钟，burst 3
  "预定义限流策略")

(defun get-preset-limit (preset-name)
  "获取预定义限流策略"
  (cdr (assoc preset-name *preset-rate-limits*)))

;;;; 统计

(defun get-rate-limiter-stats (limiter)
  "获取速率限制器统计"
  (declare (type rate-limiter limiter))
  (list :allowed-count (rate-limiter-allowed-count limiter)
        :denied-count (rate-limiter-denied-count limiter)
        :bucket-count (hash-table-count (rate-limiter-buckets limiter))
        :denial-rate (if (> (+ (rate-limiter-allowed-count limiter)
                               (rate-limiter-denied-count limiter)) 0)
                         (/ (rate-limiter-denied-count limiter)
                            (+ (rate-limiter-allowed-count limiter)
                               (rate-limiter-denied-count limiter)))
                         0)))

;;;; 高层 API

(defun init-rate-limiting (&key (default-rate 100) (default-burst 200))
  "高层初始化 API"
  (setf *rate-limiter* (init-rate-limiter :default-rate default-rate
                                           :default-burst default-burst))
  *rate-limiter*)

(defun check-rate-limit (key &optional (preset :api-default))
  "高层限流检查 API"
  (let ((limits (get-preset-limit preset)))
    (when limits
      (rate-limit-allow-p *rate-limiter* key (car limits) (cadr limits)))))

(defun get-rate-limit-stats ()
  "高层统计 API"
  (when *rate-limiter*
    (get-rate-limiter-stats *rate-limiter*)))

;;;; 清理

(defun cleanup-rate-limiter (limiter)
  "清理速率限制器"
  (declare (type rate-limiter limiter))
  (clrhash (rate-limiter-buckets limiter))
  (log-info "Rate limiter cleaned up"))

(defun shutdown-rate-limiting ()
  "关闭速率限制模块"
  (when *rate-limiter*
    (cleanup-rate-limiter *rate-limiter*)
    (setf *rate-limiter* nil))
  (log-info "Rate limiting shutdown complete"))

;;;; 导出

(export '(;; Initialization
          init-rate-limiter
          init-rate-limiting
          *rate-limiter*

          ;; Token bucket
          make-token-bucket
          token-bucket-try-acquire
          token-bucket-get-tokens

          ;; Leaky bucket
          make-leaky-bucket
          leaky-bucket-try-acquire

          ;; Sliding window
          make-sliding-window
          sliding-window-try-acquire
          sliding-window-get-count

          ;; Fixed window
          make-fixed-window
          fixed-window-try-acquire

          ;; Rate limiter
          rate-limit-allow-p
          rate-limit-remaining

          ;; Redis rate limit
          redis-rate-limit-allow-p

          ;; Presets
          get-preset-limit
          check-rate-limit
          *preset-rate-limits*

          ;; Statistics
          get-rate-limiter-stats
          get-rate-limit-stats

          ;; Cleanup
          cleanup-rate-limiter
          shutdown-rate-limiting)
        :lispim-core)
