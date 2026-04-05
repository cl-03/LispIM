;;;; voice-messages.lisp - 语音消息功能
;;;;
;;;; 参考 Telegram/WhatsApp 语音消息功能
;;;; 功能：
;;;; - 语音录制上传
;;;; - 语音波形数据生成
;;;; - 语音消息播放
;;;; - 语音转文本（可选）

(in-package :lispim-core)

;;;; 依赖声明

(eval-when (:compile-toplevel :load-toplevel :execute)
  (ql:quickload '(:postmodern :cl-redis :babel :ironclad :usocket)))

;;;; 类型定义

(defstruct voice-message
  "语音消息结构"
  (id 0 :type integer)
  (message-id 0 :type integer)
  (duration 0 :type number)        ; 时长（秒）
  (waveform nil :type list)        ; 波形数据
  (url "" :type string)            ; 存储 URL
  (mime-type "audio/webm" :type string)
  (size 0 :type integer)           ; 文件大小（字节）
  (created-at (get-universal-time) :type integer))

;;;; 语音消息存储

(defun create-voice-message (message-id duration url &key (mime-type "audio/webm") (waveform nil))
  "创建语音消息记录"
  (declare (type integer message-id)
           (type number duration)
           (type string url))
  (ensure-pg-connected)
  (let ((voice-id (postmodern:query
                   (format nil
                           "INSERT INTO voice_messages
                            (message_id, duration, url, mime_type, waveform, created_at)
                            VALUES ($1, $2, $3, $4, $5, NOW())
                            RETURNING id"
                           message-id
                           duration
                           url
                           mime-type
                           (if waveform (encode-waveform waveform) ""))
                   :single)))
    (when voice-id
      (cache-voice-message voice-id message-id duration url mime-type waveform)
      voice-id))

(defun get-voice-message (message-id)
  "获取语音消息"
  (declare (type integer message-id))
  (or (get-voice-from-cache message-id)
      (progn
        (ensure-pg-connected)
        (let ((result (postmodern:query
                       (format nil
                               "SELECT id, duration, url, mime_type, waveform, size, created_at
                                FROM voice_messages
                                WHERE message_id = $1"
                               message-id)
                       :single)))
          (when result
            (destructuring-bind (id duration url mime-type waveform size created-at)
                result
              (let ((voice (make-voice-message
                            :id id
                            :message-id message-id
                            :duration duration
                            :url url
                            :mime-type mime-type
                            :waveform (decode-waveform waveform)
                            :size (or size 0)
                            :created-at (local-time:timestamp-to-universal created-at))))
                (cache-voice-message id message-id duration url mime-type waveform)
                voice))))))))

(defun delete-voice-message (message-id)
  "删除语音消息"
  (declare (type integer message-id))
  (remove-voice-from-cache message-id)
  (ensure-pg-connected)
  (postmodern:query (format nil "DELETE FROM voice_messages WHERE message_id = ~A" message-id))
  t)

;;;; 波形数据编码/解码

(defun encode-waveform (waveform)
  "编码波形数据为 JSON 字符串"
  (declare (type list waveform))
  (with-output-to-string (s)
    (cl-json:encode-json waveform s)))

(defun decode-waveform (json-string)
  "解码波形数据"
  (declare (type string json-string))
  (when (and json-string (not (string= json-string "")))
    (handler-case
        (cl-json:decode-json-from-string json-string)
      (condition (e)
        (declare (ignore e))
        nil))))

;;;; 缓存管理

(defun cache-voice-message (voice-id message-id duration url mime-type waveform)
  "缓存语音消息"
  (declare (type integer voice-id message-id)
           (type number duration)
           (type string url mime-type))
  (with-redis-lock ()
    (let ((key (format nil "lispim:voice:~A" message-id)))
      (redis-setex key 86400 ; 24 小时缓存
                   (with-output-to-string (s)
                     (cl-json:encode-json
                      `(:id ,voice-id
                            :message-id ,message-id
                            :duration ,duration
                            :url ,url
                            :mime-type ,mime-type
                            :waveform ,waveform)
                      s))))))

(defun get-voice-from-cache (message-id)
  "从缓存获取语音消息"
  (declare (type integer message-id))
  (with-redis-lock ()
    (let ((key (format nil "lispim:voice:~A" message-id))
          (data (redis-get (format nil "lispim:voice:~A" message-id))))
      (when data
        (handler-case
            (let ((json (cl-json:decode-json-from-string data)))
              (make-voice-message
               :id (getf json :id)
               :message-id (getf json :message-id)
               :duration (getf json :duration)
               :url (getf json :url)
               :mime-type (getf json :mime-type)
               :waveform (getf json :waveform)))
          (condition (e)
            (declare (ignore e))
            nil))))))

(defun remove-voice-from-cache (message-id)
  "从缓存移除语音消息"
  (declare (type integer message-id))
  (with-redis-lock ()
    (redis-del (format nil "lispim:voice:~A" message-id))))

;;;; 波形数据生成（用于录音处理）

(defun generate-waveform (audio-data &key (points 50))
  "从音频数据生成波形"
  (declare (type (simple-array (unsigned-byte 16)) audio-data)
           (type integer points))
  (let* ((chunk-size (floor (length audio-data) points))
         (waveform nil))
    (dotimes (i points (nreverse waveform))
      (let ((start (* i chunk-size))
            (end (+ start chunk-size))
            (max-val 0))
        (loop for j from start below (min end (length audio-data))
              do (setf max-val (max max-val (aref audio-data j))))
        (push (/ max-val 65535.0) waveform)))))

;;;; 语音转文本接口（预留）

(defun speech-to-text (voice-url &key language)
  "语音转文本（预留接口）"
  (declare (type string voice-url)
           (ignore language))
  ;; TODO: 集成语音识别服务（如 Azure Speech, Google Speech-to-Text）
  (log-message :info "Speech-to-text requested for: ~A" voice-url)
  nil)

;;;; 数据库表初始化

(defun init-voice-messages-db ()
  "初始化语音消息数据库表"
  (ensure-pg-connected)
  (handler-case
      (progn
        ;; 创建语音消息表
        (postmodern:query
         "CREATE TABLE IF NOT EXISTS voice_messages (
            id BIGSERIAL PRIMARY KEY,
            message_id BIGINT NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
            duration REAL NOT NULL,
            url VARCHAR(512) NOT NULL,
            mime_type VARCHAR(64) DEFAULT 'audio/webm',
            waveform TEXT,
            size BIGINT,
            created_at TIMESTAMPTZ DEFAULT NOW(),
            UNIQUE(message_id)
          )")
        ;; 创建索引
        (postmodern:query
         "CREATE INDEX IF NOT EXISTS idx_voice_messages_message_id
          ON voice_messages(message_id)")
        (log-message :info "Voice messages table initialized"))
    (condition (e)
      (log-message :error "Failed to initialize voice messages table: ~A" e))))

;;;; API 辅助函数

(defun voice-message-to-plist (voice)
  "转换语音消息为 plist"
  (declare (type voice-message voice))
  `(:id ,(voice-message-id voice)
        :messageId ,(voice-message-message-id voice)
        :duration ,(voice-message-duration voice)
        :url ,(voice-message-url voice)
        :mimeType ,(voice-message-mime-type voice)
        :waveform ,(voice-message-waveform voice)
        :size ,(voice-message-size voice)
        :createdAt ,(voice-message-created-at voice)))

;; 导出公共函数
(export '(create-voice-message
          get-voice-message
          delete-voice-message
          generate-waveform
          speech-to-text
          init-voice-messages-db
          voice-message-to-plist))
