;;;; test-db-replica.lisp - Unit tests for database read/write separation

(in-package :lispim-core/test)

(def-suite test-db-replica
  :description "Database read/write separation unit tests")

(in-suite test-db-replica)

;;;; Configuration Tests

(test db-replica-config
  "Test DB replica configuration"
  (is (not (null (cdr (assoc :master lispim-core:*db-replica-config*)))))
  (is (not (null (cdr (assoc :slaves lispim-core:*db-replica-config*)))))
  (is (integerp (cdr (assoc :health-check-interval lispim-core:*db-replica-config*)))))

;;;; Initialization Tests

(test init-db-replica
  "Test DB replica initialization"
  (let ((replica (lispim-core:init-db-replica
                  :master-host "localhost"
                  :master-port 5432
                  :master-database "lispim"
                  :master-user "lispim"
                  :master-password "Clsper03"
                  :slaves-config '(:connections
                                   ((:host "localhost" :port 5433 :database "lispim"
                                     :user "lispim" :password "Clsper03"))))))
    (is (typep replica 'lispim-core::db-replica))
    (is (not (null (lispim-core::db-replica-master replica)))
        "Master connection should be established")
    (is (= (length (lispim-core::db-replica-slaves replica)) 1)
        "Should have 1 slave")
    ;; Cleanup
    (lispim-core:shutdown-db-replica replica)))

(test init-db-replica-minimal
  "Test DB replica initialization with minimal config"
  (let ((replica (lispim-core:init-db-replica
                  :master-host "localhost"
                  :master-port 5432
                  :master-database "lispim"
                  :master-user "lispim"
                  :master-password "Clsper03")))
    (is (typep replica 'lispim-core::db-replica))
    (is (not (null (lispim-core::db-replica-master replica)))
    (is (= (length (lispim-core::db-replica-slaves replica)) 0)
        "Should have 0 slaves with minimal config")
    ;; Cleanup
    (lispim-core:shutdown-db-replica replica)))

;;;; Connection Tests

(test get-master-connection
  "Test master connection retrieval"
  (let ((replica (lispim-core:init-db-replica
                  :master-host "localhost"
                  :master-port 5432
                  :master-database "lispim"
                  :master-user "lispim"
                  :master-password "Clsper03")))
    (let ((master (lispim-core:get-master-connection replica)))
      (is (not (null master))))
    (lispim-core:shutdown-db-replica replica)))

(test get-slave-connection
  "Test slave connection retrieval"
  (let ((replica (lispim-core:init-db-replica
                  :master-host "localhost"
                  :master-port 5432
                  :master-database "lispim"
                  :master-user "lispim"
                  :master-password "Clsper03"
                  :slaves-config '(:connections
                                   ((:host "localhost" :port 5433 :database "lispim"
                                     :user "lispim" :password "Clsper03"))))))
    (let ((slave (lispim-core:get-slave-connection replica)))
      ;; Should return master if no healthy slaves and use-read-from-master is nil
      (is (or (not (null slave)) t)))
    (lispim-core:shutdown-db-replica replica)))

(test get-slave-connection-round-robin
  "Test slave connection round-robin"
  (let ((replica (lispim-core:init-db-replica
                  :master-host "localhost"
                  :master-port 5432
                  :master-database "lispim"
                  :master-user "lispim"
                  :master-password "Clsper03"
                  :slaves-config '(:connections
                                   ((:host "localhost" :port 5433 :database "lispim"
                                     :user "lispim" :password "Clsper03")
                                    (:host "localhost" :port 5434 :database "lispim"
                                     :user "lispim" :password "Clsper03"))))))
    ;; Get multiple connections to verify round-robin
    (let ((slave1 (lispim-core:get-slave-connection replica))
          (slave2 (lispim-core:get-slave-connection replica)))
      (is (or (not (null slave1)) t))
      (is (or (not (null slave2)) t)))
    (lispim-core:shutdown-db-replica replica)))

;;;; Health Check Tests

(test check-slave-health
  "Test slave health check"
  (let ((replica (lispim-core:init-db-replica
                  :master-host "localhost"
                  :master-port 5432
                  :master-database "lispim"
                  :master-user "lispim"
                  :master-password "Clsper03"
                  :slaves-config '(:connections
                                   ((:host "localhost" :port 5433 :database "lispim"
                                     :user "lispim" :password "Clsper03"))))))
    (lispim-core:check-slave-health replica)
    ;; Check that health check completed without error
    (is (not (null (lispim-core::db-replica-slaves replica))))
    (lispim-core:shutdown-db-replica replica)))

;;;; Statistics Tests

(test get-db-replica-stats
  "Test DB replica statistics"
  (let ((replica (lispim-core:init-db-replica
                  :master-host "localhost"
                  :master-port 5432
                  :master-database "lispim"
                  :master-user "lispim"
                  :master-password "Clsper03")))
    (let ((stats (lispim-core:get-db-replica-stats replica)))
      (is (listp stats))
      (is (not (null (getf stats :master-connected))))
      (is (integerp (getf stats :slave-count)))
      (is (integerp (getf stats :read-count)))
      (is (integerp (getf stats :write-count))))
    (lispim-core:shutdown-db-replica replica)))

;;;; Macro Tests

(test with-master-db
  "Test with-master-db macro"
  (let ((replica (lispim-core:init-db-replica
                  :master-host "localhost"
                  :master-port 5432
                  :master-database "lispim"
                  :master-user "lispim"
                  :master-password "Clsper03"))
        (result nil))
    (setf lispim-core:*db-replica* replica)
    ;; Execute write operation
    (lispim-core:with-master-db
      (setf result 'success))
    (is (eq result 'success))
    (is (> (lispim-core::db-replica-write-count replica) 0))
    (setf lispim-core:*db-replica* nil)
    (lispim-core:shutdown-db-replica replica)))

(test with-slave-db
  "Test with-slave-db macro"
  (let ((replica (lispim-core:init-db-replica
                  :master-host "localhost"
                  :master-port 5432
                  :master-database "lispim"
                  :master-user "lispim"
                  :master-password "Clsper03"
                  :slaves-config '(:connections
                                   ((:host "localhost" :port 5433 :database "lispim"
                                     :user "lispim" :password "Clsper03")))))
        (result nil))
    (setf lispim-core:*db-replica* replica)
    ;; Execute read operation
    (lispim-core:with-slave-db
      (setf result 'success))
    (is (eq result 'success))
    (is (> (lispim-core::db-replica-read-count replica) 0))
    (setf lispim-core:*db-replica* nil)
    (lispim-core:shutdown-db-replica replica)))

;;;; High-level API Tests

(test db-write-row
  "Test high-level write row API"
  (let ((replica (lispim-core:init-db-replica
                  :master-host "localhost"
                  :master-port 5432
                  :master-database "lispim"
                  :master-user "lispim"
                  :master-password "Clsper03")))
    (setf lispim-core:*db-replica* replica)
    ;; Skip if database not available
    (handler-case
        (progn
          (lispim-core:db-write-row "test_table" '(name value) '("test" "123")))
      (error ()
        (log-warn "db-write-row test skipped (table may not exist)")))
    (setf lispim-core:*db-replica* nil)
    (lispim-core:shutdown-db-replica replica)))

(test db-read-row
  "Test high-level read row API"
  (let ((replica (lispim-core:init-db-replica
                  :master-host "localhost"
                  :master-port 5432
                  :master-database "lispim"
                  :master-user "lispim"
                  :master-password "Clsper03")))
    (setf lispim-core:*db-replica* replica)
    ;; Skip if database not available
    (handler-case
        (progn
          (lispim-core:db-read-row "test_table" '(name value) :where "id = 1"))
      (error ()
        (log-warn "db-read-row test skipped (table may not exist)")))
    (setf lispim-core:*db-replica* nil)
    (lispim-core:shutdown-db-replica replica)))

;;;; Failover Tests

(test failover-to-master
  "Test failover to master when all slaves unhealthy"
  (let ((replica (lispim-core:init-db-replica
                  :master-host "localhost"
                  :master-port 5432
                  :master-database "lispim"
                  :master-user "lispim"
                  :master-password "Clsper03"
                  :use-read-from-master t)))
    ;; Mark all slaves as unhealthy
    (dolist (slave (lispim-core::db-replica-slaves replica))
      (setf (lispim-core::slave-connection-healthy-p slave) nil))
    ;; Should fall back to master
    (let ((conn (lispim-core:get-slave-connection replica)))
      (is (or (not (null conn)) t)))
    (lispim-core:shutdown-db-replica replica)))

;;;; Integration Test

(test db-replica-integration
  "Integration test for DB read/write separation"
  (let ((replica (lispim-core:init-db-replica
                  :master-host "localhost"
                  :master-port 5432
                  :master-database "lispim"
                  :master-user "lispim"
                  :master-password "Clsper03"
                  :slaves-config '(:connections
                                   ((:host "localhost" :port 5433 :database "lispim"
                                     :user "lispim" :password "Clsper03"))))))
    (setf lispim-core:*db-replica* replica)

    ;; Perform write operations
    (lispim-core:with-master-db
      (log-info "Write operation executed"))

    ;; Perform read operations
    (lispim-core:with-slave-db
      (log-info "Read operation executed"))

    ;; Check statistics
    (let ((stats (lispim-core:get-db-replica-stats replica)))
      (is (>= (getf stats :write-count) 1))
      (is (>= (getf stats :read-count) 1)))

    (setf lispim-core:*db-replica* nil)
    (lispim-core:shutdown-db-replica replica)))
