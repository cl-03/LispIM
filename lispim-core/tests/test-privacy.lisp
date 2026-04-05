;;;; test-privacy.lisp - 测试隐私增强功能
;;;;
;;;; 测试阅后即焚、消息删除、元数据最小化

(in-package :lispim-core)

;;;; 加载测试依赖

(eval-when (:compile-toplevel :load-toplevel :execute)
  (ql:quickload '(:fiveam :lispim-core)))

(in-package :lispim-core/test)

;;;; 隐私功能测试

(def-suite* privacy-tests
  :description "Privacy features tests")

(in-suite privacy-tests)

;;;; 阅后即焚测试

(deftest test-disappearing-message-timers
  "Test disappearing message timer options"
  (is (member 5 lispim-core:*disappearing-message-timers*))
  (is (member 30 lispim-core:*disappearing-message-timers*))
  (is (member 60 lispim-core:*disappearing-message-timers*))
  (is (member 300 lispim-core:*disappearing-message-timers*))
  (is (member 900 lispim-core:*disappearing-message-timers*))
  (is (member 3600 lispim-core:*disappearing-message-timers*))
  (is (member 86400 lispim-core:*disappearing-message-timers*))
  (is (member 604800 lispim-core:*disappearing-message-timers*))
  (is (= lispim-core:*default-disappearing-timer* 86400)))

(deftest test-disappearing-message-config
  "Test disappearing message config structure"
  (let ((config (lispim-core:make-disappearing-message-config
                 :enabled t
                 :timer-seconds 3600
                 :timer-start :first-read)))
    (is (lispim-core:disappearing-message-config-enabled config))
    (is (= (lispim-core:disappearing-message-config-timer-seconds config) 3600))
    (is (eq (lispim-core:disappearing-message-config-timer-start config) :first-read))))

(deftest test-delete-for-everyone-time-limit
  "Test delete for everyone time limit"
  (is (= lispim-core:*delete-for-everyone-time-limit* (* 48 60 60))))

;;;; 元数据最小化测试

(deftest test-metadata-minimization-config
  "Test metadata minimization configuration"
  (is (typep lispim-core:*metadata-minimization-enabled* 'boolean))
  (is (= lispim-core:*minimal-metadata-retention-period* (* 24 60 60))))

;;;; 辅助函数测试

(deftest test-time-conversions
  "Test time conversion functions"
  (let ((now-universal (get-universal-time))
        (now-unix (lispim-core:lispim-universal-to-unix now-universal)))
    (is (typep now-unix 'integer))
    (is (> now-unix 1700000000))))

;;;; 运行测试

(defun run-privacy-tests ()
  "Run all privacy tests"
  (fiveam:run! 'privacy-tests))
