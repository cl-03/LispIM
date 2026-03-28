;;;; test-message-encoding.lisp - Message Encoding Tests
;;;;
;;;; Tests for TLV encoding/decoding

(in-package :lispim-core/test)

;;;; Test Package

(defpackage :lispim-core/test/message-encoding
  (:use :cl :fiveam :lispim-core)
  (:export :run-message-encoding-tests))

(in-package :lispim-core/test/message-encoding)

;;;; Byte Order Tests

(def-test test-write-read-u16-be ()
  "Test 16-bit big-endian write/read roundtrip"
  (let ((values '(#x0000 #x00FF #x0100 #x1234 #xABCD #xFFFF)))
    (dolist (val values)
      (let ((buffer (make-array 2 :element-type '(unsigned-byte 8))))
        (with-output-to-byte-vector (stream)
          (write-u16-be val stream)
          (let ((read-val (progn
                            (close stream)
                            (with-input-from-byte-vector (in buffer)
                              (read-u16-be in)))))
            (is (= val read-val)))))))

(def-test test-write-read-u64-be ()
  "Test 64-bit big-endian write/read roundtrip"
  (let ((values '(#x0000000000000000
                  #x00000000000000FF
                  #x0123456789ABCDEF
                  #xFFFFFFFFFFFFFFFF)))
    (dolist (val values)
      (let ((buffer (make-array 8 :element-type '(unsigned-byte 8))))
        (with-output-to-byte-vector (stream)
          (write-u64-be val stream)
          (let ((read-val (progn
                            (close stream)
                            (with-input-from-byte-vector (in buffer)
                              (read-u64-be in)))))
            (is (= val read-val)))))))

;;;; TLV Field Encoding Tests

(def-test test-encode-tlv-string ()
  "Test TLV string encoding"
  (let* ((test-string "Hello, World!")
         (field (encode-tlv-string test-string)))
    (is (= +TLV-TYPE-STRING+ (tlv-field-type field)))
    (is (> (tlv-field-length field) 0))
    (is (typep (tlv-field-value field) '(simple-array (unsigned-byte 8) (*))))))

(def-test test-encode-tlv-uint64 ()
  "Test TLV uint64 encoding"
  (let* ((test-value 123456789012345)
         (field (encode-tlv-uint64 test-value)))
    (is (= +TLV-TYPE-UINT64+ (tlv-field-type field)))
    (is (= 8 (tlv-field-length field)))
    (is (= test-value (tlv-field-value field)))))

(def-test test-encode-tlv-bool ()
  "Test TLV boolean encoding"
  (let ((true-field (encode-tlv-bool t))
        (false-field (encode-tlv-bool nil)))
    (is (= +TLV-TYPE-BOOL+ (tlv-field-type true-field)))
    (is (= +TLV-TYPE-BOOL+ (tlv-field-type false-field)))
    (is (= 1 (tlv-field-length true-field)))
    (is (= 1 (tlv-field-length false-field)))))

;;;; TLV List Encoding Tests

(def-test test-encode-decode-tlv-list ()
  "Test TLV list encode/decode roundtrip"
  (let* ((fields (list (encode-tlv-string "Test")
                       (encode-tlv-uint64 12345)
                       (encode-tlv-bool t)))
         (encoded (encode-tlv-list fields))
         (decoded (decode-tlv-list encoded)))
    (is (= (length fields) (length decoded)))
    (is (= +TLV-TYPE-STRING+ (tlv-field-type (first decoded))))
    (is (= +TLV-TYPE-UINT64+ (tlv-field-type (second decoded))))
    (is (= +TLV-TYPE-BOOL+ (tlv-field-type (third decoded))))))

(def-test test-tlv-list-roundtrip-with-values ()
  "Test TLV list values after roundtrip"
  (let* ((test-string "Hello")
         (test-number 9876543210)
         (fields (list (encode-tlv-string test-string)
                       (encode-tlv-uint64 test-number)))
         (encoded (encode-tlv-list fields))
         (decoded (decode-tlv-list encoded)))
    (is (string= test-string (tlv-field-value (first decoded))))
    (is (= test-number (tlv-field-value (second decoded))))))

;;;; Message Encoding Tests

(def-test test-encode-message-tlv ()
  "Test message to TLV encoding"
  (let* ((msg (make-message
               :id 1234567890
               :sequence 100
               :conversation-id 9876543210
               :sender-id "1"
               :message-type :text
               :content "Test message"
               :created-at (get-universal-time)))
         (encoded (encode-message-tlv msg)))
    (is (> (length encoded) 0))
    (is (typep encoded '(simple-array (unsigned-byte 8) (*))))))

(def-test test-tlv-size-vs-json ()
  "Compare TLV size vs JSON size"
  (let* ((msg (make-message
               :id 1234567890
               :sequence 100
               :conversation-id 9876543210
               :sender-id "1"
               :message-type :text
               :content "This is a test message for size comparison between TLV and JSON encoding"
               :created-at (get-universal-time)))
         (tlv-encoded (encode-message-tlv msg))
         (json-encoded (cl-json:encode-json-to-string
                        `((:id . ,(message-id msg))
                          (:seq . ,(message-sequence msg))
                          (:conv . ,(message-conversation-id msg))
                          (:from . ,(message-sender-id msg))
                          (:type . :text)
                          (:content . ,(message-content msg))
                          (:ts . ,(lispim-universal-to-unix-ms (message-created-at msg))))))
         (tlv-size (length tlv-encoded))
         (json-size (length json-encoded))
         (ratio (/ tlv-size json-size)))
    (format t "~%TLV size: ~a bytes~%" tlv-size)
    (format t "JSON size: ~a bytes~%" json-size)
    (format t "Ratio (TLV/JSON): ~,2f~%" ratio)
    ;; TLV should be smaller or comparable
    (is (<= ratio 1.0))))

;;;; Compression Tests

(def-test test-compress-threshold ()
  "Test compression threshold logic"
  (let ((small-data (make-array 100 :element-type '(unsigned-byte 8) :initial-element 0))
        (large-data (make-array 2000 :element-type '(unsigned-byte 8) :initial-element 0)))
    (multiple-value-bind (data should-compress)
        (compress-message-if-large small-data :threshold 1024)
      (is (not should-compress)))
    (multiple-value-bind (data should-compress)
        (compress-message-if-large large-data :threshold 1024)
      (is should-compress))))

;;;; Run All Tests

(defun run-message-encoding-tests ()
  "Run all message encoding tests"
  (run! :lispim-core/test/message-encoding))
