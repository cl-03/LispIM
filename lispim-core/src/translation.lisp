;;;; translation.lisp - 消息翻译模块
;;;;
;;;; 实现消息翻译功能，支持多语言
;;;; Features: AI 翻译、缓存、语言检测、自动翻译
;;;;
;;;; 参考：Google Translate API, DeepL API, OpenClaw AI

(in-package :lispim-core)

;;;; 依赖声明

(eval-when (:compile-toplevel :load-toplevel :execute)
  (ql:quickload '(:drakma :cl-json :alexandria)))

;;;; 支持的语言列表

(defparameter *supported-languages*
  '((:zh . "Chinese (简体中文)")
    (:zh-tw . "Chinese Traditional (繁體中文)")
    (:en . "English")
    (:ja . "Japanese (日本語)")
    (:ko . "Korean (한국어)")
    (:es . "Spanish (Español)")
    (:fr . "French (Français)")
    (:de . "German (Deutsch)")
    (:ru . "Russian (Русский)")
    (:pt . "Portuguese (Português)")
    (:it . "Italian (Italiano)")
    (:ar . "Arabic (العربية)")
    (:hi . "Hindi (हिन्दी)")
    (:th . "Thai (ไทย)")
    (:vi . "Vietnamese (Tiếng Việt)"))
  "支持的语言列表")

;;;; 翻译配置

(defparameter *translation-options*
  '(:provider :openclaw    ; 翻译提供商：:openclaw / :google / :deepl / :custom
    :cache-enabled t       ; 启用翻译缓存
    :cache-ttl 86400       ; 缓存过期时间 (秒)，默认 24 小时
    :auto-detect t         ; 自动检测源语言
    :fallback-to-source t  ; 翻译失败时返回源文本
    :max-text-length 5000  ; 最大文本长度
    )
  "翻译选项配置")

;;;; 全局变量

