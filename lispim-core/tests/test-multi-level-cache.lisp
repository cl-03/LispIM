;;;; test-multi-level-cache.lisp - Unit tests for multi-level cache
;;;;
;;;; Tests for L1 cache, Bloom filter, and multi-level cache operations

(in-package :lispim-core/test)

(def-suite test-multi-level-cache
  :description "Multi-level cache unit tests")

(in-suite test-multi-level-cache)

;;;; Test L1 Cache

(test l1-cache-basic
  "Test basic L1 cache operations"
  (let ((cache (lispim-core:make-l1-cache :max-size 100)))
    ;; Put and get
    (lispim-core:l1-put cache "key1" "value1")
    (multiple-value-bind (found value) (lispim-core:l1-get cache "key1")
      (is (true found))
      (is (string= value "value1")))
    ;; Get non-existent key
    (multiple-value-bind (found value) (lispim-core:l1-get cache "nonexistent")
      (is (false found))
      (is (null value)))))

(test l1-cache-ttl
  "Test L1 cache TTL expiration"
  (let ((cache (lispim-core:make-l1-cache :max-size 100)))
    ;; Put with very short TTL
    (lispim-core:l1-put cache "key1" "value1" :ttl-base 1 :ttl-random 0)
    ;; Should exist immediately
    (multiple-value-bind (found value) (lispim-core:l1-get cache "key1")
      (is (true found))
      (is (string= value "value1")))
    ;; Wait for expiration
    (sleep 2)
    ;; Should be expired
    (multiple-value-bind (found value) (lispim-core:l1-get cache "key1")
      (is (false found)))))

(test l1-cache-eviction
  "Test L1 cache LRU eviction"
  (let ((cache (lispim-core:make-l1-cache :max-size 3)))
    ;; Fill cache
    (lispim-core:l1-put cache "key1" "value1")
    (lispim-core:l1-put cache "key2" "value2")
    (lispim-core:l1-put cache "key3" "value3")
    ;; Add one more, should evict oldest
    (sleep 0.1) ; Ensure different timestamps
    (lispim-core:l1-put cache "key4" "value4")
    ;; key1 should be evicted
    (multiple-value-bind (found value) (lispim-core:l1-get cache "key1")
      (is (false found)))
    ;; Others should exist
    (multiple-value-bind (found value) (lispim-core:l1-get cache "key2")
      (is (true found)))))

(test l1-cache-remove
  "Test L1 cache removal"
  (let ((cache (lispim-core:make-l1-cache :max-size 100)))
    (lispim-core:l1-put cache "key1" "value1")
    ;; Remove
    (lispim-core:l1-remove cache "key1")
    ;; Should not exist
    (multiple-value-bind (found value) (lispim-core:l1-get cache "key1")
      (is (false found)))))

(test l1-cache-stats
  "Test L1 cache statistics"
  (let ((cache (lispim-core:make-l1-cache :max-size 100)))
    (lispim-core:l1-put cache "key1" "value1")
    (lispim-core:l1-get cache "key1") ; Hit
    (lispim-core:l1-get cache "key1") ; Hit
    (lispim-core:l1-get cache "nonexistent") ; Miss
    (let ((stats (lispim-core:l1-stats cache)))
      (is (= (getf stats :size) 1))
      (is (= (getf stats :hits) 2))
      (is (= (getf stats :misses) 1))
      (is (> (getf stats :hit-ratio) 0.5)))))

;;;; Test Bloom Filter

(test bloom-filter-basic
  "Test basic bloom filter operations"
  (let ((filter (lispim-core:init-bloom-filter :size 1000 :hash-count 3)))
    ;; Add key
    (lispim-core:bloom-filter-add filter "test-key")
    ;; Should contain added key
    (is (true (lispim-core:bloom-filter-contains-p filter "test-key")))
    ;; Should not contain other keys
    (is (false (lispim-core:bloom-filter-contains-p filter "other-key")))))

