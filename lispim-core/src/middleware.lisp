;;;; middleware.lisp - WebSocket 中间件管道系统
;;;;
;;;; 参考 Fiora 的 Socket.IO 中间件管道模式
;;;; 提供认证、限流、日志等通用功能
;;;;
;;;; 设计原则：
;;;; - 纯 Common Lisp 实现
;;;; - 可组合的中间件管道
;;;; - 支持动态添加/移除中间件

(in-package :lispim-core)

;;;; 依赖声明

(eval-when (:compile-toplevel :load-toplevel :execute)
  (ql:quickload '(:bordeaux-threads :cl-json)))

;;;; 类型定义

(deftype middleware-handler ()
  "中间件处理器函数类型"
  '(function (t t t t) t))

(deftype middleware-name ()
  "中间件名称类型"
  'keyword)

;;;; 中间件管道结构

(defstruct middleware-pipeline
  "WebSocket 中间件管道
   参考 Fiora 的 socket.use() 模式，提供可组合的请求处理链"
  (middlewares nil :type list)
  (lock (bordeaux-threads:make-lock "pipeline-lock"))
  (enabled t :type boolean))

(defstruct middleware-entry
  "中间件条目"
  (name nil :type (or null middleware-name))
  (handler nil :type middleware-handler)
  (order 0 :type integer)
  (enabled t :type boolean))

;;;; 全局管道实例

(defvar *websocket-pipeline* (make-middleware-pipeline)
  "全局 WebSocket 中间件管道")

(defvar *pipeline-registry* (make-hash-table :test 'eq)
  "中间件注册表：name -> entry")

;;;; 管道操作

(defun make-pipeline ()
  "创建空管道"
  (make-middleware-pipeline))

(defun add-middleware (pipeline name handler &key (order 0))
  "添加中间件到管道

   Parameters:
     pipeline - 管道实例
     name     - 中间件名称（关键字）
     handler  - 处理函数，签名：(socket event data result)
     order    - 执行顺序，数字越小越先执行

   Handler 返回值：
     t    - 继续执行下一个中间件
     nil  - 中断管道，拒绝请求
     :skip - 跳过当前请求处理但仍继续管道"
  (declare (type middleware-pipeline pipeline)
           (type middleware-name name)
           (type middleware-handler handler))
  (bordeaux-threads:with-lock-held ((middleware-pipeline-lock pipeline))
    (let ((entry (make-middleware-entry
                  :name name
                  :handler handler
                  :order order)))
      ;; 按 order 排序插入
      (if (null (middleware-pipeline-middlewares pipeline))
          (setf (middleware-pipeline-middlewares pipeline) (list entry))
          (let ((pos (position-if (lambda (e)
                                    (> (middleware-entry-order e) order))
                                  (middleware-pipeline-middlewares pipeline))))
            (if pos
                (setf (middleware-pipeline-middlewares pipeline)
                      (append (subseq (middleware-pipeline-middlewares pipeline) 0 pos)
                              (list entry)
                              (subseq (middleware-pipeline-middlewares pipeline) pos)))
                (push entry (middleware-pipeline-middlewares pipeline)))))
      ;; 注册到全局注册表
      (setf (gethash name *pipeline-registry*) entry))
    (log-info "Middleware added: ~a (order=~a)" name order)
    t))

(defun remove-middleware (pipeline name)
  "从管道移除中间件"
  (declare (type middleware-pipeline pipeline)
           (type middleware-name name))
  (bordeaux-threads:with-lock-held ((middleware-pipeline-lock pipeline))
    (setf (middleware-pipeline-middlewares pipeline)
          (remove name (middleware-pipeline-middlewares pipeline)
                  :key #'middleware-entry-name))
    (remhash name *pipeline-registry*))
  (log-info "Middleware removed: ~a" name))

(defun enable-middleware (pipeline name)
  "启用中间件"
  (declare (type middleware-pipeline pipeline)
           (type middleware-name name))
  (let ((entry (gethash name *pipeline-registry*)))
    (when entry
      (setf (middleware-entry-enabled entry) t)
      (setf (middleware-pipeline-enabled pipeline) t))))

(defun disable-middleware (pipeline name)
  "禁用中间件"
  (declare (type middleware-pipeline pipeline)
           (type middleware-name name))
  (let ((entry (gethash name *pipeline-registry*)))
    (when entry
      (setf (middleware-entry-enabled entry) nil)
      (when (null (find-if (lambda (e) (middleware-entry-enabled e))
                           (middleware-pipeline-middlewares pipeline)))
        (setf (middleware-pipeline-enabled pipeline) nil)))))

(defun execute-pipeline (pipeline socket event data)
  "执行中间件管道

   按顺序执行所有中间件，每个中间件可以：
   - 返回 t：继续执行
   - 返回 nil：中断并拒绝请求
   - 修改 data：传递修改后的数据给下一个中间件

   Returns:
     (values success-p final-data)"
  (declare (type middleware-pipeline pipeline)
           (type t socket event data))
  (unless (middleware-pipeline-enabled pipeline)
    (return-from execute-pipeline (values t data)))

  (let ((middlewares (remove-if-not #'middleware-entry-enabled
                                    (middleware-pipeline-middlewares pipeline))))
    (if (null middlewares)
        (values t data)
        (handler-case
            (let ((result t)
                  (current-data data))
              (dolist (entry middlewares)
                (multiple-value-bind (continue new-data)
                    (funcall (middleware-entry-handler entry) socket event current-data result)
                  (unless continue
                    (return-from execute-pipeline (values nil nil)))
                  (when new-data
                    (setf current-data new-data))
                  (setf result continue)))
              (values t current-data))
          (error (c)
            (log-error "Pipeline execution error: ~a" c)
            (values nil nil))))))

;;;; 预定义中间件

(defun authentication-middleware (socket event data result)
  "认证中间件

   检查 WebSocket 连接的 Token 是否有效
   对认证相关事件（login, register）跳过检查"
  (declare (type t socket)
           (ignore result))
  ;; 白名单事件：不需要认证
  (let ((whitelist '("login" "register" "guest" "ping" "pong")))
    (if (member event whitelist :test 'string=)
        (values t data)
        (let ((token (socket-token socket)))
          (if token
              (let ((user-id (verify-token token)))
                (if user-id
                    (progn
                      (setf (socket-user-id socket) user-id)
                      (values t data))
                    (progn
                      (log-warn "Auth middleware: invalid token for ~a" event)
                      (values nil nil))))
              (progn
                (log-warn "Auth middleware: no token for ~a" event)
                (values nil nil)))))))

(defun rate-limit-middleware (socket event data result)
  "限流中间件

   基于用户 ID 和事件类型进行限流
   防止滥用和 DDoS 攻击"
  (declare (ignore result))
  (let ((user-id (socket-user-id socket)))
    (cond
      ;; 已认证用户：基于用户 ID 限流
      (user-id
       (let ((limit-key (format nil "~a:~a" user-id event)))
         (if (rate-limit-allow-p *rate-limiter* limit-key)
             (values t data)
             (progn
               (log-warn "Rate limit exceeded: user=~a, event=~a" user-id event)
               (values nil nil)))))
      ;; 未认证用户：基于 IP 限流
      (t
       (let ((ip (socket-ip socket)))
         (when ip
           (let ((limit-key (format nil "ip:~a:~a" ip event)))
             (unless (rate-limit-allow-p *rate-limiter* limit-key)
               (log-warn "Rate limit exceeded (IP): ip=~a, event=~a" ip event)
               (return-from rate-limit-middleware (values nil nil)))))
         (values t data))))))

(defun logging-middleware (socket event data result)
  "日志中间件

   记录所有 WebSocket 事件的访问日志"
  (declare (type t socket)
           (ignore result))
  (let ((log-level (if (member event '("ping" "pong") :test 'string=)
                       :debug
                       :info)))
    (if (eq log-level :debug)
        (log-debug "WS[~a][~a]: ~a"
                   (socket-id socket)
                   (or (socket-user-id socket) "anonymous")
                   event)
        (log-info "WS[~a][~a]: ~a"
                  (socket-id socket)
                  (or (socket-user-id socket) "anonymous")
                  event))
    (values t data)))

(defun compression-middleware (socket event data result)
  "压缩中间件

   对大数据量的响应进行压缩"
  (declare (ignore socket event result))
  (let ((json (cl-json:encode-json-to-string data)))
    (if (> (length json) 1024)
        ;; 大于 1KB 的数据考虑压缩
        (let ((compressed (compress-salza2 (babel:string-to-octets json :encoding :utf-8))))
          (if (< (length compressed) (length json))
              (values t (list :compressed t
                              :data compressed
                              :original-length (length json)))
              (values t data)))
        (values t data))))

(defun validation-middleware (socket event data result)
  "数据验证中间件

   验证请求数据的基本格式"
  (declare (ignore socket result))
  (cond
    ;; 消息事件必须有 content
    ((string= event "message")
     (if (and (getf data :content) (getf data :conversation-id))
         (values t data)
         (progn
           (log-warn "Validation failed: missing content or conversation_id")
           (values nil nil))))
    ;; 其他事件默认通过
    (t (values t data))))

;;;; 工具函数

(defun register-default-middleware ()
  "注册默认中间件"
  (let ((pipeline *websocket-pipeline*))
    ;; 1. 日志中间件（最先执行，记录所有请求）
    (add-middleware pipeline :logging #'logging-middleware :order -100)
    ;; 2. 认证中间件
    (add-middleware pipeline :authentication #'authentication-middleware :order 0)
    ;; 3. 限流中间件
    (add-middleware pipeline :rate-limit #'rate-limit-middleware :order 10)
    ;; 4. 验证中间件
    (add-middleware pipeline :validation #'validation-middleware :order 20)
    ;; 5. 压缩中间件（最后执行，处理响应）
    (add-middleware pipeline :compression #'compression-middleware :order 100)
    (log-info "Default middleware registered")))

(defun clear-all-middleware ()
  "清除所有中间件"
  (setf (middleware-pipeline-middlewares *websocket-pipeline*) nil)
  (clrhash *pipeline-registry*))

;;;; 管道状态查询

(defun list-middleware ()
  "列出所有已注册的中间件"
  (let ((pipeline *websocket-pipeline*))
    (mapcar (lambda (entry)
              (list :name (middleware-entry-name entry)
                    :order (middleware-entry-order entry)
                    :enabled (middleware-entry-enabled entry)))
            (middleware-pipeline-middlewares pipeline))))

(defun get-middleware-status ()
  "获取中间件状态报告"
  (let ((pipeline *websocket-pipeline*))
    (list :enabled (middleware-pipeline-enabled pipeline)
          :count (length (middleware-pipeline-middlewares pipeline))
          :middlewares (list-middleware))))

;;;; 导出公共 API
;;;; (Symbols are exported via package.lisp)
