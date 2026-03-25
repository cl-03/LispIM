;;;; test-json2.lisp - Test JSON parsing

(ql:quickload :cl-json)

;; Test 1: Basic parsing - keys become keywords
(let* ((json-str "{\"username\":\"admin\",\"password\":\"admin123\"}")
       (data (cl-json:decode-json-from-string json-str)))
  (format t "Test 1 - Basic parsing (keys are keywords):~%")
  (format t "  Data: ~a~%" data)
  (format t "  assoc :username: ~a~%" (assoc :username data))
  (format t "  getf :username: ~a~%" (getf data :username))
  (format t "~%"))

;; Test 2: Using *key-fn* to keep strings
(let* ((json-str "{\"username\":\"admin\",\"password\":\"admin123\"}")
       (cl-json:*key-fn* #'identity)
       (data (cl-json:decode-json-from-string json-str)))
  (format t "Test 2 - With *key-fn* identity (keys are strings):~%")
  (format t "  Data: ~a~%" data)
  (format t "  assoc \"username\": ~a~%" (assoc "username" data :test #'string=))
  (format t "~%"))

(quit)
