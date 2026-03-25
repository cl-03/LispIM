;;;; test-package.lisp - LispIM 测试包定义

(defpackage :lispim-core/test
  (:use :cl :alexandria :fiveam)
  (:export
   #:run-all-tests
   #:run-gateway-tests
   #:run-module-tests
   #:run-chat-tests
   #:run-e2ee-tests
   #:run-snowflake-tests))

(in-package :lispim-core/test)

;; 导出测试运行器
(export '(run-all-tests
          run-gateway-tests
          run-module-tests
          run-chat-tests
          run-e2ee-tests
          run-snowflake-tests))
