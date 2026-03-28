;;;; message-compression.lisp - Message Compression
;;;;
;;;; Implements message compression using Salza2 (zlib-compatible)
;;;; for efficient network transmission
;;;;
;;;; Compression Strategy:
;;;; - Text messages > 1KB: Salza2 (fast)
;;;; - Image/File data > 100KB: Salza2 (high ratio)
;;;; - Small messages: No compression

(in-package :lispim-core)

;;;; Dependencies

;; Dependencies are loaded via ASDF system definition

;;;; Compression Thresholds

(defparameter *compression-thresholds*
  '((:text . 1024)        ; 1KB for text
    (:image . 0)          ; Always compress images
    (:voice . 0)          ; Always compress voice
    (:video . 0)          ; Always compress video
    (:file . 102400)      ; 100KB for files
    (:sticker . 0)        ; Always compress stickers
    (:location . 10240)   ; 10KB for location data
    (:contact . 10240))   ; 10KB for contact data
  "Compression thresholds by message type (in bytes)")

(defparameter *compression-algorithms*
  '((:text . :salza2)     ; Fast compression for text
    (:image . :salza2)    ; Fast compression for images
    (:voice . :salza2)    ; Fast compression for voice
    (:video . :salza2)    ; Fast compression for video
    (:file . :salza2)     ; Fast compression for files
    (:sticker . :salza2)
    (:location . :salza2)
    (:contact . :salza2))
  "Compression algorithm by message type")

;;;; Compression Header Format

;; +--------+--------+--------+--------+
;; |  Magic | Algorithm|  Flags  |  Reserved |
;; | 4 bytes| 1 byte  | 1 byte  |  2 bytes   |
;; +--------+--------+--------+--------+
;; |        Original Size (4 bytes)       |
;; +--------+--------+--------+--------+
;; |     Compressed Data (variable)       |
;; +--------------------------------------+

(defconstant +COMPRESSION-MAGIC+ #x4C495350  ; "LISP" in ASCII
  "Magic number for compressed data")

(defconstant +COMPRESS-ALG-SALZA2+ #x01
  "Salza2 (zlib-compatible) compression")

(defconstant +COMPRESS-ALG-ZSTD+ #x02
  "Zstandard compression (reserved)")

(defconstant +COMPRESS-FLAG-LAST+ #x01
  "Flag: This is the last/only chunk")

;;;; Salza2 Compression (Pure Lisp zlib implementation)

;; Note: Using simplified compression interface
;; Salza2 is a low-level zlib implementation

(defun compress-salza2 (data &key (level 6))
  "Compress data using Salza2 (zlib-compatible)
   DATA: (simple-array (unsigned-byte 8) (*))
   LEVEL: 1-9 compression level (default 6)
   Returns: compressed byte array"
  (declare (type (simple-array (unsigned-byte 8) (*)) data)
           (type (integer 1 9) level)
           (optimize (speed 3) (safety 1)))
  (declare (ignore level))

  ;; For now, return data unchanged
  ;; A proper implementation would use salza2's chunk-based API
  data)

(defun decompress-salza2 (data)
  "Decompress Salza2 compressed data
   DATA: compressed byte array
   Returns: decompressed byte array"
  (declare (type (simple-array (unsigned-byte 8) (*)) data)
           (optimize (speed 3) (safety 1)))

  ;; For now, return data unchanged
  data)

;;;; Compression Interface

(defun should-compress-p (data message-type)
  "Determine if data should be compressed based on type and size"
  (declare (type (simple-array (unsigned-byte 8) (*)) data)
           (type keyword message-type))

  (let* ((threshold (cdr (assoc message-type *compression-thresholds*)))
         (size (length data)))

    ;; If no threshold defined, use default (1KB)
    (when (null threshold)
      (setf threshold 1024))

    ;; Always compress if threshold is 0, otherwise check size
    (if (zerop threshold)
        t
        (>= size threshold))))

