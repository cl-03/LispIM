;;;; cluster.lisp - Multi-instance Cluster Support
;;;;
;;;; Implements multi-instance deployment with Redis Pub/Sub communication
;;;; for horizontal scalability
;;;;
;;;; Architecture:
;;;; - Redis Pub/Sub for inter-instance communication
;;;; - User routing table (user-id -> instance-id)
;;;; - Cross-instance message routing
;;;; - Instance health monitoring

(in-package :lispim-core)

;;;; Dependencies

(eval-when (:compile-toplevel :load-toplevel :execute)
  (ql:quickload '(:cl-redis :bordeaux-threads :cl-json :uuid)))

;;;; Cluster Configuration

(defparameter *cluster-config*
  '((:instance-id . nil)
    (:heartbeat-interval . 5)
    (:heartbeat-timeout . 15)
    (:redis-channel . "lispim:cluster")
    (:instance-registry . "lispim:instances")
    (:user-routing . "lispim:user-routing")
    (:max-instances . 100))
  "Cluster configuration")

;;;; Cluster State

(defvar *cluster* nil
  "Global cluster instance")
(defvar *cluster-pubsub* nil
  "Cluster Pub/Sub connection")
(defvar *cluster-running* nil
  "Cluster running flag")

(defstruct cluster
  "Multi-instance cluster manager"
  (instance-id "" :type string)
  (redis-connected nil :type boolean)
  (host "" :type string)
  (port 0 :type integer)
  (started-at 0 :type integer)
  (lock (bordeaux-threads:make-lock "cluster-lock"))
  (message-sent 0 :type integer)
  (message-received 0 :type integer)
  (instances-seen 0 :type integer))

;;;; Initialization

(defun init-cluster (&key
                     (redis-host "localhost")
                     (redis-port 6379)
                     (host "localhost")
                     (port 3000)
                     (instance-id nil))
  "Initialize cluster module"
  (declare (type string redis-host host)
           (type integer redis-port port))
  (let* ((id (or instance-id (generate-instance-id)))
         (connected nil))
    (handler-case
        (progn
          (redis:connect :host redis-host :port redis-port)
          (setf connected t)
          (log-info "Redis connected for cluster: ~a:~a" redis-host redis-port))
      (error (c)
        (log-warn "Redis connection failed for cluster: ~a" c)))
    (let ((cluster (make-cluster
                    :instance-id id
                    :redis-connected connected
                    :host host
                    :port port
                    :started-at (get-universal-time))))
      (setf *cluster* cluster)
      (if connected
          (progn
            (register-instance cluster)
            (start-cluster-pubsub cluster redis-host redis-port)
            (start-cluster-heartbeat cluster)
            (log-info "Cluster initialized: instance=~a, host=~a:~a" id host port))
          (log-warn "Cluster initialized: Redis not available"))
      cluster)))

(defun generate-instance-id ()
  "Generate unique instance ID"
  (format nil "instance-~a-~a"
          (machine-instance)
          (get-universal-time)))

;;;; Instance Registration

(defun register-instance (cluster)
  "Register instance in cluster registry"
  (declare (type cluster cluster))
  (when (cluster-redis-connected cluster)
    (let ((registry (cdr (assoc :instance-registry *cluster-config*))))
      (let ((instance-data (cl-json:encode-json-to-string
                            (list :id (cluster-instance-id cluster)
                                  :host (cluster-host cluster)
                                  :port (cluster-port cluster)
                                  :started-at (cluster-started-at cluster)
                                  :last-heartbeat (get-universal-time)))))
        (handler-case
            (progn
              (redis:red-hset registry (cluster-instance-id cluster) instance-data)
              (redis:red-expire registry (cdr (assoc :heartbeat-timeout *cluster-config*)))
              t)
          (error (c)
            (log-error "Failed to register instance: ~a" c)
            nil))))))

(defun unregister-instance (cluster)
  "Unregister instance from cluster registry"
  (declare (type cluster cluster))
  (when (cluster-redis-connected cluster)
    (let ((registry (cdr (assoc :instance-registry *cluster-config*))))
      (handler-case
          (progn
            (redis:red-hdel registry (cluster-instance-id cluster))
            t)
        (error (c)
          (log-error "Failed to unregister instance: ~a" c)
          nil)))))

;;;; Pub/Sub Communication

(defun start-cluster-pubsub (cluster redis-host redis-port)
  "Start Pub/Sub listener thread"
  (declare (type cluster cluster)
           (type string redis-host)
           (type integer redis-port))
  (let ((channel (cdr (assoc :redis-channel *cluster-config*))))
    (setf *cluster-pubsub*
          (bordeaux-threads:make-thread
           (lambda ()
             (log-info "Cluster Pub/Sub started: channel=~a" channel)
             (let ((pubsub-connected nil))
               (handler-case
                   (progn
                     (redis:connect :host redis-host :port redis-port)
                     (setf pubsub-connected t))
                 (error (c)
                   (log-error "Failed to create Pub/Sub connection: ~a" c)))
               (when pubsub-connected
                 (loop while *cluster-running*
                       do (handler-case
                              (let ((result (redis:red-subscribe channel)))
                                (when result
                                  (loop for msg across result
                                        do (process-cluster-message cluster msg))))
                            (error (c)
                              (log-debug "Pub/Sub error: ~a" c)
                              (sleep 1)))))))))))

(defun publish-to-cluster (message)
  "Publish message to cluster via Redis Pub/Sub"
  (declare (type list message))
  (let ((cluster *cluster*))
    (unless cluster
      (return-from publish-to-cluster nil))
    (when (cluster-redis-connected cluster)
      (let ((channel (cdr (assoc :redis-channel *cluster-config*))))
        (handler-case
            (let ((message-json (cl-json:encode-json-to-string
                                 (append message
                                         (list :source-instance (cluster-instance-id cluster))))))
              (redis:red-publish channel message-json)
              (incf (cluster-message-sent cluster))
              t)
          (error (c)
            (log-error "Failed to publish to cluster: ~a" c)
            nil))))))

(defun process-cluster-message (cluster message)
  "Process incoming cluster message"
  (declare (type cluster cluster)
           (type string message))
  (let ((message-json (cl-json:decode-json-from-string message)))
    (let ((type (cdr (assoc :type message-json)))
          (source (cdr (assoc :source-instance message-json))))
      (unless (string= source (cluster-instance-id cluster))
        (incf (cluster-message-received cluster))
        (case type
          (:user-routed
           (let ((user-id (cdr (assoc :user-id message-json)))
                 (instance (cdr (assoc :instance message-json))))
             (update-user-routing user-id instance)))
          (:broadcast
           (handle-cluster-broadcast message-json))
          (:direct
           (let ((target-user (cdr (assoc :target-user message-json))))
             (when (user-local-p target-user)
               (handle-cluster-direct message-json))))
          (:heartbeat
           (let ((instance (cdr (assoc :instance message-json))))
             (update-instance-heartbeat instance)))
          (t
           (log-debug "Unknown cluster message type: ~a" type)))))))

;;;; User Routing

(defun get-user-instance (user-id)
  "Get instance ID for user"
  (declare (type string user-id))
  (let ((cluster *cluster*)
        (routing-key (cdr (assoc :user-routing *cluster-config*))))
    (unless cluster
      (return-from get-user-instance nil))
    (when (cluster-redis-connected cluster)
      (handler-case
          (let ((instance (redis:red-hget routing-key user-id)))
            (if instance
                instance
                (cluster-instance-id cluster)))
        (error (c)
          (log-debug "Failed to get user routing: ~a" c)
          (cluster-instance-id cluster))))))

(defun set-user-instance (user-id instance-id)
  "Set user's instance in routing table"
  (declare (type string user-id instance-id))
  (let ((cluster *cluster*)
        (routing-key (cdr (assoc :user-routing *cluster-config*))))
    (unless cluster
      (return-from set-user-instance nil))
    (when (cluster-redis-connected cluster)
      (handler-case
          (progn
            (redis:red-hset routing-key user-id instance-id)
            (publish-to-cluster (list :type :user-routed
                                      :user-id user-id
                                      :instance instance-id))
            t)
        (error (c)
          (log-error "Failed to set user routing: ~a" c)
          nil)))))

(defun update-user-routing (user-id instance-id)
  "Update local user routing cache"
  (declare (type string user-id instance-id))
  (log-debug "User routing updated: ~a -> ~a" user-id instance-id))

(defun user-local-p (user-id)
  "Check if user is on local instance"
  (declare (type string user-id))
  (string= (get-user-instance user-id) (cluster-instance-id *cluster*)))

;;;; Cross-Instance Messaging

(defun send-to-remote-user (user-id message)
  "Send message to user on remote instance"
  (declare (type string user-id)
           (type list message))
  (let ((target-instance (get-user-instance user-id)))
    (when (and target-instance
               (not (string= target-instance (cluster-instance-id *cluster*))))
      (publish-to-cluster (list :type :direct
                                :target-user user-id
                                :message message))
      t)))

(defun handle-cluster-direct (message)
  "Handle direct message from cluster"
  (declare (type list message))
  (let ((msg-data (cdr (assoc :message message))))
    (when msg-data
      (let ((recipient (cdr (assoc :recipient-id msg-data))))
        (when recipient
          (let ((connections (get-user-connections recipient)))
            (when connections
              (dolist (conn connections)
                (send-message-to-connection conn
                                            (cdr (assoc :message-id msg-data))
                                            (cdr (assoc :content msg-data))
                                            :type (cdr (assoc :type msg-data)))))))))))

(defun handle-cluster-broadcast (message)
  "Handle broadcast message from cluster"
  (declare (type list message))
  (let ((msg-data (cdr (assoc :message message))))
    (when msg-data
      (broadcast-message msg-data))))

;;;; Instance Heartbeat

(defun start-cluster-heartbeat (cluster)
  "Start heartbeat thread"
  (declare (type cluster cluster))
  (bordeaux-threads:make-thread
   (lambda ()
     (log-info "Cluster heartbeat started")
     (let ((interval (cdr (assoc :heartbeat-interval *cluster-config*))))
       (loop while *cluster-running*
             do (handler-case
                    (progn
                      (send-cluster-heartbeat cluster)
                      (cleanup-stale-instances cluster))
                (error (c)
                  (log-debug "Heartbeat error: ~a" c)))
             (sleep interval))))))

(defun send-cluster-heartbeat (cluster)
  "Send heartbeat to cluster"
  (declare (type cluster cluster))
  (register-instance cluster)
  (publish-to-cluster (list :type :heartbeat
                            :instance (cluster-instance-id cluster))))

(defun update-instance-heartbeat (instance-id)
  "Update instance heartbeat timestamp"
  (declare (type string instance-id))
  (log-debug "Heartbeat received from: ~a" instance-id))

(defun cleanup-stale-instances (cluster)
  "Remove stale instances from registry"
  (declare (type cluster cluster))
  (when (cluster-redis-connected cluster)
    (let ((registry (cdr (assoc :instance-registry *cluster-config*)))
          (timeout (cdr (assoc :heartbeat-timeout *cluster-config*)))
          (now (get-universal-time)))
      (handler-case
          (let ((instances (redis:red-hgetall registry)))
            (when instances
              (loop for i from 0 below (length instances) by 2
                    do (let* ((instance-id (aref instances i))
                              (instance-json (aref instances (1+ i)))
                              (instance-data (cl-json:decode-json-from-string instance-json))
                              (last-heartbeat (cdr (assoc :last-heartbeat instance-data))))
                         (when (> (- now last-heartbeat) timeout)
                           (redis:red-hdel registry instance-id)
                           (log-warn "Removed stale instance: ~a" instance-id))))))
        (error (c)
          (log-debug "Failed to cleanup stale instances: ~a" c))))))

;;;; Cluster Statistics

(defun get-cluster-stats ()
  "Get cluster statistics"
  (let ((cluster *cluster*))
    (unless cluster
      (return-from get-cluster-stats nil))
    (list :instance-id (cluster-instance-id cluster)
          :message-sent (cluster-message-sent cluster)
          :message-received (cluster-message-received cluster)
          :running *cluster-running*)))

(defun print-cluster-stats ()
  "Print cluster statistics"
  (let ((stats (get-cluster-stats)))
    (when stats
      (format t "~%Cluster Statistics:~%")
      (format t "  Instance: ~a~%" (getf stats :instance-id))
      (format t "  Messages Sent: ~a~%" (getf stats :message-sent))
      (format t "  Messages Received: ~a~%" (getf stats :message-received))
      (format t "  Status: ~a~%" (if (getf stats :running) "Running" "Stopped")))))

;;;; Shutdown

(defun shutdown-cluster ()
  "Shutdown cluster module"
  (setf *cluster-running* nil)
  (when *cluster*
    (unregister-instance *cluster*)
    (when *cluster-pubsub*
      (bordeaux-threads:destroy-thread *cluster-pubsub*)
      (setf *cluster-pubsub* nil))
    (log-info "Cluster shutdown")))

;;;; Exports

(export '(;; Cluster management
          init-cluster
          shutdown-cluster
          *cluster*
          cluster
          make-cluster
          ;; Instance operations
          register-instance
          unregister-instance
          ;; Pub/Sub
          publish-to-cluster
          ;; User routing
          get-user-instance
          set-user-instance
          user-local-p
          ;; Cross-instance messaging
          send-to-remote-user
          ;; Statistics
          get-cluster-stats
          print-cluster-stats
          ;; Configuration
          *cluster-config*)
        :lispim-core)
