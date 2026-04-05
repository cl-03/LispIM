;;;; moment.lisp - Moments (朋友圈) Module
;;;;
;;;; Provides social feed functionality similar to WeChat Moments
;;;; Features: posts, comments, likes, photo albums, privacy settings

(in-package :lispim-core)

;;;; Dependencies

(eval-when (:compile-toplevel :load-toplevel :execute)
  (ql:quickload '(:postmodern :cl-redis :cl-json :bordeaux-threads :uuid)))

;;;; Configuration

(defparameter *moment-max-photos* 9
  "Maximum number of photos per moment post")

(defparameter *moment-feed-page-size* 20
  "Number of posts to fetch per page")

(defparameter *moment-ttl* 86400  ; 24 hours
  "TTL for moment feed cache in Redis")

;;;; Data Structures

(defstruct moment-post
  "Moment post structure"
  (id 0 :type integer)
  (user-id "" :type string)
  (username "" :type string)
  (display-name "" :type string)
  (avatar "" :type string)
  (content "" :type string)
  (photos nil :type list)
  (type :text :type keyword)  ; :text, :image, :video, :link
  (location "")
  (created-at 0 :type integer)
  (likes-count 0 :type integer)
  (comments-count 0 :type integer)
  (liked-by nil :type list)
  (comments nil :type list)
  (visibility :public :type keyword))  ; :public, :friends, :private

(defstruct moment-comment
  "Moment comment structure"
  (id 0 :type integer)
  (post-id 0 :type integer)
  (user-id "" :type string)
  (username "" :type string)
  (display-name "" :type string)
  (avatar "" :type string)
  (content "" :type string)
  (reply-to-user-id "")
  (reply-to-username "")
  (created-at 0 :type integer))

(defstruct moment-like
  "Moment like structure"
  (post-id 0 :type integer)
  (user-id "" :type string)
  (created-at 0 :type integer))

;;;; Redis Key Patterns

(defun moment-post-key (post-id)
  "Get Redis key for moment post"
  (format nil "moment:post:~a" post-id))

(defun moment-user-posts-key (user-id)
  "Get Redis key for user's moment posts (sorted set)"
  (format nil "moment:user:~a:posts" user-id))

(defun moment-feed-key (user-id)
  "Get Redis key for user's moment feed"
  (format nil "moment:feed:~a" user-id))

(defun moment-comments-key (post-id)
  "Get Redis key for post comments"
  (format nil "moment:post:~a:comments" post-id))

(defun moment-likes-key (post-id)
  "Get Redis key for post likes"
  (format nil "moment:post:~a:likes" post-id))

;;;; Helper Functions

(defun generate-moment-id ()
  "Generate unique moment post ID"
  (floor (* (get-universal-time) 1000)))

(defun moment-visibility-p (post-visibility viewer-id author-id)
  "Check if viewer can see the post based on visibility setting"
  (cond
    ((eq post-visibility :public) t)
    ((eq post-visibility :private)
     (string= viewer-id author-id))
    ((eq post-visibility :friends)
     ;; Check if viewer is friend of author
     (check-friendship viewer-id author-id))
    (t nil)))

(defun check-friendship (user-id-1 user-id-2)
  "Check if two users are friends"
  (handler-case
      (let ((result (postmodern:query
                     "SELECT 1 FROM friends
                      WHERE ((user_id = $1 AND friend_id = $2) OR
                             (user_id = $2 AND friend_id = $1))
                        AND status = 'accepted'
                      LIMIT 1"
                     user-id-1 user-id-2)))
        (and result (> (length result) 0)))
    (error (c)
      (log-error "Check friendship error: ~a" c)
      nil)))

;;;; Database Operations

(defun ensure-moments-table-exists ()
  "Create moments table if not exists"
  (ensure-pg-connected)
  (postmodern:query
   "CREATE TABLE IF NOT EXISTS moments (
      id BIGINT PRIMARY KEY,
      user_id VARCHAR(255) NOT NULL,
      username VARCHAR(255) NOT NULL,
      display_name VARCHAR(255),
      content TEXT,
      photos JSONB DEFAULT '[]',
      type VARCHAR(50) DEFAULT 'text',
      location VARCHAR(255),
      visibility VARCHAR(50) DEFAULT 'public',
      likes_count INTEGER DEFAULT 0,
      comments_count INTEGER DEFAULT 0,
      created_at TIMESTAMPTZ DEFAULT NOW(),
      updated_at TIMESTAMPTZ DEFAULT NOW()
    )")
  (postmodern:query
   "CREATE INDEX IF NOT EXISTS idx_moments_user_id ON moments(user_id)")
  (postmodern:query
   "CREATE INDEX IF NOT EXISTS idx_moments_created_at ON moments(created_at DESC)")
  (postmodern:query
   "CREATE INDEX IF NOT EXISTS idx_moments_user_created ON moments(user_id, created_at DESC)")

  ;; Comments table
  (postmodern:query
   "CREATE TABLE IF NOT EXISTS moment_comments (
      id BIGINT PRIMARY KEY,
      post_id BIGINT REFERENCES moments(id) ON DELETE CASCADE,
      user_id VARCHAR(255) NOT NULL,
      username VARCHAR(255) NOT NULL,
      display_name VARCHAR(255),
      avatar_url VARCHAR(500),
      content TEXT NOT NULL,
      reply_to_user_id VARCHAR(255),
      reply_to_username VARCHAR(255),
      created_at TIMESTAMPTZ DEFAULT NOW()
    )")
  (postmodern:query
   "CREATE INDEX IF NOT EXISTS idx_moment_comments_post_id ON moment_comments(post_id)")
  (postmodern:query
   "CREATE INDEX IF NOT EXISTS idx_moment_comments_created ON moment_comments(created_at)")

  ;; Likes table
  (postmodern:query
   "CREATE TABLE IF NOT EXISTS moment_likes (
      post_id BIGINT REFERENCES moments(id) ON DELETE CASCADE,
      user_id VARCHAR(255) NOT NULL,
      created_at TIMESTAMPTZ DEFAULT NOW(),
      PRIMARY KEY (post_id, user_id)
    )")
  (postmodern:query
   "CREATE INDEX IF NOT EXISTS idx_moment_likes_post_id ON moment_likes(post_id)")

  (log-info "Moments tables created"))

;;;; Moment CRUD Operations

(defun create-moment-post (user-id username display-name avatar content photos type location visibility)
  "Create a new moment post"
  (declare (type string user-id username content type location visibility)
           (type list photos))
  (ensure-moments-table-exists)

  (let ((post-id (generate-moment-id))
        (now (get-universal-time)))

    ;; Save to PostgreSQL
    (postmodern:query
     "INSERT INTO moments (id, user_id, username, display_name, content, photos, type, location, visibility, created_at, updated_at)
      VALUES ($1, $2, $3, $4, $5, $6::jsonb, $7, $8, $9, to_timestamp($10), to_timestamp($10))"
     post-id user-id username display-name content
     (cl-json:encode-json-to-string photos)
     type location visibility now)

    ;; Cache in Redis
    (let* ((key (moment-post-key post-id))
           (post-data (list :id post-id
                            :user-id user-id
                            :username username
                            :display-name display-name
                            :avatar avatar
                            :content content
                            :photos photos
                            :type type
                            :location location
                            :visibility visibility
                            :created-at (floor now)
                            :likes-count 0
                            :comments-count 0
                            :liked-by '()
                            :comments '()))
           (post-json (cl-json:encode-json-to-string post-data)))

      ;; Store post
      (let ((redis (get-redis)))
        (redis:red-set key post-json)
        (redis:red-expire key *moment-ttl*))

      ;; Add to user's posts sorted set
      (let ((user-key (moment-user-posts-key user-id)))
        (let ((redis (get-redis)))
          (redis:red-zadd user-key (floor now) post-id))))

    (log-info "Created moment post ~a for user ~a" post-id user-id)
    post-id))

(defun get-moment-post (post-id)
  "Get moment post by ID"
  (declare (type integer post-id))

  ;; Try Redis cache first
  (let* ((key (moment-post-key post-id))
         (cached (let ((redis (get-redis)))
                   (redis:red-get key))))

    (if cached
        (let ((post (cl-json:decode-json-from-string cached)))
          ;; Enrich with comments and likes
          (enrich-moment-post post))

        ;; Fallback to PostgreSQL
        (let ((result (postmodern:query
                       "SELECT * FROM moments WHERE id = $1" post-id :alists)))
          (when result
            (let ((row (car result)))
              (flet ((get-val (name)
                       (let ((cell (find name row :key #'car :test #'string=)))
                         (when cell (cdr cell)))))
                (let* ((user-id (get-val "USER-ID"))
                       (photos-str (get-val "PHOTOS"))
                       (photos (if photos-str
                                   (cl-json:decode-json-from-string photos-str)
                                   '())))
                  (list :id post-id
                        :user-id user-id
                        :username (get-val "USERNAME")
                        :display-name (get-val "DISPLAY-NAME")
                        :content (get-val "CONTENT")
                        :photos photos
                        :type (string-downcase (or (get-val "TYPE") "text"))
                        :location (get-val "LOCATION")
                        :visibility (string-downcase (or (get-val "VISIBILITY") "public"))
                        :created-at (storage-universal-to-unix (get-val "CREATED-AT"))
                        :likes-count (or (get-val "LIKES-COUNT") 0)
                        :comments-count (or (get-val "COMMENTS-COUNT") 0))))))))))

(defun enrich-moment-post (post)
  "Enrich moment post with comments and likes"
  (let* ((post-id (getf post :id))
         (comments (get-moment-comments post-id))
         (likes (get-moment-likes post-id)))

    (setf (getf post :comments) comments)
    (setf (getf post :comments-count) (length comments))
    (setf (getf post :likes-count) (length likes))
    (setf (getf post :liked-by) (mapcar (lambda (like) (getf like :user-id)) likes)))

  post)

(defun get-moment-comments (post-id)
  "Get comments for a moment post"
  (declare (type integer post-id))

  (let ((result (postmodern:query
                 "SELECT * FROM moment_comments WHERE post_id = $1 ORDER BY created_at ASC"
                 post-id :alists)))

    (when result
      (loop for row in result
            collect
            (flet ((get-val (name)
                     (let ((cell (find name row :key #'car :test #'string=)))
                       (when cell (cdr cell)))))
              (list :id (get-val "ID")
                    :post-id (get-val "POST-ID")
                    :user-id (get-val "USER-ID")
                    :username (get-val "USERNAME")
                    :display-name (get-val "DISPLAY-NAME")
                    :avatar (get-val "AVATAR-URL")
                    :content (get-val "CONTENT")
                    :reply-to-user-id (get-val "REPLY-TO-USER-ID")
                    :reply-to-username (get-val "REPLY-TO-USERNAME")
                    :created-at (storage-universal-to-unix (get-val "CREATED-AT"))))))))

(defun get-moment-likes (post-id)
  "Get likes for a moment post"
  (declare (type integer post-id))

  (let ((result (postmodern:query
                 "SELECT user_id, created_at FROM moment_likes WHERE post_id = $1 ORDER BY created_at ASC"
                 post-id :alists)))

    (when result
      (loop for row in result
            collect
            (list :user-id (cdr (assoc :|user_id| row))
                  :created-at (storage-universal-to-unix (cdr (assoc :|created_at| row))))))))

(defun delete-moment-post (post-id user-id)
  "Delete a moment post"
  (declare (type integer post-id)
           (type string user-id))

  ;; Verify ownership
  (let ((post (get-moment-post post-id)))
    (unless (and post (string= (getf post :user-id) user-id))
      (return-from delete-moment-post (values nil "Unauthorized"))))

  ;; Delete from PostgreSQL
  (postmodern:query "DELETE FROM moment_likes WHERE post_id = $1" post-id)
  (postmodern:query "DELETE FROM moment_comments WHERE post_id = $1" post-id)
  (postmodern:query "DELETE FROM moments WHERE id = $1" post-id)

  ;; Delete from Redis
  (let ((redis (get-redis)))
    (redis:red-del (moment-post-key post-id))
    (redis:red-del (moment-comments-key post-id))
    (redis:red-del (moment-likes-key post-id)))

  (log-info "Deleted moment post ~a" post-id)
  (values t nil))

;;;; Feed Operations

(defun get-moment-feed (user-id &key (page 1) (page-size *moment-feed-page-size*))
  "Get moment feed for user (posts from user and friends)"
  (declare (type string user-id)
           (type integer page page-size))

  (let* ((offset (* (1- page) page-size))
         (limit page-size))

    ;; Get friend IDs
    (let ((friend-ids (get-friend-ids user-id)))
      ;; Include user's own posts
      (push user-id friend-ids)
      (setf friend-ids (remove-duplicates friend-ids :test #'string=))

      ;; Query posts from user and friends
      (let ((result (postmodern:query
                     (format nil "
                       SELECT * FROM moments
                       WHERE user_id = ANY($1::varchar[])
                       AND visibility IN ('public', 'friends')
                       ORDER BY created_at DESC
                       LIMIT $2 OFFSET $3")
                     (coerce friend-ids 'vector) limit offset :alists)))

        (when result
          (loop for row in result
                collect
                (flet ((get-val (name)
                         (let ((cell (find name row :key #'car :test #'string=)))
                           (when cell (cdr cell)))))
                  (let* ((post-id (get-val "ID"))
                         (photos-str (get-val "PHOTOS"))
                         (photos (if photos-str
                                     (cl-json:decode-json-from-string photos-str)
                                     '())))
                    (enrich-moment-post
                     (list :id post-id
                           :user-id (get-val "USER-ID")
                           :username (get-val "USERNAME")
                           :display-name (get-val "DISPLAY-NAME")
                           :content (get-val "CONTENT")
                           :photos photos
                           :type (string-downcase (or (get-val "TYPE") "text"))
                           :location (get-val "LOCATION")
                           :created-at (storage-universal-to-unix (get-val "CREATED-AT"))
                           :likes-count (or (get-val "LIKES-COUNT") 0)
                           :comments-count (or (get-val "COMMENTS-COUNT") 0)
                           :liked-by '()
                           :comments '()))))))))))

(defun get-friend-ids (user-id)
  "Get list of friend user IDs"
  (declare (type string user-id))

  (let ((result (postmodern:query
                 "SELECT CASE WHEN user_id = $1 THEN friend_id ELSE user_id END as friend_id
                  FROM friends
                  WHERE (user_id = $1 OR friend_id = $1)
                  AND status = 'accepted'"
                 user-id)))

    (when result
      (mapcar (lambda (row) (svref row 0)) result))))

;;;; Like Operations

(defun like-moment-post (post-id user-id)
  "Like a moment post"
  (declare (type integer post-id)
           (type string user-id))

  (let ((now (get-universal-time)))

    ;; Check if already liked
    (let ((exists (postmodern:query
                   "SELECT 1 FROM moment_likes WHERE post_id = $1 AND user_id = $2"
                   post-id user-id)))

      (if exists
          (values nil "Already liked")

          ;; Insert like
          (progn
            (postmodern:query
             "INSERT INTO moment_likes (post_id, user_id, created_at) VALUES ($1, $2, to_timestamp($3))
              ON CONFLICT (post_id, user_id) DO NOTHING"
             post-id user-id now)

            ;; Update likes count
            (postmodern:query
             "UPDATE moments SET likes_count = likes_count + 1 WHERE id = $1" post-id)

            ;; Update Redis cache
            (let ((key (moment-likes-key post-id)))
              (let ((redis (get-redis)))
                (redis:red-hset key user-id (write-to-string (floor now)))))

            (log-info "User ~a liked post ~a" user-id post-id)
            (values t nil))))))

(defun unlike-moment-post (post-id user-id)
  "Unlike a moment post"
  (declare (type integer post-id)
           (type string user-id))

  ;; Delete like
  (postmodern:query
   "DELETE FROM moment_likes WHERE post_id = $1 AND user_id = $2"
   post-id user-id)

  ;; Update likes count
  (postmodern:query
   "UPDATE moments SET likes_count = GREATEST(likes_count - 1, 0) WHERE id = $1" post-id)

  ;; Update Redis cache
  (let ((redis (get-redis)))
    (redis:red-hdel (moment-likes-key post-id) user-id))

  (log-info "User ~a unliked post ~a" user-id post-id)
  (values t nil))

;;;; Comment Operations

(defun add-moment-comment (post-id user-id username display-name avatar content reply-to-user-id reply-to-username)
  "Add comment to a moment post"
  (declare (type integer post-id)
           (type string user-id username display-name avatar content))

  (let ((comment-id (generate-moment-id))
        (now (get-universal-time)))

    ;; Insert comment
    (postmodern:query
     "INSERT INTO moment_comments
      (id, post_id, user_id, username, display_name, avatar_url, content, reply_to_user_id, reply_to_username, created_at)
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, to_timestamp($10))"
     comment-id post-id user-id username display-name avatar content
     (or reply-to-user-id "") (or reply-to-username "") now)

    ;; Update comments count
    (postmodern:query
     "UPDATE moments SET comments_count = comments_count + 1 WHERE id = $1" post-id)

    (log-info "User ~a commented on post ~a" user-id post-id)
    comment-id))

(defun delete-moment-comment (comment-id post-id user-id)
  "Delete a moment comment"
  (declare (type integer comment-id post-id)
           (type string user-id))

  ;; Verify ownership or post owner
  (let ((comment (car (postmodern:query
                       "SELECT * FROM moment_comments WHERE id = $1" comment-id :alists))))

    (when (null comment)
      (return-from delete-moment-comment (values nil "Comment not found")))

    (let ((comment-user-id (cdr (assoc :|user_id| comment))))
      (unless (or (string= comment-user-id user-id)
                  (is-post-owner post-id user-id))
        (return-from delete-moment-comment (values nil "Unauthorized")))))

  ;; Delete comment
  (postmodern:query "DELETE FROM moment_comments WHERE id = $1" comment-id)

  ;; Update comments count
  (postmodern:query
   "UPDATE moments SET comments_count = GREATEST(comments_count - 1, 0) WHERE id = $1" post-id)

  (values t nil))

(defun is-post-owner (post-id user-id)
  "Check if user is the post owner"
  (let ((post (get-moment-post post-id)))
    (and post (string= (getf post :user-id) user-id))))

(defun get-user-moments (user-id &key (page 1) (page-size 20))
  "Get user's own moment posts"
  (declare (type string user-id)
           (type integer page page-size))

  (let* ((offset (* (1- page) page-size))
         (limit page-size)
         (result (postmodern:query
                  (format nil "
                    SELECT * FROM moments
                    WHERE user_id = $1
                    ORDER BY created_at DESC
                    LIMIT $2 OFFSET $3")
                  user-id limit offset :alists)))

    (when result
      (loop for row in result
            collect
            (flet ((get-val (name)
                     (let ((cell (find name row :key #'car :test #'string=)))
                       (when cell (cdr cell)))))
              (let* ((post-id (get-val "ID"))
                     (photos-str (get-val "PHOTOS"))
                     (photos (if photos-str
                                 (cl-json:decode-json-from-string photos-str)
                                 '())))
                (enrich-moment-post
                 (list :id post-id
                       :user-id (get-val "USER-ID")
                       :username (get-val "USERNAME")
                       :display-name (get-val "DISPLAY-NAME")
                       :content (get-val "CONTENT")
                       :photos photos
                       :type (string-downcase (or (get-val "TYPE") "text"))
                       :location (get-val "LOCATION")
                       :created-at (storage-universal-to-unix (get-val "CREATED-AT"))
                       :likes-count (or (get-val "LIKES-COUNT") 0)
                       :comments-count (or (get-val "COMMENTS-COUNT") 0)
                       :liked-by '()
                       :comments '()))))))))

;;;; Export Functions

(export '(ensure-moments-table-exists
          create-moment-post
          get-moment-post
          delete-moment-post
          get-moment-feed
          get-user-moments
          get-moment-comments
          get-moment-likes
          like-moment-post
          unlike-moment-post
          add-moment-comment
          delete-moment-comment
          *moment-max-photos*
          *moment-feed-page-size*
          *moment-ttl*))
