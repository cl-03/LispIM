;;;; server.lisp - OpenClaw Connector 服务器
;;;;
;;;; 负责启动和管理 Connector 服务器

(in-package :openclaw-connector)

;;;; 依赖声明

(eval-when (:compile-toplevel :load-toplevel :execute)
  (ql:quickload '(:cl-async :bordeaux-threads :log4cl)))

;;;; 服务器状态

(defvar *server-socket* nil
  "服务器 socket")

(defvar *client-connections* (make-hash-table :test 'equal)
  "客户端连接表")

(defvar *client-connections-lock* (bordeaux-threads:make-lock "clients-lock")
  "客户端连接锁")

;;;; 服务器启动

(defun start-connector (&key (host *connector-host*)
                             (port *connector-port*)
                             (api-key *connector-api-key*))
  "启动 OpenClaw Connector 服务器"
  (declare (type string host)
           (type integer port))

  (setf *connector-api-key* api-key)

  (log:info "========================================")
  (log:info "  OpenClaw Connector for LispIM v0.1.0")
  (log:info "========================================")
  (log:info "Host: ~a" host)
  (log:info "Port: ~a" port)
  (log:info "========================================")

  (setf *connector-running* t)

  ;; 启动 TCP 服务器
  (start-tcp-server host port)

  (log:info "Connector started"))

;;;; 服务器停止

(defun stop-connector ()
  "停止 OpenClaw Connector 服务器"
  (log:info "Stopping connector...")

  (setf *connector-running* nil)

  ;; 关闭所有客户端连接
  (bordeaux-threads:with-lock-held (*client-connections-lock*)
    (maphash (lambda (id conn)
               (declare (ignore id))
               (ignore-errors (close conn)))
             *client-connections*)
    (clrhash *client-connections*))

  ;; 关闭服务器 socket
  (when *server-socket*
    (ignore-errors (usocket:socket-close *server-socket*)))

  (log:info "Connector stopped"))

;;;; TCP 服务器

(defun start-tcp-server (host port)
  "启动 TCP 服务器"
  (declare (type string host)
           (type integer port))

  (let ((socket (usocket:socket-listen host port
                                        :reuseaddress t
                                        :element-type '(unsigned-byte 8))))
    (setf *server-socket* socket)

    ;; 启动接受连接线程
    (bordeaux-threads:make-thread
     (lambda ()
       (accept-loop socket))
     :name "tcp-accept-loop"
     :initial-bindings (*standard-output* . *standard-output*))

    socket))

(defun accept-loop (socket)
  "接受连接循环"
  (declare (type usocket:socket socket))
  (log:info "Accept loop started")
  (loop while *connector-running*
        do (handler-case
               (let ((client (usocket:socket-accept socket)))
                 (handle-client client))
             (error (condition)
               (log:error "Accept error: ~a" condition)))))

;;;; 客户端处理

(defun handle-client (client)
  "处理客户端连接"
  (declare (type usocket:socket client))
  (let ((client-id (uuid:to-string (uuid:make-v4-uuid)))
        (stream (usocket:socket-stream client)))

    ;; 注册连接
    (bordeaux-threads:with-lock-held (*client-connections-lock*)
      (setf (gethash client-id *client-connections*)
            (list :socket client
                  :stream stream
                  :id client-id
                  :connected-at (get-universal-time))))

    (log:info "Client connected: ~a" client-id)

    ;; 启动处理线程
    (bordeaux-threads:make-thread
     (lambda ()
       (process-client client-id stream))
     :name (format nil "client-~a" client-id)
     :initial-bindings (*standard-output* . *standard-output*))

    client-id))

(defun process-client (client-id stream)
  "处理客户端消息"
  (declare (type string client-id)
           (type stream stream))
  (let ((authenticated nil))
    (unwind-protect
         (loop while (and *connector-running*
                          (open-stream-p stream))
               do (handler-case
                      (let ((line (read-line stream nil nil)))
                        (when line
                          (let ((msg (decode-message line)))
                            ;; 检查认证
                            (if (or authenticated
                                    (eq (oc-message-type msg) :handshake))
                                (progn
                                  (when (eq (oc-message-type msg) :handshake)
                                    (setf authenticated
                                          (verify-handshake msg)))
                                  (dispatch-message msg))
                                (send-error-response
                                 msg "Authentication required")))))
                    (error (condition)
                      (log:error "Client ~a error: ~a" client-id condition)
                      (return))))
      ;; 清理连接
      (bordeaux-threads:with-lock-held (*client-connections-lock*)
        (remhash client-id *client-connections*))
      (ignore-errors (close stream))
      (log:info "Client disconnected: ~a" client-id))))

;;;; 握手验证

(defun verify-handshake (msg)
  "验证握手"
  (declare (type oc-message msg))
  (let* ((metadata (oc-message-metadata msg))
         (api-key (gethash :api_key metadata)))
    (if (string= api-key *connector-api-key*)
        (progn
          ;; 发送成功响应
          (let ((response (make-response-message msg "Handshake OK")))
            (send-message response))
          t)
        (progn
          ;; 发送失败响应
          (send-error-response msg "Invalid API key")
          nil))))

;;;; 广播

(defun broadcast-to-clients (msg)
  "广播消息到所有客户端"
  (declare (type oc-message msg))
  (bordeaux-threads:with-lock-held (*client-connections-lock*)
    (maphash (lambda (id conn)
               (declare (ignore id))
               (let ((stream (getf conn :stream)))
                 (when (and stream (open-stream-p stream))
                   (let ((data (encode-message msg)))
                     (write-line data stream)
                     (finish-output stream)))))
             *client-connections*)))

;;;; 连接统计

(defun get-connection-stats ()
  "获取连接统计"
  (bordeaux-threads:with-lock-held (*client-connections-lock*)
    (let ((count (hash-table-count *client-connections*)))
      `((:connected-clients . ,count)
        (:uptime . ,(- (get-universal-time) *server-start-time*))))))

(defvar *server-start-time* (get-universal-time)
  "服务器启动时间")

;;;; 配置加载

(defun load-config-from-file (path)
  "从文件加载配置"
  (declare (type string path))
  (when (probe-file path)
    (with-open-file (in path :direction :input)
      (let ((config (cl-json:decode-json in)))
        (when (getf config :host)
          (setf *connector-host* (getf config :host)))
        (when (getf config :port)
          (setf *connector-port* (parse-integer (getf config :port))))
        (when (getf config :api-key)
          (setf *connector-api-key* (getf config :api-key)))
        config))))

;;;; 主函数

(defun main ()
  "主函数"
  (handler-case
      (progn
        ;; 加载配置
        (load-config-from-file "config.json")

        ;; 启动服务器
        (start-connector :host *connector-host*
                         :port *connector-port*
                         :api-key *connector-api-key*)

        ;; 保持运行
        (loop while *connector-running*
              do (sleep 1)))

    (sb-sys:interrupt (condition)
      (declare (ignore condition))
      (log:info "Received interrupt signal")
      (stop-connector))))

;;;; REPL 辅助

(defun repl-start (&key (host *connector-host*)
                        (port *connector-port*)
                        (api-key ""))
  "REPL 启动辅助"
  (start-connector :host host :port port :api-key api-key))

(defun repl-stop ()
  "REPL 停止辅助"
  (stop-connector))
