;;;; file-transfer.lisp - Large File Transfer Module
;;;;
;;;; Provides chunked file upload, resume support, and offline file transfer
;;;; Features: chunked upload, progress tracking, resume from breakpoint, file expiration

(in-package :lispim-core)

;;;; Dependencies

(eval-when (:compile-toplevel :load-toplevel :execute)
  (ql:quickload '(:postmodern :cl-redis :cl-json :ironclad :babel :salza2)))

;;;; Configuration

(defparameter *max-file-size* (* 2 1024 1024 1024) ; 2GB
  "Maximum file size in bytes")

(defparameter *chunk-size* (* 1024 1024) ; 1MB
  "Default chunk size for file upload")

(defparameter *file-ttl* (* 7 24 60 60) ; 7 days
  "File expiration time in seconds (for offline files)")

(defparameter *upload-dir* #P"/tmp/lispim-uploads/"
  "Directory for storing uploaded file chunks")

;;;; Data Structures

(defstruct file-transfer
  "File transfer record"
  (file-id "" :type string)
  (filename "" :type string)
  (file-size 0 :type integer)
  (file-type "" :type string)
  (file-hash "" :type string)
  (uploader-id "" :type string)
  (chunk-size 0 :type integer)
  (total-chunks 0 :type integer)
  (uploaded-chunks 0 :type integer)
  (status :pending :type keyword) ; :pending :uploading :completed :failed
  (created-at 0 :type integer)
  (expires-at 0 :type integer))

(defstruct file-chunk
  "File chunk record"
  (chunk-id "" :type string)
  (file-id "" :type string)
  (chunk-index 0 :type integer)
  (chunk-size 0 :type integer)
  (chunk-hash "" :type string)
  (uploaded-at 0 :type integer))

;;;; Database Operations

(defun ensure-file-transfer-tables-exist ()
  "Create file transfer tables if not exist"
  (ensure-pg-connected)

  ;; File transfers table
  (postmodern:query
   "CREATE TABLE IF NOT EXISTS file_transfers (
      file_id VARCHAR(64) PRIMARY KEY,
      filename VARCHAR(255) NOT NULL,
      file_size BIGINT NOT NULL,
      file_type VARCHAR(100),
      file_hash VARCHAR(64),
      uploader_id VARCHAR(255) NOT NULL,
      chunk_size INTEGER DEFAULT 1048576,
      total_chunks INTEGER NOT NULL,
      uploaded_chunks INTEGER DEFAULT 0,
      status VARCHAR(20) DEFAULT 'pending',
      created_at TIMESTAMPTZ DEFAULT NOW(),
      expires_at TIMESTAMPTZ,
      storage_path VARCHAR(512),
      cdn_url TEXT,
      download_count INTEGER DEFAULT 0,
      is_offline BOOLEAN DEFAULT FALSE,
      recipient_id VARCHAR(255)
    )")

  (postmodern:query
   "CREATE INDEX IF NOT EXISTS idx_file_transfers_uploader ON file_transfers(uploader_id)")
  (postmodern:query
   "CREATE INDEX IF NOT EXISTS idx_file_transfers_status ON file_transfers(status)")
  (postmodern:query
   "CREATE INDEX IF NOT EXISTS idx_file_transfers_expires ON file_transfers(expires_at)")

  ;; File chunks table (for tracking uploaded chunks)
  (postmodern:query
   "CREATE TABLE IF NOT EXISTS file_chunks (
      id BIGSERIAL PRIMARY KEY,
      chunk_id VARCHAR(64) UNIQUE NOT NULL,
      file_id VARCHAR(64) REFERENCES file_transfers(file_id) ON DELETE CASCADE,
      chunk_index INTEGER NOT NULL,
      chunk_size INTEGER NOT NULL,
      chunk_hash VARCHAR(64),
      storage_path VARCHAR(512),
      uploaded_at TIMESTAMPTZ DEFAULT NOW(),
      UNIQUE(file_id, chunk_index)
    )")

  (postmodern:query
   "CREATE INDEX IF NOT EXISTS idx_file_chunks_file ON file_chunks(file_id)")
  (postmodern:query
   "CREATE INDEX IF NOT EXISTS idx_file_chunks_chunk ON file_chunks(chunk_id)")

  (log-info "File transfer tables initialized"))

;;;; File Transfer Operations

(defun init-file-transfer (file-id filename file-size file-type uploader-id
                           &key (chunk-size *chunk-size*) recipient-id)
  "Initialize a new file transfer session"
  (declare (type string file-id filename file-type uploader-id)
           (type integer file-size chunk-size)
           (type (or null string) recipient-id))

  (let* ((now (get-universal-time))
         (expires-at (+ now *file-ttl*))
         (total-chunks (ceiling file-size chunk-size)))

    (postmodern:query
     "INSERT INTO file_transfers
      (file_id, filename, file_size, file_type, uploader_id, chunk_size,
       total_chunks, created_at, expires_at, is_offline, recipient_id)
      VALUES ($1, $2, $3, $4, $5, $6, $7, to_timestamp($8), to_timestamp($9), $10, $11)"
     file-id filename file-size file-type uploader-id
     chunk-size total-chunks
     (storage-universal-to-unix now)
     (storage-universal-to-unix expires-at)
     (if recipient-id t nil)
     recipient-id)

    (log-info "Initialized file transfer ~a (~a bytes)" file-id file-size)

    (make-file-transfer
     :file-id file-id
     :filename filename
     :file-size file-size
     :file-type file-type
     :uploader-id uploader-id
     :chunk-size chunk-size
     :total-chunks total-chunks
     :uploaded-chunks 0
     :status :pending
     :created-at now
     :expires-at expires-at)))

(defun get-file-transfer (file-id)
  "Get file transfer info by ID"
  (declare (type string file-id))

  (let ((result (postmodern:query
                 "SELECT * FROM file_transfers WHERE file_id = $1"
                 file-id :alists)))

    (when result
      (let ((row (car result)))
        (flet ((get-val (name)
                 (let ((cell (find name row :key #'car :test #'string=)))
                   (when cell (cdr cell)))))
          (make-file-transfer
           :file-id (get-val "FILE_ID")
           :filename (get-val "FILENAME")
           :file-size (parse-integer (get-val "FILE_SIZE"))
           :file-type (get-val "FILE_TYPE")
           :file-hash (get-val "FILE_HASH")
           :uploader-id (get-val "UPLOADER_ID")
           :chunk-size (or (parse-integer (get-val "CHUNK_SIZE") :junk-allowed t) *chunk-size*)
           :total-chunks (parse-integer (get-val "TOTAL_CHUNKS"))
           :uploaded-chunks (parse-integer (get-val "UPLOADED_CHUNKS"))
           :status (keywordify (get-val "STATUS"))
           :created-at (storage-universal-to-unix (get-val "CREATED_AT"))
           :expires-at (storage-universal-to-unix (get-val "EXPIRES_AT"))))))))

(defun update-file-transfer-status (file-id status &key file-hash storage-path)
  "Update file transfer status"
  (declare (type string file-id status)
           (type (or null string) file-hash storage-path))

  (if storage-path
      (postmodern:query
       "UPDATE file_transfers
        SET status = $2, storage_path = $3, uploaded_chunks = total_chunks
        WHERE file_id = $1"
       file-id status storage-path)
      (postmodern:query
       "UPDATE file_transfers SET status = $2 WHERE file_id = $1"
       file-id status))

  (when file-hash
    (postmodern:query
     "UPDATE file_transfers SET file_hash = $2 WHERE file_id = $1"
     file-id file-hash))

  (log-info "Updated file transfer ~a status to ~a" file-id status))

(defun record-file-chunk (chunk-id file-id chunk-index chunk-size storage-path &key chunk-hash)
  "Record an uploaded file chunk"
  (declare (type string chunk-id file-id storage-path)
           (type integer chunk-index chunk-size)
           (type (or null string) chunk-hash))

  (postmodern:query
   "INSERT INTO file_chunks
    (chunk_id, file_id, chunk_index, chunk_size, chunk_hash, storage_path)
    VALUES ($1, $2, $3, $4, $5, $6)
    ON CONFLICT (chunk_id) DO NOTHING"
   chunk-id file-id chunk-index chunk-size chunk-hash storage-path)

  (postmodern:query
   "UPDATE file_transfers SET uploaded_chunks = uploaded_chunks + 1
    WHERE file_id = $1"
   file-id)

  chunk-id)

(defun get-uploaded-chunks (file-id)
  "Get list of uploaded chunk indices for a file"
  (declare (type string file-id))

  (let ((result (postmodern:query
                 "SELECT chunk_index FROM file_chunks
                  WHERE file_id = $1
                  ORDER BY chunk_index"
                 file-id :alists)))

    (when result
      (loop for row in result
            collect (cdr (assoc :|chunk_index| row))))))

(defun is-chunk-uploaded-p (file-id chunk-index)
  "Check if a specific chunk has been uploaded"
  (declare (type string file-id)
           (type integer chunk-index))

  (let ((result (postmodern:query
                 "SELECT 1 FROM file_chunks
                  WHERE file_id = $1 AND chunk_index = $2"
                 file-id chunk-index)))

    (and result (> (length result) 0))))

(defun delete-file-transfer (file-id)
  "Delete file transfer record and associated chunks"
  (declare (type string file-id))

  ;; Get storage paths for cleanup
  (let ((paths (postmodern:query
                "SELECT storage_path FROM file_chunks WHERE file_id = $1"
                file-id :alists)))

    ;; Delete from database
    (postmodern:query
     "DELETE FROM file_transfers WHERE file_id = $1"
     file-id)

    ;; Return paths for cleanup
    (when paths
      (loop for row in paths
            collect (cdr (assoc :|storage_path| row))))))

;;;; Redis Operations for Upload Progress

(defun redis-upload-progress-key (file-id)
  "Get Redis key for upload progress"
  (format nil "upload:progress:~a" file-id))

(defun update-upload-progress (file-id uploaded-chunks total-chunks)
  "Update upload progress in Redis"
  (declare (type string file-id)
           (type integer uploaded-chunks total-chunks))

  (when (get-redis)
    (redis:red-setex (format nil "~a:progress" file-id)
                     *file-ttl*
                     (format nil "~a/~a" uploaded-chunks total-chunks))))

(defun get-upload-progress (file-id)
  "Get upload progress from Redis"
  (declare (type string file-id))

  (let ((progress (redis:red-get (format nil "~a:progress" file-id))))

    (when progress
      (multiple-value-bind (uploaded total)
          (parse-integer progress :junk-allowed t)
        (declare (ignore total))
        uploaded))

    (let ((transfer (get-file-transfer file-id)))
      (when transfer
        (values (file-transfer-uploaded-chunks transfer)
                (file-transfer-total-chunks transfer))))))

;;;; Chunk Management

(defun generate-chunk-id (file-id chunk-index)
  "Generate unique chunk ID"
  (declare (type string file-id)
           (type integer chunk-index))

  (format nil "~a:chunk:~a" file-id chunk-index))

(defun get-chunk-storage-path (file-id chunk-index)
  "Get storage path for a file chunk"
  (declare (type string file-id)
           (type integer chunk-index))

  (let ((dir (make-pathname
              :directory (append (pathname-directory *upload-dir*)
                                 (list (subseq file-id 0 2))))))

    (ensure-directories-exist dir)

    (merge-pathnames
     (make-pathname
      :name (format nil "~a_part_~a" file-id chunk-index)
      :type "chunk")
     dir)))

(defun get-file-storage-path (file-id)
  "Get storage path for a complete file"
  (declare (type string file-id))

  (let ((dir (make-pathname
              :directory (append (pathname-directory *upload-dir*)
                                 (list "files" (subseq file-id 0 2))))))

    (ensure-directories-exist dir)

    (merge-pathnames
     (make-pathname
      :name file-id
      :type "file")
     dir)))

;;;; File Operations

(defun calculate-file-hash (file-path)
  "Calculate SHA-256 hash of a file"
  (declare (type string file-path))

  (with-open-file (stream file-path :direction :input :element-type '(unsigned-byte 8))
    (let ((hash (ironclad:make-digest :sha256))
          (buffer (make-array 8192 :element-type '(unsigned-byte 8))))

      (loop
         for bytes-read = (read-sequence buffer stream)
         while (> bytes-read 0)
         do (ironclad:update-digest hash buffer :end bytes-read))

      (ironclad:byte-array-to-hex-string
       (ironclad:digest-sequence hash (make-array 32 :element-type '(unsigned-byte 8)))))))

(defun merge-file-chunks (file-id chunk-paths output-path)
  "Merge uploaded file chunks into final file"
  (declare (type string file-id output-path)
           (type list chunk-paths))

  (ensure-directories-exist output-path)

  (with-open-file (out output-path :direction :output :if-exists :supersede
                       :element-type '(unsigned-byte 8))
    (dolist (chunk-path chunk-paths)
      (when (probe-file chunk-path)
        (with-open-file (in chunk-path :direction :input
                            :element-type '(unsigned-byte 8))
          (let ((buffer (make-array 8192 :element-type '(unsigned-byte 8))))
            (loop
               for bytes-read = (read-sequence buffer in)
               while (> bytes-read 0)
               do (write-sequence buffer out :end bytes-read)))))))

  (log-info "Merged file ~a from ~d chunks" file-id (length chunk-paths))

  output-path)

(defun cleanup-expired-files ()
  "Clean up expired file transfers"
  (let ((now (get-universal-time)))

    ;; Get expired files
    (let ((expired (postmodern:query
                    "SELECT file_id, storage_path FROM file_transfers
                     WHERE expires_at < to_timestamp($1)"
                    (storage-universal-to-unix now) :alists)))

      (dolist (row expired)
        (let ((file-id (cdr (assoc :|file_id| row)))
              (storage-path (cdr (assoc :|storage_path| row))))

          ;; Delete from Redis
          (redis:red-del (format nil "~a:progress" file-id))

          ;; Delete physical files
          (when storage-path
            (ignore-errors
              (delete-file (probe-file storage-path)))))

        ;; Delete from database
        (postmodern:query
         "DELETE FROM file_transfers WHERE file_id = $1"
         (cdr (assoc :|file_id| row)))))

    (log-info "Cleaned up ~d expired file transfers" (length expired))))

;;;; Cleanup Worker

(defvar *file-cleanup-worker* nil
  "File cleanup worker thread")

(defvar *file-cleanup-running* nil
  "File cleanup worker running flag")

(defun start-file-cleanup-worker ()
  "Start file cleanup background worker"
  (when *file-cleanup-worker*
    (stop-file-cleanup-worker))

  (setf *file-cleanup-running* t)

  (setf *file-cleanup-worker*
        (bordeaux-threads:make-thread
         (lambda ()
           (loop while *file-cleanup-running*
              do (progn
                   (cleanup-expired-files)
                   (sleep 3600)))) ; Run every hour

         :name "file-cleanup-worker"))

  (log-info "File cleanup worker started"))

(defun stop-file-cleanup-worker ()
  "Stop file cleanup background worker"
  (setf *file-cleanup-running* nil)

  (when *file-cleanup-worker*
    (bordeaux-threads:destroy-thread *file-cleanup-worker*)
    (setf *file-cleanup-worker* nil))

  (log-info "File cleanup worker stopped"))

;;;; Export Functions

(export '(ensure-file-transfer-tables-exist
          init-file-transfer
          get-file-transfer
          update-file-transfer-status
          record-file-chunk
          get-uploaded-chunks
          is-chunk-uploaded-p
          delete-file-transfer
          update-upload-progress
          get-upload-progress
          generate-chunk-id
          get-chunk-storage-path
          get-file-storage-path
          calculate-file-hash
          merge-file-chunks
          cleanup-expired-files
          start-file-cleanup-worker
          stop-file-cleanup-worker
          *max-file-size*
          *chunk-size*
          *file-ttl*
          *upload-dir*))
