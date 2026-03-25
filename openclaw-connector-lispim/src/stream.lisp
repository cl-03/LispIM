;;;; stream.lisp - OpenClaw 流式处理
;;;;
;;;; 负责流式消息的发送和接收

(in-package :openclaw-connector)

;;;; 流会话

(defstruct oc-stream-session
  "流会话"
  (id (uuid:to-string (uuid:make-v4-uuid)) :type string)
  (conversation-id nil :type (or null string))
  (created-at (get-universal-time) :type integer)
  (last-activity (get-universal-time) :type integer)
  (status :active :type (member :active :paused :closed))
  (message-count 0 :type integer)
  (metadata (make-hash-table :test 'equal) :type hash-table))

(defvar *stream-sessions* (make-hash-table :test 'equal)
  "流会话表")

;;;; 流打开

(defun oc-stream-open (conversation-id &key metadata)
  "打开流会话"
  (declare (type (or null string) conversation-id))
  (let ((session (make-oc-stream-session
                  :conversation-id conversation-id
                  :metadata (or metadata (make-hash-table :test 'equal)))))
    (setf (gethash (oc-stream-session-id session) *stream-sessions*) session)
    (log:info "Stream session opened: ~a" (oc-stream-session-id session))
    session))

;;;; 流关闭

(defun oc-stream-close (session-id)
  "关闭流会话"
  (declare (type string session-id))
  (let ((session (gethash session-id *stream-sessions*)))
    (when session
      (setf (oc-stream-session-status session) :closed)
      (remhash session-id *stream-sessions*)
      (log:info "Stream session closed: ~a" session-id)
      t)))

;;;; 流发送

(defun oc-stream-send (session-id content &key (stream-p t))
  "发送流式消息"
  (declare (type string session-id)
           (type string content))
  (let ((session (gethash session-id *stream-sessions*)))
    (unless session
      (error "Stream session not found: ~a" session-id))

    ;; 创建流消息
    (let ((msg (make-oc-message
                :stream
                content
                :metadata (let ((ht (make-hash-table :test 'equal)))
                            (setf (gethash :session-id ht) session-id)
                            (setf (gethash :stream-p ht) stream-p)
                            (setf (gethash :sequence ht)
                                  (oc-stream-session-message-count session)))
                            ht))))

      ;; 发送
      (send-message msg)

      ;; 更新会话
      (incf (oc-stream-session-message-count session))
      (setf (oc-stream-session-last-activity session) (get-universal-time))

      msg)))

;;;; 流接收

(defun oc-stream-receive (&key (timeout 30))
  "接收流式消息"
  (declare (type integer timeout))
  (let ((start-time (get-universal-time))
        (chunks nil))

    (loop
      (let ((msg (oc-receive)))
        (when msg
          (when (eq (oc-message-type msg) :stream)
            (let ((content (oc-message-content msg)))
              (push content chunks)
              ;; 检查是否结束
              (when (or (gethash :end-p (oc-message-metadata msg))
                        (not (gethash :stream-p (oc-message-metadata msg))))
                (return (values (apply #'concatenate 'string (nreverse chunks))
                                msg))))))

        ;; 超时检查
        (when (> (- (get-universal-time) start-time) timeout)
          (error "Stream receive timeout")))

      (sleep 0.1))))

;;;; 流式 AI 响应

(defun stream-ai-response (conversation-id prompt &key (chunk-size 50))
  "流式 AI 响应"
  (declare (type (or null string) conversation-id)
           (type string prompt)
           (type integer chunk-size))

  ;; 打开流会话
  (let ((session (oc-stream-open conversation-id)))
    (unwind-protect
         (progn
           ;; 发送请求
           (oc-stream-send (oc-stream-session-id session) prompt)

           ;; 接收流式响应
           (multiple-value-bind (content response-msg)
               (oc-stream-receive)
             (declare (ignore response-msg))

             ;; 分块发送
             (let ((start 0)
                   (len (length content)))
               (loop while (< start len)
                     do (let* ((end (min (+ start chunk-size) len))
                               (chunk (subseq content start end)))
                          (oc-stream-send (oc-stream-session-id session)
                                          chunk
                                          :stream-p (< end len)))
                        (incf start chunk-size)
                        (sleep 0.05)))))

         ;; 关闭会话
         (oc-stream-close (oc-stream-session-id session))))))

;;;; 流控制

(defun oc-stream-pause (session-id)
  "暂停流"
  (declare (type string session-id))
  (let ((session (gethash session-id *stream-sessions*)))
    (when session
      (setf (oc-stream-session-status session) :paused)
      (log:info "Stream paused: ~a" session-id))))

(defun oc-stream-resume (session-id)
  "恢复流"
  (declare (type string session-id))
  (let ((session (gethash session-id *stream-sessions*)))
    (when session
      (setf (oc-stream-session-status session) :active)
      (log:info "Stream resumed: ~a" session-id))))

;;;; 流合并

(defun merge-streams (stream-ids)
  "合并多个流"
  (declare (type list stream-ids))
  (let ((merged-content nil))
    (dolist (id stream-ids)
      (let ((session (gethash id *stream-sessions*)))
        (when session
          ;; 获取流内容
          )))
    merged-content))

;;;; 上下文摘要

(defun summarize-stream-context (session-id &key (max-length 1000))
  "摘要流上下文"
  (declare (type string session-id)
           (type integer max-length))
  (let ((session (gethash session-id *stream-sessions*)))
    (when session
      ;; 实现上下文摘要逻辑
      (let ((messages (gethash :messages (oc-stream-session-metadata session))))
        (summarize-messages messages max-length)))))

(defun summarize-messages (messages max-length)
  "摘要消息"
  (declare (type list messages)
           (type integer max-length))
  ;; 简化实现
  (format nil "Context summary: ~a messages" (length messages)))

;;;; 流统计

(defun get-stream-stats (session-id)
  "获取流统计"
  (declare (type string session-id))
  (let ((session (gethash session-id *stream-sessions*)))
    (when session
      `((:session-id . ,(oc-stream-session-id session))
        (:conversation-id . ,(oc-stream-session-conversation-id session))
        (:message-count . ,(oc-stream-session-message-count session))
        (:status . ,(oc-stream-session-status session))
        (:duration . ,(- (oc-stream-session-last-activity session)
                         (oc-stream-session-created-at session)))))))
