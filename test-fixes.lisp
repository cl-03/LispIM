;;;; test-fixes.lisp - Test script for verifying bug fixes
;;;;
;;;; Run with: sbcl --load test-fixes.lisp

;; Load system
(handler-case
    (progn
      (ql:quickload :lispim-core)
      (format t "~%[TEST] System loaded successfully~%")

      ;; Test 1: Check package exports
      (format t "~%[TEST] Testing package exports...~%")
      (let ((pkg (find-package :lispim-core)))
        (if pkg
            (format t "[OK] Package :lispim-core exists~%")
            (format t "[FAIL] Package :lispim-core not found~%")))

      ;; Test 2: Check time conversion functions
      (format t "~%[TEST] Testing time conversion functions...~%")
      (let* ((now-ut (get-universal-time))
             (now-unix (lispim-core::universal-to-unix now-ut))
             (back-to-ut (lispim-core::unix-to-universal now-unix)))
        (format t "Universal Time: ~a~%" now-ut)
        (format t "Unix Time: ~a~%" now-unix)
        (format t "Back to UT: ~a~%" back-to-ut)
        (if (= now-ut back-to-ut)
            (format t "[OK] Time conversion is correct~%")
            (format t "[FAIL] Time conversion mismatch~%")))

      ;; Test 3: Check auth functions exist
      (format t "~%[TEST] Testing auth function exports...~%")
      (let ((auth-fns '(authenticate authenticate-token verify-token
                                     hash-password verify-password
                                     create-session get-session invalidate-session)))
        (dolist (fn auth-fns)
          (if (fboundp (intern (symbol-name fn) :lispim-core))
              (format t "[OK] ~a is exported~%" fn)
              (format t "[FAIL] ~a is not exported~%" fn))))

      ;; Test 4: Check gateway functions
      (format t "~%[TEST] Testing gateway function exports...~%")
      (let ((gw-fns '(start-gateway stop-gateway
                      register-connection unregister-connection
                      send-ws-message make-ws-message)))
        (dolist (fn gw-fns)
          (if (fboundp (intern (symbol-name fn) :lispim-core))
              (format t "[OK] ~a is exported~%" fn)
              (format t "[FAIL] ~a is not exported~%" fn))))

      ;; Test 5: Check storage functions
      (format t "~%[TEST] Testing storage function exports...~%")
      (let ((st-fns '(init-storage close-storage
                      create-user get-user get-user-by-username
                      send-message get-messages)))
        (dolist (fn st-fns)
          (if (fboundp (intern (symbol-name fn) :lispim-core))
              (format t "[OK] ~a is exported~%" fn)
              (format t "[FAIL] ~a is not exported~%" fn))))

      (format t "~%[TEST] All basic tests completed~%~%"))

  (error (c)
    (format t "~%[FAIL] Error loading system: ~a~%" c)
    (finish-output)))

(finish-output)
