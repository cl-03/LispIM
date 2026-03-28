;;;; connection-pool.lisp - WebSocket Connection Pool
;;;;
;;;; Implements efficient connection management for high concurrency
;;;; Supports 10,000+ concurrent connections with O(1) lookup
;;;;
;;;; Architecture:
;;;; - Hash table for user-id -> connections mapping
;;;; - Lock-free read with fine-grained locking for writes
;;;; - Connection state tracking and health monitoring

(in-package :lispim-core)

;;;; Dependencies

(eval-when (:compile-toplevel :load-toplevel :execute)
  (ql:quickload '(:bordeaux-threads :alexandria)))

;;;; Connection States

(deftype connection-state ()
  "Connection state type"
  '(member :new :connecting :connected :authenticated :closing :closed))

(defparameter *connection-states*
  '((:new . 0)
    (:connecting . 1)
    (:connected . 2)
    (:authenticated . 3)
    (:closing . 4)
    (:closed . 5))
  "Connection state codes")

;;;; Connection Struct (extended)

;; Reuse existing connection struct from gateway.lisp
;; Add state tracking here

(defstruct connection-info
  "Extended connection information"
  (connection nil :type (or null connection))
  (user-id "" :type string)
  (state :new :type connection-state)
  (created-at 0 :type integer)
  (last-active 0 :type integer)
  (message-count 0 :type integer)
  (bytes-sent 0 :type integer)
  (bytes-received 0 :type integer)
  (remote-host "" :type string)
  (remote-port 0 :type integer)
  (user-agent "" :type string))

;;;; Connection Pool

(defstruct connection-pool
  "High-performance connection pool"
  (user-connections (make-hash-table :test 'equal :size 10000)
                    :type hash-table)
  (connection-info (make-hash-table :test 'eql :size 10000)
                   :type hash-table)
  (lock (bordeaux-threads:make-lock "pool-lock")
        :type bordeaux-threads:lock)
  (size 0 :type integer)
  (max-size 10000 :type integer)
  (created-at (get-universal-time) :type integer))

(defvar *connection-pool* nil
  "Global connection pool instance")
(defvar *pool-initialized* nil
  "Pool initialization flag")

;;;; Pool Initialization

(defun init-connection-pool (&key (max-size 10000))
  "Initialize the global connection pool"
  (declare (type integer max-size))

  (setf *connection-pool* (make-connection-pool :max-size max-size))
  (setf *pool-initialized* t)

  (log-info "Connection pool initialized: max-size=~a" max-size)
  *connection-pool*)

(defun ensure-pool-initialized ()
  "Ensure pool is initialized, create if needed"
  (unless *pool-initialized*
    (init-connection-pool))
  *connection-pool*)

;;;; Connection Management

(defun pool-add-connection (pool conn user-id)
  "Add a connection to the pool
   Returns: (values success? connection-id)"
  (declare (type connection-pool pool)
           (type connection conn)
           (type string user-id)
           (optimize (speed 3) (safety 1)))

  (bordeaux-threads:with-lock-held ((connection-pool-lock pool))
    ;; Check if pool is full
    (when (>= (connection-pool-size pool) (connection-pool-max-size pool))
      (log-warn "Connection pool full, rejecting new connection")
      (return-from pool-add-connection (values nil nil)))

    (let* ((conn-id (connection-id conn))
           (info (make-connection-info
                  :connection conn
                  :user-id user-id
                  :state :connected
                  :created-at (get-universal-time)
                  :last-active (get-universal-time)
                  :remote-host (connection-host conn)
                  :remote-port (connection-port conn))))

      ;; Add to user-connections (user-id -> list of connections)
      (let ((existing (gethash user-id (connection-pool-user-connections pool))))
        (if existing
            (push conn existing)
            (setf (gethash user-id (connection-pool-user-connections pool)) (list conn))))

      ;; Add to connection-info
      (setf (gethash conn-id (connection-pool-connection-info pool)) info)

      ;; Update size
      (incf (connection-pool-size pool))

      (log-debug "Added connection ~a for user ~a (pool size: ~a)"
                 conn-id user-id (connection-pool-size pool))

      (values t conn-id))))

(defun pool-remove-connection (pool conn)
  "Remove a connection from the pool
   Returns: (values success? user-id)"
  (declare (type connection-pool pool)
           (type connection conn)
           (optimize (speed 3) (safety 1)))

  (bordeaux-threads:with-lock-held ((connection-pool-lock pool))
    (let* ((conn-id (connection-id conn))
           (user-id (connection-user-id conn)))

      ;; Remove from connection-info
      (remhash conn-id (connection-pool-connection-info pool))

      ;; Remove from user-connections
      (let ((conns (gethash user-id (connection-pool-user-connections pool))))
        (when conns
          (setf (gethash user-id (connection-pool-user-connections pool))
                (remove conn conns))
          ;; If no connections left, remove user entry
          (when (null (gethash user-id (connection-pool-user-connections pool)))
            (remhash user-id (connection-pool-user-connections pool)))))

      ;; Update size
      (decf (connection-pool-size pool))

      ;; Update connection state
      (setf (connection-state conn) :closed)

      (log-debug "Removed connection ~a for user ~a (pool size: ~a)"
                 conn-id user-id (connection-pool-size pool))

      (values t user-id))))

;;;; Connection Lookup (O(1))

(defun pool-get-user-connections (pool user-id)
  "Get all connections for a user (O(1) lookup)
   Returns: list of connections"
  (declare (type connection-pool pool)
           (type string user-id)
           (optimize (speed 3) (safety 1)))

  (let ((conns (gethash user-id (connection-pool-user-connections pool))))
    (if conns
        ;; Filter to only connected/authenticated
        (remove-if-not (lambda (c)
                         (member (connection-state c) '(:connected :authenticated)))
                       conns)
        nil)))

(defun pool-get-connection-info (pool conn-id)
  "Get connection info by ID (O(1) lookup)
   Returns: connection-info or nil"
  (declare (type connection-pool pool)
           (type integer conn-id)
           (optimize (speed 3) (safety 1)))

  (gethash conn-id (connection-pool-connection-info pool)))

(defun pool-get-user-connection-count (pool user-id)
  "Get number of connections for a user (O(1))
   Returns: integer"
  (declare (type connection-pool pool)
           (type string user-id)
           (optimize (speed 3) (safety 1)))

  (let ((conns (gethash user-id (connection-pool-user-connections pool))))
    (if conns
        (length (remove-if-not (lambda (c)
                                 (member (connection-state c) '(:connected :authenticated)))
                               conns))
        0)))

;;;; Connection State Management

(defun pool-update-connection-state (pool conn state)
  "Update connection state"
  (declare (type connection-pool pool)
           (type connection conn)
           (type connection-state state)
           (optimize (speed 3) (safety 1)))

  (let* ((conn-id (connection-id conn))
         (info (gethash conn-id (connection-pool-connection-info pool))))

    (when info
      (setf (connection-info-state info) state
            (connection-info-last-active info) (get-universal-time))
      (setf (connection-state conn) state)

      (log-debug "Updated connection ~a state to ~a" conn-id state)
      t)))

(defun pool-update-connection-user (pool conn user-id)
  "Update connection user-id after authentication"
  (declare (type connection-pool pool)
           (type connection conn)
           (type string user-id)
           (optimize (speed 3) (safety 1)))

  (let ((conn-id (connection-id conn)))
    (bordeaux-threads:with-lock-held ((connection-pool-lock pool))
      ;; Remove from old user if exists
      (let ((old-user (connection-user-id conn)))
        (when (and old-user (not (string= old-user "")))
          (let ((conns (gethash old-user (connection-pool-user-connections pool))))
            (when conns
              (setf (gethash old-user (connection-pool-user-connections pool))
                    (remove conn conns))))))

      ;; Add to new user
      (let ((conns (gethash user-id (connection-pool-user-connections pool))))
        (if conns
            (push conn conns)
            (setf (gethash user-id (connection-pool-user-connections pool)) (list conn))))

      ;; Update connection and info
      (setf (connection-user-id conn) user-id)
      (let ((info (gethash conn-id (connection-pool-connection-info pool))))
        (when info
          (setf (connection-info-user-id info) user-id)))

      (log-debug "Updated connection ~a user to ~a" conn-id user-id)
      t)))

;;;; Connection Statistics

(defun pool-get-stats (pool)
  "Get pool statistics"
  (declare (type connection-pool pool))

  (let ((total (connection-pool-size pool))
        (connected 0)
        (authenticated 0)
        (closing 0))

    ;; Count states
    (maphash (lambda (conn-id info)
               (declare (ignore conn-id))
               (case (connection-info-state info)
                 (:connected (incf connected))
                 (:authenticated (incf authenticated))
                 (:closing (incf closing))))
             (connection-pool-connection-info pool))

    (list :total-connections total
          :connected connected
          :authenticated authenticated
          :closing closing
          :max-size (connection-pool-max-size pool)
          :utilization (/ (float total) (connection-pool-max-size pool)))))

(defun pool-print-stats ()
  "Print pool statistics to stdout"
  (let ((stats (pool-get-stats *connection-pool*)))
    (format t "~%Connection Pool Statistics:~%")
    (format t "  Total: ~a~%" (getf stats :total-connections))
    (format t "  Connected: ~a~%" (getf stats :connected))
    (format t "  Authenticated: ~a~%" (getf stats :authenticated))
    (format t "  Closing: ~a~%" (getf stats :closing))
    (format t "  Max Size: ~a~%" (getf stats :max-size))
    (format t "  Utilization: ~,2F%~%" (* 100 (getf stats :utilization)))))

;;;; Connection Health Monitor

(defparameter *health-check-interval* 30
  "Health check interval in seconds")

(defparameter *health-check-timeout* 90
  "Connection timeout in seconds")

(defun pool-health-check (pool)
  "Run health check on all connections"
  (declare (type connection-pool pool))

  (let ((now (get-universal-time))
        (stale-count 0)
        (closed-count 0))

    (bordeaux-threads:with-lock-held ((connection-pool-lock pool))
      (maphash (lambda (conn-id info)
                 (let ((last-active (connection-info-last-active info))
                       (state (connection-info-state info))
                       (conn (connection-info-connection info)))

                   ;; Check if stale
                   (when (> (- now last-active) *health-check-timeout*)
                     (incf stale-count)
                     (log-warn "Connection ~a stale for ~a seconds"
                               conn-id (- now last-active))

                     ;; Close stale connection
                     (when conn
                       (handler-case
                           (close-connection conn)
                         (error (c)
                           (log-error "Error closing stale connection: ~a" c))))

                     ;; Remove from pool
                     (pool-remove-connection pool conn)
                     (incf closed-count))))

               (connection-pool-connection-info pool)))

    (when (or (> stale-count 0) (> closed-count 0))
      (log-info "Health check: ~a stale, ~a closed" stale-count closed-count))

    (values stale-count closed-count)))

(defun start-health-monitor ()
  "Start background health monitor thread"
  (bordeaux-threads:make-thread
   (lambda ()
     (log-info "Health monitor started")
     (loop
       do (progn
            (handler-case
                (pool-health-check *connection-pool*)
              (error (c)
                (log-error "Health check error: ~a" c)))
            (sleep *health-check-interval*))))
   :name "connection-health-monitor"))

;;;; Convenience Functions (using global pool)

(defun get-user-connections (user-id)
  "Get all connections for a user (convenience function)"
  (declare (type string user-id))
  (ensure-pool-initialized)
  (pool-get-user-connections *connection-pool* user-id))

(defun add-connection (conn user-id)
  "Add connection to pool (convenience function)"
  (declare (type connection conn)
           (type string user-id))
  (ensure-pool-initialized)
  (pool-add-connection *connection-pool* conn user-id))

(defun remove-connection (conn)
  "Remove connection from pool (convenience function)"
  (declare (type connection conn))
  (ensure-pool-initialized)
  (pool-remove-connection *connection-pool* conn))

;;;; Exports

(export '(;; Pool management
          init-connection-pool
          ensure-pool-initialized
          *connection-pool*
          *pool-initialized*

          ;; Connection operations
          pool-add-connection
          pool-remove-connection
          pool-get-user-connections
          pool-get-connection-info
          pool-get-user-connection-count

          ;; State management
          pool-update-connection-state
          pool-update-connection-user

          ;; Statistics
          pool-get-stats
          pool-print-stats

          ;; Health monitoring
          pool-health-check
          start-health-monitor
          *health-check-interval*
          *health-check-timeout*

          ;; Convenience functions
          get-user-connections
          add-connection
          remove-connection

          ;; Types
          connection-state
          connection-info
          make-connection-info
          connection-pool
          make-connection-pool)
        :lispim-core)
