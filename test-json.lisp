;;;; test-json.lisp - Test JSON parsing

(ql:quickload :cl-json)

;; Test 1: Basic parsing
(let* ((json-str "{\"username\":\"admin\",\"password\":\"admin123\"}")
       (data (cl-json:decode-json-from-string json-str)))
  (format t "Test 1 - Basic parsing:~%")
  (format t "  Data: ~a~%" data)
  (format t "  Data type: ~a~%" (type-of data))
  (dolist (item data)
    (format t "  Item: ~a -> ~a (key type: ~a)~%" (car item) (cdr item) (type-of (car item))))
  (format t "  assoc username: ~a~%" (assoc "username" data :test #'string=))
  (format t "  assoc USERNAME: ~a~%" (assoc "USERNAME" data :test #'string=))
  (format t "~%"))

;; Test 2: Using keyword keys
(let* ((json-str "{\"username\":\"admin\",\"password\":\"admin123\"}")
       (cl-json:*key-fn* #'identity)
       (data (cl-json:decode-json-from-string json-str)))
  (format t "Test 2 - With *key-fn* identity:~%")
  (format t "  Data: ~a~%" data)
  (dolist (item data)
    (format t "  Item: ~a (type: ~a)~%" (car item) (type-of (car item))))
  (format t "~%"))

;; Test 3: Using make-keyword-function
(let* ((json-str "{\"username\":\"admin\",\"password\":\"admin123\"}")
       (cl-json:*key-fn* (cl-json:make-keyword-function))
       (data (cl-json:decode-json-from-string json-str)))
  (format t "Test 3 - With *key-fn* keyword:~%")
  (format t "  Data: ~a~%" data)
  (dolist (item data)
    (format t "  Item: ~a -> ~a~%" (car item) (cdr item)))
  (format t "  getf :username: ~a~%" (getf data :username))
  (format t "~%"))

(quit)
