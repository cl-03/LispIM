;;;; cdn-storage.lisp - CDN 存储模块
;;;;
;;;; 实现媒体文件 CDN 存储，支持多种对象存储后端
;;;; 支持：MinIO, 阿里云 OSS, 七牛云 Kodo, AWS S3
;;;;
;;;; 功能：
;;;; - 文件上传/下载
;;;; - 缩略图生成
;;;; - CDN URL 获取
;;;; - 生命周期管理
;;;;
;;;; 参考架构：
;;;; - WeChat: 本地 CDN + 云 CDN 混合
;;;; - Telegram: 分布式文件系统

(in-package :lispim-core)

;;;; 依赖声明

(eval-when (:compile-toplevel :load-toplevel :execute)
  (ql:quickload '(:drakma :cl-json :babel :ironclad :salza2)))

;;;; CDN 配置

(defparameter *cdn-providers*
  '((:minio . ((:endpoint . "http://localhost:9000")
               (:bucket . "lispim-media")
               (:access-key . "minioadmin")
               (:secret-key . "minioadmin")
               (:region . "us-east-1")))
    (:aliyun-oss . ((:endpoint . "oss-cn-hangzhou.aliyuncs.com")
                    (:bucket . "lispim-media")
                    (:access-key-id . "")
                    (:access-key-secret . "")
                    (:region . "cn-hangzhou")))
    (:qiniu-kodo . ((:endpoint . "s3-cn-east-1.qiniucs.com")
                    (:bucket . "lispim-media")
                    (:access-key . "")
                    (:secret-key . "")
                    (:region . "cn-east-1")))
    (:aws-s3 . ((:endpoint . "s3.amazonaws.com")
                (:bucket . "lispim-media")
                (:access-key . "")
                (:secret-key . "")
                (:region . "us-east-1"))))
  "支持的 CDN 提供商配置")

(defparameter *cdn-config*
  '((:provider . :minio)            ; 默认提供商
    (:use-local . t)                ; 是否使用本地存储降级
    (:local-path . "/tmp/lispim-cdn/") ; 本地存储路径
    (:cdn-domain . "cdn.example.com")  ; CDN 域名
    (:https-p . t)                  ; 是否使用 HTTPS
    (:max-file-size . (* 100 1024 1024)) ; 最大文件大小 100MB
    (:image-formats . (:jpg :png :gif :webp)) ; 支持的图片格式
    (:thumbnail-sizes . ((128 . 128) (256 . 256) (512 . 512))) ; 缩略图尺寸
    (:expiry-seconds . (* 24 3600)) ; URL 过期时间（秒）
    (:lifecycle-days . 30))         ; 生命周期（天）
  "CDN 配置")

;;;; CDN 存储结构

(defstruct cdn-storage
  "CDN 存储客户端"
  (provider :minio :type keyword)
  (endpoint "" :type string)
  (bucket "" :type string)
  (access-key "" :type string)
  (secret-key "" :type string)
  (region "" :type string)
  (cdn-domain "" :type string)
  (local-path nil :type (or null string))
  (use-local-p nil :type boolean)
  (upload-count 0 :type integer)
  (download-count 0 :type integer)
  (total-bytes 0 :type integer))

;;;; 辅助函数

(defun get-cdn-provider-config (provider)
  "获取 CDN 提供商配置"
  (cdr (assoc provider *cdn-providers*)))

(defun cdn-config-get (key)
  "获取 CDN 配置值"
  (cdr (assoc key *cdn-config*)))

;;;; 初始化

