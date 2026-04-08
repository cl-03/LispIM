;;;; utils.lisp - Client Utility Functions

(in-package :lispim-client)

;;;; Logging

(defun log-debug (format-string &rest args)
  "Log debug message"
  (apply #'format t format-string args)
  (terpri))

(defun log-info (format-string &rest args)
  "Log info message"
  (format t "[INFO] ")
  (apply #'format t format-string args)
  (terpri))

(defun log-error (format-string &rest args)
  "Log error message"
  (format t "[ERROR] ")
  (apply #'format t format-string args)
  (terpri))

;;;; Time utilities

(defun now-unix ()
  "Get current Unix timestamp"
  (floor (get-universal-time)))

(defun now-unix-ms ()
  "Get current Unix timestamp in milliseconds"
  (* (get-universal-time) 1000))

;;;; JSON utilities

(defun json-to-plist (json-string)
  "Convert JSON string to plist"
  (cl-json:decode-json-from-string json-string))

(defun plist-to-json (plist &optional (pretty nil))
  "Convert plist to JSON string"
  (declare (ignore pretty))
  (cl-json:encode-json-to-string plist))

(defun get-json-string (plist key)
  "Get string value from JSON plist"
  (getf plist key))

(defun get-json-integer (plist key)
  "Get integer value from JSON plist"
  (getf plist key))

(defun get-json-boolean (plist key)
  "Get boolean value from JSON plist"
  (getf plist key))

;;;; Condition system

(define-condition client-error (condition)
  ((message :initarg :message :reader client-error-message))
  (:report (lambda (c s) (format s "Client error: ~a" (client-error-message c)))))

(define-condition client-connection-error (client-error)
  ((host :initarg :host :reader client-error-host)
   (port :initarg :port :reader client-error-port))
  (:report (lambda (c s) (format s "Connection failed to ~a:~a - ~a"
                                 (client-error-host c)
                                 (client-error-port c)
                                 (client-error-message c)))))

(define-condition client-auth-error (client-error)
  ()
  (:report (lambda (c s) (format s "Authentication error: ~a" (client-error-message c)))))
