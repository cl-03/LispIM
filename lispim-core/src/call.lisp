;;;; call.lisp - 语音/视频通话模块
;;;;
;;;; 提供 WebRTC 信令支持，通话管理等功能
;;;; Features: 呼叫邀请，信令转发，通话记录

(in-package :lispim-core)

;;;; 依赖声明

(eval-when (:compile-toplevel :load-toplevel :execute)
  (ql:quickload '(:postmodern :cl-redis :cl-json :uuid)))

;;;; 数据结构

(defstruct call
  "通话记录"
  (id "" :type string)
  (caller-id "" :type string)
  (callee-id "" :type string)
  (conversation-id 0 :type integer)
  (type :voice :type keyword) ; :voice / :video
  (status :calling :type keyword) ; :calling / :answered / :ended / :cancelled / :rejected
  (started-at nil :type (or null integer))
  (ended-at nil :type (or null integer))
  (duration 0 :type integer)
  (created-at 0 :type integer))

;;;; 数据库表初始化

(defun ensure-call-tables-exist ()
  "创建通话相关数据库表"
  (ensure-pg-connected)

  ;; 通话记录表
  (postmodern:query
   "CREATE TABLE IF NOT EXISTS calls (
      id VARCHAR(64) PRIMARY KEY,
      caller_id VARCHAR(255) NOT NULL,
      callee_id VARCHAR(255) NOT NULL,
      conversation_id BIGINT,
      type VARCHAR(20) DEFAULT 'voice',
      status VARCHAR(20) DEFAULT 'calling',
      started_at TIMESTAMPTZ,
      ended_at TIMESTAMPTZ,
      duration INTEGER DEFAULT 0,
      created_at TIMESTAMPTZ DEFAULT NOW()
    )")

  (postmodern:query
   "CREATE INDEX IF NOT EXISTS idx_calls_caller ON calls(caller_id)")
  (postmodern:query
   "CREATE INDEX IF NOT EXISTS idx_calls_callee ON calls(callee_id)")
  (postmodern:query
   "CREATE INDEX IF NOT EXISTS idx_calls_conversation ON calls(conversation_id)")
  (postmodern:query
   "CREATE INDEX IF NOT EXISTS idx_calls_status ON calls(status)")
  (postmodern:query
   "CREATE INDEX IF NOT EXISTS idx_calls_created ON calls(created_at DESC)")

  (log-info "Call tables initialized"))

;;;; 通话操作

(defun create-call (caller-id callee-id call-type &key conversation-id)
  "创建通话记录"
  (declare (type string caller-id callee-id)
           (type keyword call-type)
           (type (or null integer) conversation-id))

  (let* ((call-id (generate-snowflake))
         (now (get-universal-time)))

    (postmodern:query
     "INSERT INTO calls
      (id, caller_id, callee_id, conversation_id, type, status, created_at)
      VALUES ($1, $2, $3, $4, $5, $6, to_timestamp($7))"
     call-id caller-id callee-id conversation-id
     (string-downcase call-type) "calling"
     (storage-universal-to-unix now))

    (log-info "Call created: ~a (~a -> ~a)" call-id caller-id callee-id)

    (make-call
     :id call-id
     :caller-id caller-id
     :callee-id callee-id
     :conversation-id (or conversation-id 0)
     :type call-type
     :status :calling
     :created-at now)))

(defun get-call (call-id)
  "获取通话记录"
  (declare (type string call-id))

  (let ((result (postmodern:query
                 "SELECT * FROM calls WHERE id = $1"
                 call-id :alists)))

    (when result
      (let ((row (car result)))
        (flet ((get-val (name)
                 (let ((cell (find name row :key #'car :test #'string=)))
                   (when cell (cdr cell)))))
          (make-call
           :id (get-val "ID")
           :caller-id (get-val "CALLER_ID")
           :callee-id (get-val "CALLEE_ID")
           :conversation-id (parse-integer (get-val "CONVERSATION_ID"))
           :type (keywordify (get-val "TYPE"))
           :status (keywordify (get-val "STATUS"))
           :started-at (storage-universal-to-unix (get-val "STARTED_AT"))
           :ended-at (storage-universal-to-unix (get-val "ENDED_AT"))
           :duration (parse-integer (get-val "DURATION"))
           :created-at (storage-universal-to-unix (get-val "CREATED_AT"))))))))

(defun update-call-status (call-id status &key duration)
  "更新通话状态"
  (declare (type string call-id status)
           (type (or null integer) duration))

  (let ((now (get-universal-time)))
    (cond
      ((string= status "answered")
       (postmodern:query
        "UPDATE calls SET status = $2, started_at = to_timestamp($3)
         WHERE id = $1"
        call-id status (storage-universal-to-unix now)))
      ((member (keywordify status) '(:ended :cancelled :rejected))
       (let ((call (get-call call-id)))
         (when call
           (let ((call-duration (or duration
                                    (if (call-started-at call)
                                        (- now (call-started-at call))
                                        0))))
             (postmodern:query
              "UPDATE calls SET status = $2, ended_at = to_timestamp($3), duration = $4
               WHERE id = $1"
              call-id status (storage-universal-to-unix now) call-duration)))))
      (t
       (postmodern:query
        "UPDATE calls SET status = $2 WHERE id = $1"
        call-id status))))

  (log-info "Call ~a status updated to ~a" call-id status)
  t)

(defun get-user-calls (user-id &key limit offset)
  "获取用户的通话记录列表"
  (declare (type string user-id)
           (type (or null integer) limit offset))

  (let* ((sql "SELECT * FROM calls
               WHERE caller_id = $1 OR callee_id = $1
               ORDER BY created_at DESC")
         (params (list user-id)))

    (when limit
      (setf sql (concat sql " LIMIT " (write-to-string limit))))

    (when offset
      (setf sql (concat sql " OFFSET " (write-to-string offset))))

    (let ((result (apply (function (lambda (s p) (postmodern:query s p :alists))) (list sql params))))
      (when result
        (loop for row in result
              collect
              (flet ((get-val (name)
                       (let ((cell (find name row :key #'car :test #'string=)))
                         (when cell (cdr cell)))))
                (list :id (get-val "ID")
                      :caller-id (get-val "CALLER_ID")
                      :callee-id (get-val "CALLEE_ID")
                      :conversation-id (parse-integer (get-val "CONVERSATION_ID"))
                      :type (keywordify (get-val "TYPE"))
                      :status (keywordify (get-val "STATUS"))
                      :duration (parse-integer (get-val "DURATION"))
                      :started-at (storage-universal-to-unix (get-val "STARTED_AT"))
                      :ended-at (storage-universal-to-unix (get-val "ENDED_AT"))
                      :created-at (storage-universal-to-unix (get-val "CREATED_AT")))))))))

;;;; Redis 信令通道

(defun redis-call-signaling-channel (call-id)
  "获取通话信令 Redis 频道"
  (declare (type string call-id))
  (format nil "call:signaling:~a" call-id))

(defun publish-call-offer (call-id caller-id offer)
  "发布 SDP Offer"
  (declare (type string call-id caller-id)
           (type string offer))

  (when (get-redis)
    (redis:red-publish (redis-call-signaling-channel call-id)
                       (cl-json:encode-json-to-string
                        (list :type "offer"
                              :callId call-id
                              :callerId caller-id
                              :offer offer))))
  t)

(defun publish-call-answer (call-id callee-id answer)
  "发布 SDP Answer"
  (declare (type string call-id callee-id)
           (type string answer))

  (when (get-redis)
    (redis:red-publish (redis-call-signaling-channel call-id)
                       (cl-json:encode-json-to-string
                        (list :type "answer"
                              :callId call-id
                              :calleeId callee-id
                              :answer answer))))
  t)

(defun publish-ice-candidate (call-id sender-id candidate)
  "发布 ICE Candidate"
  (declare (type string call-id sender-id candidate))

  (when (get-redis)
    (redis:red-publish (redis-call-signaling-channel call-id)
                       (cl-json:encode-json-to-string
                        (list :type "ice-candidate"
                              :callId call-id
                              :senderId sender-id
                              :candidate candidate))))
  t)

(defun subscribe-call-signaling (call-id callback)
  "订阅通话信令"
  (declare (type string call-id)
           (type function callback))

  (let ((channel (redis-call-signaling-channel call-id))
        (running t))

    ;; 启动订阅线程
    (bordeaux-threads:make-thread
     (lambda ()
       (handler-case
           (progn
             (redis:red-subscribe channel)
             (loop while running
                   do (let ((msg (redis:red-get channel)))
                        (when msg
                          (funcall callback msg)))))
         (error (c)
           (log-error "Call signaling error: ~a" c)
           (setf running nil)))))

    ;; 返回取消订阅函数
    (lambda ()
      (setf running nil)
      (redis:red-unsubscribe channel))))

;;;; 导出函数

(export '(ensure-call-tables-exist
          create-call
          get-call
          update-call-status
          get-user-calls
          redis-call-signaling-channel
          publish-call-offer
          publish-call-answer
          publish-ice-candidate
          subscribe-call-signaling))
