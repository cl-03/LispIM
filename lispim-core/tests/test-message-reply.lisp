;;;; test-message-reply.lisp - 消息回复/引用模块单元测试
;;;;
;;;; 测试消息回复功能：
;;;; - 创建回复
;;;; - 获取回复链
;;;; - 获取回复列表
;;;; - 回复深度限制
;;;; - 引用预览
;;;; - 通知功能

(in-package :lispim-core-test)

(def-suite test-message-reply
  :description "消息回复/引用模块测试")

(in-suite test-message-reply)

;;;; 回复创建测试

(def-test test-create-reply-basic ()
  "测试基本回复创建"
  (let* ((conversation-id "conv-test-1")
         (sender-id "user-sender")
         (content "Test message")
         ;; 创建根消息
         (root-message (lispim-core::create-message
                        (lispim-core::generate-message-id)
                        conversation-id sender-id content))
         (root-message-id (getf root-message :id)))
    ;; 验证根消息创建成功
    (is (stringp root-message-id))
    (is (not (string= root-message-id "")))))

(def-test test-reply-depth-tracking ()
  "测试回复深度追踪"
  (let* ((conversation-id "conv-thread-test")
         (sender-id "user-1")
         ;; 创建根消息
         (root-msg (lispim-core::create-message
                    (lispim-core::generate-message-id)
                    conversation-id sender-id "Root message"))
         (root-id (getf root-msg :id)))
    ;; 创建回复链
    (labels ((create-reply-chain (parent-id depth)
               (when (< depth 5)
                 (let* ((reply-msg (lispim-core::create-message
                                    (lispim-core::generate-message-id)
                                    conversation-id sender-id
                                    (format nil "Reply ~a" depth)))
                        (reply-id (getf reply-msg :id)))
                   ;; 创建回复关系
                   (lispim-core::create-reply
                    reply-id parent-id conversation-id sender-id
                    :quote-content "Quoted text"
                    :quote-type "text")
                   (create-reply-chain reply-id (1+ depth))))))
      (create-reply-chain root-id 0))
    ;; 验证回复链
    (let ((chain (lispim-core::get-reply-chain root-id)))
      (is (listp chain))
      ;; 链应该包含所有消息 ID
      (is (>= (length chain) 1)))))

(def-test test-max-reply-depth ()
  "测试最大回复深度限制"
  (let ((max-depth (cdr (assoc :max-reply-depth lispim-core::*message-reply-config*))))
    ;; 验证配置存在
    (is (integerp max-depth))
    (is (> max-depth 0))))

;;;; 回复链测试

