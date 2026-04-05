;;;; test-new-modules.lisp - 测试新模块功能
;;;;
;;;; 测试中间件管道、房间管理、系统命令、消息反应、在线缓存

(in-package :lispim-core)

;;;; 加载测试依赖

(eval-when (:compile-toplevel :load-toplevel :execute)
  (ql:quickload '(:fiveam :lispim-core)))

(in-package :lispim-core/test)

;;;; 中间件管道测试

(def-suite* middleware-tests
  :description "WebSocket 中间件管道测试")

(deftest test-middleware-pipeline-create
  "测试创建管道"
  (let ((pipeline (lispim-core:make-pipeline)))
    (is (typep pipeline 'lispim-core:middleware-pipeline))
    (is (null (lispim-core:middleware-pipeline-middleware pipeline)))))

(deftest test-middleware-add
  "测试添加中间件"
  (let ((pipeline (lispim-core:make-pipeline))
        (called nil))
    (lispim-core:add-middleware pipeline
                                :test
                                (lambda (socket event data result)
                                  (declare (ignore socket event data result))
                                  (setf called t)
                                  t))
    (is (find-if (lambda (e)
                   (eq (lispim-core:middleware-entry-name e) :test))
                 (lispim-core:middleware-pipeline-middleware pipeline)))
    ;; 执行管道
    (multiple-value-bind (success data)
        (lispim-core:execute-pipeline pipeline "socket" "event" "data")
      (is success)
      (is called))))

(deftest test-middleware-order
  "测试中间件执行顺序"
  (let ((pipeline (lispim-core:make-pipeline))
        (order nil))
    (lispim-core:add-middleware pipeline :first
                                (lambda (socket event data result)
                                  (declare (ignore socket event data result))
                                  (push :first order)
                                  t)
                                :order 0)
    (lispim-core:add-middleware pipeline :second
                                (lambda (socket event data result)
                                  (declare (ignore socket event data result))
                                  (push :second order)
                                  t)
                                :order 10)
    (lispim-core:execute-pipeline pipeline "socket" "event" "data")
    ;; 应该按顺序执行
    (is (equal order '(:second :first)))))

(deftest test-middleware-auth
  "测试认证中间件"
  (let ((pipeline (lispim-core:make-pipeline)))
    (lispim-core:add-middleware pipeline :authentication
                                #'lispim-core:authentication-middleware
                                :order 0)
    ;; 白名单事件应该通过
    (multiple-value-bind (success data)
        (lispim-core:execute-pipeline pipeline
                                      (list :token nil)
                                      "login"
                                      nil)
      (is success))
    ;; 非白名单事件没有 token 应该失败
    (multiple-value-bind (success data)
        (lispim-core:execute-pipeline pipeline
                                      (list :token nil)
                                      "message"
                                      nil)
      (is (not success)))))

;;;; 房间管理测试

(def-suite* room-tests
  :description "房间管理系统测试")

(deftest test-room-create
  "测试创建房间"
  (let ((room-id "test-room-1"))
    (let ((room (lispim-core:create-room room-id :type :group)))
      (is room)
      (is (string= (lispim-core:room-id room) room-id))
      (is (eq (lispim-core:room-type room) :group))
      ;; 清理
      (lispim-core:destroy-room room-id))))

(deftest test-room-join-leave
  "测试加入/离开房间"
  (let ((room-id "test-room-2")
        (user-id "user-123"))
    (lispim-core:create-room room-id :type :group)
    ;; 加入
    (is (lispim-core:join-room room-id user-id))
    (is (lispim-core:is-member-of-room-p room-id user-id))
    ;; 重复加入应该返回 t
    (is (lispim-core:join-room room-id user-id))
    ;; 离开
    (is (lispim-core:leave-room room-id user-id))
    (is (not (lispim-core:is-member-of-room-p room-id user-id)))
    ;; 清理
    (lispim-core:destroy-room room-id)))

(deftest test-room-broadcast
  "测试房间广播"
  (let ((room-id "test-room-3")
        (messages nil))
    (lispim-core:create-room room-id :type :group)
    ;; 模拟 broadcast-to-user
    (let ((lispim-core:*connections* (make-hash-table :test 'equal)))
      (lispim-core:join-room room-id "user-1")
      (lispim-core:join-room room-id "user-2")
      ;; 广播（这里只测试逻辑，不实际发送）
      (is (= 2 (length (lispim-core:get-room-members room-id)))))
    (lispim-core:destroy-room room-id)))

(deftest test-room-members-count
  "测试房间成员数量"
  (let ((room-id "test-room-4"))
    (lispim-core:create-room room-id :type :group)
    (is (= 0 (lispim-core:get-room-member-count room-id)))
    (lispim-core:join-room room-id "user-1")
    (is (= 1 (lispim-core:get-room-member-count room-id)))
    (lispim-core:join-room room-id "user-2")
    (is (= 2 (lispim-core:get-room-member-count room-id)))
    (lispim-core:leave-room room-id "user-1")
    (is (= 1 (lispim-core:get-room-member-count room-id)))
    (lispim-core:destroy-room room-id)))

;;;; 系统命令测试

(def-suite* commands-tests
  :description "系统命令测试")

(deftest test-command-roll
  "测试掷骰子命令"
  (let ((result (lispim-core:execute-command "-roll" '(100))))
    (is result)
    (is (eq (getf result :type) :system))
    (is (string= (getf result :command) "roll"))
    (is (getf result :value))
    (is (<= 0 (getf result :value) 100))))

(deftest test-command-rps
  "测试石头剪刀布命令"
  (let ((result (lispim-core:execute-command "-rps" nil)))
    (is result)
    (is (member (getf result :value) '("石头" "剪刀" "布") :test 'string=))))

(deftest test-command-help
  "测试帮助命令"
  (let ((result (lispim-core:execute-command "-help" nil)))
    (is result)
    (is (string= (getf result :command) "help"))
    (is (getf result :display))))

(deftest test-command-draw
  "测试抽签命令"
  (let ((result (lispim-core:execute-command "-draw" '("选项 A" "选项 B" "选项 C"))))
    (is result)
    (is (member (getf result :result) '("选项 A" "选项 B" "选项 C") :test 'string=))))

(deftest test-command-parse
  "测试命令解析"
  (multiple-value-bind (is-cmd cmd-name args)
      (lispim-core:parse-command "-roll 100")
    (is is-cmd)
    (is (string= cmd-name "-roll"))
    (is (equal args '("100"))))
  (multiple-value-bind (is-cmd cmd-name args)
      (lispim-core:parse-command "普通消息")
    (is (not is-cmd))))

(deftest test-command-list
  "测试命令列表"
  (let ((commands (lispim-core:list-commands)))
    (is (> (length commands) 0))
    ;; 检查是否有内置命令
    (is (find-if (lambda (cmd)
                   (string= (getf cmd :name) "-roll"))
                 commands))))

;;;; 消息反应测试

(def-suite* reactions-tests
  :description "消息反应测试")

(deftest test-reaction-add
  "测试添加反应"
  (let ((message-id 99999)
        (emoji "👍")
        (user-id "user-test"))
    (multiple-value-bind (success info)
        (lispim-core:add-reaction message-id emoji user-id)
      (is success)
      (is (string= (getf info :emoji) emoji))
      (is (= 1 (getf info :count))))))

(deftest test-reaction-remove
  "测试移除反应"
  (let ((message-id 99998)
        (emoji "❤️")
        (user-id "user-test"))
    ;; 先添加
    (lispim-core:add-reaction message-id emoji user-id)
    ;; 再移除
    (multiple-value-bind (success count)
        (lispim-core:remove-reaction message-id emoji user-id)
      (is success)
      (is (= 0 count)))))

(deftest test-reaction-get
  "测试获取反应"
  (let ((message-id 99997)
        (emoji "😂")
        (user-id "user-test"))
    (lispim-core:add-reaction message-id emoji user-id)
    (let ((reactions (lispim-core:get-message-reactions message-id)))
      (is reactions)
      (is (find-if (lambda (r)
                     (string= (getf r :emoji) emoji))
                   reactions)))))

(deftest test-reaction-multiple-users
  "测试多用户反应"
  (let ((message-id 99996)
        (emoji "🎉"))
    (lispim-core:add-reaction message-id emoji "user-1")
    (lispim-core:add-reaction message-id emoji "user-2")
    (lispim-core:add-reaction message-id emoji "user-3")
    (let ((reactions (lispim-core:get-message-reactions message-id)))
      (is reactions)
      (let ((target (find-if (lambda (r)
                               (string= (getf r :emoji) emoji))
                             reactions)))
        (is (= 3 (getf target :count)))))))

;;;; 在线缓存测试

(def-suite* online-cache-tests
  :description "在线用户缓存测试")

(deftest test-online-cache-put-get
  "测试缓存存取"
  (let ((room-id "cache-test-1")
        (members '("user-1" "user-2" "user-3"))
        (cache-key "abc123"))
    (lispim-core:online-cache-put room-id members cache-key)
    (multiple-value-bind (cached-members cached-key)
        (lispim-core:online-cache-get room-id)
      (is cached-members)
      (is (string= cached-key cache-key))
      (is (equal cached-members members)))))

(deftest test-online-cache-invalidate
  "测试缓存失效"
  (let ((room-id "cache-test-2"))
    (lispim-core:online-cache-put room-id '("user-1") "key1")
    (lispim-core:online-cache-invalidate room-id)
    (multiple-value-bind (members key)
        (lispim-core:online-cache-get room-id)
      (is (null members)))))

(deftest test-cache-key-compute
  "测试缓存键计算"
  (let ((members1 '("user-1" "user-2"))
        (members2 '("user-2" "user-1"))  ;; 顺序不同
        (members3 '("user-1" "user-3")))
    ;; 相同成员（顺序不同）应该产生相同键
    (is (string= (lispim-core:compute-members-cache-key members1)
                 (lispim-core:compute-members-cache-key members2)))
    ;; 不同成员应该产生不同键
    (is (not (string= (lispim-core:compute-members-cache-key members1)
                      (lispim-core:compute-members-cache-key members3))))))

(deftest test-online-cache-stats
  "测试缓存统计"
  (lispim-core:reset-online-cache-stats)
  (let ((room-id "cache-test-3"))
    (lispim-core:online-cache-put room-id '("user-1") "key1")
    (lispim-core:online-cache-get room-id)
    (let ((stats (lispim-core:get-online-cache-stats)))
      (is (getf stats :entries))
      (is (getf stats :hits))
      (is (getf stats :misses)))))

;;;; 运行所有测试

(defun run-all-new-tests ()
  "运行所有新模块测试"
  (let ((results nil))
    (format t "~%========================================~%")
    (format t "Running LispIM New Modules Tests~%")
    (format t "========================================~%~%")

    (push (fiveam:run 'middleware-tests) results)
    (push (fiveam:run 'room-tests) results)
    (push (fiveam:run 'commands-tests) results)
    (push (fiveam:run 'reactions-tests) results)
    (push (fiveam:run 'online-cache-tests) results)

    (format t "~%========================================~%")
    (format t "Tests Summary~%")
    (format t "========================================~%")
    (format t "Middleware: ~a~%" (first results))
    (format t "Room: ~a~%" (second results))
    (format t "Commands: ~a~%" (third results))
    (format t "Reactions: ~a~%" (fourth results))
    (format t "Online-cache: ~a~%" (fifth results))

    results))
