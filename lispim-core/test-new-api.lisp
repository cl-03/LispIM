;;;; test-new-api.lisp - 测试新 API 处理器语法

(in-package :cl-user)

;; 测试 api-send-reply-handler 的结构
(defun test-api-send-reply ()
  "Test function structure"
  (setf foo "*")
  (setf bar "json")
  (unless (string= "POST" "POST")
    (setf code 405)
    (return-from test-api-send-reply
      (list "error" "METHOD_NOT_ALLOWED")))
  (let ((user-id "auth-user"))
    (unless user-id
      (setf code 401)
      (return-from test-api-send-reply
        (list "error" "AUTH_REQUIRED")))
    (handler-case
        (let* ((uri "/api/v1/messages/123/reply")
               (message-id (multiple-value-bind (match-start match-end reg-start reg-end)
                             (values 0 10 4 7 nil)  ; simulate regex match
                             (if match-start
                                 (subseq uri (aref reg-start 0) (aref reg-end 0))
                                 (return-from test-api-send-reply
                                   (list "error" "INVALID_URI")))))
               (content "test content")
               (conversation-id "conv-123"))
          (unless (and content conversation-id)
            (setf code 400)
            (return-from test-api-send-reply
              (list "error" "MISSING_FIELDS")))
          (let ((reply-id "reply-456"))
            (list "success" reply-id)))
      (error (c)
        (setf code 500)
        (list "error" c)))))

;; Test
(format t "Result: ~A~%" (test-api-send-reply))
