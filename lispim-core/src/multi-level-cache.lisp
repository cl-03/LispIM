;;;; multi-level-cache.lisp - Multi-Level Cache System
;;;;
;;;; Implements L1 Memory → L2 Redis → L3 Database three-tier caching
;;;; for efficient data access and reduced database load
;;;;
;;;; Architecture:
;;;; - L1: In-memory hash table with LRU eviction (hot data)
;;;; - L2: Redis distributed cache (warm data)
;;;; - L3: PostgreSQL database (cold data)
;;;;
;;;; Cache Protection:
;;;; - Bloom filter for cache penetration protection
;;;; - Random TTL for cache avalanche protection
;;;; - Write-through strategy for consistency

(in-package :lispim-core)

;;;; Dependencies

(eval-when (:compile-toplevel :load-toplevel :execute)
  (ql:quickload '(:bordeaux-threads :alexandria :serapeum)))

;;;; Cache Configuration

(defparameter *cache-config*
  '((:l1-max-size . 10000)        ; L1 max entries
    (:l1-ttl-base . 300)          ; L1 base TTL (5 min)
    (:l1-ttl-random . 120)        ; L1 random TTL range (±2 min)
    (:l2-ttl-base . 3600)         ; L2 base TTL (1 hour)
    (:l2-ttl-random . 600)        ; L2 random TTL range (±10 min)
    (:bloom-fp-rate . 0.01))      ; Bloom filter false positive rate (1%)
  "Cache configuration parameters")

;;;; Cache Entry Structure

(defstruct cache-entry
  "Cache entry with metadata"
  (key nil :type (or null string))
  (value nil :type t)
  (created-at 0 :type integer)
  (expires-at 0 :type integer)
  (access-count 0 :type integer)
  (last-accessed 0 :type integer))

;;;; L1 In-Memory Cache

(defstruct l1-cache
  "L1 in-memory cache with LRU eviction"
  (store (make-hash-table :test 'equal :size 10000) :type hash-table)
  (lock (bordeaux-threads:make-lock "l1-cache-lock") :type bordeaux-threads:lock)
  (size 0 :type integer)
  (max-size 10000 :type integer)
  (hit-count 0 :type integer)
  (miss-count 0 :type integer)
  (eviction-count 0 :type integer))

(defvar *l1-cache* nil
  "Global L1 cache instance")

(defun init-l1-cache (&key (max-size 10000))
  "Initialize L1 cache"
  (declare (type integer max-size))
  (setf *l1-cache* (make-l1-cache :max-size max-size))
  (log-info "L1 cache initialized: max-size=~a" max-size)
  *l1-cache*)

(defun l1-get (cache key)
  "Get value from L1 cache
   Returns: (values found? value)"
  (declare (type l1-cache cache)
           (type string key)
           (optimize (speed 3) (safety 1)))
  (bordeaux-threads:with-lock-held ((l1-cache-lock cache))
    (let* ((entry (gethash key (l1-cache-store cache))))
      (if (and entry
               (> (cache-entry-expires-at entry) (get-universal-time)))
          (progn
            ;; Update access stats
            (incf (cache-entry-access-count entry))
            (setf (cache-entry-last-accessed entry) (get-universal-time))
            (incf (l1-cache-hit-count cache))
            (values t (cache-entry-value entry)))
          (progn
            (incf (l1-cache-miss-count cache))
            (values nil nil))))))

(defun l1-put (cache key value &key (ttl-base 300) (ttl-random 120))
  "Put value into L1 cache with random TTL"
  (declare (type l1-cache cache)
           (type string key)
           (type t value)
           (type integer ttl-base ttl-random))
  (bordeaux-threads:with-lock-held ((l1-cache-lock cache))
    ;; Check if need eviction
    (when (>= (l1-cache-size cache) (l1-cache-max-size cache))
      (l1-evict-oldest cache))
    ;; Create entry with random TTL
    (let* ((now (get-universal-time))
           (ttl (+ ttl-base (random (1+ ttl-random))))
           (entry (make-cache-entry
                   :key key
                   :value value
                   :created-at now
                   :expires-at (+ now ttl)
                   :access-count 0
                   :last-accessed now)))
      (setf (gethash key (l1-cache-store cache)) entry)
      (incf (l1-cache-size cache)))
    (values)))

(defun l1-remove (cache key)
  "Remove value from L1 cache"
  (declare (type l1-cache cache)
           (type string key))
  (bordeaux-threads:with-lock-held ((l1-cache-lock cache))
    (let ((removed (remhash key (l1-cache-store cache))))
      (when removed
        (decf (l1-cache-size cache)))
      removed)))

(defun l1-evict-oldest (cache)
  "Evict oldest/least accessed entry (LRU)"
  (declare (type l1-cache cache)
           (optimize (speed 3) (safety 1)))
  (let ((oldest-key nil)
        (oldest-time most-positive-fixnum)
        (lowest-access most-positive-fixnum))
    ;; Find entry with lowest priority (access-count * time)
    (maphash (lambda (key entry)
               (declare (ignore key))
               (let* ((access (cache-entry-access-count entry))
                      (time (cache-entry-last-accessed entry))
                      (priority (+ (- most-positive-fixnum time)
                                   (* access 1000))))
                 (when (< priority lowest-access)
                   (setf lowest-access priority
                         oldest-key (cache-entry-key entry)))))
             (l1-cache-store cache))
    ;; Remove oldest entry
    (when oldest-key
      (remhash oldest-key (l1-cache-store cache))
      (decf (l1-cache-size cache))
      (incf (l1-cache-eviction-count cache))
      (log-debug "L1 cache evicted: ~a" oldest-key))))

(defun l1-clear (cache)
  "Clear all entries in L1 cache"
  (declare (type l1-cache cache))
  (bordeaux-threads:with-lock-held ((l1-cache-lock cache))
    (clrhash (l1-cache-store cache))
    (setf (l1-cache-size cache) 0)))

(defun l1-stats (cache)
  "Get L1 cache statistics"
  (declare (type l1-cache cache))
  (list :size (l1-cache-size cache)
        :max-size (l1-cache-max-size cache)
        :hits (l1-cache-hit-count cache)
        :misses (l1-cache-miss-count cache)
        :evictions (l1-cache-eviction-count cache)
        :hit-ratio (if (> (+ (l1-cache-hit-count cache)
                             (l1-cache-miss-count cache))
                          0)
                       (/ (float (l1-cache-hit-count cache))
                          (+ (l1-cache-hit-count cache)
                             (l1-cache-miss-count cache)))
                       0.0)))

;;;; Bloom Filter for Cache Penetration Protection

(defstruct bloom-filter
  "Simple bloom filter for cache penetration protection"
  (bits nil :type (simple-array bit (*)))
  (size 0 :type integer)
  (hash-count 3 :type integer)) ; Number of hash functions

(defun init-bloom-filter (&key (size 1000000) (hash-count 3))
  "Initialize bloom filter"
  (declare (type integer size hash-count))
  (make-bloom-filter
   :bits (make-array size :element-type 'bit :initial-element 0)
   :size size
   :hash-count hash-count))

(defun bloom-filter-hash (key index size)
  "Generate hash for bloom filter"
  (declare (type string key)
           (type integer index size)
           (optimize (speed 3) (safety 1)))
  ;; Simple hash combining key with index
  (let ((hash 5381))
    (loop for char across key
          do (setf hash (logand #xFFFFFFFF
                                (logxor (ash hash 5)
                                        (char-code char)
                                        index))))
    (mod hash size)))

(defun bloom-filter-add (filter key)
  "Add key to bloom filter"
  (declare (type bloom-filter filter)
           (type string key))
  (loop for i from 0 below (bloom-filter-hash-count filter)
        do (let ((pos (bloom-filter-hash key i (bloom-filter-size filter))))
             (setf (aref (bloom-filter-bits filter) pos) 1))))

(defun bloom-filter-contains-p (filter key)
  "Check if key might be in bloom filter"
  (declare (type bloom-filter filter)
           (type string key))
  (loop for i from 0 below (bloom-filter-hash-count filter)
        always (let ((pos (bloom-filter-hash key i (bloom-filter-size filter))))
                 (= (aref (bloom-filter-bits filter) pos) 1))))

(defvar *bloom-filter* nil
  "Global bloom filter instance")

(defun init-bloom-filter-global (&key (size 1000000) (hash-count 3))
  "Initialize global bloom filter"
  (setf *bloom-filter* (init-bloom-filter :size size :hash-count hash-count))
  (log-info "Bloom filter initialized: size=~a" size)
  *bloom-filter*)

;;;; Multi-Level Cache Interface

(defparameter *redis-host* "localhost"
  "Redis host")
(defparameter *redis-port* 6379
  "Redis port")
(defparameter *redis-db* 0
  "Redis database")

(defstruct multi-level-cache
  "Multi-level cache manager"
  (l1-cache nil)
  (redis-connected nil :type boolean)
  (bloom-filter nil)
  (lock (bordeaux-threads:make-lock "mlc-lock")))

(defvar *multi-level-cache* nil
  "Global multi-level cache instance")

(defun init-multi-level-cache (&key
                                (l1-max-size 10000)
                                (bloom-size 1000000)
                                (redis-host "localhost")
                                (redis-port 6379))
  "Initialize multi-level cache system"
  (declare (type integer l1-max-size bloom-size)
           (type string redis-host)
           (type integer redis-port))
  (setf *redis-host* redis-host
        *redis-port* redis-port)
  ;; Connect to Redis
  (let ((connected nil))
    (handler-case
        (progn
          (redis:connect :host redis-host :port redis-port)
          (setf connected t)
          (log-info "Redis connected for cache: ~a:~a" redis-host redis-port))
      (error (c)
        (log-warn "Redis connection failed: ~a" c)))
    (let ((cache (make-multi-level-cache
                  :l1-cache (init-l1-cache :max-size l1-max-size)
                  :bloom-filter (init-bloom-filter-global :size bloom-size)
                  :redis-connected connected)))
      (setf *multi-level-cache* cache)
      (if (multi-level-cache-redis-connected cache)
          (log-info "Multi-level cache initialized: L1=~a, L2=Redis, L3=DB" l1-max-size)
          (log-warn "Multi-level cache initialized: L1=~a, L2=disabled, L3=DB" l1-max-size))
      cache)))

;;;; Cache Operations with Random TTL

(defun random-ttl (base random-range)
  "Calculate random TTL to prevent cache avalanche"
  (declare (type integer base random-range)
           (optimize (speed 3) (safety 1)))
  (+ base (random (1+ random-range))))

(defun mlc-get (cache key fetch-fn &key (ttl-base 300) (ttl-random 120))
  "Get value from multi-level cache
   If not found, call fetch-fn and cache result
   Returns: value"
  (declare (type multi-level-cache cache)
           (type string key)
           (type function fetch-fn)
           (type integer ttl-base ttl-random))
  (let ((l1 (multi-level-cache-l1-cache cache))
        (l2-connected (multi-level-cache-redis-connected cache))
        (bloom (multi-level-cache-bloom-filter cache)))
    ;; Check bloom filter first (cache penetration protection)
    (when (and bloom (not (bloom-filter-contains-p bloom key)))
      ;; Key definitely doesn't exist, return nil without fetching
      (log-debug "Bloom filter miss: ~a" key)
      (return-from mlc-get nil))
    ;; Try L1 cache
    (when l1
      (multiple-value-bind (found value) (l1-get l1 key)
        (when found
          (log-debug "L1 cache hit: ~a" key)
          (return-from mlc-get value))))
    ;; Try L2 cache (Redis)
    (when l2-connected
      (handler-case
          (let ((value (redis:red-get key)))
            (when value
              (log-debug "L2 cache hit: ~a" key)
              ;; Promote to L1
              (l1-put l1 key value :ttl-base ttl-base :ttl-random ttl-random)
              (return-from mlc-get value))))
        (error (c)
          (log-debug "L2 cache error: ~a" c))))
    ;; Cache miss, fetch from L3 (database via fetch-fn)
    (log-debug "Cache miss: ~a" key)
    (let ((value (funcall fetch-fn)))
      (when value
        ;; Cache in L2 first
        (when l2-connected
          (handler-case
              (let ((ttl (random-ttl ttl-base (* 10 ttl-random))))
                (redis:red-setex key ttl value))
            (error (c)
              (log-debug "L2 cache set error: ~a" c))))
        ;; Cache in L1
        (when l1
          (l1-put l1 key value :ttl-base ttl-base :ttl-random ttl-random))
        ;; Add to bloom filter
        (when bloom
          (bloom-filter-add bloom key))
      value)))

(defun mlc-put (cache key value &key (ttl-base 300) (ttl-random 120))
  "Put value into multi-level cache"
  (declare (type multi-level-cache cache)
           (type string key)
           (type t value)
           (type integer ttl-base ttl-random))
  (let ((l1 (multi-level-cache-l1-cache cache))
        (l2-connected (multi-level-cache-redis-connected cache))
        (bloom (multi-level-cache-bloom-filter cache)))
    ;; Cache in L2 first
    (when l2-connected
      (handler-case
          (let ((ttl (random-ttl ttl-base (* 10 ttl-random))))
            (redis:red-setex key ttl value))
        (error (c)
          (log-debug "L2 cache set error: ~a" c))))
    ;; Cache in L1
    (when l1
      (l1-put l1 key value :ttl-base ttl-base :ttl-random ttl-random))
    ;; Add to bloom filter
    (when bloom
      (bloom-filter-add bloom key))))

(defun mlc-remove (cache key)
  "Remove value from multi-level cache"
  (declare (type multi-level-cache cache)
           (type string key))
  (let ((l1 (multi-level-cache-l1-cache cache))
        (l2-connected (multi-level-cache-redis-connected cache)))
    ;; Remove from L2 first
    (when l2-connected
      (handler-case
          (redis:red-del key)
        (error (c)
          (log-debug "L2 cache del error: ~a" c))))
    ;; Remove from L1
    (when l1
      (l1-remove l1 key))))

(defun mlc-clear (cache)
  "Clear all caches"
  (declare (type multi-level-cache cache))
  (let ((l1 (multi-level-cache-l1-cache cache))
        (l2-connected (multi-level-cache-redis-connected cache)))
    ;; Clear L2 first
    (when l2-connected
      (handler-case
          (redis:red-flushdb)
        (error (c)
          (log-warn "L2 cache flush error: ~a" c))))
    ;; Clear L1
    (when l1
      (l1-clear l1))))

(defun mlc-stats (cache)
  "Get multi-level cache statistics"
  (declare (type multi-level-cache cache))
  (let ((l1 (multi-level-cache-l1-cache cache))
        (l2-connected (multi-level-cache-redis-connected cache)))
    (list :l1-stats (when l1 (l1-stats l1))
          :l2-connected l2-connected
          :bloom-filter (if (multi-level-cache-bloom-filter cache) t nil))))

;;;; Convenience Functions for Message Caching

(defun cache-message (message-id message &key (ttl-base 300) (ttl-random 120))
  "Cache a message object"
  (declare (type string message-id)
           (type t message)
           (type integer ttl-base ttl-random))
  (ensure-pool-initialized)
  (let ((cache *multi-level-cache*))
    (when cache
      (mlc-put cache (format nil "msg:~a" message-id)
               (cl-json:encode-json-to-string message)
               :ttl-base ttl-base :ttl-random ttl-random))))

(defun get-cached-message (message-id &optional fetch-fn)
  "Get cached message, fetch if not cached"
  (declare (type string message-id)
           (type (or null function) fetch-fn))
  (ensure-pool-initialized)
  (let ((cache *multi-level-cache*))
    (when cache
      (mlc-get cache (format nil "msg:~a" message-id)
               (or fetch-fn (lambda () nil))
               :ttl-base 300 :ttl-random 120))))

(defun remove-cached-message (message-id)
  "Remove cached message"
  (declare (type string message-id))
  (ensure-pool-initialized)
  (let ((cache *multi-level-cache*))
    (when cache
      (mlc-remove cache (format nil "msg:~a" message-id)))))

;;;; Cache User Data

(defun cache-user (user-id user &key (ttl-base 600) (ttl-random 300))
  "Cache a user object"
  (declare (type string user-id)
           (type t user)
           (type integer ttl-base ttl-random))
  (ensure-pool-initialized)
  (let ((cache *multi-level-cache*))
    (when cache
      (mlc-put cache (format nil "user:~a" user-id)
               (cl-json:encode-json-to-string user)
               :ttl-base ttl-base :ttl-random ttl-random))))

(defun get-cached-user (user-id &optional fetch-fn)
  "Get cached user, fetch if not cached"
  (declare (type string user-id)
           (type (or null function) fetch-fn))
  (ensure-pool-initialized)
  (let ((cache *multi-level-cache*))
    (when cache
      (mlc-get cache (format nil "user:~a" user-id)
               (or fetch-fn (lambda () nil))
               :ttl-base 600 :ttl-random 300))))

;;;; Cache Conversation Data

(defun cache-conversation (conversation-id conversation &key (ttl-base 600) (ttl-random 300))
  "Cache a conversation object"
  (declare (type string conversation-id)
           (type t conversation)
           (type integer ttl-base ttl-random))
  (ensure-pool-initialized)
  (let ((cache *multi-level-cache*))
    (when cache
      (mlc-put cache (format nil "conv:~a" conversation-id)
               (cl-json:encode-json-to-string conversation)
               :ttl-base ttl-base :ttl-random ttl-random))))

(defun get-cached-conversation (conversation-id &optional fetch-fn)
  "Get cached conversation, fetch if not cached"
  (declare (type string conversation-id)
           (type (or null function) fetch-fn))
  (ensure-pool-initialized)
  (let ((cache *multi-level-cache*))
    (when cache
      (mlc-get cache (format nil "conv:~a" conversation-id)
               (or fetch-fn (lambda () nil))
               :ttl-base 600 :ttl-random 300))))

;;;; Health Check

(defun cache-health-check ()
  "Check cache system health"
  (let ((cache *multi-level-cache*)
        (healthy t)
        (issues nil))
    ;; Check L1
    (unless (multi-level-cache-l1-cache cache)
      (setf healthy nil)
      (push "L1 cache not initialized" issues))
    ;; Check L2
    (unless (multi-level-cache-redis-client cache)
      (push "L2 cache (Redis) not connected" issues))
    ;; Check Bloom Filter
    (unless (multi-level-cache-bloom-filter cache)
      (push "Bloom filter not initialized" issues))
    (list :healthy healthy :issues issues)))

;;;; Print Statistics

(defun print-cache-stats ()
  "Print cache statistics to stdout"
  (let ((cache *multi-level-cache*))
    (when cache
      (format t "~%Multi-Level Cache Statistics:~%")
      (let ((stats (mlc-stats cache)))
        (format t "  L1 Cache:~%")
        (let ((l1-stats (getf stats :l1-stats)))
          (when l1-stats
            (format t "    Size: ~a/~a~%"
                    (getf l1-stats :size)
                    (getf l1-stats :max-size))
            (format t "    Hits: ~a, Misses: ~a~%"
                    (getf l1-stats :hits)
                    (getf l1-stats :misses))
            (format t "    Hit Ratio: ~,2F%~%"
                    (* 100 (getf l1-stats :hit-ratio)))
            (format t "    Evictions: ~a~%"
                    (getf l1-stats :evictions))))
        (format t "  L2 Cache (Redis): ~a~%"
                (if (getf stats :l2-connected) "Connected" "Disconnected"))
        (format t "  Bloom Filter: ~a~%"
                (if (getf stats :bloom-filter) "Active" "Disabled"))))))

;;;; Exports

(export '(;; Configuration
          *cache-config*
          ;; L1 cache
          l1-cache
          make-l1-cache
          init-l1-cache
          l1-get
          l1-put
          l1-remove
          l1-clear
          l1-stats
          ;; Bloom filter
          bloom-filter
          make-bloom-filter
          init-bloom-filter
          init-bloom-filter-global
          bloom-filter-add
          bloom-filter-contains-p
          *bloom-filter*
          ;; Multi-level cache
          multi-level-cache
          make-multi-level-cache
          init-multi-level-cache
          mlc-get
          mlc-put
          mlc-remove
          mlc-clear
          mlc-stats
          *multi-level-cache*
          ;; Convenience functions
          cache-message
          get-cached-message
          remove-cached-message
          cache-user
          get-cached-user
          cache-conversation
          get-cached-conversation
          ;; Health check
          cache-health-check
          print-cache-stats)
        :lispim-core)
