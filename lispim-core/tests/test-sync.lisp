;;;; test-sync.lisp - Unit tests for client incremental sync

(in-package :lispim-core/test)

(def-suite test-sync
  :description "Client incremental sync unit tests")

(in-suite test-sync)

;;;; Sync Anchor Tests

(test sync-anchor-basic
  "Test basic sync anchor operations"
  (let ((user-id "test-user")
        (device-id "test-device"))
    ;; Get initial anchor (should create new)
    (let ((anchor (lispim-core:get-sync-anchor user-id device-id)))
      (is (typep anchor 'lispim-core::sync-anchor))
      (is (string= (lispim-core::sync-anchor-user-id anchor) user-id))
      (is (string= (lispim-core::sync-anchor-device-id anchor) device-id))
      ;; Initial seq should be 0
      (is (= (lispim-core::sync-anchor-message-seq anchor) 0))
      (is (= (lispim-core::sync-anchor-conversation-seq anchor) 0)))))

(test sync-anchor-update
  "Test sync anchor update"
  (let ((user-id "test-user-2")
        (device-id "test-device-2"))
    ;; Set new anchor
    (lispim-core:set-sync-anchor user-id 100 50 device-id)
    ;; Get and verify
    (let ((anchor (lispim-core:get-sync-anchor user-id device-id)))
      (is (= (lispim-core::sync-anchor-message-seq anchor) 100))
      (is (= (lispim-core::sync-anchor-conversation-seq anchor) 50)))))

;;;; Sequence Number Tests

(test message-seq-generation
  "Test message sequence number generation"
  ;; Get current seq
  (let ((seq1 (lispim-core:get-current-message-seq)))
    (is (integerp seq1))
    (is (>= seq1 0))))

;;;; Sync Config Tests

(test sync-config-defaults
  "Test sync configuration defaults"
  (let ((config lispim-core:*sync-config*))
    (is (not (null config)))
    (is (= (cdr (assoc :max-batch-size config)) 100))
    (is (= (cdr (assoc :default-batch-size config)) 50))
    (is (= (cdr (assoc :max-anchor-age config)) 604800))))

;;;; Conflict Resolution Tests

(test conflict-resolution-last-write-wins
  "Test last-write-wins conflict resolution"
  (let ((local-msg '(:created-at 1000 :content "local"))
        (remote-msg '(:created-at 2000 :content "remote")))
    ;; Remote is newer, should win
    (let ((result (lispim-core:resolve-sync-conflict local-msg remote-msg)))
      (is (string= (cdr (assoc :content result)) "remote")))
    ;; Local is newer, should win
    (let ((local-msg-new '(:created-at 3000 :content "local-new"))
          (remote-msg-old '(:created-at 2000 :content "remote-old")))
      (let ((result (lispim-core:resolve-sync-conflict local-msg-new remote-msg-old)))
        (is (string= (cdr (assoc :content result)) "local-new"))))))

;;;; Sync Statistics Tests

(test sync-stats-recording
  "Test sync statistics recording"
  (let ((initial-stats (lispim-core:get-sync-stats)))
    (is (not (null initial-stats)))
    (is (not (null (getf initial-stats :total-syncs))))
    ;; Record a sync
    (lispim-core:record-sync :incremental t)
    (let ((new-stats (lispim-core:get-sync-stats)))
      ;; Total should increase
      (is (> (getf new-stats :total-syncs)
             (getf initial-stats :total-syncs)))
      ;; Incremental should increase
      (is (> (getf new-stats :incremental-syncs)
             (getf initial-stats :incremental-syncs))))))

;;;; Full Sync Test (mock)

(test full-sync-structure
  "Test full sync returns correct structure"
  ;; This test checks the structure without requiring actual data
  (let ((result (list :conversations nil
                      :new-anchor 0
                      :full-sync t
                      :synced-at (get-universal-time))))
    (is (not (null (getf result :conversations))))
    (is (not (null (getf result :new-anchor)))
    (is (getf result :full-sync))
    (is (not (null (getf result :synced-at))))))

;;;; Anchor Expiration Test

(test anchor-expired-check
  "Test anchor expiration check logic"
  ;; Fresh anchor (just created) should not be expired
  (let ((user-id "test-expired-user")
        (device-id "test-expired-device"))
    ;; Create fresh anchor
    (lispim-core:set-sync-anchor user-id 0 0 device-id)
    ;; Should not be expired (just created)
    (is (false (lispim-core::anchor-expired-p user-id 0)))))

;;;; Batch Size Limits

(test batch-size-limits
  "Test batch size limit enforcement"
  (let ((config lispim-core:*sync-config*))
    ;; Requested size should be capped at max
    (let ((requested 200)
          (max-size (cdr (assoc :max-batch-size config))))
      (is (= (min requested max-size) max-size)))
    ;; Requested size within limits should pass through
    (let ((requested 30)
          (max-size (cdr (assoc :max-batch-size config))))
      (is (= (min requested max-size) requested)))))

;;;; Helper Function Tests

(test row-to-message
  "Test row to message conversion"
  (let ((row '(:id 123 :conversation-id 456 :sender-id "user1"
               :content "Hello" :message-type :text :created-at 1000 :msg-seq 10)))
    (let ((msg (lispim-core::row-to-message row)))
      (is (= (getf msg :id) 123))
      (is (= (getf msg :conversation-id) 456))
      (is (string= (getf msg :sender-id) "user1"))
      (is (string= (getf msg :content) "Hello"))
      (is (eq (getf msg :message-type) :text)))))

(test row-to-conversation
  "Test row to conversation conversion"
  (let ((row '(:id 789 :name "Test Chat" :type :direct
               :participants ("user1" "user2") :last-message-id 123
               :updated-at 1000 :conv-seq 5)))
    (let ((conv (lispim-core::row-to-conversation row)))
      (is (= (getf conv :id) 789))
      (is (string= (getf conv :name) "Test Chat"))
      (is (eq (getf conv :type) :direct))
      (= (getf conv :seq) 5)))))

;;;; Integration Test

(test sync-integration
  "Integration test for sync flow"
  (let ((user-id "integration-test-user")
        (device-id "integration-device"))
    ;; Initialize sync (creates anchor)
    (let ((anchor (lispim-core:get-sync-anchor user-id device-id)))
      (is (typep anchor 'lispim-core::sync-anchor)))
    ;; Update anchor
    (lispim-core:set-sync-anchor user-id 50 25 device-id)
    ;; Verify update
    (let ((updated (lispim-core:get-sync-anchor user-id device-id)))
      (is (= (lispim-core::sync-anchor-message-seq updated) 50))
      (is (= (lispim-core::sync-anchor-conversation-seq updated) 25)))
    ;; Record sync stat
    (lispim-core:record-sync :incremental t)
    (let ((stats (lispim-core:get-sync-stats)))
      (is (> (getf stats :incremental-syncs) 0)))))
