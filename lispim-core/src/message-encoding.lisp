;;;; message-encoding.lisp - Message Encoding/Decoding
;;;;
;;;; Implements efficient binary message encoding using TLV format
;;;; and MessagePack for comparison and fallback
;;;;
;;;; TLV Format:
;;;; +--------+--------+--------+----------+
;;;; |  Type  |    Length     |  Value    |
;;;; | 1 byte | 2 bytes     | N bytes   |
;;;; +--------+--------+--------+----------+
;;;;
;;;; Reference: Telegram TLV, Protocol Buffers

(in-package :lispim-core)

;;;; Dependencies

;; Dependencies are loaded via ASDF system definition

;;;; Message Type Constants

;; Message types (1 byte)
(defconstant +MSG-TYPE-TEXT+      #x01 "Text message")
(defconstant +MSG-TYPE-IMAGE+     #x02 "Image message")
(defconstant +MSG-TYPE-VOICE+     #x03 "Voice message")
(defconstant +MSG-TYPE-VIDEO+     #x04 "Video message")
(defconstant +MSG-TYPE-FILE+      #x05 "File message")
(defconstant +MSG-TYPE-SYSTEM+    #x06 "System notification")
(defconstant +MSG-TYPE-NOTIFICATION+ #x07 "Push notification")
(defconstant +MSG-TYPE-LINK+      #x08 "Link share message")
(defconstant +MSG-TYPE-STICKER+   #x09 "Sticker message")
(defconstant +MSG-TYPE-LOCATION+  #x0A "Location share")
(defconstant +MSG-TYPE-CONTACT+   #x0B "Contact share")
(defconstant +MSG-TYPE-RECEIPT+   #x10 "Message receipt/ACK")
(defconstant +MSG-TYPE-PRESENCE+  #x11 "Presence update")
(defconstant +MSG-TYPE-TYPING+    #x12 "Typing indicator")

;; Field types for TLV encoding
(defconstant +TLV-TYPE-END+       #x00 "End of message")
(defconstant +TLV-TYPE-STRING+    #x01 "UTF-8 string")
(defconstant +TLV-TYPE-INT64+     #x02 "Signed 64-bit integer")
(defconstant +TLV-TYPE-UINT64+    #x03 "Unsigned 64-bit integer")
(defconstant +TLV-TYPE-BYTES+     #x04 "Raw bytes")
(defconstant +TLV-TYPE-FLOAT64+   #x05 "Double precision float")
(defconstant +TLV-TYPE-BOOL+      #x06 "Boolean (0x00=false, 0x01=true)")
(defconstant +TLV-TYPE-LIST+      #x10 "Nested TLV list")

;;;; Byte Order Utilities

(declaim (inline write-u16-be read-u16-be write-u64-be read-u64-be))

(defun write-u16-be (value stream)
  "Write 16-bit unsigned integer in big-endian format"
  (declare (type (unsigned-byte 16) value)
           (type stream stream)
           (optimize (speed 3) (safety 0)))
  (write-byte (ldb (byte 8 8) value) stream)
  (write-byte (ldb (byte 8 0) value) stream))

(defun read-u16-be (stream)
  "Read 16-bit unsigned integer in big-endian format"
  (declare (type stream stream)
           (optimize (speed 3) (safety 0)))
  (let ((b1 (read-byte stream))
        (b2 (read-byte stream)))
    (declare (type (unsigned-byte 8) b1 b2))
    (logior (ash b1 8) b2)))

(defun write-u64-be (value stream)
  "Write 64-bit unsigned integer in big-endian format"
  (declare (type (unsigned-byte 64) value)
           (type stream stream)
           (optimize (speed 3) (safety 0)))
  (loop for i from 56 downto 0 by 8 do
    (write-byte (ldb (byte 8 i) value) stream)))

(defun read-u64-be (stream)
  "Read 64-bit unsigned integer in big-endian format"
  (declare (type stream stream)
           (optimize (speed 3) (safety 0)))
  (loop with result = 0
        for i from 56 downto 0 by 8 do
          (let ((byte (read-byte stream)))
            (incf result (ash byte i)))
        finally (return result)))

;;;; TLV Field Structure

(defstruct tlv-field
  "TLV (Type-Length-Value) field"
  (type 0 :type (unsigned-byte 8))
  (length 0 :type (unsigned-byte 16))
  (value nil :type (or null (simple-array (unsigned-byte 8) (*)) string integer float boolean)))

;;;; TLV Encoding

(defun encode-tlv-string (string)
  "Encode a string as TLV field"
  (declare (type string string))
  (let* ((octets (babel:string-to-octets string :encoding :utf-8))
         (length (length octets)))
    (assert (< length 65536) (string) "String too long for TLV encoding (~a bytes)" length)
    (make-tlv-field
     :type +TLV-TYPE-STRING+
     :length length
     :value (coerce octets '(simple-array (unsigned-byte 8) (*))))))

(defun encode-tlv-int64 (value)
  "Encode a 64-bit integer as TLV field"
  (declare (type integer value))
  (make-tlv-field
   :type +TLV-TYPE-INT64+
   :length 8
   :value value))

(defun encode-tlv-uint64 (value)
  "Encode a 64-bit unsigned integer as TLV field"
  (declare (type (unsigned-byte 64) value))
  (make-tlv-field
   :type +TLV-TYPE-UINT64+
   :length 8
   :value value))

(defun encode-tlv-bytes (bytes)
  "Encode raw bytes as TLV field"
  (declare (type (simple-array (unsigned-byte 8) (*)) bytes))
  (let ((length (length bytes)))
    (assert (< length 65536) (bytes) "Bytes too long for TLV encoding (~a bytes)" length)
    (make-tlv-field
     :type +TLV-TYPE-BYTES+
     :length length
     :value bytes)))

(defun encode-tlv-bool (value)
  "Encode boolean as TLV field"
  (declare (type boolean value))
  (make-tlv-field
   :type +TLV-TYPE-BOOL+
   :length 1
   :value (if value 1 0)))

(defun encode-tlv-field (field)
  "Encode a single TLV field to byte vector"
  (declare (type tlv-field field)
           (optimize (speed 3) (safety 1)))
  (with-output-to-byte-vector (stream)
    ;; Type (1 byte)
    (write-byte (tlv-field-type field) stream)
    ;; Length (2 bytes, big-endian)
    (write-u16-be (tlv-field-length field) stream)
    ;; Value
    (let ((value (tlv-field-value field)))
      (cond
        ((stringp value)
         (let ((octets (babel:string-to-octets value :encoding :utf-8)))
           (loop for byte across octets do
             (write-byte byte stream))))
        ((typep value '(simple-array (unsigned-byte 8) (*)))
         (loop for byte across value do
           (write-byte byte stream)))
        ((integerp value)
         (write-u64-be value stream))
        ((typep value '(unsigned-byte 8))
         (write-byte value stream))
        (t
         (error "Unsupported TLV value type: ~a" (type-of value)))))))

(defun encode-tlv-list (fields)
  "Encode a list of TLV fields to byte vector"
  (declare (type list fields)
           (optimize (speed 3) (safety 1)))
  (with-output-to-byte-vector (stream)
    (dolist (field fields)
      (cond
        ((typep field 'tlv-field)
         (let ((encoded (encode-tlv-field field)))
           (loop for byte across encoded do
             (write-byte byte stream))))
        (t
         (error "Expected tlv-field, got ~a" (type-of field)))))
    ;; Write end marker
    (write-byte +TLV-TYPE-END+ stream)
    (write-u16-be 0 stream)))

;;;; TLV Decoding

(defun decode-tlv-field (stream)
  "Decode a single TLV field from stream"
  (declare (type stream stream)
           (optimize (speed 3) (safety 1)))
  (let ((type (read-byte stream nil nil)))
    (when (null type)
      (return-from decode-tlv-field nil))

    (let ((length (read-u16-be stream)))
      (when (zerop length)
        ;; End marker
        (return-from decode-tlv-field nil))

      (let ((value-bytes (make-array length :element-type '(unsigned-byte 8))))
        (read-sequence value-bytes stream)

        (let ((value (case type
                       ((+TLV-TYPE-STRING+)
                        (babel:octets-to-string value-bytes :encoding :utf-8))
                       ((+TLV-TYPE-INT64+ +TLV-TYPE-UINT64+)
                        (loop with result = 0
                              for i from (- length 1) downto 0 do
                                (incf result (ash (aref value-bytes (- length i 1)) (* 8 i)))
                              finally (return result)))
                       ((+TLV-TYPE-BOOL+)
                        (not (zerop (aref value-bytes 0))))
                       (t
                        value-bytes))))
          (make-tlv-field
           :type type
           :length length
           :value value)))))

(defun decode-tlv-list (bytes)
  "Decode TLV byte stream to list of fields"
  (declare (type (simple-array (unsigned-byte 8) (*)) bytes)
           (optimize (speed 3) (safety 1)))
  (let ((stream (flexi-streams:make-in-memory-input-stream bytes))
        (fields nil))
    (loop
      (let ((field (decode-tlv-field stream)))
        (if field
            (push field fields)
            (return)))))
    (nreverse fields)))

;;;; Message Encoding (High-level)

(defun encode-message-tlv (message)
  "Encode a message struct to TLV format"
  (declare (type message message))
  (let ((fields nil))
    ;; Message ID (uint64)
    (push (encode-tlv-uint64 (message-id message)) fields)
    ;; Sequence (uint64)
    (push (encode-tlv-uint64 (message-sequence message)) fields)
    ;; Conversation ID (uint64)
    (push (encode-tlv-uint64 (message-conversation-id message)) fields)
    ;; Sender ID (string)
    (push (encode-tlv-string (message-sender-id message)) fields)
    ;; Message type (uint64)
    (let ((type-code (case (message-message-type message)
                       (:text +MSG-TYPE-TEXT+)
                       (:image +MSG-TYPE-IMAGE+)
                       (:voice +MSG-TYPE-VOICE+)
                       (:video +MSG-TYPE-VIDEO+)
                       (:file +MSG-TYPE-FILE+)
                       (:system +MSG-TYPE-SYSTEM+)
                       (:notification +MSG-TYPE-NOTIFICATION+)
                       (:link +MSG-TYPE-LINK+)
                       (t +MSG-TYPE-TEXT+))))
      (push (encode-tlv-uint64 type-code) fields))
    ;; Content (string)
    (when (message-content message)
      (push (encode-tlv-string (message-content message)) fields))
    ;; Created at (uint64)
    (push (encode-tlv-uint64 (lispim-universal-to-unix-ms (message-created-at message))) fields)

    (encode-tlv-list fields)))

(defun decode-message-tlv (bytes)
  "Decode TLV format to message struct"
  (declare (type (simple-array (unsigned-byte 8) (*)) bytes))
  (let* ((fields (decode-tlv-list bytes))
         (msg-id 0)
         (sequence 0)
         (conv-id 0)
         (sender-id "")
         (msg-type :text)
         (content nil)
         (created-at 0))

    (dolist (field fields)
      (case (tlv-field-type field)
        (+TLV-TYPE-UINT64+
         ;; Determine field by position/order
         (cond
           ((zerop msg-id) (setf msg-id (tlv-field-value field)))
           ((zerop sequence) (setf sequence (tlv-field-value field)))
           ((zerop conv-id) (setf conv-id (tlv-field-value field)))
           (t (setf created-at (tlv-field-value field)))))
        (+TLV-TYPE-STRING+
         (if (stringp sender-id)
             (if (string= sender-id "")
                 (setf sender-id (tlv-field-value field))
                 (setf content (tlv-field-value field)))
             (setf sender-id (tlv-field-value field))))))

    ;; Need to properly track field positions - simplified version for now
    (make-message
     :id msg-id
     :sequence sequence
     :conversation-id conv-id
     :sender-id sender-id
     :message-type msg-type
     :content content
     :created-at (storage-unix-to-universal (truncate created-at 1000)))))

;;;; Compression Support

(defun compress-message-if-large (data &key (threshold 1024))
  "Compress message data if larger than threshold"
  (declare (type (simple-array (unsigned-byte 8) (*)) data)
           (type integer threshold))
  (if (< (length data) threshold)
      ;; Below threshold, return as-is with compression flag
      (values data nil)
      ;; Above threshold, compress
      ;; Note: For actual compression, would use zstd or gzip library
      ;; This is a placeholder for the compression interface
      (values data t)))

(defun encode-message-with-compression (message &key (compression-threshold 1024))
  "Encode message with optional compression"
  (declare (type message message))
  (let* ((encoded (encode-message-tlv message))
         (should-compress (> (length encoded) compression-threshold)))
    (if should-compress
        ;; Add compression header
        (let ((compressed encoded))  ;; Placeholder for actual compression
          compressed)
        encoded)))

;;;; Performance Utilities

(defun calculate-compression-ratio (original-bytes encoded-bytes)
  "Calculate compression ratio between original and encoded data"
  (declare (type integer original-bytes encoded-bytes))
  (float (/ encoded-bytes original-bytes)))

(defun benchmark-encoding (&key (iterations 1000))
  "Benchmark TLV encoding performance"
  (let* ((msg (make-message
               :id 1234567890
               :sequence 100
               :conversation-id 9876543210
               :sender-id "1"
               :message-type :text
               :content "Hello, World! This is a test message for benchmarking."
               :created-at (get-universal-time))))
    (with-timing (elapsed)
      (loop repeat iterations do
        (encode-message-tlv msg)))
    (log-info "Benchmark completed: ~a iterations" iterations)))

;;;; Exports

(export '(;; Constants
          +MSG-TYPE-TEXT+
          +MSG-TYPE-IMAGE+
          +MSG-TYPE-VOICE+
          +MSG-TYPE-VIDEO+
          +MSG-TYPE-FILE+
          +MSG-TYPE-SYSTEM+
          +MSG-TYPE-NOTIFICATION+
          +MSG-TYPE-LINK+
          +MSG-TYPE-RECEIPT+
          +MSG-TYPE-PRESENCE+
          +MSG-TYPE-TYPING+

          +TLV-TYPE-END+
          +TLV-TYPE-STRING+
          +TLV-TYPE-INT64+
          +TLV-TYPE-UINT64+
          +TLV-TYPE-BYTES+
          +TLV-TYPE-FLOAT64+
          +TLV-TYPE-BOOL+
          +TLV-TYPE-LIST+

          ;; TLV structures
          tlv-field
          make-tlv-field
          tlv-field-type
          tlv-field-length
          tlv-field-value

          ;; TLV encoding
          encode-tlv-string
          encode-tlv-int64
          encode-tlv-uint64
          encode-tlv-bytes
          encode-tlv-bool
          encode-tlv-field
          encode-tlv-list

          ;; TLV decoding
          decode-tlv-field
          decode-tlv-list

          ;; Message encoding
          encode-message-tlv
          decode-message-tlv
          encode-message-with-compression

          ;; Compression
          compress-message-if-large

          ;; Performance
          calculate-compression-ratio
          benchmark-encoding)
        :lispim-core)
