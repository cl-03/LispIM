;;; Run All LispIM Core Tests

;; Load ASDF
(require 'asdf)

;; Load system definition
(let* ((base-path (or *load-pathname* *default-pathname-defaults*))
       (base-dir (pathname (directory-namestring base-path))))
  (pushnew base-dir asdf:*central-registry* :test #'equal))

;; Load dependencies
(ql:quickload :fiveam)

;; Load the system
(asdf:load-system :lispim-core)
(asdf:load-system :lispim-core/test)

(format t "~%========================================~%")
(format t "Running All LispIM Tests~%")
(format t "========================================~%~%")

;; Test 1: Snowflake
(format t "=== Snowflake Tests ===~%")
(defparameter *snowflake-result* (fiveam:run! :test-snowflake))
(format t "Snowflake: ~a~%~%" *snowflake-result*)

;; Test 2: Gateway
(format t "=== Gateway Tests ===~%")
(defparameter *gateway-result* (fiveam:run! :test-gateway))
(format t "Gateway: ~a~%~%" *gateway-result*)

;; Test 3: Module
(format t "=== Module Tests ===~%")
(defparameter *module-result* (fiveam:run! :test-module))
(format t "Module: ~a~%~%" *module-result*)

;; Test 4: Chat
(format t "=== Chat Tests ===~%")
(defparameter *chat-result* (fiveam:run! :test-chat))
(format t "Chat: ~a~%~%" *chat-result*)

;; Test 5: E2EE
(format t "=== E2EE Tests ===~%")
(defparameter *e2ee-result* (fiveam:run! :test-e2ee))
(format t "E2EE: ~a~%~%" *e2ee-result*)

(format t "~%========================================~%")
(format t "All Tests Completed~%")
(format t "========================================~%")

(sb-ext:quit :unix-status 0)