(defvar *translation-cache* (make-hash-table :test 'equal :size 10000)
  "翻译缓存：(text . from-lang . to-lang) -> (translation . timestamp)")

(defvar *translation-api-endpoint* nil
  "自定义翻译 API 端点")

(defvar *translation-api-key* nil
  "自定义翻译 API 密钥")

;;;; 翻译结果结构

(defstruct translation-result
  "翻译结果"
  (original-text "" :type string)
  (translated-text "" :type string)
  (source-language nil :type (or null keyword))
  (target-language nil :type (or null keyword))
  (provider nil :type (or null keyword))
  (confidence 1.0 :type float)
  (cached-p nil :type boolean)
  (error nil :type (or null string)))

;;;; 语言检测

(defun detect-language (text)
  "检测文本语言
   返回语言关键词 (:zh/:en/:ja/:ko 等)"
  (declare (type string text))

  ;; 简化的语言检测逻辑 - 使用实际 Unicode 字符而非转义
  (cond
    ;; 中文：包含中文字符 (CJK Unified Ideographs)
    ((cl-ppcre:scan "[一 - 龥]" text) :zh)
    ;; 日文：包含平假名或片假名
    ((cl-ppcre:scan "[ぁ - んァ - ヴ]" text) :ja)
    ;; 韩文：包含谚文
    ((cl-ppcre:scan "[가 - 힣]" text) :ko)
    ;; 泰文
    ((cl-ppcre:scan "[ก - ฮ]" text) :th)
    ;; 阿拉伯文
    ((cl-ppcre:scan "[ا - ي]" text) :ar)
    ;; 俄文 (西里尔字母)
    ((cl-ppcre:scan "[а - яА - Я]" text) :ru)
    ;; 默认视为英文
    (t :en)))

(defun get-language-name (lang-keyword)
  "获取语言名称"
  (declare (type keyword lang-keyword))
  (or (cdr (assoc lang-keyword *supported-languages*))
      (string-downcase lang-keyword)))

;;;; 翻译缓存

(defun get-cached-translation (text from-lang to-lang)
  "从缓存获取翻译"
  (declare (type string text)
           (type keyword from-lang to-lang))

  (let* ((cache-key (format nil "~a:~a:~a" text from-lang to-lang))
         (cached (gethash cache-key *translation-cache*)))
    (when cached
      (let ((translation (car cached))
            (timestamp (cdr cached)))
        ;; 检查缓存是否过期
        (if (< (- (get-universal-time) timestamp)
               (getf *translation-options* :cache-ttl 86400))
            translation
            (progn
              (remhash cache-key *translation-cache*)
              nil))))))

(defun cache-translation (text from-lang to-lang translation)
  "缓存翻译结果"
  (declare (type string text translation)
           (type keyword from-lang to-lang))

  (when (getf *translation-options* :cache-enabled)
    (let ((cache-key (format nil "~a:~a:~a" text from-lang to-lang)))
      (setf (gethash cache-key *translation-cache*)
            (cons translation (get-universal-time))))))

;;;; AI 翻译（使用 OpenClaw）

(defun translate-with-openclaw (text from-lang to-lang)
  "使用 OpenClaw AI 进行翻译"
  (declare (type string text)
           (type keyword from-lang to-lang))

  (let* ((prompt (format nil "Translate the following text from ~a to ~a. Output only the translation, no explanations:~%~%"
                         (get-language-name from-lang)
                         (get-language-name to-lang)))
         (full-prompt (concatenate 'string prompt text))
         (oc-endpoint *oc-endpoint*)
         (oc-api-key *oc-api-key*))

    (unless (and oc-endpoint (not (str:emptyp oc-endpoint)))
      (return-from translate-with-openclaw
        (values nil "OpenClaw endpoint not configured")))

    (handler-case
        (let* ((json-payload (cl-json:encode-json-to-string
                              `(("model" . "claude-translation")
                                ("messages" . ((("role" . "user")
                                                ("content" . ,full-prompt))))
                                ("max_tokens" . 1000)
                                ("temperature" . 0.3))))
               (response (drakma:http-request oc-endpoint
                                              :method :post
                                              :content json-payload
                                              :additional-headers
                                              `(("Authorization" . ,(format nil "Bearer ~a" oc-api-key))
                                                ("Content-Type" . "application/json"))
                                              :read-timeout 30000))
               (json (cl-json:decode-json-from-string response))
               (content (cdr (assoc :content (car (cdr (assoc :choices json)))))))

          (when (and content (stringp content))
            (values (string-trim '(#\Space #\Newline #\Tab) content) nil)))

      (error (c)
        (values nil (format nil "OpenClaw error: ~a" c))))))

;;;; Google Translate API

(defun translate-with-google (text from-lang to-lang)
  "使用 Google Translate API 进行翻译"
  (declare (type string text)
           (type keyword from-lang to-lang))

  ;; Note: This requires a valid Google Cloud API key
  (let* ((api-key "YOUR_GOOGLE_API_KEY")  ; TODO: Configure via environment
         (url (format nil "https://translation.googleapis.com/language/translate/v2?key=~a" api-key))
         (json-payload (cl-json:encode-json-to-string
                        `(("q" . ,(list text))
                          ("source" . ,(string-downcase (symbol-name from-lang)))
                          ("target" . ,(string-downcase (symbol-name to-lang)))
                          ("format" . "text")))))

    (handler-case
        (let* ((response (drakma:http-request url
                                              :method :post
                                              :content json-payload
                                              :additional-headers
                                              '(("Content-Type" . "application/json"))
                                              :read-timeout 15000))
               (json (cl-json:decode-json-from-string response))
               (data (cdr (assoc :data json)))
               (translations (cdr (assoc :translations data)))
               (translated-text (cdr (assoc :translatedText (car translations)))))

          (values translated-text nil))

      (error (c)
        (values nil (format nil "Google Translate error: ~a" c))))))

;;;; DeepL API

(defun translate-with-deepl (text from-lang to-lang)
  "使用 DeepL API 进行翻译"
  (declare (type string text)
           (type keyword from-lang to-lang))

  ;; Note: This requires a valid DeepL API key
  (let* ((api-key "YOUR_DEEPL_API_KEY")  ; TODO: Configure via environment
         (url "https://api.deepl.com/v2/translate")
         (json-payload (cl-json:encode-json-to-string
                        `(("text" . ,(list text))
                          ("source_lang" . ,(string-upcase (symbol-name from-lang)))
                          ("target_lang" . ,(string-upcase (symbol-name to-lang)))))))

    (handler-case
        (let* ((response (drakma:http-request url
                                              :method :post
                                              :content json-payload
                                              :additional-headers
                                              `(("Authorization" . ,(format nil "DeepL-Auth-Key ~a" api-key))
                                                ("Content-Type" . "application/json"))
                                              :read-timeout 15000))
               (json (cl-json:decode-json-from-string response))
               (translations (cdr (assoc :translations json)))
               (translated-text (cdr (assoc :text (car translations)))))

          (values translated-text nil))

      (error (c)
        (values nil (format nil "DeepL error: ~a" c))))))

;;;; 主翻译函数

(defun translate-text (text target-lang &key (source-lang nil))
  "翻译文本
   参数:
   - text: 要翻译的文本
   - target-lang: 目标语言关键词 (:zh/:en/:ja 等)
   - source-lang: 源语言关键词（可选，nil 表示自动检测）

   返回：translation-result 结构体"
  (declare (type string text)
           (type keyword target-lang)
           (type (or null keyword) source-lang))

  ;; 验证文本长度
  (when (> (length text) (getf *translation-options* :max-text-length 5000))
    (return-from translate-text
      (make-translation-result
       :original-text text
       :target-language target-lang
       :error (format nil "Text too long (max ~a chars)" (getf *translation-options* :max-text-length 5000)))))

  ;; 检测源语言
  (let ((from-lang (or source-lang
                       (when (getf *translation-options* :auto-detect)
                         (detect-language text))
                       :zh)))

    ;; 如果源语言和目标语言相同，直接返回
    (when (eq from-lang target-lang)
      (return-from translate-text
        (make-translation-result
         :original-text text
         :translated-text text
         :source-language from-lang
         :target-language target-lang
         :confidence 1.0
         :cached-p t)))

    ;; 检查缓存
    (let ((cached (get-cached-translation text from-lang target-lang)))
      (when cached
        (return-from translate-text
          (make-translation-result
           :original-text text
           :translated-text cached
           :source-language from-lang
           :target-language target-lang
           :cached-p t))))

    ;; 选择翻译提供商
    (let ((provider (getf *translation-options* :provider :openclaw))
          (translated nil)
          (error nil))

      (case provider
        (:openclaw
         (multiple-value-setq (translated error)
           (translate-with-openclaw text from-lang target-lang)))
        (:google
         (multiple-value-setq (translated error)
           (translate-with-google text from-lang target-lang)))
        (:deepl
         (multiple-value-setq (translated error)
           (translate-with-deepl text from-lang target-lang)))
        (t
         (setf error "Unknown translation provider")))

      ;; 处理结果
      (cond
        (translated
         ;; 缓存翻译结果
         (cache-translation text from-lang target-lang translated)
         (make-translation-result
          :original-text text
          :translated-text translated
          :source-language from-lang
          :target-language target-lang
          :provider provider
          :confidence 0.95))
        ((getf *translation-options* :fallback-to-source)
         ;; 翻译失败，返回源文本
         (make-translation-result
          :original-text text
          :translated-text text
          :source-language from-lang
          :target-language target-lang
          :error error))
        (t
         (make-translation-result
          :original-text text
          :target-language target-lang
          :error error))))))

;;;; 消息翻译

(defun translate-message (message-id target-lang)
  "翻译消息
   参数:
   - message-id: 消息 ID
   - target-lang: 目标语言关键词

   返回：(values success translated-text error)"
  (declare (type integer message-id)
           (type keyword target-lang))

  ;; 获取消息
  (let ((msg (get-message message-id)))
    (unless msg
      (return-from translate-message
        (values nil nil "Message not found")))

    ;; 只翻译文本消息
    (unless (eq (message-message-type msg) :text)
      (return-from translate-message
        (values nil nil "Only text messages can be translated")))

    (let ((content (message-content msg)))
      (unless content
        (return-from translate-message
          (values nil nil "Empty message content")))

      ;; 翻译
      (let ((result (translate-text content target-lang)))
        (if (translation-result-error result)
            (values nil nil (translation-result-error result))
            (values t (translation-result-translated-text result) nil))))))

;;;; 批量翻译

(defun translate-batch (texts target-lang &key (source-lang nil))
  "批量翻译文本列表"
  (declare (type list texts)
           (type keyword target-lang)
           (type (or null keyword) source-lang))

  (loop for text in texts
        collect (translate-text text target-lang :source-lang source-lang)))

;;;; 翻译历史

(defvar *translation-history* nil
  "翻译历史记录（内存）")

(defvar *translation-history-lock* (bordeaux-threads:make-lock "translation-history-lock")
  "翻译历史锁")

(defun record-translation (original translated from-lang to-lang)
  "记录翻译到历史"
  (declare (type string original translated)
           (type keyword from-lang to-lang))

  (bordeaux-threads:with-lock-held (*translation-history-lock*)
    (push (list :original original
                :translated translated
                :from-lang from-lang
                :to-lang to-lang
                :timestamp (get-universal-time))
          *translation-history*)
    ;; 限制历史记录大小
    (when (> (length *translation-history*) 1000)
      (setf *translation-history* (subseq *translation-history* 0 1000)))))

(defun get-translation-history (&key (limit 50))
  "获取翻译历史"
  (declare (type integer limit))

  (bordeaux-threads:with-lock-held (*translation-history-lock*)
    (subseq *translation-history* 0 (min limit (length *translation-history*)))))

;;;; 统计

(defun get-translation-stats ()
  "获取翻译统计"
  `((:cache-size . ,(hash-table-count *translation-cache*))
    (:history-size . ,(length *translation-history*))
    (:supported-languages . ,(length *supported-languages*))
    (:provider . ,(getf *translation-options* :provider))))

;;;; 初始化

(defun init-translation (&key (provider :openclaw) (cache-enabled t))
  "初始化翻译模块"
  (setf (getf *translation-options* :provider) provider)
  (setf (getf *translation-options* :cache-enabled) cache-enabled)

  (log-info "Translation module initialized with provider: ~a" provider)
  t)

;;;; 导出

(export '(;; Main functions
          translate-text
          translate-message
          translate-batch

          ;; Language detection
          detect-language
          get-language-name

          ;; History
          record-translation
          get-translation-history

          ;; Statistics
          get-translation-stats

          ;; Configuration
          *supported-languages*
          *translation-options*
          *translation-cache*

          ;; Initialization
          init-translation)
        :lispim-core)

;;;; End of translation.lisp
