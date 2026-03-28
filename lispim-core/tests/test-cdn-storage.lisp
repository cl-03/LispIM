;;;; test-cdn-storage.lisp - Unit tests for CDN storage

(in-package :lispim-core/test)

(def-suite test-cdn-storage
  :description "CDN storage unit tests")

(in-suite test-cdn-storage)

;;;; Configuration Tests

(test cdn-config-get
  "Test CDN configuration access"
  (is (not (null (lispim-core:cdn-config-get :provider))))
  (is (not (null (lispim-core:cdn-config-get :local-path))))
  (is (integerp (lispim-core:cdn-config-get :max-file-size))))

(test get-cdn-provider-config
  "Test CDN provider configuration"
  (let ((minio-config (lispim-core:get-cdn-provider-config :minio)))
    (is (not (null minio-config)))
    (is (string= (cdr (assoc :endpoint minio-config)) "http://localhost:9000"))
    (is (string= (cdr (assoc :bucket minio-config)) "lispim-media"))))

;;;; Initialization Tests

(test init-cdn-storage
  "Test CDN storage initialization"
  (let ((cdn (lispim-core:init-cdn-storage
              :provider :minio
              :endpoint "http://localhost:9000"
              :bucket "test-bucket"
              :access-key "test-key"
              :secret-key "test-secret")))
    (is (typep cdn 'lispim-core::cdn-storage))
    (is (eq (lispim-core::cdn-storage-provider cdn) :minio))
    (is (string= (lispim-core::cdn-storage-endpoint cdn) "http://localhost:9000"))
    (is (string= (lispim-core::cdn-storage-bucket cdn) "test-bucket"))
    (is (string= (lispim-core::cdn-storage-access-key cdn) "test-key"))
    (is (string= (lispim-core::cdn-storage-secret-key cdn) "test-secret"))))

(test init-cdn-storage-defaults
  "Test CDN storage initialization with defaults"
  (let ((cdn (lispim-core:init-cdn-storage)))
    (is (typep cdn 'lispim-core::cdn-storage))
    (is (keywordp (lispim-core::cdn-storage-provider cdn)))
    (is (stringp (lispim-core::cdn-storage-endpoint cdn)))
    (is (stringp (lispim-core::cdn-storage-bucket cdn)))))

;;;; Helper Function Tests

(test generate-object-key
  "Test object key generation"
  (let ((key1 (lispim-core::generate-object-key "/tmp/test.jpg"))
        (key2 (lispim-core::generate-object-key "/tmp/test.png")))
    (is (stringp key1))
    (is (stringp key2))
    ;; Keys should be unique (different UUIDs)
    (is (not (string= key1 key2)))
    ;; Keys should contain date prefix
    (is (find #\/ key1))))

(test guess-content-type
  "Test content type guessing"
  (is (string= (lispim-core::guess-content-type "/tmp/test.jpg") "image/jpeg"))
  (is (string= (lispim-core::guess-content-type "/tmp/test.png") "image/png"))
  (is (string= (lispim-core::guess-content-type "/tmp/test.mp4") "video/mp4"))
  (is (string= (lispim-core::guess-content-type "/tmp/test.pdf") "application/pdf"))
  (is (string= (lispim-core::guess-content-type "/tmp/test.unknown") "application/octet-stream")))

;;;; Upload Tests (Local)

(test upload-file-local
  "Test local file upload"
  (let* ((cdn (lispim-core:init-cdn-storage :use-local-p t))
         (test-file (probe-file "test-cdn-storage.lisp"))
         (test-key "test/upload-key.txt"))
    (skip-unless test-file)
    (let ((result (lispim-core::upload-file-local cdn test-file test-key)))
      (is (string= result test-key)))))

;;;; Download Tests (Local)

(test download-file-local
  "Test local file download"
  (let* ((cdn (lispim-core:init-cdn-storage :use-local-p t))
         (test-file (probe-file "test-cdn-storage.lisp"))
         (test-key "test/download-key.txt"))
    (skip-unless test-file)
    ;; First upload
    (lispim-core::upload-file-local cdn test-file test-key)
    ;; Then download
    (let ((result (lispim-core::download-file-local cdn test-key)))
      (is (vectorp result)))))

;;;; Delete Tests (Local)

(test delete-file-local
  "Test local file deletion"
  (let* ((cdn (lispim-core:init-cdn-storage :use-local-p t))
         (test-file (probe-file "test-cdn-storage.lisp"))
         (test-key "test/delete-key.txt"))
    (skip-unless test-file)
    ;; First upload
    (lispim-core::upload-file-local cdn test-file test-key)
    ;; Then delete
    (let ((result (lispim-core:delete-file cdn test-key)))
      (is (eq result t)))))

;;;; URL Generation Tests

(test generate-cdn-url
  "Test CDN URL generation"
  (let ((cdn (lispim-core:init-cdn-storage
              :cdn-domain "cdn.example.com")))
    (let ((url (lispim-core:generate-cdn-url cdn "test/file.jpg")))
      (is (stringp url))
      ;; Should contain CDN domain
      (is (search "cdn.example.com" url))
      ;; Should contain file key
      (is (search "test/file.jpg" url)))))

(test generate-cdn-url-with-expires
  "Test CDN URL generation with expiry"
  (let ((cdn (lispim-core:init-cdn-storage)))
    (let ((url (lispim-core:generate-cdn-url cdn "test/file.jpg" :expires 3600)))
      (is (stringp url))
      ;; Should contain signature parameter
      (is (search "X-Amz-Signature" url))
      ;; Should contain expires parameter
      (is (search "X-Amz-Expires" url)))))

(test generate-cdn-url-thumbnail
  "Test CDN URL generation with thumbnail"
  (let ((cdn (lispim-core:init-cdn-storage)))
    (let ((url (lispim-core:generate-cdn-url cdn "test/image.jpg"
                                              :thumbnail-size '(256 . 256))))
      (is (stringp url))
      ;; Should contain thumbnail prefix
      (is (search "thumbnails/256x256/" url)))))

;;;; Thumbnail Tests

(test generate-thumbnail
  "Test thumbnail generation"
  (let* ((cdn (lispim-core:init-cdn-storage :use-local-p t))
         (test-file (probe-file "test-cdn-storage.lisp")))
    (skip-unless test-file)
    (let ((result (lispim-core:generate-thumbnail cdn test-file :size '(128 . 128))))
      (is (stringp result))
      ;; Should contain thumbnail dimensions
      (is (search "thumbnails/128x128/" result)))))

;;;; Metadata Tests

(test get-file-metadata
  "Test file metadata retrieval"
  (let* ((cdn (lispim-core:init-cdn-storage :use-local-p t))
         (test-file (probe-file "test-cdn-storage.lisp")))
    (skip-unless test-file)
    (let* ((test-key "test/metadata-key.txt")
           (lispim-core::upload-file-local cdn test-file test-key)
           (metadata (lispim-core:get-file-metadata cdn test-key)))
      (is (listp metadata))
      (is (not (null (getf metadata :key))))
      (is (not (null (getf metadata :size))))
      (is (not (null (getf metadata :content-type)))))))

;;;; Statistics Tests

(test get-cdn-stats
  "Test CDN statistics"
  (let ((cdn (lispim-core:init-cdn-storage)))
    (let ((stats (lispim-core:get-cdn-stats cdn)))
      (is (listp stats))
      (is (not (null (getf stats :provider))))
      (is (not (null (getf stats :endpoint))))
      (is (not (null (getf stats :bucket))))
      (is (integerp (getf stats :upload-count)))
      (is (integerp (getf stats :download-count)))
      (is (integerp (getf stats :total-bytes))))))

;;;; High-level API Tests

(test cdn-upload-download
  "Test high-level CDN upload/download"
  (let* ((cdn (lispim-core:init-cdn-storage :use-local-p t))
         (test-file (probe-file "test-cdn-storage.lisp")))
    (skip-unless test-file)
    ;; Set global CDN storage
    (setf lispim-core:*cdn-storage* cdn)
    ;; Upload
    (let ((key (lispim-core:cdn-upload test-file)))
      (is (stringp key))
      ;; Download
      (let ((content (lispim-core:cdn-download key)))
        (is (vectorp content)))
      ;; Get URL
      (let ((url (lispim-core:cdn-get-url key)))
        (is (stringp url)))
      ;; Delete
      (let ((result (lispim-core:cdn-delete key)))
        (is (eq result t))))
    ;; Cleanup
    (setf lispim-core:*cdn-storage* nil)))

;;;; Lifecycle Tests

(test set-lifecycle
  "Test lifecycle setting"
  (let ((cdn (lispim-core:init-cdn-storage)))
    (let ((result (lispim-core:set-lifecycle cdn "test/file.jpg" 30)))
      (is (eq result t)))))

;;;; Integration Test

(test cdn-integration
  "Integration test for CDN operations"
  (let* ((cdn (lispim-core:init-cdn-storage :use-local-p t))
         (test-file (probe-file "test-cdn-storage.lisp")))
    (skip-unless test-file)
    (setf lispim-core:*cdn-storage* cdn)

    ;; Upload file
    (let ((key (lispim-core:cdn-upload test-file :content-type "text/plain")))
      (is (stringp key))

      ;; Generate URL
      (let ((url (lispim-core:cdn-get-url key)))
        (is (stringp url)))

      ;; Generate thumbnail URL
      (let ((thumb-url (lispim-core:cdn-get-url key :thumbnail-size '(256 . 256))))
        (is (stringp thumb-url))
        (is (search "thumbnails/256x256/" thumb-url)))

      ;; Download file
      (let ((content (lispim-core:cdn-download key)))
        (is (vectorp content)))

      ;; Delete file
      (lispim-core:cdn-delete key))

    (setf lispim-core:*cdn-storage* nil)))
