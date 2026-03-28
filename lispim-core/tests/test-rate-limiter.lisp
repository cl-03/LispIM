;;;; test-rate-limiter.lisp - Unit tests for rate limiting

(in-package :lispim-core/test)

(def-suite test-rate-limiter
  :description "Rate limiter unit tests")

(in-suite test-rate-limiter)

;;;; Token Bucket Tests

(test make-token-bucket
  "Test token bucket creation"
  (let ((bucket (lispim-core:make-token-bucket 100 10)))
    (is (typep bucket 'lispim-core::token-bucket))
    (is (= (lispim-core::token-bucket-capacity bucket) 100))
    (is (= (lispim-core::token-bucket-refill-rate bucket) 10))
    (is (= (lispim-core::token-bucket-tokens bucket) 100))))

(test token-bucket-try-acquire
  "Test token bucket acquire"
  (let ((bucket (lispim-core:make-token-bucket 10 1)))
    ;; Should be able to acquire tokens
    (is (lispim-core:token-bucket-try-acquire bucket 1))
    (is (lispim-core:token-bucket-try-acquire bucket 1))
    ;; Acquire all remaining
    (loop repeat 8 do (lispim-core:token-bucket-try-acquire bucket 1))
    ;; Should fail when empty
    (is (not (lispim-core:token-bucket-try-acquire bucket 1)))))

(test token-bucket-refill
  "Test token bucket refill"
  (let ((bucket (lispim-core:make-token-bucket 100 10)))
    ;; Empty the bucket
    (loop repeat 100 do (lispim-core:token-bucket-try-acquire bucket 1))
    (is (= (lispim-core:token-bucket-get-tokens bucket) 0))
    ;; Wait for refill (1 second = 10 tokens at rate 10/s)
    (sleep 1.1)
    ;; Should have refilled
    (is (>= (lispim-core:token-bucket-get-tokens bucket) 5))))

;;;; Leaky Bucket Tests

(test make-leaky-bucket
  "Test leaky bucket creation"
  (let ((bucket (lispim-core:make-leaky-bucket 100 10)))
    (is (typep bucket 'lispim-core::leaky-bucket))
    (is (= (lispim-core::leaky-bucket-capacity bucket) 100))
    (is (= (lispim-core::leaky-bucket-leak-rate bucket) 10))
    (is (= (lispim-core::leaky-bucket-water-level bucket) 0))))

(test leaky-bucket-try-acquire
  "Test leaky bucket acquire"
  (let ((bucket (lispim-core:make-leaky-bucket 10 1)))
    ;; Should be able to add water up to capacity
    (loop repeat 10 do (is (lispim-core:leaky-bucket-try-acquire bucket 1)))
    ;; Should fail when full
    (is (not (lispim-core:leaky-bucket-try-acquire bucket 1)))))

;;;; Sliding Window Tests

(test make-sliding-window
  "Test sliding window creation"
  (let ((window (lispim-core:make-sliding-window 60 100)))
    (is (typep window 'lispim-core::sliding-window))
    (is (= (lispim-core::sliding-window-window-size window) 60))
    (is (= (lispim-core::sliding-window-max-requests window) 100))))

(test sliding-window-try-acquire
  "Test sliding window acquire"
  (let ((window (lispim-core:make-sliding-window 60 10)))
    ;; Should allow up to max requests
    (loop repeat 10 do (is (lispim-core:sliding-window-try-acquire window)))
    ;; Should deny after limit
    (is (not (lispim-core:sliding-window-try-acquire window)))))

(test sliding-window-cleanup
  "Test sliding window cleanup"
  (let ((window (lispim-core:make-sliding-window 1 10)))
    ;; Add some requests
    (loop repeat 5 do (lispim-core:sliding-window-try-acquire window))
    (is (= (lispim-core:sliding-window-get-count window) 5))
    ;; Wait for window to expire
    (sleep 1.1)
    ;; Should be cleaned up
    (is (= (lispim-core:sliding-window-get-count window) 0))))

;;;; Fixed Window Tests

(test make-fixed-window
  "Test fixed window creation"
  (let ((window (lispim-core:make-fixed-window 60 100)))
    (is (listp window))
    (is (= (getf window :window-size) 60))
    (is (= (getf window :max-requests) 100))))

(test fixed-window-try-acquire
  "Test fixed window acquire"
  (let ((window (lispim-core:make-fixed-window 60 10)))
    ;; Should allow up to max requests
    (loop repeat 10 do (is (lispim-core:fixed-window-try-acquire window)))
    ;; Should deny after limit
    (is (not (lispim-core:fixed-window-try-acquire window)))))

;;;; Rate Limiter Tests

(test init-rate-limiter
  "Test rate limiter initialization"
  (let ((limiter (lispim-core:init-rate-limiter :default-rate 100 :default-burst 200)))
    (is (typep limiter 'lispim-core::rate-limiter))
    (is (= (lispim-core::rate-limiter-default-rate limiter) 100))
    (is (= (lispim-core::rate-limiter-default-burst limiter) 200))))

(test rate-limit-allow-p
  "Test rate limit check"
  (let ((limiter (lispim-core:init-rate-limiter :default-rate 10 :default-burst 10)))
    ;; Should allow initial requests
    (loop repeat 10 do (is (lispim-core:rate-limit-allow-p limiter "user1")))
    ;; Should deny after limit
    (is (not (lispim-core:rate-limit-allow-p limiter "user1")))
    ;; Different key should be allowed
    (is (lispim-core:rate-limit-allow-p limiter "user2"))))

(test rate-limit-remaining
  "Test rate limit remaining"
  (let ((limiter (lispim-core:init-rate-limiter :default-rate 10 :default-burst 10)))
    (is (= (lispim-core:rate-limit-remaining limiter "user1") 10))
    (lispim-core:rate-limit-allow-p limiter "user1")
    (is (= (lispim-core:rate-limit-remaining limiter "user1") 9))))

;;;; Preset Tests

(test get-preset-limit
  "Test preset limit retrieval"
  (let ((limits (lispim-core:get-preset-limit :api-default)))
    (is (not (null limits)))
    (is (= (car limits) 100))
    (is (= (cadr limits) 200))))

(test check-rate-limit
  "Test high-level rate limit check"
  (lispim-core:init-rate-limiting :default-rate 100 :default-burst 200)
  ;; Should allow with default preset
  (is (lispim-core:check-rate-limit "user1" :api-default))
  ;; Strict preset should have lower limits
  (let ((strict (lispim-core:get-preset-limit :api-strict)))
    (is (= (car strict) 10)))
  (lispim-core:shutdown-rate-limiting))

;;;; Statistics Tests

(test get-rate-limiter-stats
  "Test rate limiter statistics"
  (let ((limiter (lispim-core:init-rate-limiter :default-rate 10 :default-burst 10)))
    ;; Generate some traffic
    (loop repeat 5 do (lispim-core:rate-limit-allow-p limiter "user1"))
    (loop repeat 5 do (lispim-core:rate-limit-allow-p limiter "user1")) ; Some will be denied
    ;; Get stats
    (let ((stats (lispim-core:get-rate-limiter-stats limiter)))
      (is (listp stats))
      (is (>= (getf stats :allowed-count) 0))
      (is (>= (getf stats :denied-count) 0))
      (is (>= (getf stats :denial-rate) 0)))))

;;;; High-level API Tests

(test init-rate-limiting
  "Test high-level init API"
  (let ((limiter (lispim-core:init-rate-limiting :default-rate 100 :default-burst 200)))
    (is (not (null limiter)))
    (is (not (null lispim-core:*rate-limiter*)))
    (lispim-core:shutdown-rate-limiting)))

(test get-rate-limit-stats
  "Test high-level stats API"
  (lispim-core:init-rate-limiting)
  (lispim-core:check-rate-limit "user1")
  (let ((stats (lispim-core:get-rate-limit-stats)))
    (is (not (null stats))))
  (lispim-core:shutdown-rate-limiting))

;;;; Integration Test

(test rate-limiter-integration
  "Integration test for rate limiting"
  (let ((limiter (lispim-core:init-rate-limiter :default-rate 100 :default-burst 100)))
    ;; Simulate multiple users
    (loop for user from 1 to 10
          do (loop for i from 1 to 50
                   do (lispim-core:rate-limit-allow-p limiter (format nil "user~d" user))))
    ;; Check stats
    (let ((stats (lispim-core:get-rate-limiter-stats limiter)))
      (is (>= (getf stats :allowed-count) 0))
      (is (>= (getf stats :denied-count) 0))
      (is (= (getf stats :bucket-count) 10))))
  (lispim-core:shutdown-rate-limiting))