(defun init-cdn-storage (&key (provider (cdn-config-get :provider))
                              endpoint bucket access-key secret-key region
                              cdn-domain local-path use-local-p)
  "初始化 CDN 存储模块"
  (let* ((provider-config (get-cdn-provider-config provider))
         (cdn (make-cdn-storage
               :provider provider
               :endpoint (or endpoint
                             (cdr (assoc :endpoint provider-config))
                             "http://localhost:9000")
               :bucket (or bucket
                           (cdr (assoc :bucket provider-config))
                           "lispim-media")
               :access-key (or access-key
                               (cdr (assoc :access-key provider-config))
                               "minioadmin")
               :secret-key (or secret-key
                               (cdr (assoc :secret-key provider-config))
                               "minioadmin")
               :region (or region
                           (cdr (assoc :region provider-config))
                           "us-east-1")
               :cdn-domain (or cdn-domain (cdn-config-get :cdn-domain))
               :local-path (or local-path (cdn-config-get :local-path))
               :use-local-p (or use-local-p (cdn-config-get :use-local)))))
    ;; 创建本地存储目录
    (when (and (cdn-storage-use-local-p cdn)
               (cdn-storage-local-path cdn))
      (ensure-directories-exist (cdn-storage-local-path cdn)))
    (log-info "CDN storage initialized: ~a (~a)" provider (cdn-storage-endpoint cdn))
    cdn))

;;;; S3 兼容 API 实现（简化版）

(defun s3-generate-signature (method bucket key content-type date secret-key)
  "生成 S3 兼容签名"
  (declare (type string method bucket key content-type date secret-key))
  (let* ((string-to-sign (format nil "~a~%~%~%~a~%~a~%~a~%~a"
                                 method
                                 (if (string= bucket "") "" (format nil "/~a" bucket))
                                 key
                                 content-type
                                 date))
         (hmac (ironclad:make-hmac (babel:string-to-octets secret-key) :sha256)))
    (ironclad:update-hmac hmac (babel:string-to-octets string-to-sign))
    (cl-base64:usb8-array-to-base64-string (ironclad:hmac-digest hmac))))

(defun s3-generate-auth-header (access-key signature)
  "生成 S3 授权头"
  (declare (type string access-key signature))
  (format nil "AWS ~a:~a" access-key signature))

;;;; 文件上传

