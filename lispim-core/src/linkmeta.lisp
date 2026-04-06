;;;; linkmeta.lisp - 链接元数据解析插件
;;;;
;;;; 解析聊天消息中的 URL，提取预览信息（标题/描述/图片）
;;;; 支持特殊网站（YouTube/Bilibili）的嵌入卡片
;;;; 参考：Tailchat com.msgbyte.linkmeta 插件

(in-package :lispim-core)

;;;; 依赖声明

(eval-when (:compile-toplevel :load-toplevel :execute)
  (ql:quickload '(::dexador :cl-ppcre :cl-json :bordeaux-threads)))

;;;; 链接元数据结构

(defstruct link-meta
  "链接元数据"
  (url nil :type string)                ; 原始 URL
  (title nil :type (or null string))    ; 页面标题
  (description nil :type (or null string)) ; 页面描述
  (image nil :type (or null string))    ; 缩略图 URL
  (site-name nil :type (or null string)) ; 网站名称
  (type :link :type keyword)            ; 类型：:link, :video, :article
  (embed-url nil :type (or null string)) ; 嵌入 URL（视频网站用）
  (fetched-at nil :type integer))       ; 获取时间（Unix timestamp）

;;;; 缓存配置

(defparameter *link-meta-cache-ttl*
  (* 24 60 60)  ; 24 小时
  "链接元数据缓存过期时间（秒）")

(defvar *link-meta-cache*
  (make-hash-table :test 'equal)
  "内存缓存：URL -> link-meta")

(defvar *link-meta-cache-lock*
  (bordeaux-threads:make-lock "link-meta-cache")
  "缓存锁")

;;;; 特殊网站处理器注册表

(defvar *special-website-handlers*
  (make-hash-table :test 'equal)
  "特殊网站处理器：domain -> function")

;;;; 辅助函数

(defun url-domain (url)
  "从 URL 提取域名"
  (handler-case
      (let ((match (cl-ppcre:scan-to-strings "^[a-zA-Z]+://([^/:]+)" url)))
        (if (and match (> (length match) 0))
            (aref match 0)
            (let ((match2 (cl-ppcre:scan-to-strings "^([^/:]+)" url)))
              (if (and match2 (> (length match2) 0))
                  (aref match2 0)
                  nil))))
    (error ()
      nil)))

(defun extract-meta-tag (html tag-name &optional property-p)
  "从 HTML 中提取 meta 标签内容"
  (let* ((pattern (if property-p
                      (format nil "<meta[^>]+property=[\"']~a:[\"'][^>]+content=[\"']([^\"']*)[\"']" tag-name)
                      (format nil "<meta[^>]+name=[\"']~a:[\"'][^>]+content=[\"']([^\"']*)[\"']" tag-name)))
         (match (multiple-value-list (cl-ppcre:scan-to-strings pattern html :case-fold-mode t))))
    (if (and match (first match) (> (length (first match)) 0))
        (aref (first match) 0)
        nil)))

(defun extract-title (html)
  "从 HTML 中提取 title"
  (let ((match (cl-ppcre:scan-to-strings "<title>([^<]*)</title>" html :case-fold-mode t)))
    (if (and match (> (length match) 0))
        (aref match 0)
        nil)))

(defun extract-og-tag (html tag)
  "提取 Open Graph 标签"
  (let* ((pattern (format nil "<meta[^>]+property=[\"']og:~a[\"'][^>]+content=[\"']([^\"']*)[\"']" tag))
         (match (multiple-value-list (cl-ppcre:scan-to-strings pattern html :case-fold-mode t)))
         (reverse-pattern (format nil "<meta[^>]+content=[\"']([^\"']*)[\"'][^>]+property=[\"']og:~a[\"']" tag))
         (reverse-match (multiple-value-list (cl-ppcre:scan-to-strings reverse-pattern html :case-fold-mode t))))
    (cond
      ((and match (first match) (> (length (first match)) 0))
       (aref (first match) 0))
      ((and reverse-match (first reverse-match) (> (length (first reverse-match)) 0))
       (aref (first reverse-match) 0))
      (t nil))))

(defun extract-twitter-tag (html tag)
  "提取 Twitter Card 标签"
  (let* ((pattern (format nil "<meta[^>]+name=[\"']twitter:~a[\"'][^>]+content=[\"']([^\"']*)[\"']" tag))
         (match (multiple-value-list (cl-ppcre:scan-to-strings pattern html :case-fold-mode t)))
         (reverse-pattern (format nil "<meta[^>]+content=[\"']([^\"']*)[\"'][^>]+name=[\"']twitter:~a[\"']" tag))
         (reverse-match (multiple-value-list (cl-ppcre:scan-to-strings reverse-pattern html :case-fold-mode t))))
    (cond
      ((and match (first match) (> (length (first match)) 0))
       (aref (first match) 0))
      ((and reverse-match (first reverse-match) (> (length (first reverse-match)) 0))
       (aref (first reverse-match) 0))
      (t nil))))

;;;; 通用链接元数据抓取

(defun fetch-link-preview (url)
  "抓取链接预览信息"
  (handler-case
      (let* ((response (dex:get url :headers '(("User-Agent" . "Mozilla/5.0 (compatible; LispIM LinkMeta Bot/1.0)"))))
             (html (if (stringp response)
                       response
                       (babel:octets-to-string response :encoding :utf-8)))
             (title (or (extract-og-tag html "title")
                        (extract-twitter-tag html "title")
                        (extract-title html)))
             (description (or (extract-og-tag html "description")
                              (extract-twitter-tag html "description")))
             (image (or (extract-og-tag html "image")
                        (extract-twitter-tag html "image")))
             (site-name (or (extract-og-tag html "site_name")
                            (extract-twitter-tag html "site"))))
        (make-link-meta
         :url url
         :title (when title (strip-whitespace title))
         :description (when description (strip-whitespace description))
         :image (when image (ensure-absolute-url image url))
         :site-name (when site-name (strip-whitespace site-name))
         :type :link
         :fetched-at (get-universal-time)))
    (error (c)
      (log-error "Failed to fetch link preview for ~a: ~a" url c)
      ;; 返回基本元数据
      (make-link-meta
       :url url
       :title url
       :description nil
       :image nil
       :site-name nil
       :type :link
       :fetched-at (get-universal-time)))))

(defun strip-whitespace (str)
  "去除字符串首尾空白"
  (cl-ppcre:regex-replace-all "^\\s+|\\s+$" str ""))

(defun ensure-absolute-url (url base-url)
  "确保 URL 是绝对的"
  (cond
    ((null url) nil)
    ((or (cl-ppcre:scan "^https?://" url)
         (cl-ppcre:scan "^//" url))
     url)
    ((cl-ppcre:scan "^/" url)
     ;; 相对根路径
     (let ((base (parse-base-url base-url)))
       (concatenate 'string base url)))
    (t
     ;; 相对路径
     (let ((base (parse-base-url base-url)))
       (concatenate 'string base url)))))

(defun parse-base-url (url)
  "解析 URL 的基础部分（协议 + 域名）"
  (handler-case
      (let ((match (cl-ppcre:scan-to-strings "^(https?://[^/]+)" url)))
        (if (and match (> (length match) 0))
            (aref match 0)
            ""))
    (error ()
      "")))

;;;; 特殊网站处理器

(defun register-special-handler (domain handler)
  "注册特殊网站处理器"
  (setf (gethash domain *special-website-handlers*) handler)
  (log-info "Registered special handler for ~a" domain))

(defun get-special-handler (domain)
  "获取特殊网站处理器"
  (gethash domain *special-website-handlers*))

;;;; Bilibili 处理器

(defun extract-bilibili-bvid (url)
  "从 Bilibili URL 中提取 BV 号"
  (let ((match (cl-ppcre:scan-to-strings "/video/(BV[a-zA-Z0-9]+)" url)))
    (if (and match (> (length match) 0))
        (aref match 0)
        nil)))

(defun extract-bilibili-avid (url)
  "从 Bilibili URL 中提取 AV 号"
  (let ((match (cl-ppcre:scan-to-strings "av(\\d+)" url)))
    (if (and match (> (length match) 0))
        (aref match 0)
        nil)))

(defun bilibili-handler (url)
  "Bilibili 视频处理器"
  (let ((bvid (extract-bilibili-bvid url))
        (avid (extract-bilibili-avid url)))
    (when (or bvid avid)
      (make-link-meta
       :url url
       :type :video
       :embed-url (format nil "https://player.bilibili.com/player.html~a~a"
                          (if bvid (format nil "?bvid=~a" bvid) "")
                          (if (and avid (not bvid)) (format nil "?aid=~a" avid) ""))
       :site-name "哔哩哔哩"
       :fetched-at (get-universal-time)))))

;;;; YouTube 处理器

(defun extract-youtube-video-id (url)
  "从 YouTube URL 中提取视频 ID"
  (cond
    ;; youtu.be 短链接
    ((cl-ppcre:scan "youtu\\.be/([a-zA-Z0-9_-]+)" url)
     (let ((match (cl-ppcre:scan-to-strings "youtu\\.be/([a-zA-Z0-9_-]+)" url)))
       (if (and match (> (length match) 0))
           (aref match 0)
           nil)))
    ;; youtube.com/watch?v=
    ((cl-ppcre:scan "youtube\\.com/watch\\?v=([a-zA-Z0-9_-]+)" url)
     (let ((match (cl-ppcre:scan-to-strings "youtube\\.com/watch\\?v=([a-zA-Z0-9_-]+)" url)))
       (if (and match (> (length match) 0))
           (aref match 0)
           nil)))
    ;; youtube.com/embed/
    ((cl-ppcre:scan "youtube\\.com/embed/([a-zA-Z0-9_-]+)" url)
     (let ((match (cl-ppcre:scan-to-strings "youtube\\.com/embed/([a-zA-Z0-9_-]+)" url)))
       (if (and match (> (length match) 0))
           (aref match 0)
           nil)))
    (t nil)))

(defun youtube-handler (url)
  "YouTube 视频处理器"
  (let ((video-id (extract-youtube-video-id url)))
    (when video-id
      (make-link-meta
       :url url
       :type :video
       :embed-url (format nil "https://www.youtube.com/embed/~a" video-id)
       :site-name "YouTube"
       :fetched-at (get-universal-time)))))

;;;; 注册特殊网站处理器

(defun init-special-handlers ()
  "初始化特殊网站处理器"
  (register-special-handler "bilibili.com" #'bilibili-handler)
  (register-special-handler "www.bilibili.com" #'bilibili-handler)
  (register-special-handler "youtube.com" #'youtube-handler)
  (register-special-handler "www.youtube.com" #'youtube-handler)
  (register-special-handler "youtu.be" #'youtube-handler)
  (log-info "Special website handlers initialized"))

;;;; 缓存操作

(defun get-cached-meta (url)
  "获取缓存的链接元数据"
  (bordeaux-threads:with-lock-held (*link-meta-cache-lock*)
    (let ((cached (gethash url *link-meta-cache*)))
      (when cached
        (let ((age (- (get-universal-time) (link-meta-fetched-at cached))))
          (if (< age *link-meta-cache-ttl*)
              cached
              ;; 过期，删除
              (progn
                (remhash url *link-meta-cache*)
                nil)))))))

(defun cache-meta (url meta)
  "缓存链接元数据"
  (bordeaux-threads:with-lock-held (*link-meta-cache-lock*)
    (setf (gethash url *link-meta-cache*) meta)))

;;;; Redis 缓存集成

(defun redis-cache-key (url)
  "生成 Redis 缓存键"
  (format nil "lispim:linkmeta:~a" (url-hash url)))

(defun url-hash (url)
  "生成 URL 哈希"
  (let ((hash (sxhash url)))
    (format nil "~x" hash)))

(defun redis-get-meta (url)
  "从 Redis 获取缓存的元数据"
  (handler-case
      (let* ((key (redis-cache-key url))
             (json (redis:red-get key)))
        (when json
          (let* ((obj (cl-json:decode-json-from-string json))
                 (meta (make-link-meta
                       :url (or (cdr (assoc "url" obj :test 'equal)) url)
                       :fetched-at (or (cdr (assoc "fetchedAt" obj :test 'equal)) (get-universal-time)))))
            (setf (link-meta-title meta) (cdr (assoc "title" obj :test 'equal))
                  (link-meta-description meta) (cdr (assoc "description" obj :test 'equal))
                  (link-meta-image meta) (cdr (assoc "image" obj :test 'equal))
                  (link-meta-site-name meta) (cdr (assoc "siteName" obj :test 'equal))
                  (link-meta-type meta) (keywordify (cdr (assoc "type" obj :test 'equal))))
            ;; 检查是否过期
            (let ((age (- (get-universal-time) (link-meta-fetched-at meta))))
              (cond
                ((< age *link-meta-cache-ttl*) meta)
                (t
                 ;; 过期，删除
                 (redis:red-del key)
                 nil))))))
    (error (c)
      (log-warn "Failed to get link meta from Redis: ~a" c)
      nil)))

(defun redis-set-meta (url meta)
  "将元数据缓存到 Redis"
  (handler-case
      (let* ((key (redis-cache-key url))
             (obj `(("url" . ,(link-meta-url meta))
                    ("title" . ,(or (link-meta-title meta) ""))
                    ("description" . ,(or (link-meta-description meta) ""))
                    ("image" . ,(or (link-meta-image meta) ""))
                    ("siteName" . ,(or (link-meta-site-name meta) ""))
                    ("type" . ,(string-downcase (link-meta-type meta)))
                    ("fetchedAt" . ,(link-meta-fetched-at meta))))
             (json (cl-json:encode-json-to-string obj)))
        (redis:red-setex key *link-meta-cache-ttl* json))
    (error (c)
      (log-warn "Failed to set link meta to Redis: ~a" c))))

;;;; 主 API：获取链接元数据

(defun get-link-meta (url)
  "获取链接元数据（带缓存）"
  (declare (type string url))

  ;; 1. 检查内存缓存
  (let ((cached (get-cached-meta url)))
    (when cached
      (log-debug "Link meta cache hit (memory): ~a" url)
      (return-from get-link-meta cached)))

  ;; 2. 检查 Redis 缓存
  (let ((redis-meta (redis-get-meta url)))
    (when redis-meta
      (log-debug "Link meta cache hit (Redis): ~a" url)
      ;; 同时写入内存缓存
      (cache-meta url redis-meta)
      (return-from get-link-meta redis-meta)))

  ;; 3. 检查特殊网站处理器
  (let* ((domain (url-domain url))
         (handler (when domain (get-special-handler domain))))
    (when handler
      (let ((special-meta (funcall handler url)))
        (when special-meta
          (log-info "Special handler used for ~a: ~a" url domain)
          (cache-meta url special-meta)
          (redis-set-meta url special-meta)
          (return-from get-link-meta special-meta)))))

  ;; 4. 抓取元数据
  (log-info "Fetching link meta: ~a" url)
  (let ((meta (fetch-link-preview url)))
    ;; 写入缓存
    (cache-meta url meta)
    (redis-set-meta url meta)
    meta))

;;;; 消息处理：自动解析消息中的 URL

(defun extract-urls-from-message (content)
  "从消息内容中提取所有 URL"
  (let ((url-pattern "https?://[^\\s\\)\\]\"]+")
        (urls nil))
    (multiple-value-bind (matches-starts matches-ends)
        (cl-ppcre:all-matches url-pattern content)
      (when matches-starts
        (loop for start across matches-starts
              for end across matches-ends
              do (push (subseq content start end) urls))))
    (nreverse urls)))

(defun parse-message-content (content)
  "解析消息内容，自动提取链接元数据"
  (let ((urls (extract-urls-from-message content)))
    (if urls
        (let ((metas (mapcar #'get-link-meta urls)))
          (list :type :rich
                :text content
                :links metas))
        (list :type :plain
              :text content))))

;;;; 插件 API 导出

(defun linkmeta-fetch (url)
  "插件 API: 获取链接元数据"
  (get-link-meta url))

(defun linkmeta-cache (url meta)
  "插件 API: 缓存链接元数据"
  (cache-meta url meta)
  (redis-set-meta url meta))

(defun linkmeta-parse-message (content)
  "插件 API: 解析消息中的链接"
  (parse-message-content content))

;;;; 注册插件 API

(defun register-linkmeta-apis ()
  "注册链接元数据插件 API"
  (register-plugin-api "linkmeta-fetch" #'linkmeta-fetch)
  (register-plugin-api "linkmeta-cache" #'linkmeta-cache)
  (register-plugin-api "linkmeta-parse-message" #'linkmeta-parse-message)
  (log-info "LinkMeta plugin APIs registered"))

;;;; 初始化

(defun init-linkmeta ()
  "初始化链接元数据解析"
  (log-info "Initializing LinkMeta...")

  ;; 初始化特殊网站处理器
  (init-special-handlers)

  ;; 注册插件 API
  (register-linkmeta-apis)

  (log-info "LinkMeta initialized"))

;;;; 导出 - Removed: exports are in package.lisp