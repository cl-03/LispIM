;;;; handler.lisp - OpenClaw 消息处理器
;;;;
;;;; 负责注册和处理各种消息类型

(in-package :openclaw-connector)

;;;; 消息处理器注册表

(defvar *message-handlers* (make-hash-table :test 'eq)
  "消息处理器注册表：message-type -> handler-function")

(defvar *command-handlers* (make-hash-table :test 'equal)
  "命令处理器注册表：command-name -> handler-function")

;;;; 处理器注册

(defun register-handler (type handler)
  "注册消息处理器"
  (declare (type oc-message-type type)
           (type function handler))
  (setf (gethash type *message-handlers*) handler)
  (log:info "Registered handler for: ~a" type))

(defun unregister-handler (type)
  "注销消息处理器"
  (declare (type oc-message-type type))
  (remhash type *message-handlers*))

(defun register-command-handler (command handler)
  "注册命令处理器"
  (declare (type string command)
           (type function handler))
  (setf (gethash command *command-handlers*) handler)
  (log:info "Registered command handler: ~a" command))

;;;; 消息分发

(defun dispatch-message (msg)
  "分发消息到处理器"
  (declare (type oc-message msg))
  (let ((handler (gethash (oc-message-type msg) *message-handlers*)))
    (if handler
        (handler-case
            (funcall handler msg)
          (error (condition)
            (log:error "Handler error: ~a" condition)
            (send-error-response msg condition)))
        (progn
          (log:warn "No handler for message type: ~a" (oc-message-type msg))
          (handle-default msg)))))

;;;; 默认处理器

(defun handle-default (msg)
  "默认消息处理"
  (declare (type oc-message msg))
  (log:debug "Default handling: ~a" (oc-message-id msg)))

;;;; 握手处理器

(defun handle-handshake (msg)
  "握手消息处理"
  (declare (type oc-message msg))
  (log:info "Handshake received from: ~a" (oc-message-sender msg))
  ;; 发送握手确认
  (let ((response (make-response-message msg "Handshake OK")))
    (send-message response)))

(register-handler :handshake #'handle-handshake)

;;;; Chat 消息处理器

(defun handle-chat (msg)
  "Chat 消息处理"
  (declare (type oc-message msg))
  (log:info "Chat message from: ~a" (oc-message-sender msg))

  (let* ((content (oc-message-content msg))
         (response-content (process-chat-message content)))

    ;; 发送响应
    (let ((response (make-response-message msg response-content)))
      (send-message response))))

(register-handler :chat #'handle-chat)

(defun process-chat-message (content)
  "处理 Chat 消息内容"
  (declare (type (or null string) content))
  ;; 这里可以实现本地 AI 处理逻辑
  ;; 或者转发到外部 AI 服务
  (format nil "Received: ~a" content))

;;;; Command 消息处理器

(defun handle-command (msg)
  "Command 消息处理"
  (declare (type oc-message msg))
  (let* ((metadata (oc-message-metadata msg))
         (command (gethash :command metadata))
         (args (gethash :args metadata)))

    (if command
        (let ((handler (gethash command *command-handlers*)))
          (if handler
              (handler-case
                  (let ((result (funcall handler args)))
                    (send-response msg result))
                (error (condition)
                  (send-error-response msg condition)))
              (send-error-response msg (format nil "Unknown command: ~a" command))))
        (send-error-response msg "Command name required"))))

(register-handler :command #'handle-command)

;;;; Stream 消息处理器

(defun handle-stream (msg)
  "Stream 消息处理"
  (declare (type oc-message msg))
  (log:info "Stream message from: ~a" (oc-message-sender msg))
  ;; 流式处理逻辑
  (handle-stream-data msg))

(register-handler :stream #'handle-stream)

(defun handle-stream-data (msg)
  "处理流式数据"
  (declare (type oc-message msg))
  ;; 实现流式数据处理
  )

;;;; Heartbeat 处理器

(defun handle-heartbeat (msg)
  "Heartbeat 消息处理"
  (declare (type oc-message msg))
  (log:debug "Heartbeat received")
  ;; 更新最后活跃时间
  (setf (gethash :last-active (oc-message-metadata msg)) (get-universal-time)))

(register-handler :heartbeat #'handle-heartbeat)

;;;; Error 处理器

(defun handle-error (msg)
  "Error 消息处理"
  (declare (type oc-message msg))
  (log:error "Error received: ~a" (oc-message-content msg)))

(register-handler :error #'handle-error)

;;;; 响应辅助

(defun send-response (request-msg content)
  "发送响应"
  (declare (type oc-message request-msg)
           (type (or null string) content))
  (let ((response (make-response-message request-msg content)))
    (send-message response)))

(defun send-error-response (request-msg error)
  "发送错误响应"
  (declare (type oc-message request-msg)
           (type (or string condition) error))
  (let ((response (make-response-message
                   request-msg
                   (if (stringp error) error (format nil "~a" error))
                   :error-p t)))
    (setf (gethash :error-type (oc-message-metadata response))
          (type-of error))
    (send-message response)))

;;;; 消息验证

(defun validate-message (msg)
  "验证消息"
  (declare (type oc-message msg))
  (let ((valid t))
    ;; 检查版本
    (unless (string= (oc-message-version msg) *oc-protocol-version*)
      (setf valid nil)
      (log:warn "Invalid protocol version: ~a" (oc-message-version msg)))
    ;; 检查大小
    (let ((encoded (encode-message msg)))
      (when (> (length encoded) +oc-max-message-size+)
        (setf valid nil)
        (log:warn "Message too large: ~a bytes" (length encoded))))
    valid))

;;;; 消息过滤

(defvar *message-filters* nil
  "消息过滤器列表")

(defun add-message-filter (filter)
  "添加消息过滤器"
  (declare (type function filter))
  (push filter *message-filters*))

(defun remove-message-filter (filter)
  "移除消息过滤器"
  (declare (type function filter))
  (setf *message-filters* (remove filter *message-filters*)))

(defun apply-filters (msg)
  "应用消息过滤器"
  (declare (type oc-message msg))
  (let ((result msg))
    (dolist (filter *message-filters* result)
      (setf result (funcall filter result))
      (when (null result)
        (return nil)))))