(test bloom-filter-false-positive
  "Test bloom filter false positive rate"
  (let ((filter (lispim-core:init-bloom-filter :size 10000 :hash-count 3)))
    ;; Add 100 keys
    (loop for i from 1 to 100
          do (lispim-core:bloom-filter-add filter (format nil "key-~a" i)))
    ;; Check false positive rate for 1000 non-existent keys
    (let ((false-positives 0))
      (loop for i from 101 to 1100
            do (when (lispim-core:bloom-filter-contains-p filter (format nil "key-~a" i))
                 (incf false-positives)))
      ;; False positive rate should be low (< 10% for this test)
      (is (< (/ false-positives 1000.0) 0.1)))))

;;;; Test Multi-Level Cache

(test mlc-cache-basic
  "Test basic multi-level cache operations"
  (let ((cache (lispim-core:make-multi-level-cache
                :l1-cache (lispim-core:init-l1-cache :max-size 100)
                :bloom-filter (lispim-core:init-bloom-filter :size 1000))))
    ;; Put value
    (lispim-core:mlc-put cache "key1" "value1")
    ;; Get value
    (let ((value (lispim-core:mlc-get cache "key1" (lambda () "fetched"))))
      (is (string= value "value1")))))

(test mlc-cache-fetch
  "Test multi-level cache fetch-on-miss"
  (let ((cache (lispim-core:make-multi-level-cache
                :l1-cache (lispim-core:init-l1-cache :max-size 100)
                :bloom-filter (lispim-core:init-bloom-filter :size 1000)))
        (fetch-count 0))
    ;; Get with fetch function (cache miss)
    (lispim-core:mlc-get cache "key1" (lambda () (incf fetch-count) "fetched"))
    ;; Fetch should be called once
    (is (= fetch-count 1))
    ;; Get again (cache hit)
    (lispim-core:mlc-get cache "key1" (lambda () (incf fetch-count) "fetched"))
    ;; Fetch should still be called once
    (is (= fetch-count 1))))

(test mlc-cache-remove
  "Test multi-level cache removal"
  (let ((cache (lispim-core:make-multi-level-cache
                :l1-cache (lispim-core:init-l1-cache :max-size 100)
                :bloom-filter (lispim-core:init-bloom-filter :size 1000))))
    (lispim-core:mlc-put cache "key1" "value1")
    ;; Remove
    (lispim-core:mlc-remove cache "key1")
    ;; Should fetch again
    (let ((value (lispim-core:mlc-get cache "key1" (lambda () "fetched"))))
      (is (string= value "fetched")))))

(test mlc-cache-bloom-filter
  "Test bloom filter integration in multi-level cache"
  (let ((cache (lispim-core:make-multi-level-cache
                :l1-cache (lispim-core:init-l1-cache :max-size 100)
                :bloom-filter (lispim-core:init-bloom-filter :size 1000))))
    ;; Add to cache
    (lispim-core:mlc-put cache "key1" "value1")
    ;; Bloom filter should contain key
    (is (true (lispim-core:bloom-filter-contains-p
               (lispim-core:multi-level-cache-bloom-filter cache)
               "key1")))))

;;;; Test Convenience Functions

(test cache-message-basic
  "Test message caching convenience functions"
  (lispim-core:init-multi-level-cache :l1-max-size 100 :bloom-size 1000)
  (let ((msg (list :id "123" :content "Hello" :type :text)))
    (lispim-core:cache-message "123" msg)
    (let ((cached (lispim-core:get-cached-message "123")))
      (is (not (null cached))))))

(test cache-user-basic
  "Test user caching convenience functions"
  (lispim-core:init-multi-level-cache :l1-max-size 100 :bloom-size 1000)
  (let ((user (list :id "user1" :username "test")))
    (lispim-core:cache-user "user1" user)
    (let ((cached (lispim-core:get-cached-user "user1")))
      (is (not (null cached))))))

(test cache-conversation-basic
  "Test conversation caching convenience functions"
  (lispim-core:init-multi-level-cache :l1-max-size 100 :bloom-size 1000)
  (let ((conv (list :id "conv1" :name "Test")))
    (lispim-core:cache-conversation "conv1" conv)
    (let ((cached (lispim-core:get-cached-conversation "conv1")))
      (is (not (null cached))))))