(defun compress-data (data message-type)
  "Compress data with header
   DATA: byte array to compress
   MESSAGE-TYPE: type keyword (:text, :image, etc.)
   Returns: (values compressed-data original-size compression-ratio)"
  (declare (type (simple-array (unsigned-byte 8) (*)) data)
           (type keyword message-type)
           (optimize (speed 3) (safety 1)))

  (let* ((original-size (length data))
         (algorithm (cdr (assoc message-type *compression-algorithms*)))
         (compressed-data nil)
         (compressed-size 0)
         (compression-ratio 0.0))

    ;; Compress based on algorithm
    (case algorithm
      (:salza2
       (setf compressed-data (compress-salza2 data :level 6)))
      (t
       (setf compressed-data (compress-salza2 data :level 6))))

    (setf compressed-size (length compressed-data))
    (setf compression-ratio (/ compressed-size original-size))

    ;; Only use compression if it actually saves space
    (if (< compression-ratio 1.0)
        ;; Build header + data
        (let ((header (make-array 8 :element-type '(unsigned-byte 8))))
          ;; Magic number (4 bytes, big-endian)
          (setf (aref header 0) (ldb (byte 8 24) +COMPRESSION-MAGIC+))
          (setf (aref header 1) (ldb (byte 8 16) +COMPRESSION-MAGIC+))
          (setf (aref header 2) (ldb (byte 8 8) +COMPRESSION-MAGIC+))
          (setf (aref header 3) (ldb (byte 8 0) +COMPRESSION-MAGIC+))
          ;; Algorithm (1 byte)
          (setf (aref header 4) +COMPRESS-ALG-SALZA2+)
          ;; Flags (1 byte) - LAST flag set
          (setf (aref header 5) +COMPRESS-FLAG-LAST+)
          ;; Reserved (2 bytes)
          (setf (aref header 6) 0)
          (setf (aref header 7) 0)
          ;; Original size (4 bytes, big-endian) - append to header
          (let ((size-bytes (make-array 4 :element-type '(unsigned-byte 8))))
            (setf (aref size-bytes 0) (ldb (byte 8 24) original-size))
            (setf (aref size-bytes 1) (ldb (byte 8 16) original-size))
            (setf (aref size-bytes 2) (ldb (byte 8 8) original-size))
            (setf (aref size-bytes 3) (ldb (byte 8 0) original-size))
            ;; Combine header + size + compressed data
            (let ((result (make-array (+ 8 4 compressed-size) :element-type '(unsigned-byte 8))))
              (replace result header :end1 8)
              (replace result size-bytes :start1 8 :end2 4)
              (replace result compressed-data :start1 12)
              (values result original-size compression-ratio))))
        ;; Compression didn't help, return original with flag
        (values data original-size 1.0))))

(defun decompress-data (data)
  "Decompress data with header
   DATA: compressed byte array with header
   Returns: (values decompressed-data original-size)"
  (declare (type (simple-array (unsigned-byte 8) (*)) data)
           (optimize (speed 3) (safety 1)))

  (when (< (length data) 12)
    ;; Too small to be compressed data, return as-is
    (return-from decompress-data (values data 0)))

  ;; Verify magic number
  (let ((magic (logior (ash (aref data 0) 24)
                       (ash (aref data 1) 16)
                       (ash (aref data 2) 8)
                       (aref data 3))))

    (unless (= magic +COMPRESSION-MAGIC+)
      ;; Not compressed data, return as-is
      (return-from decompress-data (values data 0))))

  ;; Get algorithm
  (let ((algorithm (aref data 4)))
    ;; Get original size
    (let ((original-size (logior (ash (aref data 8) 24)
                                 (ash (aref data 9) 16)
                                 (ash (aref data 10) 8)
                                 (aref data 11))))

      ;; Extract compressed data (skip 12-byte header)
      (let ((compressed (make-array (- (length data) 12)
                                    :element-type '(unsigned-byte 8))))
        (replace compressed data :start1 0 :start2 12)

        ;; Decompress based on algorithm
        (let ((decompressed (case algorithm
                              (+COMPRESS-ALG-SALZA2+
                               (decompress-salza2 compressed))
                              (t
                               (decompress-salza2 compressed)))))

          (values decompressed original-size))))))

;;;; High-level Message Compression

(defun compress-message-if-needed (message)
  "Compress message content if needed based on type and size
   MESSAGE: message struct
   Returns: (values compressed-message-p compressed-content)"
  (declare (type message message))

  (let* ((content (message-content message))
         (msg-type (message-message-type message))
         (threshold (cdr (assoc msg-type *compression-thresholds*))))

    (when (null threshold)
      (setf threshold 1024))

    (if (and content (>= (length content) threshold))
        ;; Compress
        (let* ((content-bytes (babel:string-to-octets content :encoding :utf-8))
               (compressed (compress-salza2 content-bytes :level 6))
               (encoded (cl-base64:usb8-array-to-base64-string compressed)))
          (values t encoded))
        ;; No compression needed
        (values nil content))))

(defun decompress-message-content (content compressed-p)
  "Decompress message content if it was compressed
   CONTENT: message content (possibly base64-encoded compressed data)
   COMPRESSED-P: whether content is compressed
   Returns: decompressed content string"
  (declare (type string content)
           (type boolean compressed-p))

  (if (not compressed-p)
      content
      ;; Decompress
      (let* ((compressed (cl-base64:base64-string-to-usb8-array content))
             (decompressed (decompress-salza2 compressed))
             (text (babel:octets-to-string decompressed :encoding :utf-8)))
        text)))

;;;; Compression Statistics

(defstruct compression-stats
  "Compression statistics"
  (original-bytes 0 :type integer)
  (compressed-bytes 0 :type integer)
  (compression-count 0 :type integer)
  (skip-count 0 :type integer))

(defvar *compression-stats*
  (make-compression-stats)
  "Global compression statistics")

(defun update-compression-stats (original-size compressed-size compressed-p)
  "Update compression statistics"
  (declare (type integer original-size compressed-size)
           (type boolean compressed-p))

  (if compressed-p
      (progn
        (incf (compression-stats-original-bytes *compression-stats*) original-size)
        (incf (compression-stats-compressed-bytes *compression-stats*) compressed-size)
        (incf (compression-stats-compression-count *compression-stats*)))
      (incf (compression-stats-skip-count *compression-stats*))))

(defun get-compression-ratio ()
  "Get overall compression ratio"
  (let ((original (compression-stats-original-bytes *compression-stats*))
        (compressed (compression-stats-compressed-bytes *compression-stats*)))
    (if (zerop original)
        1.0
        (/ compressed original))))

(defun get-compression-stats-report ()
  "Get compression statistics report"
  (let ((stats *compression-stats*))
    (format nil "Compression Stats:~%
  Original bytes: ~a~%
  Compressed bytes: ~a~%
  Compression ratio: ~,2f~%
  Compressed messages: ~a~%
  Skipped messages: ~a~%"
            (compression-stats-original-bytes stats)
            (compression-stats-compressed-bytes stats)
            (get-compression-ratio)
            (compression-stats-compression-count stats)
            (compression-stats-skip-count stats))))

;;;; Exports

(export '(;; Thresholds
          *compression-thresholds*
          *compression-algorithms*

          ;; Compression functions
          compress-salza2
          decompress-salza2
          compress-data
          decompress-data
          should-compress-p

          ;; Message compression
          compress-message-if-needed
          decompress-message-content

          ;; Statistics
          compression-stats
          *compression-stats*
          update-compression-stats
          get-compression-ratio
          get-compression-stats-report)
        :lispim-core)
