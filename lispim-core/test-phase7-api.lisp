;;;; test-phase7-api.lisp - Phase 7 API Handler Test
;;;;
;;;; 测试 Phase 7 API handler 函数的编译和基本信息

(in-package :lispim-core)

(defun test-phase7-api-handlers ()
  "测试 Phase 7 API handler 是否正确定义"
  (format t "~%========================================~%")
  (format t "  Phase 7 API Handler 测试~%")
  (format t "========================================~%")

  (let ((passed 0)
        (failed 0))

    ;; 测试 1: api-search-handler
    (format t "~%测试 api-search-handler... ~%")
    (if (fboundp 'api-search-handler)
        (progn
          (format t "  [PASS] api-search-handler 已定义~%")
          (incf passed))
        (progn
          (format t "  [FAIL] api-search-handler 未定义~%")
          (incf failed)))

    ;; 测试 2: api-reply-message-handler
    (format t "测试 api-reply-message-handler... ~%")
    (if (fboundp 'api-reply-message-handler)
        (progn
          (format t "  [PASS] api-reply-message-handler 已定义~%")
          (incf passed))
        (progn
          (format t "  [FAIL] api-reply-message-handler 未定义~%")
          (incf failed)))

    ;; 测试 3: api-get-replies-handler
    (format t "测试 api-get-replies-handler... ~%")
    (if (fboundp 'api-get-replies-handler)
        (progn
          (format t "  [PASS] api-get-replies-handler 已定义~%")
          (incf passed))
        (progn
          (format t "  [FAIL] api-get-replies-handler 未定义~%")
          (incf failed)))

    ;; 测试 4: api-get-reply-chain-handler
    (format t "测试 api-get-reply-chain-handler... ~%")
    (if (fboundp 'api-get-reply-chain-handler)
        (progn
          (format t "  [PASS] api-get-reply-chain-handler 已定义~%")
          (incf passed))
        (progn
          (format t "  [FAIL] api-get-reply-chain-handler 未定义~%")
          (incf failed)))

    ;; 测试 5: api-get-thread-handler
    (format t "测试 api-get-thread-handler... ~%")
    (if (fboundp 'api-get-thread-handler)
        (progn
          (format t "  [PASS] api-get-thread-handler 已定义~%")
          (incf passed))
        (progn
          (format t "  [FAIL] api-get-thread-handler 未定义~%")
          (incf failed)))

    ;; 测试 6: fulltext-search 函数
    (format t "测试 fulltext-search 函数... ~%")
    (if (fboundp 'fulltext-search)
        (progn
          (format t "  [PASS] fulltext-search 已定义~%")
          (incf passed))
        (progn
          (format t "  [FAIL] fulltext-search 未定义~%")
          (incf failed)))

    ;; 测试 7: create-message-reply 函数
    (format t "测试 create-message-reply 函数... ~%")
    (if (fboundp 'create-message-reply)
        (progn
          (format t "  [PASS] create-message-reply 已定义~%")
          (incf passed))
        (progn
          (format t "  [FAIL] create-message-reply 未定义~%")
          (incf failed)))

    ;; 测试 8: get-reply-chain 函数
    (format t "测试 get-reply-chain 函数... ~%")
    (if (fboundp 'get-reply-chain)
        (progn
          (format t "  [PASS] get-reply-chain 已定义~%")
          (incf passed))
        (progn
          (format t "  [FAIL] get-reply-chain 未定义~%")
          (incf failed)))

    ;; 测试 9: get-message-replies 函数
    (format t "测试 get-message-replies 函数... ~%")
    (if (fboundp 'get-message-replies)
        (progn
          (format t "  [PASS] get-message-replies 已定义~%")
          (incf passed))
        (progn
          (format t "  [FAIL] get-message-replies 未定义~%")
          (incf failed)))

    ;; 测试 10: get-reply-thread 函数
    (format t "测试 get-reply-thread 函数... ~%")
    (if (fboundp 'get-reply-thread)
        (progn
          (format t "  [PASS] get-reply-thread 已定义~%")
          (incf passed))
        (progn
          (format t "  [FAIL] get-reply-thread 未定义~%")
          (incf failed)))

    (format t "~%========================================~%")
    (format t "  结果：~A 通过，~A 失败~%" passed failed)
    (format t "========================================~%")

    (zerop failed)))

;; 自动运行测试
(test-phase7-api-handlers)
