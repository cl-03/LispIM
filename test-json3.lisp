;;;; test-json3.lisp - Test JSON parsing

(ql:quickload :cl-json)

;; Test parsing
(let* ((json-str "{\"count\":3,\"lastAttempt\":12345}")
       (data (cl-json:decode-json-from-string json-str)))
  (format t "Data: ~a~%" data)
  (format t "Type: ~a~%" (type-of data))
  (dolist (item data)
    (format t "  Item: ~a -> ~a (key type: ~a)~%" (car item) (cdr item) (type-of (car item))))
  (format t "assoc :count: ~a~%" (assoc :count data))
  (format t "assoc \"count\": ~a~%" (assoc "count" data :test #'string=))
  (format t "cdr assoc: ~a~%" (cdr (assoc "count" data :test #'string=))))

(quit)
