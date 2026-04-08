;;;; utils.lisp - Utility functions for LispIM Client

(in-package :lispim-client)

;; ============================================================================
;; String utilities
;; ============================================================================

(defun kebab-to-camel-case (str)
  "Convert kebab-case string to camelCase"
  (let ((parts (split-sequence:split-sequence #\- str)))
    (if (null parts)
        ""
        (concatenate 'string
                     (string-downcase (car parts))
                     (format nil "~{~@[~A~]~}"
                             (mapcar #'string-upcase (cdr parts)))))))

(defun camel-to-kebab-case (str)
  "Convert camelCase string to kebab-case"
  (with-output-to-string (out)
    (let ((first t))
      (loop for char across str do
        (if first
            (progn
              (write-char (char-downcase char) out)
              (setf first nil))
            (if (upper-case-p char)
                (progn
                  (write-char #\- out)
                  (write-char (char-downcase char) out))
                (write-char char out)))))))

;; ============================================================================
;; JSON utilities
;; ============================================================================

(defun json-to-plist (json-string)
  "Convert JSON string to plist"
  (let ((data (cl-json:decode-json-from-string json-string)))
    (cond
      ((null data) nil)
      ((hash-table-p data)
       (let ((result nil))
         (maphash (lambda (key value)
                    (push key result)
                    (push value result))
                  data)
         (nreverse result)))
      (t data))))

(defun plist-to-json (plist)
  "Convert plist to JSON string"
  (let ((hash (make-hash-table :test 'equal)))
    (loop for (key value) on plist by #'cddr do
      (setf (gethash (string-downcase (symbol-name key)) hash) value))
    (cl-json:encode-json-to-string hash)))

;; ============================================================================
;; Property list utilities
;; ============================================================================

(defun plist-get (plist key)
  "Get value from plist by key"
  (getf plist key))

(defun plist-set (plist key value)
  "Set value in plist, returning new plist"
  (let ((existing (getf plist key)))
    (if existing
        (setf (getf plist key) value)
        (nconc plist (list key value)))))

;; ============================================================================
;; Time utilities
;; ============================================================================

(defun unix-to-universal-time (unix-time)
  "Convert Unix timestamp (milliseconds) to Universal Time"
  (let ((seconds (/ unix-time 1000)))
    (encode-universal-time 0 0 0 1 1 1970 0)
    (+ (encode-universal-time 0 0 0 1 1 1970 0) seconds)))

(defun universal-to-unix-time (universal-time)
  "Convert Universal Time to Unix timestamp (milliseconds)"
  (* (- universal-time (encode-universal-time 0 0 0 1 1 1970 0))
     1000))

(defun format-timestamp (unix-time &optional (format "%Y-%m-%d %H:%M"))
  "Format Unix timestamp (milliseconds) as human-readable string"
  (let* ((seconds (/ unix-time 1000))
         (ut (decode-universal-time seconds 0)))
    (multiple-value-bind (second minute hour day month year)
        ut
      (format nil "~4,'0d-~2,'0d-~2,'0d ~2,'0d:~2,'0d"
              year month day hour minute))))
