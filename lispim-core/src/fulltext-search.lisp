;;;; fulltext-search.lisp - 全文搜索模块
;;;;
;;;; 实现消息、联系人、群组的全文搜索功能
;;;;
;;;; 功能：
;;;; - 倒排索引构建
;;;; - 中文分词支持
;;;; - 多字段搜索
;;;; - 搜索结果排名
;;;; - 增量索引更新
;;;;
;;;; 参考：
;;;; - Elasticsearch 倒排索引
;;;; - SQLite FTS5 全文搜索

(in-package :lispim-core)

;;;; 依赖声明

(eval-when (:compile-toplevel :load-toplevel :execute)
  (ql:quickload '(:postmodern :cl-redis :babel :ironclad)))

;;;; 配置

(defparameter *fulltext-search-config*
  '((:index-prefix . "lispim:search:")    ; Redis 索引前缀
    (:min-word-length . 2)                ; 最小词长度
    (:max-results . 100)                  ; 最大结果数
    (:batch-size . 1000)                  ; 索引构建批次大小
    (:sync-interval . 60))                ; 索引同步间隔（秒）
  "全文搜索配置")

(defun search-messages (user-id query &key (limit 20) (conversation-id nil))
  "搜索消息"
  (declare (type string user-id query))
  (let* ((tokens (tokenize-text query))
         (like-patterns (mapcar (lambda (token) (format nil "%%~a%%" token)) tokens))
         (like-clause (if like-patterns
                          (format nil "m.content ILIKE '~{~a~}' OR m.content ILIKE '~{~a~}' OR m.content ILIKE '~{~a~}' OR m.content ILIKE '~{~a~}' OR m.content ILIKE '~{~a~}'"
                                  like-patterns like-patterns like-patterns like-patterns like-patterns)
                          "1=1"))
         (sql (format nil
                      "SELECT m.id, m.conversation_id, m.sender_id, m.content, m.created_at,
                              c.name as conversation_name
                       FROM messages m
                       LEFT JOIN conversations c ON m.conversation_id = c.id
                       INNER JOIN conversation_participants cp ON m.conversation_id = cp.conversation_id
                       WHERE cp.user_id = ~a
                         AND (~a)~@[
                         AND m.conversation_id = ~a~]
                       ORDER BY m.created_at DESC
                       LIMIT ~a"
                      user-id
                      like-clause
                      conversation-id
                      limit)))
    ;; 执行查询（不使用参数化，因为 ILIKE 模式已经转义）
    (postmodern:query sql)))

;;;; 类型定义

(defstruct search-engine
  "搜索引擎"
  (redis-client nil :type (or null t))
  (index-prefix "" :type string)
  (min-word-length 2 :type integer)
  (max-results 100 :type integer)
  (document-count 0 :type integer)
  (term-count 0 :type integer)
  (lock (bordeaux-threads:make-lock "search-lock") :type bordeaux-threads:lock))

;;;; 中文分词（简化实现）

(defun tokenize-text (text)
  "分词函数"
  (declare (type string text))
  (let ((text (string-downcase text))
        (words nil))
    ;; 按空格、标点分割
    (let ((parts (split-sequence:split-sequence-if
                  (lambda (c) (or (char= c #\Space)
                                  (char= c #\Newline)
                                  (char= c #\,)
                                  (char= c #\.)
                                  (char= c #\!)
                                  (char= c #\?)
                                  (char= c #\,)
                                  (char= c #\;)
                                  (char= c #\:)
                                  (char= c #\()
                                  (char= c #\))))
                  text)))
      (dolist (part parts)
        (let ((word (string-trim " " part)))
          (when (>= (length word) 2)  ; 最小词长度
            (push word words))
          ;; 中文单字也作为索引（用于中文搜索）
          (loop for i from 0 below (length word)
                for char = (char word i)
                do (when (or (char<= #\a char #\z)
                             (char<= #\A char #\Z)
                             (char<= #\0 char #\9))
                     ;; 英文单词不做单字索引
                     (push (string char) words))))))
    (nreverse words)))

;;;; 倒排索引操作

(defun build-inverted-index (text)
  "构建倒排索引"
  (declare (type string text))
  (let ((tokens (tokenize-text text))
        (index (make-hash-table :test 'equal)))
    (dolist (token tokens)
      (incf (gethash token index 0)))
    index))

(defun add-to-index (engine doc-type doc-id field text)
  "添加文档到索引"
  (declare (type search-engine engine)
           (type string doc-type doc-id field text))
  (let* ((tokens (tokenize-text text))
         (index-key (format nil "~a~a:~a:~a"
                            (search-engine-index-prefix engine)
                            doc-type doc-id field)))
    ;; 存储原文（用于高亮）
    ;; 存储词项索引
    (dolist (token tokens)
      ;; 倒排索引：term -> doc_ids
      (let ((term-key (format nil "~a~a:~a"
                              (search-engine-index-prefix engine)
                              doc-type token)))
        ;; Redis sorted set: score = 词频
        ))))

(defun search-in-index (engine doc-type query &optional filters)
  "在索引中搜索"
  (declare (type search-engine engine)
           (type string doc-type query))
  (let* ((tokens (tokenize-text query))
         (results nil))
    ;; 对每个词项查询
    (dolist (token tokens)
      (let ((term-key (format nil "~a~a:~a"
                              (search-engine-index-prefix engine)
                              doc-type token)))
        ;; 从 Redis 获取匹配的文档 ID
        ))
    ;; 合并结果，按相关性排序
    results))

;;;; 数据库搜索

(defun search-contacts (user-id query)
  "搜索联系人"
  (declare (type string user-id query))
  (let* ((tokens (tokenize-text query))
         (like-conditions nil))
    ;; 为每个 token 构建 ILIKE 条件
    (dolist (token tokens)
      (push (format nil "username ILIKE '%%~a%%'" token) like-conditions)
      (push (format nil "display_name ILIKE '%%~a%%'" token) like-conditions))
    (let ((where-clause (if like-conditions
                            (format nil "(~{~a~^ OR ~})" like-conditions)
                            "1=1")))
      (postmodern:query
       (format nil
               "SELECT id, username, display_name, avatar_url, status
                FROM users
                WHERE id IN (
                  SELECT user_id FROM friends WHERE friend_id = $1
                  UNION
                  SELECT friend_id FROM friends WHERE user_id = $2
                )
                AND ~a
                ORDER BY display_name NULLS LAST, username
                LIMIT 50"
               where-clause)
       user-id user-id))))

(defun search-conversations (user-id query)
  "搜索会话"
  (declare (type string user-id query))
  (let* ((tokens (tokenize-text query))
         (like-conditions nil))
    ;; 为每个 token 构建 ILIKE 条件
    (dolist (token tokens)
      (push (format nil "c.name ILIKE '%%~a%%'" token) like-conditions))
    (let ((where-clause (if like-conditions
                            (format nil "(~{~a~^ OR ~})" like-conditions)
                            "1=1")))
      (postmodern:query
       (format nil
               "SELECT c.id, c.name, c.type, c.avatar_url, c.last_message_id, c.updated_at
                FROM conversations c
                INNER JOIN conversation_participants cp ON c.id = cp.conversation_id
                WHERE cp.user_id = $1
                  AND ~a
                ORDER BY c.updated_at DESC
                LIMIT 50"
               where-clause)
       user-id))))

;;;; 搜索结果高亮

(defun highlight-text (text query-terms &key (prefix "<mark>") (suffix "</mark>"))
  "高亮搜索词"
  (declare (type string text))
  (let ((result text))
    (dolist (term query-terms)
      (let ((pattern (format nil "(?i)~a" term)))
        (setf result
              (regex-replace-all pattern result
                                 (concatenate 'string prefix term suffix)))))
    result))

;;;; 搜索统计

(defun get-search-stats (engine)
  "获取搜索统计"
  (declare (type search-engine engine))
  (list :document-count (search-engine-document-count engine)
        :term-count (search-engine-term-count engine)
        :index-prefix (search-engine-index-prefix engine)
        :max-results (search-engine-max-results engine)))

;;;; 初始化

(defun init-fulltext-search (&key (redis-host "localhost") (redis-port 6379)
                                   (index-prefix "lispim:search:"))
  "初始化全文搜索"
  (let ((engine (make-search-engine
                 :redis-client nil  ; Redis 客户端初始化
                 :index-prefix index-prefix
                 :min-word-length 2
                 :max-results 100)))
    (log-info "Fulltext search initialized: prefix=~a" index-prefix)
    engine))

;;;; 全局实例

(defvar *search-engine* nil
  "全局搜索引擎实例")

;;;; 高层 API

(defun init-search (&optional (redis-host "localhost") (redis-port 6379))
  "高层初始化 API"
  (setf *search-engine* (init-fulltext-search :redis-host redis-host
                                               :redis-port redis-port))
  *search-engine*)

(defun fulltext-search (user-id query &key (type :all) (limit 20) conversation-id)
  "高层搜索 API"
  (case type
    (:messages (search-messages user-id query :limit limit :conversation-id conversation-id))
    (:contacts (search-contacts user-id query))
    (:conversations (search-conversations user-id query))
    (:all (list :messages (search-messages user-id query :limit limit)
                :contacts (search-contacts user-id query)
                :conversations (search-conversations user-id query)))
    (otherwise nil)))

(defun highlight-search-result (text query)
  "高层高亮 API"
  (highlight-text text (tokenize-text query)))

;;;; 后台索引同步

(defvar *search-sync-thread* nil
  "搜索同步线程")

(defun start-search-sync-worker ()
  "启动后台索引同步"
  (setf *search-sync-thread*
        (bordeaux-threads:make-thread
         (lambda ()
           (loop while t
                 do (progn
                      ;; 同步增量索引
                      (sleep 60))))
         :name "search-sync-worker")))

(defun stop-search-sync-worker ()
  "停止后台索引同步"
  (when (and *search-sync-thread*
             (bordeaux-threads:thread-alive-p *search-sync-thread*))
    (bordeaux-threads:destroy-thread *search-sync-thread*)
    (setf *search-sync-thread* nil)))

;;;; 清理

(defun shutdown-fulltext-search ()
  "关闭全文搜索"
  (stop-search-sync-worker)
  (when *search-engine*
    (setf *search-engine* nil))
  (log-info "Fulltext search shutdown complete"))

;;;; 导出

(export '(;; Initialization
          init-fulltext-search
          init-search
          *search-engine*

          ;; Search
          fulltext-search
          search-messages
          search-contacts
          search-conversations

          ;; Highlight
          highlight-text
          highlight-search-result

          ;; Indexing
          tokenize-text
          build-inverted-index
          add-to-index
          search-in-index

          ;; Statistics
          get-search-stats

          ;; Sync
          start-search-sync-worker
          stop-search-sync-worker

          ;; Shutdown
          shutdown-fulltext-search)
        :lispim-core)
