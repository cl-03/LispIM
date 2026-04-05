;;;; favorites.lisp - 收藏夹模块
;;;;
;;;; 提供消息收藏、分类管理等功能
;;;; Features: 收藏消息，分类管理，标签标记

(in-package :lispim-core)

;;;; 依赖声明

(eval-when (:compile-toplevel :load-toplevel :execute)
  (ql:quickload '(:postmodern :cl-redis :cl-json :uuid)))

;;;; 数据结构

(defstruct (favorite (:conc-name favorite-))
  "收藏记录"
  (id 0 :type integer)
  (user-id "" :type string)
  (message-id 0 :type integer)
  (conversation-id 0 :type integer)
  (content "" :type string)
  (message-type :text :type keyword)
  (category-id nil :type (or null integer))
  (tags nil :type list)
  (note "" :type string)
  (is-starred nil :type boolean)
  (created-at 0 :type integer)
  (updated-at 0 :type integer))

(defstruct (fav-category (:conc-name fav-category-)
                         (:print-object print-fav-category))
  "收藏分类"
  (id 0 :type integer)
  (user-id "" :type string)
  (name "" :type string)
  (color "" :type string)
  (icon "" :type string)
  (sort-order 0 :type integer)
  (created-at 0 :type integer))

(defun print-fav-category (obj stream)
  (print-unreadable-object (obj stream :type t)
    (format stream "~a" (fav-category-name obj))))

;;;; 数据库表初始化

(defun ensure-favorites-tables-exist ()
  "创建收藏相关数据库表"
  (ensure-pg-connected)

  ;; 收藏表
  (postmodern:query
   "CREATE TABLE IF NOT EXISTS favorites (
      id BIGSERIAL PRIMARY KEY,
      user_id VARCHAR(255) NOT NULL,
      message_id BIGINT,
      conversation_id BIGINT,
      content TEXT,
      message_type VARCHAR(50) DEFAULT 'text',
      category_id BIGINT,
      tags TEXT[] DEFAULT '{}',
      note TEXT DEFAULT '',
      is_starred BOOLEAN DEFAULT FALSE,
      created_at TIMESTAMPTZ DEFAULT NOW(),
      updated_at TIMESTAMPTZ DEFAULT NOW()
    )")

  (postmodern:query
   "CREATE INDEX IF NOT EXISTS idx_favorites_user ON favorites(user_id)")
  (postmodern:query
   "CREATE INDEX IF NOT EXISTS idx_favorites_category ON favorites(category_id)")
  (postmodern:query
   "CREATE INDEX IF NOT EXISTS idx_favorites_message ON favorites(message_id)")

  ;; 收藏分类表
  (postmodern:query
   "CREATE TABLE IF NOT EXISTS favorite_categories (
      id BIGSERIAL PRIMARY KEY,
      user_id VARCHAR(255) NOT NULL,
      name VARCHAR(100) NOT NULL,
      color VARCHAR(20) DEFAULT '#6366f1',
      icon VARCHAR(50) DEFAULT 'folder',
      sort_order INTEGER DEFAULT 0,
      created_at TIMESTAMPTZ DEFAULT NOW(),
      UNIQUE(user_id, name)
    )")

  (postmodern:query
   "CREATE INDEX IF NOT EXISTS idx_favorite_categories_user ON favorite_categories(user_id)")

  ;; 插入默认分类
  (postmodern:query
   "INSERT INTO favorite_categories (user_id, name, color, icon, sort_order)
    VALUES ('__default__', '默认', '#6366f1', 'folder', 0)
    ON CONFLICT (user_id, name) DO NOTHING")

  (log-info "Favorites tables initialized"))

;;;; 收藏操作

(defun add-favorite (user-id message-id &key content message-type conversation-id category-id tags note)
  "添加收藏"
  (declare (type string user-id)
           (type integer message-id)
           (type (or null string) content)
           (type (or null keyword) message-type)
           (type (or null integer) conversation-id)
           (type (or null integer) category-id)
           (type (or null list) tags)
           (type (or null string) note))

  (let* ((now (get-universal-time))
         (result (postmodern:query
                  "INSERT INTO favorites
                   (user_id, message_id, content, message_type, conversation_id,
                    category_id, tags, note, created_at, updated_at)
                   VALUES ($1, $2, $3, $4, $5, $6, $7, $8, to_timestamp($9), to_timestamp($10))
                   RETURNING id"
                  user-id message-id (or content "") (string-downcase (or message-type :text))
                  conversation-id category-id
                  (when tags (coerce tags 'vector))
                  (or note "")
                  (storage-universal-to-unix now)
                  (storage-universal-to-unix now)
                  :alists)))
    (when result
      (let ((fid (cdr (assoc :|id| (car result)))))
        (log-info "Favorite added: ~a for user ~a" fid user-id)
        fid))))

(defun remove-favorite (favorite-id user-id)
  "移除收藏"
  (declare (type integer favorite-id)
           (type string user-id))

  (postmodern:query
   "DELETE FROM favorites WHERE id = $1 AND user_id = $2"
   favorite-id user-id)

  (log-info "Favorite ~a removed" favorite-id)
  t)

(defun get-favorites (user-id &key category-id limit offset search-query)
  "获取收藏列表"
  (declare (type string user-id)
           (type (or null integer) category-id)
           (type (or null integer) limit offset)
           (type (or null string) search-query))

  (let* ((sql (concat
               "SELECT f.*, fc.name as category_name, fc.color as category_color "
               "FROM favorites f "
               "LEFT JOIN favorite_categories fc ON f.category_id = fc.id "
               "WHERE f.user_id = $1"))
         (params (list user-id))
         (param-idx 2))

    (when category-id
      (setf sql (concat sql " AND f.category_id = $" (write-to-string param-idx)))
      (push category-id params)
      (incf param-idx))

    (when search-query
      (setf sql (concat sql " AND (f.content ILIKE $" (write-to-string param-idx)
                       " OR f.note ILIKE $" (write-to-string param-idx) ")"))
      (push (concat "%" search-query "%") params)
      (incf param-idx))

    (setf sql (concat sql " ORDER BY f.created_at DESC"))

    (when limit
      (setf sql (concat sql " LIMIT " (write-to-string limit))))

    (when offset
      (setf sql (concat sql " OFFSET " (write-to-string offset))))

    (let ((result (apply (function (lambda (s p) (postmodern:query s p :alists))) (list sql params))))
      (when result
        (loop for row in result
              collect
              (flet ((get-val (name)
                       (let ((cell (find name row :key #'car :test #'string=)))
                         (when cell (cdr cell)))))
                (list :id (parse-integer (get-val "ID"))
                      :user-id (get-val "USER_ID")
                      :message-id (parse-integer (get-val "MESSAGE_ID"))
                      :conversation-id (parse-integer (get-val "CONVERSATION_ID"))
                      :content (get-val "CONTENT")
                      :message-type (keywordify (get-val "MESSAGE_TYPE"))
                      :category-id (let ((v (get-val "CATEGORY_ID")))
                                     (when v (parse-integer v)))
                      :category-name (get-val "CATEGORY_NAME")
                      :category-color (get-val "CATEGORY_COLOR")
                      :tags (let ((v (get-val "TAGS")))
                              (when v (coerce v 'list)))
                      :note (get-val "NOTE")
                      :is-starred (string= (get-val "IS_STARRED") "t")
                      :created-at (storage-universal-to-unix (get-val "CREATED_AT"))
                      :updated-at (storage-universal-to-unix (get-val "UPDATED_AT")))))))))

(defun get-favorite (favorite-id user-id)
  "获取单个收藏"
  (declare (type integer favorite-id)
           (type string user-id))

  (let ((result (postmodern:query
                 "SELECT * FROM favorites WHERE id = $1 AND user_id = $2"
                 favorite-id user-id :alists)))
    (when result
      (let ((row (car result)))
        (flet ((get-val (name)
                 (let ((cell (find name row :key #'car :test #'string=)))
                   (when cell (cdr cell)))))
          (list :id (parse-integer (get-val "ID"))
                :user-id (get-val "USER_ID")
                :message-id (parse-integer (get-val "MESSAGE_ID"))
                :content (get-val "CONTENT")
                :message-type (keywordify (get-val "MESSAGE_TYPE"))
                :category-id (let ((v (get-val "CATEGORY_ID")))
                               (when v (parse-integer v)))
                :tags (let ((v (get-val "TAGS")))
                        (when v (coerce v 'list)))
                :note (get-val "NOTE")
                :is-starred (string= (get-val "IS_STARRED") "t")
                :created-at (storage-universal-to-unix (get-val "CREATED_AT"))
                :updated-at (storage-universal-to-unix (get-val "UPDATED_AT"))))))))

(defun update-favorite (favorite-id user-id &key content category-id tags note is-starred)
  "更新收藏"
  (declare (type integer favorite-id)
           (type string user-id)
           (type (or null string) content)
           (type (or null integer) category-id)
           (type (or null list) tags)
           (type (or null string) note)
           (type (or null boolean) is-starred))

  (let ((updates nil)
        (params nil)
        (param-idx 1))

    (when content
      (push (format nil "content = $~a" param-idx) updates)
      (push content params)
      (incf param-idx))

    (when category-id
      (push (format nil "category_id = $~a" param-idx) updates)
      (push category-id params)
      (incf param-idx))

    (when tags
      (push (format nil "tags = $~a" param-idx) updates)
      (push (coerce tags 'vector) params)
      (incf param-idx))

    (when note
      (push (format nil "note = $~a" param-idx) updates)
      (push note params)
      (incf param-idx))

    (when (booleanp is-starred)
      (push (format nil "is_starred = $~a" param-idx) updates)
      (push is-starred params)
      (incf param-idx))

    (when updates
      (push (format nil "updated_at = to_timestamp($~a)" param-idx) updates)
      (push (storage-universal-to-unix (get-universal-time)) params)
      (incf param-idx)

      (push favorite-id params)
      (let ((sql (format nil "UPDATE favorites SET ~a WHERE id = $~a AND user_id = $~a"
                         (format nil "~{~a~^, ~}" updates) param-idx (1+ param-idx))))
        (apply (function (lambda (s p) (postmodern:query s p :alists))) (list sql params))))

    (log-info "Favorite ~a updated" favorite-id)
    t))

;;;; 分类操作

(defun create-favorite-category (user-id name &key color icon sort-order)
  "创建收藏分类"
  (declare (type string user-id name)
           (type (or null string) color icon)
           (type (or null integer) sort-order))

  (let ((result (postmodern:query
                 "INSERT INTO favorite_categories
                  (user_id, name, color, icon, sort_order, created_at)
                  VALUES ($1, $2, $3, $4, $5, to_timestamp($6))
                  RETURNING id"
                 user-id name (or color "#6366f1") (or icon "folder")
                 (or sort-order 0)
                 (storage-universal-to-unix (get-universal-time))
                 :alists)))
    (when result
      (let ((cid (cdr (assoc :|id| (car result)))))
        (log-info "Favorite category created: ~a for user ~a" cid user-id)
        (make-fav-category
         :id cid
         :user-id user-id
         :name name
         :color (or color "#6366f1")
         :icon (or icon "folder")
         :sort-order (or sort-order 0)
         :created-at (get-universal-time)))))
  t)

(defun get-favorite-categories (user-id)
  "获取收藏分类列表"
  (declare (type string user-id))

  (let ((result (postmodern:query
                 "SELECT * FROM favorite_categories
                  WHERE user_id = $1 OR user_id = '__default__'
                  ORDER BY sort_order, created_at"
                 user-id :alists)))
    (when result
      (loop for row in result
            collect
            (flet ((get-val (name)
                     (let ((cell (find name row :key #'car :test #'string=)))
                       (when cell (cdr cell)))))
              (list :id (parse-integer (get-val "ID"))
                    :user-id (get-val "USER_ID")
                    :name (get-val "NAME")
                    :color (get-val "COLOR")
                    :icon (get-val "ICON")
                    :sort-order (parse-integer (get-val "SORT_ORDER"))
                    :created-at (storage-universal-to-unix (get-val "CREATED_AT"))))))))

(defun update-favorite-category (category-id user-id &key name color icon sort-order)
  "更新收藏分类"
  (declare (type integer category-id)
           (type string user-id)
           (type (or null string) name color icon)
           (type (or null integer) sort-order))

  (let ((updates nil)
        (params nil)
        (param-idx 1))

    (when name
      (push (format nil "name = $~a" param-idx) updates)
      (push name params)
      (incf param-idx))

    (when color
      (push (format nil "color = $~a" param-idx) updates)
      (push color params)
      (incf param-idx))

    (when icon
      (push (format nil "icon = $~a" param-idx) updates)
      (push icon params)
      (incf param-idx))

    (when sort-order
      (push (format nil "sort_order = $~a" param-idx) updates)
      (push sort-order params)
      (incf param-idx))

    (when updates
      (push category-id params)
      (push user-id params)
      (let ((sql (format nil "UPDATE favorite_categories SET ~a
                              WHERE id = $~a AND user_id = $~a"
                         (format nil "~{~a~^, ~}" updates) param-idx (1+ param-idx))))
        (apply (function (lambda (s p) (postmodern:query s p :alists))) (list sql params))))

    (log-info "Favorite category ~a updated" category-id)
    t))

(defun delete-favorite-category (category-id user-id)
  "删除收藏分类"
  (declare (type integer category-id)
           (type string user-id))

  ;; 将分类下的收藏移到默认分类
  (postmodern:query
   "UPDATE favorites SET category_id = NULL
    WHERE category_id = $1"
   category-id)

  (postmodern:query
   "DELETE FROM favorite_categories WHERE id = $1 AND user_id = $2"
   category-id user-id)

  (log-info "Favorite category ~a deleted" category-id)
  t)

;;;; 导出函数

(export '(ensure-favorites-tables-exist
          add-favorite
          remove-favorite
          get-favorites
          get-favorite
          update-favorite
          create-favorite-category
          get-favorite-categories
          update-favorite-category
          delete-favorite-category))

;;; End of favorites.lisp