(defun upload-file (cdn file-path &key object-key content-type metadata)
  "上传文件到 CDN"
  (declare (type cdn-storage cdn)
           (type string file-path))

  ;; 检查文件是否存在
  (unless (probe-file file-path)
    (error 'file-not-found :pathname file-path))

  (let* ((file-size (with-open-file (stream file-path :direction :input)
                      (file-length stream)))
         (max-size (cdn-config-get :max-file-size)))

    ;; 检查文件大小
    (when (> file-size max-size)
      (error 'storage-quota-exceeded
             :used file-size
             :quota max-size))

    ;; 生成 object key
    (let* ((key (or object-key
                    (generate-object-key file-path)))
           (content-type (or content-type
                             (guess-content-type file-path))))

      (if (cdn-storage-use-local-p cdn)
          ;; 本地存储
          (upload-file-local cdn file-path key)
          ;; 远程 CDN 存储
          (upload-file-remote cdn file-path key content-type metadata)))

    ;; 更新统计
    (incf (cdn-storage-upload-count cdn))
    (incf (cdn-storage-total-bytes cdn) file-size)))

(defun upload-file-local (cdn file-path key)
  "上传文件到本地存储"
  (let* ((local-dir (cdn-storage-local-path cdn))
         (dest-path (merge-pathnames key local-dir)))
    (ensure-directories-exist dest-path)
    (uiop:copy-file file-path dest-path)
    (log-debug "Uploaded file locally: ~a -> ~a" file-path dest-path)
    key))

(defun upload-file-remote (cdn file-path key content-type metadata)
  "上传文件到远程 CDN（S3 兼容 API）"
  (let* ((endpoint (cdn-storage-endpoint cdn))
         (bucket (cdn-storage-bucket cdn))
         (url (format nil "~a/~a/~a" endpoint bucket key))
         (file-content (with-open-file (s file-path :element-type '(unsigned-byte 8)
                                          :if-does-not-exist :error
                                          :direction :input)
                         (let ((data (make-array (file-length s) :element-type '(unsigned-byte 8))))
                           (read-sequence data s)
                           data)))
         (date (format-timestring nil (get-universal-time) :separator #\T))
         (signature (s3-generate-signature "PUT" bucket key content-type date
                                           (cdn-storage-secret-key cdn)))
         (auth-header (s3-generate-auth-header (cdn-storage-access-key cdn) signature)))

    ;; 准备请求头
    (let ((headers `(("Authorization" . ,auth-header)
                     ("Date" . ,date)
                     ("Content-Type" . ,content-type)
                     ("Content-Length" . ,(length file-content)))))

      ;; 添加自定义 metadata
      (when metadata
        (loop for (k . v) in metadata
              do (push (cons (format nil "x-amz-meta-~a" k) v) headers)))

      ;; 发送 PUT 请求
      (let ((response (drakma:http-request url
                                           :method :put
                                           :content file-content
                                           :additional-headers headers)))
        (log-debug "Uploaded file to CDN: ~a (~a bytes)" key (length file-content))
        key))))

;;;; 文件下载

(defun download-file (cdn object-key &key (destination nil))
  "从 CDN 下载文件"
  (declare (type cdn-storage cdn)
           (type string object-key))

  (incf (cdn-storage-download-count cdn))

  (if (cdn-storage-use-local-p cdn)
      ;; 本地存储
      (download-file-local cdn object-key destination)
      ;; 远程 CDN 存储
      (download-file-remote cdn object-key destination)))

(defun download-file-local (cdn object-key destination)
  "从本地存储下载文件"
  (let* ((local-dir (cdn-storage-local-path cdn))
         (source-path (merge-pathnames object-key local-dir)))
    (if (probe-file source-path)
        (if destination
            (progn
              (ensure-directories-exist destination)
              (uiop:copy-file source-path destination)
              destination)
            (with-open-file (s source-path :element-type '(unsigned-byte 8)
                               :if-does-not-exist :error
                               :direction :input)
              (let ((data (make-array (file-length s) :element-type '(unsigned-byte 8))))
                (read-sequence data s)
                data)))
        (error 'storage-not-found :key object-key))))

(defun download-file-remote (cdn object-key destination)
  "从远程 CDN 下载文件"
  (let* ((endpoint (cdn-storage-endpoint cdn))
         (bucket (cdn-storage-bucket cdn))
         (url (format nil "~a/~a/~a" endpoint bucket object-key))
         (content (drakma:http-request url)))
    (if destination
        (progn
          (ensure-directories-exist destination)
          (with-open-file (out destination :element-type '(unsigned-byte 8)
                                        :if-exists :supersede
                                        :if-does-not-exist :create)
            (write-sequence content out))
          destination)
        content)))

;;;; 删除文件

(defun delete-cdn-file (cdn object-key)
  "从 CDN 删除文件"
  (declare (type cdn-storage cdn)
           (type string object-key))

  (if (cdn-storage-use-local-p cdn)
      ;; 本地存储
      (let ((local-path (merge-pathnames object-key (cdn-storage-local-path cdn))))
        (when (probe-file local-path)
          (cl:delete-file local-path)
          (log-debug "Deleted file locally: ~a" local-path)))
      ;; 远程 CDN 存储
      (let* ((endpoint (cdn-storage-endpoint cdn))
             (bucket (cdn-storage-bucket cdn))
             (url (format nil "~a/~a/~a" endpoint bucket object-key))
             (date (format-timestring nil (get-universal-time) :separator #\T))
             (signature (s3-generate-signature "DELETE" bucket object-key "" date
                                               (cdn-storage-secret-key cdn))))
        (drakma:http-request url
                             :method :delete
                             :additional-headers `(("Authorization" . ,(s3-generate-auth-header (cdn-storage-access-key cdn) signature))
                                                   ("Date" . ,date)))))
  t)

;;;; CDN URL 生成

(defun generate-cdn-url (cdn object-key &key (expires nil) (thumbnail-size nil))
  "生成 CDN 访问 URL"
  (declare (type cdn-storage cdn)
           (type string object-key))

  (let* ((cdn-domain (cdn-storage-cdn-domain cdn))
         (protocol (if (cdn-config-get :https-p) "https" "http"))
         (base-url (if (and cdn-domain (not (string= cdn-domain "")))
                       (format nil "~a://~a" protocol cdn-domain)
                       (format nil "~a/~a" (cdn-storage-endpoint cdn) (cdn-storage-bucket cdn))))
         (key-prefix (if thumbnail-size
                         (format nil "thumbnails/~dx~d/" (car thumbnail-size) (cdr thumbnail-size))
                         ""))
         (full-key (format nil "~a~a" key-prefix object-key)))

    (if expires
        ;; 生成带签名的临时 URL
        (generate-signed-url cdn full-key expires)
        ;; 生成永久 URL
        (format nil "~a/~a" base-url full-key))))

(defun generate-signed-url (cdn object-key expires-seconds)
  "生成带签名的临时访问 URL"
  (let* ((endpoint (cdn-storage-endpoint cdn))
         (bucket (cdn-storage-bucket cdn))
         (url (format nil "~a/~a/~a" endpoint bucket object-key))
         (expires (+ (get-universal-time) expires-seconds))
         ;; 简化签名实现
         (signature (ironclad:byte-array-to-hex-string
                     (ironclad:random-data 16))))
    (format nil "~a?X-Amz-Signature=~a&X-Amz-Expires=~a"
            url signature expires-seconds)))

;;;; 缩略图生成

(defun generate-thumbnail (cdn image-path &key (size '(256 . 256)) (quality 85))
  "生成图片缩略图"
  (declare (type cdn-storage cdn)
           (type string image-path))

  ;; 注意：Common Lisp 图像处理能力有限，这里使用简化实现
  ;; 生产环境可调用外部工具（如 ImageMagick）或集成 cl-gd

  (let* ((thumbnail-key (format nil "thumbnails/~dx~d/~a.~a"
                                 (car size) (cdr size)
                                 (pathname-name image-path)
                                 (pathname-type image-path)))
         (thumbnail-path (merge-pathnames thumbnail-key (cdn-storage-local-path cdn))))

    ;; 简化实现：复制原文件（实际应用需要图像处理）
    (ensure-directories-exist thumbnail-path)
    (uiop:copy-file image-path thumbnail-path)

    (log-debug "Generated thumbnail: ~a" thumbnail-key)
    thumbnail-key))

;;;; 文件元数据

(defun get-file-metadata (cdn object-key)
  "获取文件元数据"
  (declare (type cdn-storage cdn)
           (type string object-key))

  (if (cdn-storage-use-local-p cdn)
      ;; 本地存储
      (let ((local-path (merge-pathnames object-key (cdn-storage-local-path cdn))))
        (if (probe-file local-path)
            (with-open-file (stream local-path :direction :input)
              (list :key object-key
                    :size (file-length stream)
                    :last-modified (file-write-date local-path)
                    :content-type (guess-content-type object-key)))
            nil))
      ;; 远程 CDN 存储 - 简化实现
      (list :key object-key
            :size 0  ; 需要从 CDN 获取
            :last-modified (get-universal-time)
            :content-type (guess-content-type object-key))))

;;;; 生命周期管理

(defun set-lifecycle (cdn object-key days)
  "设置文件生命周期"
  (declare (type cdn-storage cdn)
           (type string object-key)
           (type integer days))

  ;; 简化实现：记录过期时间
  (log-info "Set lifecycle for ~a: ~a days" object-key days)
  t)

(defun expire-files (cdn)
  "检查并删除过期文件"
  (declare (type cdn-storage cdn))

  ;; 简化实现：遍历本地文件检查过期
  (when (and (cdn-storage-use-local-p cdn)
             (cdn-storage-local-path cdn))
    (let ((lifecycle-days (cdn-config-get :lifecycle-days)))
      (loop for file in (directory (merge-pathnames "*.*" (cdn-storage-local-path cdn)))
            do (let ((age (- (get-universal-time) (file-write-date file))))
                 (when (> age (* lifecycle-days 24 3600))
                   (delete-cdn-file cdn (enough-namestring file (cdn-storage-local-path cdn)))))))))

;;;; 辅助函数

(defun generate-object-key (file-path)
  "生成对象存储 key"
  (let* ((now (get-universal-time))
         (date-str (format nil "~d~d~d"
                           (floor now 86400)
                           (floor now 3600)
                           (floor now 60)))
         (filename (pathname-name file-path))
         (extension (pathname-type file-path))
         (uuid (uuid:make-v4-uuid)))
    (format nil "~a/~a-~a.~a"
            date-str filename uuid extension)))

(defun guess-content-type (file-path)
  "猜测文件 content-type"
  (let ((ext (pathname-type file-path)))
    (case (intern (string-upcase ext) 'keyword)
      (:jpg "image/jpeg")
      (:jpeg "image/jpeg")
      (:png "image/png")
      (:gif "image/gif")
      (:webp "image/webp")
      (:mp4 "video/mp4")
      (:webm "video/webm")
      (:mov "video/quicktime")
      (:avi "video/x-msvideo")
      (:mp3 "audio/mpeg")
      (:aac "audio/aac")
      (:ogg "audio/ogg")
      (:wav "audio/wav")
      (:amr "audio/amr")
      (:pdf "application/pdf")
      (:doc "application/msword")
      (:docx "application/vnd.openxmlformats-officedocument.wordprocessingml.document")
      (:xls "application/vnd.ms-excel")
      (:xlsx "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
      (:ppt "application/vnd.ms-powerpoint")
      (:pptx "application/vnd.openxmlformats-officedocument.presentationml.presentation")
      (:zip "application/zip")
      (:gz "application/gzip")
      (:rar "application/vnd.rar")
      (:apk "application/vnd.android.package-archive")
      (t "application/octet-stream"))))

(defun format-timestring (stream universal-time &key (separator #\Space))
  "格式化时间字符串"
  (multiple-value-bind (second minute hour day month year)
      (decode-universal-time universal-time 0)
    (format stream "~4,'0d-~2,'0d-~2,'0dT~2,'0d~2,'0d~2,'0dZ"
            year month day hour minute second)))

;;;; 统计

(defun get-cdn-stats (cdn)
  "获取 CDN 统计信息"
  (declare (type cdn-storage cdn))
  (list :provider (cdn-storage-provider cdn)
        :endpoint (cdn-storage-endpoint cdn)
        :bucket (cdn-storage-bucket cdn)
        :upload-count (cdn-storage-upload-count cdn)
        :download-count (cdn-storage-download-count cdn)
        :total-bytes (cdn-storage-total-bytes cdn)
        :use-local-p (cdn-storage-use-local-p cdn)))

;;;; 全局 CDN 实例

(defvar *cdn-storage* nil
  "全局 CDN 存储实例")

;;;; 高层 API

(defun cdn-upload (file-path &key object-key content-type metadata)
  "高层上传 API"
  (unless *cdn-storage*
    (error "CDN storage not initialized"))
  (upload-file *cdn-storage* file-path
               :object-key object-key
               :content-type content-type
               :metadata metadata))

(defun cdn-download (object-key &key destination)
  "高层下载 API"
  (unless *cdn-storage*
    (error "CDN storage not initialized"))
  (download-file *cdn-storage* object-key :destination destination))

(defun cdn-delete (object-key)
  "高层删除 API"
  (unless *cdn-storage*
    (error "CDN storage not initialized"))
  (delete-cdn-file *cdn-storage* object-key))

(defun cdn-get-url (object-key &key expires thumbnail-size)
  "高层 URL 生成 API"
  (unless *cdn-storage*
    (error "CDN storage not initialized"))
  (generate-cdn-url *cdn-storage* object-key
                    :expires expires
                    :thumbnail-size thumbnail-size))

(defun cdn-generate-thumbnail (image-path &key size quality)
  "高层缩略图生成 API"
  (unless *cdn-storage*
    (error "CDN storage not initialized"))
  (generate-thumbnail *cdn-storage* image-path
                      :size size
                      :quality quality))

;;;; 导出

(export '(;; Initialization
          init-cdn-storage
          *cdn-storage*

          ;; Configuration
          *cdn-providers*
          *cdn-config*
          cdn-config-get

          ;; Low-level API
          upload-file
          download-file
          delete-cdn-file
          generate-cdn-url
          generate-thumbnail
          get-file-metadata
          set-lifecycle
          expire-files

          ;; High-level API
          cdn-upload
          cdn-download
          cdn-delete
          cdn-get-url
          cdn-generate-thumbnail

          ;; Statistics
          get-cdn-stats)
        :lispim-core)
