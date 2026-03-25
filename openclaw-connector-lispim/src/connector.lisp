;;;; connector.lisp - OpenClaw Connector 核心
;;;;
;;;; 负责与 OpenClaw 建立和维持连接

(in-package :openclaw-connector)

;;;; 依赖声明

(eval-when (:compile-toplevel :load-toplevel :execute)
  (ql:quickload '(:cl-async :cl-json :drakma :bordeaux-threads)))

;;;; 连接状态

(defvar *oc-socket* nil
  "OpenClaw WebSocket socket")

(defvar *oc-connected* nil
  "连接状态")

(defvar *oc-stream* nil
  "输入/输出流")

(defvar *oc-heartbeat-thread* nil
  "心跳线程")

;;;; 连接管理

(defun oc-connect (host port &key (api-key ""))
  "连接到 OpenClaw 服务器"
  (declare (type string host)
           (type integer port))
  (log:info "Connecting to OpenClaw: ~a:~a" host port)

  (handler-case
      (progn
        ;; 建立 TCP 连接
        (setf *oc-socket* (usocket:socket-connect host port :element-type '(unsigned-byte 8)))
        (setf *oc-stream* (usocket:socket-stream *oc-socket*))

        ;; 发送握手
        (let ((handshake (make-handshake-message (uuid:to-string (uuid:make-v4-uuid))
                                                 api-key)))
          (send-message handshake))

        ;; 等待握手响应
        (let ((response (receive-message)))
          (if (eq (oc-message-type response) :handshake)
              (progn
                (setf *oc-connected* t)
                (start-heartbeat)
                (log:info "Connected to OpenClaw"))
              (error "Handshake failed")))

        t)

    (error (condition)
      (log:error "Failed to connect to OpenClaw: ~a" condition)
      (oc-disconnect)
      nil)))

(defun oc-disconnect ()
  "断开 OpenClaw 连接"
  (log:info "Disconnecting from OpenClaw")

  ;; 停止心跳
  (stop-heartbeat)

  ;; 关闭连接
  (when *oc-stream*
    (ignore-errors (close *oc-stream*)))
  (when *oc-socket*
    (ignore-errors (usocket:socket-close *oc-socket*)))

  (setf *oc-connected* nil
        *oc-socket* nil
        *oc-stream* nil)

  (log:info "Disconnected from OpenClaw"))

;;;; 消息发送

(defun oc-send (msg)
  "发送消息到 OpenClaw"
  (declare (type oc-message msg))
  (when (and *oc-connected* *oc-stream*)
    (let ((data (encode-message msg)))
      (write-line data *oc-stream*)
      (finish-output *oc-stream*)
      (log:debug "Sent: ~a" (oc-message-id msg)))))

(defun send-message (msg)
  "发送消息（别名）"
  (oc-send msg))

;;;; 消息接收

(defun oc-receive ()
  "从 OpenClaw 接收消息"
  (when (and *oc-connected* *oc-stream*)
    (let ((line (read-line *oc-stream* nil nil)))
      (when line
        (let ((msg (decode-message line)))
          (log:debug "Received: ~a" (oc-message-id msg))
          msg)))))

(defun receive-message ()
  "接收消息（别名）"
  (oc-receive))

;;;; 心跳

(defun start-heartbeat ()
  "启动心跳线程"
  (setf *oc-heartbeat-thread*
        (bordeaux-threads:make-thread
         (lambda ()
           (log:info "Heartbeat thread started")
           (loop while *oc-connected*
                 do (sleep +oc-heartbeat-interval+)
                    (when *oc-connected*
                      (send-message (make-heartbeat-message)))))
         :name "oc-heartbeat"
         :initial-bindings (*standard-output* . *standard-output*))))

(defun stop-heartbeat ()
  "停止心跳线程"
  (when *oc-heartbeat-thread*
    (bordeaux-threads:destroy-thread *oc-heartbeat-thread*)
    (setf *oc-heartbeat-thread* nil)
    (log:info "Heartbeat thread stopped")))

;;;; 自动重连

(defvar *reconnect-p* t
  "是否自动重连")

(defvar *reconnect-delay* +oc-reconnect-delay+
  "重连延迟（秒）")

(defun reconnect-with-retry ()
  "带重试的重连"
  (loop
    (when (oc-connect "localhost" *connector-port*
                      :api-key *connector-api-key*)
      (return t))
    (log:error "Reconnect failed, retrying in ~as" *reconnect-delay*)
    (sleep *reconnect-delay*)))

;;;; 流式处理

(defun handle-stream (callback)
  "处理流式消息"
  (declare (type function callback))
  (loop while *oc-connected*
        do (let ((msg (oc-receive)))
             (when msg
               (funcall callback msg))
             (sleep 0.1))))

;;;; 批量发送

(defun oc-send-batch (messages)
  "批量发送消息"
  (declare (type list messages))
  (dolist (msg messages)
    (oc-send msg)))

;;;; 请求 - 响应模式

(defun oc-request (msg &key (timeout 30))
  "发送请求并等待响应"
  (declare (type oc-message msg)
           (type integer timeout))
  (let* ((request-id (oc-message-id msg))
         (response nil)
         (start-time (get-universal-time)))

    ;; 发送请求
    (oc-send msg)

    ;; 等待响应
    (loop while (and (null response)
                     (< (- (get-universal-time) start-time) timeout))
          do (let ((msg (oc-receive)))
               (when (and msg
                          (string= (gethash :in-reply-to
                                            (oc-message-metadata msg))
                                   request-id))
                 (setf response msg)))
          (sleep 0.1))

    (if response
        response
        (error "Request timeout"))))
