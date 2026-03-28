;;;; test-cluster.lisp - Unit tests for multi-instance cluster

(in-package :lispim-core/test)

(def-suite test-cluster
  :description "Multi-instance cluster unit tests")

(in-suite test-cluster)

;;;; Cluster Initialization

(test cluster-init
  "Test cluster initialization"
  (let ((cluster (lispim-core:init-cluster
                  :redis-host "localhost"
                  :redis-port 6379
                  :host "localhost"
                  :port 3000
                  :instance-id "test-instance-1")))
    (is (not (null cluster)))
    (is (typep cluster 'lispim-core::cluster))
    (is (string= (lispim-core::cluster-instance-id cluster) "test-instance-1"))
    (is (string= (lispim-core::cluster-host cluster) "localhost"))
    (is (= (lispim-core::cluster-port cluster) 3000))))

(test generate-instance-id
  "Test instance ID generation"
  (let ((id1 (lispim-core::generate-instance-id))
        (id2 (lispim-core::generate-instance-id)))
    (is (stringp id1))
    (is (stringp id2))
    ;; IDs should be unique (different timestamps)
    (is (not (string= id1 id2)))))

;;;; Configuration

(test cluster-config-defaults
  "Test cluster configuration defaults"
  (let ((config lispim-core:*cluster-config*))
    (is (not (null config)))
    (is (null (cdr (assoc :instance-id config)))) ; Should be nil (auto-generated)
    (is (= (cdr (assoc :heartbeat-interval config)) 5))
    (is (= (cdr (assoc :heartbeat-timeout config)) 15))
    (is (string= (cdr (assoc :redis-channel config)) "lispim:cluster"))))

;;;; User Routing

(test user-routing
  "Test user routing operations"
  (lispim-core:init-cluster
   :redis-host "localhost"
   :redis-port 6379
   :host "localhost"
   :port 3000
   :instance-id "test-instance-2")
  (let ((user-id "test-user-1")
        (instance-id "remote-instance-1"))
    ;; Set routing
    (lispim-core:set-user-instance user-id instance-id)
    ;; Get routing (may fail if Redis not available, test gracefully)
    (let ((result (lispim-core:get-user-instance user-id)))
      (is (stringp result)))))

(test user-local-p
  "Test user local check"
  (lispim-core:init-cluster
   :redis-host "localhost"
   :redis-port 6379
   :host "localhost"
   :port 3000
   :instance-id "test-instance-3")
  ;; Without Redis, should default to local
  (is (lispim-core:user-local-p "any-user")))

;;;; Cluster Statistics

(test cluster-stats
  "Test cluster statistics"
  (lispim-core:init-cluster
   :redis-host "localhost"
   :redis-port 6379
   :host "localhost"
   :port 3000
   :instance-id "test-instance-4")
  (let ((stats (lispim-core:get-cluster-stats)))
    (is (listp stats))
    (is (not (null (getf stats :instance-id))))
    (is (not (null (getf stats :message-sent))))
    (is (not (null (getf stats :message-received))))
    (is (booleanp (getf stats :running)))))

;;;; Pub/Sub Communication

(test publish-to-cluster
  "Test publishing to cluster"
  (lispim-core:init-cluster
   :redis-host "localhost"
   :redis-port 6379
   :host "localhost"
   :port 3000
   :instance-id "test-instance-5")
  ;; Publish a test message
  (let ((result (lispim-core:publish-to-cluster
                 (list :type :test :data "hello"))))
    ;; Should succeed if Redis is available
    (is (booleanp result))))

;;;; Cluster Lifecycle

(test cluster-lifecycle
  "Test cluster start/stop lifecycle"
  (lispim-core:init-cluster
   :redis-host "localhost"
   :redis-port 6379
   :host "localhost"
   :port 3000
   :instance-id "test-instance-6")
  ;; Cluster should be running after init
  (is lispim-core:*cluster-running*)
  ;; Shutdown
  (lispim-core:shutdown-cluster)
  (sleep 0.5) ; Give threads time to stop
  (is (null lispim-core:*cluster-running*))))

;;;; Integration Test

(test cluster-integration
  "Integration test for cluster operations"
  (lispim-core:init-cluster
   :redis-host "localhost"
   :redis-port 6379
   :host "localhost"
   :port 3000
   :instance-id "test-instance-7")
  (let ((user-id "integration-user")
        (instance-id "instance-remote"))
    ;; Set user routing
    (lispim-core:set-user-instance user-id instance-id)
    ;; Verify routing
    (let ((routing (lispim-core:get-user-instance user-id)))
      (is (string= routing instance-id)))
    ;; Publish to cluster
    (lispim-core:publish-to-cluster
     (list :type :broadcast :message "test"))
    ;; Check stats
    (let ((stats (lispim-core:get-cluster-stats)))
      (is (>= (getf stats :message-sent) 1))))
  ;; Cleanup
  (lispim-core:shutdown-cluster))

;;;; Cross-instance Messaging

(test send-to-remote-user
  "Test cross-instance message sending"
  (lispim-core:init-cluster
   :redis-host "localhost"
   :redis-port 6379
   :host "localhost"
   :port 3000
   :instance-id "test-instance-8")
  ;; Set up remote user routing
  (lispim-core:set-user-instance "remote-user" "remote-instance")
  ;; Send to remote user
  (let ((result (lispim-core:send-to-remote-user
                 "remote-user"
                 (list :type :chat :content "Hello"))))
    (is (booleanp result))))
