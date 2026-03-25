;;;; test-snowflake.lisp - Snowflake ID 生成器测试
;;;; 可直接在 lispim-core 包中运行

(eval-when (:compile-toplevel :load-toplevel :execute)
  (ql:quickload '(:fiveam))
  (use-package :fiveam))

(in-package :lispim-core)

(fiveam:def-suite :test-snowflake
  :description "Snowflake ID 生成器测试套件")

(fiveam:in-suite :test-snowflake)

;;;; 测试：唯一性

(fiveam:test test-snowflake-uniqueness
  "测试生成的 ID 是否唯一"
  (let ((ids (loop for i from 1 to 100
                   collect (lispim-core::generate-snowflake-id))))
    ;; 所有 ID 应该都是唯一的
    (fiveam:is (= 100 (length (remove-duplicates ids :test #'=))))))

;;;; 测试：有序性

(fiveam:test test-snowflake-ordering
  "测试生成的 ID 是否有序"
  (let ((id1 (lispim-core::generate-snowflake-id))
        (id2 nil)
        (id3 nil))
    (sleep 0.01)  ; 等待时间前进
    (setf id2 (lispim-core::generate-snowflake-id))
    (sleep 0.01)
    (setf id3 (lispim-core::generate-snowflake-id))

    ;; ID 应该递增
    (fiveam:is (< id1 id2 id3))))

;;;; 测试：解析

(fiveam:test test-snowflake-parse
  "测试 ID 解析功能"
  (let ((id (lispim-core::generate-snowflake-id)))
    (multiple-value-bind (timestamp datacenter worker seq)
        (lispim-core::parse-snowflake-id id)
      (fiveam:is (>= timestamp 0))
      (fiveam:is (>= datacenter 0))
      (fiveam:is (<= datacenter 31))
      (fiveam:is (>= worker 0))
      (fiveam:is (<= worker 31))
      (fiveam:is (>= seq 0))
      (fiveam:is (<= seq 4095)))))

;;;; 测试：字符串转换

(fiveam:test test-snowflake-string-conversion
  "测试 ID 与字符串的转换"
  (let ((test-id (lispim-core::generate-snowflake-id)))
    (let ((test-str (lispim-core::snowflake-to-string test-id)))
      (fiveam:is (stringp test-str))
      (fiveam:is (= test-id (lispim-core::string-to-snowflake test-str))))))

;;;; 测试：并发安全

(fiveam:test test-snowflake-concurrent
  "测试并发生成 ID 的安全性"
  (let ((ids '())
        (lock (bordeaux-threads:make-lock "test-lock")))
    ;; 创建多个线程并发生成 ID
    (let ((threads (loop for i from 1 to 10
                         collect
                         (bordeaux-threads:make-thread
                          (lambda ()
                            (let ((thread-ids (loop for j from 1 to 100
                                                    collect (lispim-core::generate-snowflake-id))))
                              (bordeaux-threads:with-lock-held (lock)
                                (setf ids (append ids thread-ids)))))))))
      ;; 等待所有线程完成
      (dolist (thread threads)
        (bordeaux-threads:join-thread thread)))

    ;; 所有 ID 应该都是唯一的
    (fiveam:is (= 1000 (length (remove-duplicates ids :test #'=))))))

;;;; 测试：时钟回拨检测

(fiveam:test test-snowflake-clock-backwards
  "测试时钟回拨检测"
  ;; 重置 Snowflake 状态
  (lispim-core::reset-snowflake)

  ;; 先产生一个正常的时间戳
  (lispim-core::generate-snowflake-id)

  ;; 模拟时钟回拨：设置 last-timestamp 为未来 1 秒（毫秒单位）
  ;; get-epoch-ms 返回的是毫秒数，所以需要设置一个未来的毫秒值
  (let* ((current-universal (get-universal-time))
         (epoch (+ 1735689600 2208988800))  ; 与 get-epoch-ms 使用的纪元一致
         (current-ms (* (- current-universal epoch) 1000))
         (future-ms (+ current-ms 1000)))  ; 未来 1 秒（毫秒）
    (setf lispim-core::*snowflake-last-timestamp* future-ms)
    (fiveam:signals error (lispim-core::generate-snowflake-id))))

;;;; 运行所有测试

(defun run-snowflake-tests ()
  "运行所有 Snowflake 测试"
  (fiveam:run! :test-snowflake))