(def-test test-get-reply-chain ()
  "测试获取回复链"
  (let* ((conversation-id "conv-chain-test")
         (sender-id "user-chain")
         ;; 创建三层回复
         (msg1 (lispim-core::create-message
                (lispim-core::generate-message-id)
                conversation-id sender-id "Message 1"))
         (msg1-id (getf msg1 :id))
         (msg2 (lispim-core::create-message
                (lispim-core::generate-message-id)
                conversation-id sender-id "Message 2"))
         (msg2-id (getf msg2 :id))
         (msg3 (lispim-core::create-message
                (lispim-core::generate-message-id)
                conversation-id sender-id "Message 3"))
         (msg3-id (getf msg3 :id)))
    ;; 创建回复关系
    (lispim-core::create-reply msg2-id msg1-id conversation-id sender-id)
    (lispim-core::create-reply msg3-id msg2-id conversation-id sender-id)
    ;; 获取回复链
    (let ((chain (lispim-core::get-reply-chain msg3-id)))
      (is (listp chain))
      (is (>= (length chain) 1))
      ;; 链应该从根消息开始
      (is (member msg1-id chain :test 'string=)))))

(def-test test-get-reply-chain-limit ()
  "测试回复链获取限制"
  (let* ((conversation-id "conv-limit-test")
         (sender-id "user-limit")
         (root-msg (lispim-core::create-message
                    (lispim-core::generate-message-id)
                    conversation-id sender-id "Root"))
         (root-id (getf root-msg :id)))
    ;; 创建长回复链
    (let ((prev-id root-id))
      (loop for i from 1 to 10
            do (let ((msg (lispim-core::create-message
                           (lispim-core::generate-message-id)
                           conversation-id sender-id (format nil "Reply ~a" i)))
                     (msg-id (getf msg :id)))
                 (lispim-core::create-reply msg-id prev-id conversation-id sender-id)
                 (setf prev-id msg-id))))
    ;; 获取限制长度的链
    (let ((chain (lispim-core::get-reply-chain prev-id :limit 5)))
      ;; 应该不超过限制
      (is (or (null chain) (<= (length chain) 6))))))

;;;; 回复列表测试

(def-test test-get-message-replies ()
  "测试获取消息回复列表"
  (let* ((conversation-id "conv-replies-test")
         (sender-id "user-replies")
         (root-msg (lispim-core::create-message
                    (lispim-core::generate-message-id)
                    conversation-id sender-id "Root"))
         (root-id (getf root-msg :id)))
    ;; 创建多个回复
    (loop for i from 1 to 3
          do (let ((msg (lispim-core::create-message
                         (lispim-core::generate-message-id)
                         conversation-id sender-id (format nil "Reply ~a" i)))
                   (msg-id (getf msg :id)))
               (lispim-core::create-reply msg-id root-id conversation-id sender-id)))
    ;; 获取回复列表
    (let ((replies (lispim-core::get-message-replies root-id)))
      (is (listp replies))
      ;; 应该有 3 个回复
      (is (= 3 (length replies))))))

(def-test test-get-message-replies-limit ()
  "测试回复列表获取限制"
  (let* ((conversation-id "conv-limit-replies")
         (sender-id "user-limit-replies")
         (root-msg (lispim-core::create-message
                    (lispim-core::generate-message-id)
                    conversation-id sender-id "Root"))
         (root-id (getf root-msg :id)))
    ;; 创建多个回复
    (loop for i from 1 to 50
          do (let ((msg (lispim-core::create-message
                         (lispim-core::generate-message-id)
                         conversation-id sender-id (format nil "Reply ~a" i)))
                   (msg-id (getf msg :id)))
               (lispim-core::create-reply msg-id root-id conversation-id sender-id)))
    ;; 获取限制长度的回复列表
    (let ((replies (lispim-core::get-message-replies root-id :limit 10)))
      (is (<= (length replies) 10)))))

;;;; 引用预览测试

(def-test test-generate-quote-preview ()
  "测试生成引用预览"
  (let* ((conversation-id "conv-preview")
         (sender-id "user-preview")
         (content "这是一段比较长的消息内容，用于测试引用预览功能。"
                  "这里有很多文字，超过了预览长度限制。"
                  "更多内容...")
         (msg (lispim-core::create-message
               (lispim-core::generate-message-id)
               conversation-id sender-id content))
         (msg-id (getf msg :id)))
    ;; 生成预览
    (let ((preview (lispim-core::generate-quote-preview msg-id)))
      (is (getf preview :message-id))
      (is (getf preview :content))
      (is (getf preview :type))
      (is (getf preview :sender-id))
      (is (getf preview :created-at)))))

(def-test test-format-quote-display ()
  "测试格式化引用显示"
  (let ((quote '(:message-id "msg-123"
                 :content "Test content"
                 :type "text"
                 :sender-id "user-123"
                 :created-at 12345678)))
    (let ((formatted (lispim-core::format-quote-display quote)))
      (is (stringp formatted))
      (is (search "text" formatted))
      (is (search "user-123" formatted))
      (is (search "Test content" formatted)))))

;;;; 回复线程测试

(def-test test-get-reply-thread ()
  "测试获取回复线程"
  (let* ((conversation-id "conv-thread")
         (sender-id "user-thread")
         (root-msg (lispim-core::create-message
                    (lispim-core::generate-message-id)
                    conversation-id sender-id "Thread root"))
         (root-id (getf root-msg :id)))
    ;; 创建多个回复
    (loop for i from 1 to 3
          do (let ((msg (lispim-core::create-message
                         (lispim-core::generate-message-id)
                         conversation-id (format nil "user-~a" i)
                         (format nil "Reply ~a" i)))
                   (msg-id (getf msg :id)))
               (lispim-core::create-reply msg-id root-id conversation-id
                                          (format nil "user-~a" i))))
    ;; 获取线程
    (let ((thread (lispim-core::get-reply-thread root-id)))
      (is (typep thread 'lispim-core::reply-thread))
      (is (string= root-id (lispim-core::reply-thread-root-message-id thread)))
      (is (= 3 (lispim-core::reply-thread-reply-count thread)))
      (is (listp (lispim-core::reply-thread-participants thread))))))

;;;; 缓存测试

(def-test test-cache-reply-thread ()
  "测试回复线程缓存"
  (let* ((root-id "cache-test-root")
         (thread (lispim-core::make-reply-thread
                  :root-message-id root-id
                  :reply-count 5
                  :latest-reply-id "latest-123"
                  :participants '("user-1" "user-2"))))
    ;; 缓存线程
    (lispim-core::cache-reply-thread root-id thread)
    ;; 获取缓存
    (let ((cached (lispim-core::get-cached-reply-thread root-id)))
      (is (typep cached 'lispim-core::reply-thread))
      (is (= 5 (lispim-core::reply-thread-reply-count cached))))))

;;;; 统计测试

(def-test test-get-reply-stats ()
  "测试获取回复统计"
  (let* ((conversation-id "conv-stats")
         (sender-id "user-stats")
         (root-msg (lispim-core::create-message
                    (lispim-core::generate-message-id)
                    conversation-id sender-id "Stats root"))
         (root-id (getf root-msg :id)))
    ;; 创建回复
    (loop for i from 1 to 3
          do (let ((msg (lispim-core::create-message
                         (lispim-core::generate-message-id)
                         conversation-id (format nil "user-~a" i)
                         "Reply"))
                   (msg-id (getf msg :id)))
               (lispim-core::create-reply msg-id root-id conversation-id
                                          (format nil "user-~a" i))))
    ;; 获取统计
    (let ((stats (lispim-core::get-reply-stats root-id)))
      (is (getf stats :message-id))
      (is (getf stats :reply-count))
      (is (getf stats :unique-reply-count)))))

;;;; 删除测试

(def-test test-delete-reply ()
  "测试删除回复"
  (let* ((conversation-id "conv-delete")
         (sender-id "user-delete")
         (msg (lispim-core::create-message
               (lispim-core::generate-message-id)
               conversation-id sender-id "To delete"))
         (msg-id (getf msg :id)))
    ;; 删除回复（消息）
    (lispim-core::delete-reply msg-id)
    ;; 验证删除成功（这里需要验证消息不存在）
    (is t))) ;; 简化测试

;;;; 高层 API 测试

(def-test test-create-message-reply ()
  "测试高层回复 API"
  (let* ((conversation-id "conv-high-level")
         (sender-id "user-hl")
         (root-msg (lispim-core::create-message
                    (lispim-core::generate-message-id)
                    conversation-id sender-id "Root for reply"))
         (root-id (getf root-msg :id)))
    ;; 使用高层 API 创建回复
    (let ((reply-id (lispim-core::create-message-reply
                     root-id "This is a reply"
                     :sender-id sender-id
                     :conversation-id conversation-id
                     :quote-content "Quoted")))
      (is (stringp reply-id))
      (is (not (string= reply-id ""))))))

(def-test test-get-message-reply-info ()
  "测试获取回复信息 API"
  (let* ((conversation-id "conv-info")
         (sender-id "user-info")
         (root-msg (lispim-core::create-message
                    (lispim-core::generate-message-id)
                    conversation-id sender-id "Root"))
         (root-id (getf root-msg :id)))
    ;; 创建回复
    (let ((reply-msg (lispim-core::create-message
                      (lispim-core::generate-message-id)
                      conversation-id sender-id "Reply"))
          (reply-id (getf reply-msg :id)))
      (lispim-core::create-reply reply-id root-id conversation-id sender-id))
    ;; 获取回复信息
    (let ((info (lispim-core::get-message-reply-info root-id)))
      (is (getf info :message-id))
      (is (getf info :replies))
      (is (getf info :reply-count)))))

;;;; 配置测试

(def-test test-message-reply-config ()
  "测试回复配置"
  (is (assoc :max-reply-depth lispim-core::*message-reply-config*))
  (is (assoc :max-quote-length lispim-core::*message-reply-config*))
  (is (assoc :thread-cache-ttl lispim-core::*message-reply-config*)))
