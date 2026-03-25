;;;; test-chat.lisp - Chat 模块测试

(in-package :lispim-core/test)

(eval-when (:compile-toplevel :load-toplevel :execute)
  (ql:quickload '(:fiveam :lispim-core)))

(in-package :lispim-core/test)

(def-suite :test-chat
  :description "Chat 模块测试套件")

(in-suite :test-chat)

;;;; 测试：消息创建

(test test-message-create
  "测试消息创建"
  (let ((msg (lispim-core::make-message
              :sender-id "user-123"
              :content "Hello, World!"
              :message-type :text)))
    (is (typep (lispim-core::message-id msg) 'integer))
    (is (string= (lispim-core::message-sender-id msg) "user-123"))
    (is (string= (lispim-core::message-content msg) "Hello, World!"))
    (is (eq (lispim-core::message-message-type msg) :text))
    (is (not (lispim-core::message-recalled-p msg)))))

;;;; 测试：会话创建

(test test-conversation-create
  "测试会话创建"
  (let ((conv (lispim-core::make-conversation
               :type :direct
               :participants (list "user-1" "user-2"))))
    (is (typep (lispim-core::conversation-id conv) 'integer))
    (is (eq (lispim-core::conversation-type conv) :direct))
    (is (= 2 (length (lispim-core::conversation-participants conv))))))

;;;; 测试：群组会话创建

(test test-group-conversation-create
  "测试群组会话创建"
  (let ((conv (lispim-core::make-conversation
               :type :group
               :name "Test Group"
               :creator-id "user-1"
               :participants (list "user-1" "user-2" "user-3"))))
    (is (eq (lispim-core::conversation-type conv) :group))
    (is (string= (lispim-core::conversation-name conv) "Test Group"))
    (is (= 3 (length (lispim-core::conversation-participants conv))))))

;;;; 测试：消息序列号

(test test-message-sequence
  "测试消息序列号生成"
  (let ((conv-id 12345))
    (lispim-core::reset-snowflake)  ; 重置计数器

    (let ((seq1 (lispim-core::get-next-sequence conv-id))
          (seq2 (lispim-core::get-next-sequence conv-id))
          (seq3 (lispim-core::get-next-sequence conv-id)))
      (is (= seq1 1))
      (is (= seq2 2))
      (is (= seq3 3))
      (is (< seq1 seq2 seq3)))))

;;;; 测试：消息已读回执

(test test-message-read-receipt
  "测试消息已读回执"
  (let ((msg (lispim-core::make-message
              :sender-id "user-1"
              :content "Test message")))
    ;; 初始应该是未读
    (is (null (lispim-core::message-read-by msg)))

    ;; 标记已读
    (push (cons "user-2" (get-universal-time))
          (lispim-core::message-read-by msg))

    ;; 应该有一个已读记录
    (is (= 1 (length (lispim-core::message-read-by msg))))))

;;;; 测试：消息撤回

(test test-message-recall
  "测试消息撤回"
  (let ((msg (lispim-core::make-message
              :sender-id "user-1"
              :content "Test message"
              :created-at (get-universal-time))))
    ;; 初始应该是未撤回
    (is (not (lispim-core::message-recalled-p msg)))

    ;; 撤回消息
    (setf (lispim-core::message-recalled-p msg) t
          (lispim-core::message-content msg) "[消息已撤回]")

    ;; 应该是已撤回状态
    (is (lispim-core::message-recalled-p msg))
    (is (string= (lispim-core::message-content msg) "[消息已撤回]"))))

;;;; 测试：@提及

(test test-message-mentions
  "测试消息@提及"
  (let ((msg (lispim-core::make-message
              :sender-id "user-1"
              :content "@user-2 @user-3 Hello!"
              :mentions (list "user-2" "user-3"))))
    (is (= 2 (length (lispim-core::message-mentions msg))))
    (is (member "user-2" (lispim-core::message-mentions msg) :test #'string=))
    (is (member "user-3" (lispim-core::message-mentions msg) :test #'string=))))

;;;; 测试：回复消息

(test test-message-reply
  "测试消息回复"
  (let* ((original (lispim-core::make-message
                    :sender-id "user-1"
                    :content "Original message"))
         (reply (lispim-core::make-message
                 :sender-id "user-2"
                 :content "Reply to original"
                 :reply-to (lispim-core::message-id original))))
    (is (not (null (lispim-core::message-reply-to reply))))
    (is (= (lispim-core::message-reply-to reply)
           (lispim-core::message-id original)))))

;;;; 运行所有测试

(defun run-chat-tests ()
  "运行所有 Chat 测试"
  (fiveam:run! :test-chat))
