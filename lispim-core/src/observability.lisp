;;;; observability.lisp - 可观测性模块
;;;;
;;;; 负责指标收集、分布式追踪、健康检查

(in-package :lispim-core)

;;;; 依赖声明

(eval-when (:compile-toplevel :load-toplevel :execute)
  (ql:quickload '(:uuid :bordeaux-threads)))

;;;; 指标定义

(defstruct metric
  "指标定义"
  (name "" :type string)
  (type :gauge :type (member :gauge :counter :histogram :summary))
  (description "" :type string)
  (labels (make-hash-table :test 'equal) :type hash-table)
  (value 0 :type number)
  (samples nil :type list))  ; 用于 histogram

(defvar *metrics* (make-hash-table :test 'equal)
  "指标注册表")

(defvar *metrics-lock* (bordeaux-threads:make-lock "metrics-lock")
  "指标锁")

;;;; 指标宏

(defmacro defmetric (name &key type description labels buckets)
  "定义指标"
  `(progn
     (register-metric
      (make-metric
       :name ,(symbol-name name)
       :type ,(or type :gauge)
       :description ,(or description "")
       :labels (make-hash-table :test 'equal)))
     (setf ,name (get-metric ,(symbol-name name)))))

;;;; 指标注册

(defun register-metric (metric)
  "注册指标"
  (declare (type metric metric))
  (bordeaux-threads:with-lock-held (*metrics-lock*)
    (setf (gethash (metric-name metric) *metrics*) metric)))

(defun get-metric (name)
  "获取指标"
  (declare (type string name))
  (bordeaux-threads:with-lock-held (*metrics-lock*)
    (gethash name *metrics*)))

;;;; 指标操作

(defun incf-metric (metric &optional (delta 1) &rest labels)
  "增加计数器"
  (declare (type metric metric)
           (type number delta))
  (when (eq (metric-type metric) :counter)
    (incf (metric-value metric) delta)
    (record-metric-value metric)))

(defun decf-metric (metric &optional (delta 1) &rest labels)
  "减少计数器"
  (declare (type metric metric)
           (type number delta))
  (when (eq (metric-type metric) :gauge)
    (decf (metric-value metric) delta)
    (record-metric-value metric)))

(defun setf-metric (metric value &rest labels)
  "设置指标值"
  (declare (type metric metric)
           (type number value))
  (when (eq (metric-type metric) :gauge)
    (setf (metric-value metric) value)
    (record-metric-value metric)))

(defun observe-histogram (metric value &rest labels)
  "记录直方图观测值"
  (declare (type metric metric)
           (type number value))
  (when (eq (metric-type metric) :histogram)
    (push value (metric-samples metric))
    (record-metric-value metric)))

(defun record-metric-value (metric)
  "记录指标值（用于时间序列）"
  (declare (type metric metric))
  ;; 简化实现，实际应存储到时间序列数据库
  )

;;;; 预定义指标

(defmetric *lispim-connections-active*
  :type :gauge
  :description "活跃连接数"
  :labels '(region instance))

(defmetric *lispim-messages-processed*
  :type :counter
  :description "处理的消息总数"
  :labels '(message-type status))

(defmetric *lispim-module-reload-duration*
  :type :histogram
  :description "模块热更新耗时"
  :labels '(module-name success-p)
  :buckets '(0.1 0.5 1.0 5.0 10.0))

(defmetric *lispim-oc-api-latency*
  :type :histogram
  :description "OpenClaw API 调用延迟"
  :labels '(endpoint status)
  :buckets '(0.05 0.1 0.25 0.5 1.0 2.5))

(defmetric *lispim-oc-token-cost*
  :type :counter
  :description "AI Token 消耗成本"
  :labels '(model direction))

(defmetric *lispim-e2ee-operations*
  :type :counter
  :description "加密操作次数"
  :labels '(operation success-p))

(defmetric *lispim-conversation-active*
  :type :gauge
  :description "活跃会话数"
  :labels '(conversation-type))

(defmetric *lispim-message-latency*
  :type :histogram
  :description "消息延迟 (发送 - 接收)"
  :labels '(message-type)
  :buckets '(0.01 0.05 0.1 0.25 0.5 1.0))

;;;; Prometheus 格式输出

(defun get-metrics ()
  "获取 Prometheus 格式指标"
  (let ((parts nil))
    (bordeaux-threads:with-lock-held (*metrics-lock*)
      (maphash (lambda (name metric)
                 (declare (ignore name))
                 (push (format nil "# HELP ~a ~a" (metric-name metric) (metric-description metric)) parts)
                 (push (format nil "# TYPE ~a ~a" (metric-name metric) (symbol-name (metric-type metric))) parts)
                 (push (format nil "~a ~a" (metric-name metric) (metric-value metric)) parts))
               *metrics*))
    (if (null parts)
        "# No metrics registered"
        (format nil "~{~A~^~%~}" (nreverse parts)))))

;;;; 分布式追踪

(defstruct message-trace
  "消息追踪上下文"
  (trace-id (uuid:make-v4-uuid) :type uuid:uuid)
  (span-id (uuid:make-v4-uuid) :type uuid:uuid)
  (parent-span-id nil :type (or null uuid:uuid))
  (operation-name "" :type string)
  (start-time 0 :type integer)
  (end-time nil :type (or null integer))
  (tags (make-hash-table :test 'equal) :type hash-table)
  (logs nil :type list))

(defvar *trace-context* (make-hash-table :test 'eq)
  "追踪上下文（线程本地存储模拟）")

(defvar *trace-storage* (make-hash-table :test 'equal)
  "追踪存储")

(defmacro with-trace-span ((operation-name &rest tags &key &allow-other-keys) &body body)
  "创建追踪 Span 并自动完成"
  (let ((parent-sym (gensym "PARENT"))
        (span-sym (gensym "SPAN"))
        (values-sym (gensym "VALUES")))
    `(let* ((,parent-sym (get-trace-context))
            (,span-sym (make-message-trace
                        :operation-name ,operation-name
                        :parent-span-id (when ,parent-sym
                                          (message-trace-span-id ,parent-sym))
                        :start-time (get-universal-time))))
       ;; 添加标签
       ,@(when tags
           `((setf ,@(loop for (k v) on tags by #'cddr
                   when (keywordp k)
                   append `(,(let ((key-name (string-downcase (symbol-name k))))
                               `(gethash ,key-name (message-trace-tags ,span-sym))) ,v)
                   when (stringp k)
                   append `((gethash ,k (message-trace-tags ,span-sym)) ,v)))))
       (set-trace-context ,span-sym)
       (unwind-protect
            (multiple-value-setq (,values-sym)
              (progn
                (record-span-start ,span-sym)
                ,@body))
         (setf (message-trace-end-time ,span-sym) (get-universal-time))
         (record-span-end ,span-sym)
         (restore-trace-context ,parent-sym))
       ,values-sym)))

(defun get-trace-context ()
  "获取追踪上下文"
  (gethash (bordeaux-threads:current-thread) *trace-context*))

(defun set-trace-context (context)
  "设置追踪上下文"
  (setf (gethash (bordeaux-threads:current-thread) *trace-context*) context))

(defun restore-trace-context (context)
  "恢复追踪上下文"
  (setf (gethash (bordeaux-threads:current-thread) *trace-context*) context))

(defun record-span-start (span)
  "记录 Span 开始"
  (declare (type message-trace span))
  (setf (gethash (format nil "~a" (message-trace-span-id span)) *trace-storage*)
        span))

(defun record-span-end (span)
  "记录 Span 结束"
  (declare (type message-trace span))
  ;; 可以导出到追踪系统
  )

;;;; 健康检查

(defstruct health-check
  "健康检查项"
  (name "" :type string)
  (check-fn nil :type function)
  (critical nil :type boolean)  ; 是否关键检查
  (last-status :unknown :type (member :healthy :unhealthy :unknown))
  (last-checked 0 :type integer))

(defvar *health-checks* (make-hash-table :test 'equal)
  "健康检查注册表")

(defun register-health-check (name check-fn &key (critical t))
  "注册健康检查"
  (declare (type string name)
           (type function check-fn))
  (setf (gethash name *health-checks*)
        (make-health-check
         :name name
         :check-fn check-fn
         :critical critical)))

(defun check-all-health ()
  "检查所有健康项"
  (let ((results nil)
        (all-healthy t))
    (maphash (lambda (name check)
               (let ((status (handler-case
                                 (funcall (health-check-check-fn check))
                               (error () nil))))
                 (setf (health-check-last-status check)
                       (if status :healthy :unhealthy))
                 (setf (health-check-last-checked check) (get-universal-time))
                 (push (cons name status) results)
                 (when (and (health-check-critical check) (not status))
                   (setf all-healthy nil))))
             *health-checks*)
    (values all-healthy results)))

;;;; 健康检查端点

(defun handle-healthz ()
  "处理 /healthz 请求（liveness probe）"
  (multiple-value-bind (healthy checks) (check-all-health)
    (declare (ignore checks))
    (if healthy
        '(200 (("Content-Type" . "text/plain")) ("OK"))
        '(503 (("Content-Type" . "text/plain")) ("UNHEALTHY")))))

(defun handle-readyz ()
  "处理 /readyz 请求（readiness probe）"
  (if *server-running*
      '(200 (("Content-Type" . "text/plain")) ("READY"))
      '(503 (("Content-Type" . "text/plain")) ("NOT_READY"))))

(defun handle-metrics ()
  "处理 /metrics 请求"
  `(200 (("Content-Type" . "text/plain; version=0.0.4"))
    (,(get-metrics))))

;;;; 注册默认健康检查

(defun register-default-health-checks ()
  "注册默认健康检查"
  (register-health-check
   "database"
   (lambda ()
     ;; 检查数据库连接
     t)
   :critical t)

  (register-health-check
   "redis"
   (lambda ()
     ;; 检查 Redis 连接
     t)
   :critical t)

  (register-health-check
   "modules"
   (lambda ()
     ;; 检查所有模块健康
     (every (lambda (m) (eq (module-info-health-status m) :healthy))
            (list-modules)))
   :critical t)

  (log-info "Default health checks registered"))

;;;; 日志配置 - 使用 log4cl 回调

(defvar *log-callbacks* nil
  "日志回调函数列表")

(defun setup-logging (&key (level :info) (file nil) callbacks)
  "配置日志"
  (declare (type keyword level)
           (type (or null pathname) file)
           (ignore level file))

  ;; 注册回调
  (when callbacks
    (setf *log-callbacks* (if (listp callbacks) callbacks (list callbacks))))

  ;; log4cl 在 Windows 上简化配置
  (log:info "Logging configured"))

(defun add-log-callback (callback)
  "添加日志回调函数"
  (declare (type function callback))
  (pushnew callback *log-callbacks*))

(defun remove-log-callback (callback)
  "移除日志回调"
  (declare (type function callback))
  (setf *log-callbacks* (remove callback *log-callbacks*)))

(defun log-with-callbacks (level format-str args)
  "带回调的日志记录"
  (declare (type keyword level)
           (type string format-str))
  (let ((message (apply #'format nil format-str args))
        (timestamp (get-universal-time)))
    ;; 调用所有回调
    (dolist (callback *log-callbacks*)
      (handler-case
          (funcall callback level timestamp message)
        (error (c)
          (log:error "Log callback error: ~a" c))))))

;;;; 性能分析

(defvar *profiling-data* (make-hash-table :test 'equal)
  "性能分析数据")

(defmacro with-profiling (operation-name &body body)
  "性能分析宏"
  (let ((start (gensym "START"))
        (end (gensym "END"))
        (duration (gensym "DURATION")))
    `(let ((,start (get-internal-real-time)))
       (multiple-value-prog1
           (progn ,@body)
         (let* ((,end (get-internal-real-time))
                (,duration (/ (- ,end ,start) internal-time-units-per-second)))
           (push ,duration (gethash ,operation-name *profiling-data*))
           (when (> ,duration 1.0)
             (log-warn "Slow operation: ~a took ~fs" ,operation-name ,duration)))))))

;;;; 告警

(defstruct alert
  "告警定义"
  (name "" :type string)
  (condition nil :type function)
  (severity :warning :type (member :info :warning :error :critical))
  (message "" :type string)
  (last-triggered 0 :type integer))

(defvar *alerts* (make-hash-table :test 'equal)
  "告警注册表")

(defvar *alert-history* nil
  "告警历史")

(defun register-alert (name condition &key severity message)
  "注册告警"
  (declare (type string name)
           (type function condition))
  (setf (gethash name *alerts*)
        (make-alert
         :name name
         :condition condition
         :severity (or severity :warning)
         :message (or message ""))))

(defun check-alerts ()
  "检查所有告警"
  (maphash (lambda (name alert)
             (when (funcall (alert-condition alert))
               (trigger-alert alert)))
           *alerts*))

(defun trigger-alert (alert)
  "触发告警"
  (declare (type alert alert))
  (setf (alert-last-triggered alert) (get-universal-time))
  (push (list :alert alert :timestamp (get-universal-time)) *alert-history*)
  (log:error "ALERT [~a]: ~a" (alert-severity alert) (alert-message alert)))

;;;; 初始化

(defun init-observability (&key (log-level :info) (log-file nil))
  "初始化可观测性模块"
  (setup-logging :level log-level :file log-file)
  (register-default-health-checks)
  (log-info "Observability initialized"))

;;;; 清理

(defun shutdown-observability ()
  "关闭可观测性模块"
  (check-alerts)  ; 最后检查一次告警
  (log:info "Observability shutdown")
  (close-logging))

(defun close-logging ()
  "关闭日志"
  ;; 清理回调
  (setf *log-callbacks* nil)
  (log:info "Logging closed"))
