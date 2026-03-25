;;;; test-redis.lisp - Test Redis operations

(ql:quickload :redis)
(ql:quickload :cl-json)

(redis:connect "127.0.0.1" 6379)

;; Set a test key
(redis:set "testkey" "{\"count\":3,\"lastAttempt\":12345}")

;; Get it back
(let ((val (redis:get "testkey")))
  (format t "Raw value: ~a~%" val)
  (let ((data (cl-json:decode-json-from-string val)))
    (format t "Decoded: ~a~%" data)
    (format t "Type: ~a~%" (type-of data))
    (dolist (item data)
      (format t "  Item: ~a (car type: ~a)~%" item (type-of (car item))))
    (format t "assoc :count: ~a~%" (assoc :count data))
    (format t "assoc \"count\": ~a~%" (assoc "count" data :test #'string=))))

(redis:quit)
(quit)
