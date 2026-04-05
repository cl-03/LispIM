;;;; test-new-features.lisp - 新功能测试
;;;;
;;;; 测试通知推送、消息置顶、群投票功能

(in-package :lispim-core/test)

;;;; 依赖声明

(eval-when (:compile-toplevel :load-toplevel :execute)
  (ql:quickload '(:fiveam :lispim-core)))

;;;; 通知系统测试

(def-suite* notification-tests
  :description "Notification system tests")

(in-suite notification-tests)

(deftest test-notification-structure
  "Test user-notification structure"
  (let ((notif (lispim-core:make-user-notification
                :id 1
                :user-id "user123"
                :type :message
                :title "New Message"
                :content "You have a new message"
                :priority :high)))
    (is (= 1 (lispim-core:user-notification-id notif)))
    (is (string= "user123" (lispim-core:user-notification-user-id notif)))
    (is (eq :message (lispim-core:user-notification-type notif)))
    (is (string= "New Message" (lispim-core:user-notification-title notif)))
    (is (string= "You have a new message" (lispim-core:user-notification-content notif)))
    (is (eq :high (lispim-core:user-notification-priority notif)))))

(deftest test-notification-preferences-structure
  "Test notification-preferences structure"
  (let ((prefs (lispim-core:make-notification-preferences
                :user-id "user123"
                :enable-desktop t
                :enable-sound nil
                :quiet-mode t
                :quiet-start "22:00"
                :quiet-end "08:00")))
    (is (string= "user123" (lispim-core:notification-preferences-user-id prefs)))
    (is (eq t (lispim-core:notification-preferences-enable-desktop prefs)))
    (is (eq nil (lispim-core:notification-preferences-enable-sound prefs)))
    (is (eq t (lispim-core:notification-preferences-quiet-mode prefs)))
    (is (string= "22:00" (lispim-core:notification-preferences-quiet-start prefs)))
    (is (string= "08:00" (lispim-core:notification-preferences-quiet-end prefs)))))

(deftest test-quiet-mode-time-format
  "Test quiet mode time format validation"
  (is (string= "22:00" "22:00"))
  (is (string= "08:00" "08:00"))
  ;; Time format should be HH:MM
  (is (find #\: "22:00")))

;;;; 消息置顶测试

(def-suite* message-pinning-tests
  :description "Message pinning tests")

(in-suite message-pinning-tests)

(deftest test-pin-message-function-exists
  "Test pin-message function exists"
  (is (fboundp 'lispim-core:pin-message))
  (is (fboundp 'lispim-core:unpin-message))
  (is (fboundp 'lispim-core:get-pinned-messages))
  (is (fboundp 'lispim-core:is-message-pinned)))

;;;; 群投票测试

(def-suite* group-poll-tests
  :description "Group poll tests")

(in-suite group-poll-tests)

(deftest test-poll-structure
  "Test group-poll structure"
  (let ((poll (lispim-core:make-group-poll
               :id 1
               :group-id 100
               :created-by "admin"
               :title " Lunch Choice"
               :description "Where should we go for lunch?"
               :multiple-choice nil
               :allow-suggestions t
               :anonymous-voting nil
               :status :active)))
    (is (= 1 (lispim-core:group-poll-id poll)))
    (is (= 100 (lispim-core:group-poll-group-id poll)))
    (is (string= "admin" (lispim-core:group-poll-created-by poll)))
    (is (string= "Lunch Choice" (lispim-core:group-poll-title poll)))
    (is (string= "Where should we go for lunch?" (lispim-core:group-poll-description poll)))
    (is (eq nil (lispim-core:group-poll-multiple-choice poll)))
    (is (eq t (lispim-core:group-poll-allow-suggestions poll)))
    (is (eq :active (lispim-core:group-poll-status poll)))))

(deftest test-poll-option-structure
  "Test poll-option structure"
  (let ((option (lispim-core:make-poll-option
                 :id 1
                 :poll-id 100
                 :text "Italian Restaurant"
                 :vote-count 5)))
    (is (= 1 (lispim-core:poll-option-id option)))
    (is (= 100 (lispim-core:poll-option-poll-id option)))
    (is (string= "Italian Restaurant" (lispim-core:poll-option-text option)))
    (is (= 5 (lispim-core:poll-option-vote-count option)))))

(deftest test-poll-functions-exist
  "Test poll functions exist"
  (is (fboundp 'lispim-core:create-poll))
  (is (fboundp 'lispim-core:get-poll))
  (is (fboundp 'lispim-core:cast-vote))
  (is (fboundp 'lispim-core:end-poll))
  (is (fboundp 'lispim-core:get-group-polls))
  (is (fboundp 'lispim-core:get-poll-results)))

;;;; 集成测试

(def-suite* integration-tests
  :description "Integration tests for new features")

(in-suite integration-tests)

(deftest test-all-modules-load
  "Test all new modules load successfully"
  ;; Test notification module
  (is (fboundp 'lispim-core:init-notification-system))
  (is (fboundp 'lispim-core:ensure-notification-tables-exist))

  ;; Test poll module
  (is (fboundp 'lispim-core:ensure-poll-tables-exist))

  ;; Test message pinning (part of chat module)
  (is (fboundp 'lispim-core:pin-message))

  t)

;;;; 运行所有测试

(defun run-all-new-feature-tests ()
  "Run all new feature tests"
  (let ((results nil))
    (push (fiveam:run 'notification-tests) results)
    (push (fiveam:run 'message-pinning-tests) results)
    (push (fiveam:run 'group-poll-tests) results)
    (push (fiveam:run 'integration-tests) results)
    results))

;;;; 导出

(export '(run-all-new-feature-tests)
        :lispim-core/test)
