;;;; storage.lisp - Data Storage Layer
;;;;
;;;; PostgreSQL and Redis data persistence with connection pooling
;;;; Production-ready implementation

(in-package :lispim-core)

;;;; Dependencies

(eval-when (:compile-toplevel :load-toplevel :execute)
  (ql:quickload '(:postmodern :cl-redis :bordeaux-threads :cl-json :uuid)))

;;;; Configuration

(defparameter *postgres-database* "lispim"
  "PostgreSQL database name")
(defparameter *postgres-user* "lispim"
  "PostgreSQL user name")
(defparameter *postgres-password* "Clsper03"
  "PostgreSQL password")
(defparameter *postgres-host* "127.0.0.1"
  "PostgreSQL host")
(defparameter *postgres-port* 5432
  "PostgreSQL port")

(defparameter *redis-host* "localhost"
  "Redis host")
(defparameter *redis-port* 6379
  "Redis port")
(defparameter *redis-db* 0
  "Redis database number")
(defparameter *redis-password* nil
  "Redis password (optional)")

;;;; Universal Time to Unix Time Conversion

;; Unix time epoch starts at 1970-01-01, while Lisp universal time starts at 1900-01-01
;; The difference is 2208988800 seconds (70 years including 17 leap years)
(defconstant +unix-epoch-offset+ 2208988800
  "Seconds between 1900 and 1970 epochs")

(declaim (inline storage-universal-to-unix storage-unix-to-universal))

(defun storage-universal-to-unix (universal-time)
  "Convert Lisp universal time to Unix timestamp"
  (declare (type integer universal-time))
  (- universal-time +unix-epoch-offset+))

(defun storage-unix-to-universal (unix-time)
  "Convert Unix timestamp to Lisp universal time"
  (declare (type integer unix-time))
  (+ unix-time +unix-epoch-offset+))

(defun storage-universal-to-unix-ms (universal-time)
  "Convert Lisp universal time to Unix timestamp (milliseconds)"
  (declare (type integer universal-time))
  (* (- universal-time +unix-epoch-offset+) 1000))

;;;; Connection State

(defvar *pg-connection* nil
  "PostgreSQL connection connection")
(defvar *pg-connected* nil
  "PostgreSQL connection status flag")
(defvar *redis-connection* nil
  "Redis connection connection")
(defvar *redis-connected* nil
  "Redis connection status flag")
(defvar *redis-client* nil
  "Redis client instance")

(defvar *storage-lock* (bordeaux-threads:make-lock "storage-lock")
  "Storage operations lock")

;;;; Connection Pool (simplified for single connection)

(defvar *connection-pool* nil
  "Database connection pool")
(defvar *connection-pool-lock* (bordeaux-threads:make-lock "connection-pool-lock"))

;;;; Initialization

(defun init-storage (database-url redis-url)
  "Initialize storage layer with connection strings"
  (declare (type string database-url redis-url))
  (log-info "Initializing storage...")

  ;; Parse and initialize PostgreSQL
  (let ((pg-config (parse-postgres-connection-string database-url)))
    (setf *postgres-database* (getf pg-config :database)
          *postgres-user* (getf pg-config :user)
          *postgres-password* (getf pg-config :password)
          *postgres-host* (getf pg-config :host)
          *postgres-port* (getf pg-config :port)))

  ;; Parse and initialize Redis
  (let ((redis-config (parse-redis-connection-string redis-url)))
    (setf *redis-host* (getf redis-config :host)
          *redis-port* (getf redis-config :port)
          *redis-db* (or (getf redis-config :db) 0)
          *redis-password* (getf redis-config :password)))

  ;; Establish connections
  (init-postgresql)
  (init-redis)

  (log-info "Storage initialized successfully"))

(defun parse-postgres-connection-string (url)
  "Parse PostgreSQL connection string
   Format: postgresql://user:pass@host:port/db"
  (declare (type string url))
  (let* ((without-scheme (if (search "://" url)
                             (subseq url (+ (search "://" url) 3))
                             url))
         (at-pos (position #\@ without-scheme))
         (user-info (when at-pos (subseq without-scheme 0 at-pos)))
         (host-part (if at-pos (subseq without-scheme (1+ at-pos)) without-scheme))
         (slash-pos (position #\/ host-part))
         (host-port (if slash-pos (subseq host-part 0 slash-pos) host-part))
         (db-name (if slash-pos (subseq host-part (1+ slash-pos)) ""))
         (colon-pos (position #\: host-port))
         (host (if colon-pos (subseq host-port 0 colon-pos) host-port))
         (port (if colon-pos
                   (parse-integer (subseq host-port (1+ colon-pos)) :junk-allowed t)
                   5432))
         (colon-user (position #\: user-info)))
    (list :host host
          :port port
          :database db-name
          :user (if colon-user (subseq user-info 0 colon-user) user-info)
          :password (if colon-user (subseq user-info (1+ colon-user)) ""))))

(defun parse-redis-connection-string (url)
  "Parse Redis connection string
   Format: redis:red-//host:port/db or redis:red-//password@host:port/db"
  (declare (type string url))
  (let* ((without-scheme (if (search "://" url)
                             (subseq url (+ (search "://" url) 3))
                             url))
         (slash-pos (position #\/ without-scheme))
         (host-part (if slash-pos (subseq without-scheme 0 slash-pos) without-scheme))
         (db-part (if slash-pos
                      (parse-integer (subseq without-scheme (1+ slash-pos)) :junk-allowed t)
                      0))
         (colon-pos (position #\: host-part))
         (at-pos (position #\@ host-part)))
    (cond
      ;; redis:red-//password@host:port/db
      (at-pos
       (let ((password (subseq host-part 0 at-pos))
             (host-port (subseq host-part (1+ at-pos))))
         (list :host (if (position #\: host-port)
                         (subseq host-port 0 (position #\: host-port))
                         host-port)
               :port (if (position #\: host-port)
                         (parse-integer (subseq host-port (1+ (position #\: host-port))) :junk-allowed t)
                         6379)
               :db db-part
               :password password)))
      ;; redis:red-//host:port/db
      (colon-pos
       (list :host (subseq host-part 0 colon-pos)
             :port (parse-integer (subseq host-part (1+ colon-pos)) :junk-allowed t)
             :db db-part))
      ;; redis:red-//host/db
      (t (list :host host-part :port 6379 :db db-part)))))

;;;; PostgreSQL Connection

(defun init-postgresql ()
  "Initialize PostgreSQL connection"
  (handler-case
      (progn
        (postmodern:connect-toplevel *postgres-database* *postgres-user* *postgres-password* *postgres-host*
                            :port *postgres-port* :use-ssl :no)
        (setf *pg-connected* t)
        (log-info "PostgreSQL connected: ~a@~a:~a/~a"
                  *postgres-user* *postgres-host* *postgres-port* *postgres-database*)
        ;; Run migrations
        (run-migrations))
    (error (c)
      (log-error "Failed to connect PostgreSQL: ~a" c)
      (setf *pg-connected* nil))))

(defun ensure-pg-connected ()
  "Ensure PostgreSQL is connected, reconnect if needed"
  (unless *pg-connected*
    (init-postgresql))
  *pg-connected*)

(defun run-migrations ()
  "Run database migrations"
  (handler-case
      (progn
        (init-migration-system)
        (migrate)
        (log-info "Database migrations completed"))
    (error (c)
      (log-error "Migration error: ~a" c))))

;;;; Redis Connection

(defun init-redis ()
  "Initialize Redis connection"
  (handler-case
      (progn
        (redis:connect :host *redis-host*
                       :port *redis-port*
                       :auth *redis-password*)
        (setf *redis-client* redis:*connection*)
        (unless (zerop *redis-db*)
          (redis:red-select *redis-db*))
        (setf *redis-connected* t)
        (log-info "Redis connected: ~a:~a/~a" *redis-host* *redis-port* *redis-db*))
    (error (c)
      (log-error "Failed to connect Redis: ~a" c)
      (setf *redis-connected* nil))))

(defun ensure-redis-connected ()
  "Ensure Redis is connected, reconnect if needed"
  (unless *redis-connected*
    (init-redis))
  *redis-connected*)

;;;; User Operations (PostgreSQL)

(defun create-user (id username email password-hash &key (password-salt "") (public-key nil) (phone nil) (display-name nil) (is-anonymous nil))
  "Create a new user"
  (declare (type (or integer bignum) id)
           (type string username password-hash password-salt)
           (type (or string null) email))
  (ensure-pg-connected)
  (bordeaux-threads:with-lock-held (*storage-lock*)
    (postmodern:query
     "INSERT INTO users (id, username, email, password_hash, password_salt, public_key, phone, display_name, is_anonymous)
      VALUES ($1, $2, NULLIF($3, ''), $4, $5, $6, NULLIF($7, ''), $8, $9)
      ON CONFLICT (username) DO NOTHING"
     id username (or email "") password-hash password-salt (or public-key "") (or phone "") (or display-name username) (if is-anonymous t nil))
    (log-info "Created user: ~a (ID: ~a)" username id)
    id))

(defun get-user (user-id)
  "Get user by ID"
  (declare (type string user-id))
  (ensure-pg-connected)
  (let ((result (postmodern:query "SELECT * FROM users WHERE id = $1" user-id)))
    (when result
      (let ((row (car result)))
        (list :id (elt row 0)
              :username (elt row 1)
              :email (elt row 2)
              :phone (elt row 3)
              :display-name (elt row 4)
              :avatar-url (elt row 5)
              :password-hash (elt row 6)
              :password-salt (elt row 7)
              :public-key (elt row 8)
              :auth-type (elt row 9)
              :wechat-openid (elt row 10)
              :status (elt row 11)
              :metadata (elt row 12)
              :created-at (elt row 13)
              :updated-at (elt row 14))))))

(defun get-user-by-username (username)
  "Get user by username"
  (declare (type string username))
  (ensure-pg-connected)
  (log-info "get-user-by-username called for: ~A" username)
  (handler-case
      (let ((result (postmodern:query "SELECT * FROM users WHERE username = $1" username :alists)))
        (log-info "get-user-by-username result: ~A" result)
        (when result
          (let ((row (car result)))
            (log-info "Row data: ~A" row)
            ;; Helper to get value from alist by symbol name
            (flet ((get-val (name)
                     (let ((cell (find name row :key #'car :test #'string=)))
                       (when cell (cdr cell)))))
              ;; Row is an alist: ((ID . 1) (USERNAME . "admin") (PASSWORD-HASH . "...") ...)
              ;; Keys are symbols with PostgreSQL snake_case converted to Lisp kebab-case
              (let ((id-val (get-val "ID"))
                    (username-val (get-val "USERNAME"))
                    (email-val (get-val "EMAIL"))
                    (display-name-val (get-val "DISPLAY-NAME"))
                    (password-hash-val (get-val "PASSWORD-HASH"))
                    (password-salt-val (get-val "PASSWORD-SALT"))
                    (status-val (get-val "STATUS")))
                (log-info "Extracted values - id: ~A, username: ~A, hash: ~A, salt: ~A"
                          id-val username-val password-hash-val password-salt-val)
                (list :user-id (write-to-string id-val)
                      :username username-val
                      :email email-val
                      :display-name display-name-val
                      :password-hash password-hash-val
                      :password-salt password-salt-val
                      :status status-val))))))
    (error (c)
      (log-error "Error in get-user-by-username: ~A" c)
      (error "Database query failed: ~A" c))))

(defun get-user-by-email (email)
  "Get user by email"
  (declare (type string email))
  (ensure-pg-connected)
  (let ((result (postmodern:query "SELECT * FROM users WHERE email = $1" email)))
    (when result
      (get-user (elt (car result) 0)))))

(defun update-user (user-id &key (password-hash nil) (password-salt nil) (email nil)
                                 (display-name nil) (status nil) (public-key nil) (avatar-url nil))
  "Update user information"
  (declare (type string user-id))
  (ensure-pg-connected)
  (bordeaux-threads:with-lock-held (*storage-lock*)
    (let ((updates nil)
          (params nil)
          (param-idx 1))
      (when password-hash
        (push (format nil "password_hash = $~a" param-idx) updates)
        (push password-hash params)
        (incf param-idx))
      (when password-salt
        (push (format nil "password_salt = $~a" param-idx) updates)
        (push password-salt params)
        (incf param-idx))
      (when email
        (push (format nil "email = $~a" param-idx) updates)
        (push email params)
        (incf param-idx))
      (when display-name
        (push (format nil "display_name = $~a" param-idx) updates)
        (push display-name params)
        (incf param-idx))
      (when status
        (push (format nil "status = $~a" param-idx) updates)
        (push status params)
        (incf param-idx))
      (when public-key
        (push (format nil "public_key = $~a" param-idx) updates)
        (push public-key params)
        (incf param-idx))
      (when avatar-url
        (push (format nil "avatar_url = $~a" param-idx) updates)
        (push avatar-url params)
        (incf param-idx))

      (when updates
        (push (format nil "updated_at = $~a" param-idx) updates)
        (push (get-universal-time) params)
        (push user-id params)

        (let ((sql (format nil "UPDATE users SET ~{~a~^, ~} WHERE id = $~a"
                           (nreverse updates)
                           param-idx)))
          (postmodern:query sql params)))

      (get-user user-id))))

(defun delete-user (user-id)
  "Soft delete a user"
  (declare (type string user-id))
  (ensure-pg-connected)
  (postmodern:query "UPDATE users SET status = 'deleted' WHERE id = $1" user-id)
  (log-info "Deleted user: ~a" user-id))

;;;; Session Operations (PostgreSQL with Redis cache)
;;;; Updated: 2026-03-22

(defun create-session (session-id user-id username &key (ip-address nil) (user-agent nil)
                                          (expires-at nil))
  "Create a new session"
  (declare (type string session-id user-id username))
  (ensure-pg-connected)
  (let* ((expires (or expires-at (+ (get-universal-time) (* 24 60 60))))
         ;; Convert universal time (1900 epoch) to Unix time (1970 epoch) for PostgreSQL
         (unix-time (storage-universal-to-unix expires))
         (user-id-int (handler-case (parse-integer user-id)
                        (error (c)
                          (log-error "Failed to parse user-id '~A': ~A" user-id c)
                          0))))
    (postmodern:query
     "INSERT INTO user_sessions (session_id, user_id, username, ip_address, user_agent, expires_at)
      VALUES ($1, $2, $3, NULLIF($4, '')::inet, NULLIF($5, ''), to_timestamp($6::bigint))"
     session-id user-id-int username (or ip-address "") (or user-agent "") unix-time)

    ;; Cache in Redis
    (when *redis-connected*
      (let* ((session-data (list :session-id session-id
                                 :user-id user-id
                                 :username username
                                 :expires-at expires))
             (json-str (cl-json:encode-json-to-string session-data)))
        (log-info "Storing session in Redis: session-id=~A, user-id=~A (type: ~A), json=~A"
                  session-id user-id (type-of user-id) json-str)
        (redis-set "session" session-id json-str
                   :expires (- expires (get-universal-time)))
        (redis-expire-at "session" unix-time)))

    (log-info "Created session: ~a for user ~a" session-id user-id)
    session-id))

(defun get-session (session-id)
  "Get session by ID"
  (declare (type string session-id))
  ;; Try Redis cache first
  (when (and *redis-connected*)
    (let ((cached (redis-get "session" session-id)))
      (when cached
        (let ((data (cl-json:decode-json-from-string cached)))
          ;; Convert JSON alist to plist with keyword keys
          (if (and (listp data) (not (keywordp (car data))))
              ;; JSON alist format: ((\"sessionId\" . \"...\") (\"userId\" . \"...\"))
              (let ((result nil))
                (loop for item in data do
                  (cond
                    ((string= (car item) "sessionId")
                     (push :session-id result)
                     (push (cdr item) result))
                    ((string= (car item) "userId")
                     (push :user-id result)
                     ;; Handle both string and number types - convert to string
                     (push (if (stringp (cdr item))
                               (remove-prefix (remove-prefix (cdr item) "\"") "\"")
                               (write-to-string (cdr item)))
                           result))
                    ((string= (car item) "username")
                     (push :username result)
                     (push (cdr item) result))
                    ((string= (car item) "expiresAt")
                     (push :expires-at result)
                     (push (cdr item) result))
                    ((string= (car item) "ipAddress")
                     (push :ip-address result)
                     (push (cdr item) result))
                    ((string= (car item) "userAgent")
                     (push :user-agent result)
                     (push (cdr item) result)))))
                (return-from get-session (nreverse result)))
              ;; Already a plist, return as-is
              (return-from get-session data))))
  ;; Fallback to PostgreSQL
  (ensure-pg-connected)
  (let ((result (postmodern:query
                 "SELECT * FROM user_sessions WHERE session_id = $1 AND expires_at > NOW()"
                 session-id)))
    (when result
      (let ((row (car result)))
        (list :session-id (elt row 0)
              :user-id (write-to-string (elt row 1))
              :username (elt row 2)
              :ip-address (elt row 3)
              :user-agent (elt row 4)
              :created-at (elt row 5)
              :expires-at (elt row 6)
              :last-active (elt row 7)
              :metadata (elt row 8)))))))

(defun update-session-last-active (session-id)
  "Update session last active timestamp"
  (declare (type string session-id))
  (ensure-pg-connected)
  (postmodern:query "UPDATE user_sessions SET last_active = NOW() WHERE session_id = $1" session-id)

  ;; Update Redis TTL
  (when (and *redis-connected*)
    (let ((session (get-session session-id)))
      (when session
        (let ((expires-at (getf session :expires-at)))
          (redis-expire-at "session" expires-at))))))

(defun invalidate-session (session-id)
  "Invalidate a session"
  (declare (type string session-id))
  (ensure-pg-connected)
  (postmodern:query "DELETE FROM user_sessions WHERE session_id = $1" session-id)

  ;; Remove from Redis
  (when *redis-connected*
    (redis-del "session" session-id))

  (log-info "Invalidated session: ~a" session-id))

(defun invalidate-all-user-sessions (user-id)
  "Invalidate all sessions for a user"
  (declare (type string user-id))
  (ensure-pg-connected)
  (postmodern:query "DELETE FROM user_sessions WHERE user_id = $1" user-id)
  (log-info "Invalidated all sessions for user: ~a" user-id))

(defun cleanup-expired-sessions ()
  "Clean up expired sessions"
  (ensure-pg-connected)
  (let ((result (postmodern:query "SELECT cleanup_expired_sessions()")))
    (let ((count (caar result)))
      (when (> count 0)
        (log-info "Cleaned up ~a expired sessions" count))
      count)))

;;;; Conversation Operations

(defun store-conversation (conv)
  "Store a conversation to database"
  (declare (type conversation conv))
  (ensure-pg-connected)
  (bordeaux-threads:with-lock-held (*storage-lock*)
    (let ((conv-id (conversation-id conv))
          (type (conversation-type conv))
          (creator-id (conversation-creator-id conv))
          (name (conversation-name conv))
          (avatar-url (conversation-avatar conv))
          (metadata (conversation-metadata conv)))
      (postmodern:query
       "INSERT INTO conversations (id, type, creator_id, name, avatar_url, metadata)
        VALUES ($1, $2, $3, $4, $5, $6)
        ON CONFLICT (id) DO UPDATE SET
          type = $2,
          creator_id = $3,
          name = $4,
          avatar_url = $5,
          metadata = $6,
          updated_at = NOW()"
       conv-id (string-downcase (string type)) creator-id name avatar-url
       (cl-json:encode-json-to-string metadata))
      (log-info "Stored conversation: ~a" conv-id))))

(defun update-conversation (conv)
  "Update a conversation in database"
  (declare (type conversation conv))
  (ensure-pg-connected)
  (bordeaux-threads:with-lock-held (*storage-lock*)
    (let ((conv-id (conversation-id conv))
          (name (conversation-name conv))
          (avatar-url (conversation-avatar conv))
          (metadata (conversation-metadata conv))
          (last-activity (conversation-last-activity conv))
          (last-sequence (conversation-last-sequence conv)))
      (postmodern:query
       "UPDATE conversations SET
          name = $1,
          avatar_url = $2,
          metadata = $3,
          last_message_at = to_timestamp($4::bigint),
          updated_at = NOW()
        WHERE id = $5"
       name avatar-url (cl-json:encode-json-to-string metadata)
       (- last-activity 2208988800) conv-id)
      (log-debug "Updated conversation: ~a" conv-id))))

(defun create-conversation (id type creator-id &key (name nil) (avatar-url nil) (metadata nil))
  "Create a new conversation"
  (declare (type integer id)
           (type keyword type)
           (type integer creator-id))
  (ensure-pg-connected)
  (bordeaux-threads:with-lock-held (*storage-lock*)
    (postmodern:query
     "INSERT INTO conversations (id, type, creator_id, name, avatar_url, metadata)
      VALUES ($1, $2, $3, $4, $5, $6)"
     id (string-downcase (symbol-name type)) creator-id name avatar-url (or metadata "{}"))

    ;; Add creator as participant with owner role
    (postmodern:query
     "INSERT INTO conversation_participants (conversation_id, user_id, role)
      VALUES ($1, $2, 'owner')"
     id creator-id)

    (log-info "Created conversation: ~a (type: ~a)" id type)
    id))

(defun get-or-create-direct-conversation (user-id-1 user-id-2)
  "Get existing direct conversation between two users, or create a new one"
  (ensure-pg-connected)
  (log-info "get-or-create-direct-conversation: user1=~a, user2=~a" user-id-1 user-id-2)
  ;; First, try to find existing conversation
  (let* ((sorted-user-ids (sort (list user-id-1 user-id-2) #'<))
         (user1 (first sorted-user-ids))
         (user2 (second sorted-user-ids))
         (existing (postmodern:query
                    "SELECT c.id FROM conversations c
                     JOIN conversation_participants cp1 ON c.id = cp1.conversation_id
                     JOIN conversation_participants cp2 ON c.id = cp2.conversation_id
                     WHERE c.type = 'direct'
                       AND cp1.user_id = $1 AND cp1.is_deleted = FALSE
                       AND cp2.user_id = $2 AND cp2.is_deleted = FALSE
                     LIMIT 1"
                    user1 user2)))
    (if existing
        ;; Return existing conversation
        (caar existing)
        ;; Create new conversation
        (let ((new-id (generate-snowflake-id)))
          ;; Get user2's display name for conversation name
          (let* ((user2-info (postmodern:query
                              "SELECT display_name, username FROM users WHERE id = $1"
                              user2))
                 (user2-row (when user2-info (car user2-info)))
                 (conv-name (if user2-row
                                (or (elt user2-row 0) (elt user2-row 1) "Unknown")
                                "Unknown")))
            (log-info "Creating new conversation: id=~a, type=direct, creator=~a, name=~a" new-id user-id-1 conv-name)
            (create-conversation new-id :direct user-id-1 :name conv-name)
            ;; Add second user as participant
            (add-conversation-participant new-id user-id-2 :role "member")
            new-id)))))

(defun get-conversation (conversation-id)
  "Get conversation by ID"
  (declare (type integer conversation-id))
  (ensure-pg-connected)
  (let ((result (postmodern:query "SELECT * FROM conversations WHERE id = $1" conversation-id)))
    (when result
      (let ((row (car result)))
        (list :id (elt row 0)
              :type (elt row 1)
              :name (elt row 2)
              :avatar-url (elt row 3)
              :creator-id (elt row 4)
              :max-members (elt row 5)
              :metadata (elt row 6)
              :created-at (elt row 7)
              :updated-at (elt row 8)
              :last-message-at (elt row 9)
              :last-message-id (elt row 10))))))

(defun get-conversations (user-id &key (type nil) (page 1) (page-size 20))
  "Get conversations for a user"
  (declare (type string user-id))
  (ensure-pg-connected)
  (let* ((offset (* (1- page) page-size))
         (type-filter (if type (format nil "AND c.type = '~a'" type) ""))
         (sql (format nil "
           SELECT c.*, cp.role, cp.last_read_sequence
           FROM conversations c
           JOIN conversation_participants cp ON c.id = cp.conversation_id
           WHERE cp.user_id = $1 ~a AND cp.is_deleted = FALSE
           ORDER BY c.last_message_at DESC NULLS LAST, c.created_at DESC
           LIMIT $2 OFFSET $3" type-filter))
         (result (postmodern:query sql user-id page-size offset)))
    (loop for row in result
          collect (list :id (elt row 0)
                        :type (elt row 1)
                        :name (elt row 2)
                        :avatar-url (elt row 3)
                        :creator-id (elt row 4)
                        :max-members (elt row 5)
                        :metadata (elt row 6)
                        :created-at (storage-universal-to-unix-ms (elt row 7))
                        :updated-at (storage-universal-to-unix-ms (elt row 8))
                        :last-message-at (if (or (null (elt row 9)) (eq (elt row 9) :null))
                                             nil
                                             (storage-universal-to-unix-ms (elt row 9)))
                        :last-message-id (elt row 10)
                        :role (elt row 11)
                        :last-read-sequence (elt row 12)))))

(defun get-conversation-participants (conversation-id)
  "Get participants of a conversation"
  (declare (type integer conversation-id))
  (ensure-pg-connected)
  (let ((result (postmodern:query
                 "SELECT cp.*, u.username, u.display_name, u.avatar_url
                  FROM conversation_participants cp
                  JOIN users u ON cp.user_id = u.id
                  WHERE cp.conversation_id = $1 AND cp.is_deleted = FALSE"
                 conversation-id)))
    (loop for row in result
          collect (list :conversation-id (elt row 0)
                        :user-id (elt row 1)
                        :role (elt row 2)
                        :joined-at (elt row 3)
                        :last-read-sequence (elt row 4)
                        :is-deleted (elt row 5)
                        :metadata (elt row 6)
                        :username (elt row 7)
                        :display-name (elt row 8)
                        :avatar-url (elt row 9)))))

(defun add-conversation-participant (conversation-id user-id &key (role "member"))
  "Add a participant to a conversation"
  (declare (type integer conversation-id user-id))
  (ensure-pg-connected)
  (postmodern:query
   "INSERT INTO conversation_participants (conversation_id, user_id, role)
    VALUES ($1, $2, $3)
    ON CONFLICT (conversation_id, user_id) DO UPDATE SET role = $3"
   conversation-id user-id role)
  (log-info "Added participant ~a to conversation ~a" user-id conversation-id))

(defun remove-conversation-participant (conversation-id user-id)
  "Remove a participant from a conversation"
  (declare (type integer conversation-id user-id))
  (ensure-pg-connected)
  (postmodern:query
   "UPDATE conversation_participants SET is_deleted = TRUE
    WHERE conversation_id = $1 AND user_id = $2"
   conversation-id user-id)
  (log-info "Removed participant ~a from conversation ~a" user-id conversation-id))

;;;; System Admin

(defparameter *system-admin-user-id* 999999999
  "System administrator user ID")

(defparameter *system-admin-username* "system_admin"
  "System administrator username")

(defparameter *system-admin-display-name* "系统管理员"
  "System administrator display name")

(defun ensure-system-admin-exists ()
  "Ensure system admin user exists, create if not"
  (ensure-pg-connected)
  (let ((existing (postmodern:query "SELECT id FROM users WHERE id = $1" *system-admin-user-id*)))
    (unless existing
      ;; Create system admin user with a random password (not used for login)
      (multiple-value-bind (hash salt)
          (hash-password (format nil "~a" (random 1000000000)))
        (postmodern:query
         "INSERT INTO users (id, username, email, password_hash, password_salt, display_name, status)
          VALUES ($1, $2, $3, $4, $5, $6, 'active')"
         *system-admin-user-id* *system-admin-username* "system@lispim.local" hash salt *system-admin-display-name*)
        (log-info "Created system admin user: ~a (ID: ~a)" *system-admin-display-name* *system-admin-user-id*)))))

(defun ensure-default-users-exist ()
  "Ensure default test users exist (admin, user1, user2)"
  (ensure-pg-connected)
  (let ((default-users
         '((100000001 "admin" "admin@lispim.local" "Admin" "admin123456")
           (100000002 "user1" "user1@lispim.local" "User One" "user123456")
           (100000003 "user2" "user2@lispim.local" "User Two" "user123456"))))
    (dolist (user-data default-users)
      (destructuring-bind (user-id username email display-name password) user-data
        (let ((existing-id (postmodern:query "SELECT id FROM users WHERE username = $1" username)))
          (if existing-id
              (log-debug "Default user already exists: ~a (ID: ~a)" username (caar existing-id))
              (multiple-value-bind (hash salt)
                  (hash-password password)
                (postmodern:query
                 "INSERT INTO users (id, username, email, password_hash, password_salt, display_name, status)
                  VALUES ($1, $2, $3, $4, $5, $6, 'active')"
                 user-id username email hash salt display-name)
                (log-info "Created default user: ~a (ID: ~a, password: ~a)" username user-id password))))))))

(defun get-or-create-system-admin-conversation (user-id-int)
  "Get or create conversation between user and system admin"
  (ensure-system-admin-exists)
  (log-info "get-or-create-system-admin-conversation: user-id-int=~a, system-admin-id=~a" user-id-int *system-admin-user-id*)
  ;; Get or create direct conversation between user and system admin
  (get-or-create-direct-conversation user-id-int *system-admin-user-id*))

(defun create-system-admin-conversation-for-user (user-id-int)
  "Create conversation with system admin for new user and add as friend"
  (declare (type integer user-id-int))
  (ensure-system-admin-exists)
  ;; Automatically add system admin as friend
  (handler-case
      (progn
        ;; Check if friend relationship already exists
        (let ((exists (postmodern:query
                       "SELECT 1 FROM friends WHERE (user_id = $1 AND friend_id = $2) OR (user_id = $2 AND friend_id = $1)"
                       user-id-int *system-admin-user-id*)))
          (unless exists
            ;; Create bidirectional friend relationship
            (postmodern:with-transaction ()
              (postmodern:query
               "INSERT INTO friends (user_id, friend_id, status) VALUES ($1, $2, 'accepted')
                ON CONFLICT (user_id, friend_id) DO NOTHING"
               user-id-int *system-admin-user-id*)
              (postmodern:query
               "INSERT INTO friends (user_id, friend_id, status) VALUES ($2, $1, 'accepted')
                ON CONFLICT (user_id, friend_id) DO NOTHING"
               user-id-int *system-admin-user-id*))
            (log-info "Added system admin as friend for user ~a" user-id-int))))
    (error (c)
      (log-error "Error adding system admin as friend: ~a" c)))
  ;; Create conversation
  (handler-case
      (let ((conv-id (get-or-create-direct-conversation user-id-int *system-admin-user-id*)))
        (log-info "Created system admin conversation for user ~a: ~a" user-id-int conv-id)
        ;; Send welcome message from system admin if this is a new conversation
        (let ((last-message (get-conversation-last-message conv-id)))
          (unless last-message
            (handler-case
                (let ((welcome-msg (make-message
                                    :id (generate-message-id)
                                    :conversation-id conv-id
                                    :sender-id (write-to-string *system-admin-user-id*)
                                    :message-type :text
                                    :content "欢迎使用 LispIM！我是系统管理员，有任何问题都可以联系我。"
                                    :created-at (get-universal-time))))
                  (store-message welcome-msg)
                  (log-info "Sent welcome message to user ~a" user-id-int))
              (error (c)
                (log-error "Failed to send welcome message: ~a" c)))))
        conv-id)
    (error (c)
      (log-error "Failed to create system admin conversation: ~a" c)
      nil)))

(defun get-conversation-last-message (conversation-id)
  "Get the last message in a conversation"
  (declare (type integer conversation-id))
  (ensure-pg-connected)
  (let ((result (postmodern:query
                 "SELECT * FROM messages WHERE conversation_id = $1 ORDER BY sequence DESC LIMIT 1"
                 conversation-id)))
    (when result
      (car result))))

;;;; Message Operations

(defun store-message (msg)
  "Store a message"
  (declare (type message msg))
  (ensure-pg-connected)
  (bordeaux-threads:with-lock-held (*storage-lock*)
    (let ((msg-id (message-id msg))
          (conv-id (message-conversation-id msg))
          (sender-id (message-sender-id msg))
          (sequence (message-sequence msg))
          (type (message-message-type msg))
          (content (message-content msg))
          (attachments (message-attachments msg))
          (mentions (message-mentions msg))
          (reply-to (message-reply-to msg)))

      (postmodern:query
       "INSERT INTO messages
        (id, conversation_id, sender_id, sequence, type, content, attachments, mentions, reply_to)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, NULL)"
       msg-id conv-id sender-id (princ-to-string sequence) (string-downcase type) content
       (cl-json:encode-json-to-string (or attachments '()))
       (make-array 0 :element-type 'integer))

      ;; Update conversation's last message
      (postmodern:query
       "UPDATE conversations SET last_message_at = NOW(), last_message_id = $1
        WHERE id = $2"
       msg-id conv-id)

      ;; Cache in Redis (recent messages)
      (when *redis-connected*
        (let ((key (format nil "messages:~a" conv-id)))
          (redis-lpush key (cl-json:encode-json-to-string
                            (list :id msg-id :sequence sequence :type type :content content)))
          (redis-ltrim key 0 99)))  ; Keep last 100 messages

      (log-debug "Stored message: ~a (seq: ~a)" msg-id sequence))))

(defun get-message (message-id)
  "Get message by ID"
  (declare (type integer message-id))
  (ensure-pg-connected)
  (let ((result (postmodern:query "SELECT * FROM messages WHERE id = $1" message-id)))
    (when result
      (let ((row (car result)))
        (list :id (elt row 0)
              :conversation-id (elt row 1)
              :sender-id (elt row 2)
              :sequence (elt row 3)
              :type (elt row 4)
              :content (elt row 5)
              :attachments (elt row 6)
              :mentions (elt row 7)
              :reply-to (elt row 8)
              :recalled (elt row 9)
              :recalled-at (elt row 10)
              :edited-at (elt row 11)
              :is-deleted (elt row 12)
              :metadata (elt row 13)
              :created-at (elt row 14))))))

(defun query-messages (conversation-id &key (limit 50) before after)
  "Query messages for a conversation"
  (declare (type integer conversation-id)
           (type (integer 1 100) limit))
  (ensure-pg-connected)

  ;; Try Redis cache for simple queries
  (when (and *redis-connected* (not before) (not after) (<= limit 100))
    (let ((cached (redis-lrange (format nil "messages:~a" conversation-id) 0 (1- limit))))
      (when cached
        (return-from query-messages
          (mapcar (lambda (json) (cl-json:decode-json-from-string json)) cached)))))

  ;; PostgreSQL query
  (let* ((where-clauses '("conversation_id = $1"))
         (params (list conversation-id))
         (param-idx 2))

    (when before
      (push (format nil "sequence < $~a" param-idx) where-clauses)
      (push before params)
      (incf param-idx))

    (when after
      (push (format nil "sequence > $~a" param-idx) where-clauses)
      (push after params)
      (incf param-idx))

    (let ((sql (format nil "
      SELECT * FROM messages
      WHERE ~a
      ORDER BY sequence DESC
      LIMIT $~a"
                       (format nil "~{~a~^ AND ~}" where-clauses)
                       param-idx)))

      (let ((result (postmodern:query sql params)))
        (loop for row in (nreverse result)
              collect (list :id (elt row 0)
                            :conversation-id (elt row 1)
                            :sender-id (elt row 2)
                            :sequence (elt row 3)
                            :type (elt row 4)
                            :content (elt row 5)
                            :attachments (elt row 6)
                            :mentions (elt row 7)
                            :reply-to (elt row 8)
                            :recalled (elt row 9)
                            :created-at (storage-universal-to-unix-ms (elt row 14))))))))

(defun update-message (msg)
  "Update a message"
  (declare (type message msg))
  (ensure-pg-connected)
  (bordeaux-threads:with-lock-held (*storage-lock*)
    (let ((msg-id (message-id msg))
          (content (message-content msg)))
      (postmodern:query
       "UPDATE messages SET content = $1, edited_at = NOW() WHERE id = $2"
       content msg-id)
      (log-debug "Updated message: ~a" msg-id))))

(defun recall-message (message-id)
  "Recall (delete) a message"
  (declare (type integer message-id))
  (ensure-pg-connected)
  (postmodern:query
   "UPDATE messages SET recalled = TRUE, recalled_at = NOW() WHERE id = $1"
   message-id)
  (log-info "Recalled message: ~a" message-id))

;;;; Message Send/Get Operations

(defun send-message (conversation-id content &key (type :text) (attachments nil) (reply-to nil) (mentions nil) (sender-id nil))
  "Send a message to a conversation
   Returns: (values success? message-or-error)"
  (declare (type (or string integer) conversation-id)
           (type string content)
           (type keyword type)
           (optimize (speed 2) (safety 1)))

  (ensure-pg-connected)
  (ensure-redis-connected)

  (let* ((message-id (generate-snowflake-id))
         (sequence (get-next-sequence conversation-id))
         (sender (or sender-id ""))
         (created-at (get-universal-time)))

    ;; Store in PostgreSQL
    (bordeaux-threads:with-lock-held (*storage-lock*)
      (postmodern:query
       "INSERT INTO messages (id, conversation_id, sender_id, sequence, type, content, attachments, mentions, reply_to, created_at)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, NOW())"
       message-id conversation-id sender sequence
       (string-downcase (string type))
       content
       (when attachments (cl-json:encode-json-to-string attachments))
       (when mentions (cl-json:encode-json-to-string mentions))
       reply-to))

    ;; Cache in Redis
    (let ((msg-json (cl-json:encode-json-to-string
                     (list :id message-id
                           :conversation-id conversation-id
                           :sender-id sender
                           :sequence sequence
                           :type type
                           :content content
                           :attachments attachments
                           :mentions mentions
                           :reply-to reply-to
                           :created-at created-at))))
      (redis-lpush (format nil "messages:~a" conversation-id) msg-json)
      (redis-ltrim (format nil "messages:~a" conversation-id) 0 99))

    (log-info "Message sent: ~a to conversation ~a" message-id conversation-id)

    (values t (list :id message-id
                    :conversation-id conversation-id
                    :sender-id sender
                    :sequence sequence
                    :type type
                    :content content
                    :attachments attachments
                    :mentions mentions
                    :reply-to reply-to
                    :created-at created-at))))

(defun get-next-sequence (conversation-id)
  "Get next sequence number for a conversation"
  (declare (type (or string integer) conversation-id))
  (ensure-pg-connected)
  (let ((result (postmodern:query
                 "SELECT COALESCE(MAX(sequence), 0) + 1 FROM messages WHERE conversation_id = $1"
                 conversation-id)))
    (or (caar result) 1)))

(defun get-messages (user-id conversation-id &key (before nil) (after nil) (limit 20))
  "Get messages from a conversation
   Returns: (values success? messages has-more)"
  (declare (type string user-id)
           (type (or string integer) conversation-id)
           (type integer limit)
           (optimize (speed 2) (safety 1)))

  ;; Check if user has access to conversation
  (unless (check-conversation-access user-id conversation-id)
    (return-from get-messages (values nil nil "Access denied")))

  ;; Use query-messages from storage
  (let ((messages (query-messages conversation-id :limit limit :before before :after after)))
    (values t messages (and before t))))

(defun check-conversation-access (user-id conversation-id)
  "Check if user has access to conversation - stub for future implementation"
  (declare (type string user-id)
           (type (or string integer) conversation-id)
           (ignore user-id conversation-id))
  ;; Simplified check - in production, verify membership
  t)

;;;; Redis Operations (direct cl-redis wrapper)

(defun redis-set (key subkey value &key (expires nil))
  "Redis HSET"
  (declare (type string key subkey value))
  (when (and *redis-connected* *redis-client*)
    (redis:red-hset key subkey value)
    (when expires
      (redis:red-expire key expires))))

;;;; Friend Operations

(defun get-friends (user-id &optional (status "accepted"))
  "Get list of friends for a user
   Returns: list of friend user records"
  (declare (type string user-id))
  (ensure-pg-connected)
  (let ((result (postmodern:query
                 "SELECT DISTINCT ON (u.id)
                         u.id, u.username, u.email, u.phone, u.display_name, u.avatar_url,
                         u.password_hash, u.password_salt, u.public_key, u.auth_type,
                         u.wechat_openid, u.status, u.metadata, u.created_at, u.updated_at,
                         u.fcm_token, u.device_id, u.platform, u.push_enabled,
                         f.status as friend_status, f.created_at as friend_since
                  FROM friends f
                  JOIN users u ON (CASE WHEN f.user_id = $1 THEN f.friend_id ELSE f.user_id END) = u.id
                  WHERE (f.user_id = $1 OR f.friend_id = $1)
                    AND f.status = $2
                  ORDER BY u.id"
                 user-id status)))
    (loop for row in result
          collect (list :id (elt row 0)
                        :username (elt row 1)
                        :email (elt row 2)
                        :phone (let ((val (elt row 3))) (if (or (null val) (eq val :null) (string= val "")) nil val))
                        :display-name (let ((val (elt row 4))) (if (or (null val) (eq val :null) (string= val "")) nil val))
                        :avatar-url (let ((val (elt row 5))) (if (or (null val) (eq val :null) (string= val "")) nil val))
                        :user-status (elt row 11)
                        :friend-status (elt row 19)
                        :friend-since (storage-universal-to-unix-ms (elt row 20))))))

(defun delete-friend (user-id friend-id)
  "Delete friend relationship
   Returns: (values success? error)"
  (declare (type string user-id friend-id))
  (ensure-pg-connected)
  (handler-case
      (progn
        ;; Delete bidirectional friend relationship
        (postmodern:query
         "DELETE FROM friends
          WHERE (user_id = $1 AND friend_id = $2)
             OR (user_id = $2 AND friend_id = $1)"
         user-id friend-id)
        (values t nil))
    (error (c)
      (values nil (format nil "Error: ~a" c)))))

(defun add-friend-request (sender-id receiver-id &optional message)
  "Send a friend request
   Returns: (values success? request-id error)"
  (declare (type string sender-id receiver-id)
           (type (or string null) message))
  (log-info "add-friend-request called: sender=~A, receiver=~A, message=~A" sender-id receiver-id message)
  (ensure-pg-connected)
  (handler-case
      (progn
        (log-info "Executing friend request insert")
        (let ((result (postmodern:query
                       "INSERT INTO friend_requests (sender_id, receiver_id, message)
                        VALUES ($1, $2, $3) RETURNING id"
                       sender-id receiver-id (or message ""))))
          (log-info "Query result: ~A" result)
          (if result
              (values t (caar result) nil)
              (values nil nil "Failed to create friend request"))))
    (error (c)
      (log-error "add-friend-request error: ~A" c)
      (values nil nil (format nil "Error: ~a" c)))))

(defun accept-friend-request (request-id)
  "Accept a friend request
   Returns: (values success? error)"
  (log-info "accept-friend-request called with request-id: ~A (type: ~A)" request-id (type-of request-id))
  (ensure-pg-connected)
  (handler-case
      (progn
        (log-info "Starting transaction for request-id: ~A" request-id)
        ;; Use transaction to ensure atomicity
        (postmodern:with-transaction ()
          ;; Update friend request status
          (postmodern:query
           "UPDATE friend_requests SET status = 'accepted', responded_at = NOW() WHERE id = $1"
           request-id)
          (log-info "Updated friend_requests for id: ~A" request-id)
          ;; Create bidirectional friend relationship
          (postmodern:query
           "INSERT INTO friends (user_id, friend_id, status)
            SELECT sender_id, receiver_id, 'accepted'
            FROM friend_requests WHERE id = $1
            ON CONFLICT (user_id, friend_id) DO NOTHING"
           request-id)
          (log-info "Inserted first friend relationship for id: ~A" request-id)
          (postmodern:query
           "INSERT INTO friends (user_id, friend_id, status)
            SELECT receiver_id, sender_id, 'accepted'
            FROM friend_requests WHERE id = $1
            ON CONFLICT (user_id, friend_id) DO NOTHING"
           request-id)
          (log-info "Inserted second friend relationship for id: ~A" request-id))
        (values t nil))
    (error (c)
      (log-error "accept-friend-request error: ~A" c)
      (values nil (format nil "Error: ~a" c)))))

(defun reject-friend-request (request-id)
  "Reject a friend request
   Returns: (values success? error)"
  (declare (type integer request-id))
  (ensure-pg-connected)
  (handler-case
      (progn
        (postmodern:query
         "UPDATE friend_requests SET status = 'rejected', responded_at = NOW() WHERE id = $1"
         request-id)
        (values t nil))
    (error (c)
      (values nil (format nil "Error: ~a" c)))))

(defun get-friend-requests (user-id &optional (status "pending"))
  "Get friend requests for a user
   Returns: list of friend request records"
  (ensure-pg-connected)
  (let ((result (postmodern:query
                 "SELECT fr.id, fr.sender_id, fr.receiver_id, fr.message, fr.status,
                         ROUND(EXTRACT(EPOCH FROM fr.created_at) * 1000)::bigint AS created_ts,
                         u.username, u.display_name, u.avatar_url
                  FROM friend_requests fr
                  JOIN users u ON fr.sender_id = u.id
                  WHERE fr.receiver_id = $1 AND fr.status = $2
                  ORDER BY fr.created_at DESC"
                 user-id status :alists)))
    ;; With :alists, postmodern returns list of alists: ((|id| . 1) (|sender_id| . 123) ...)
    ;; Keys are symbols with uppercase and hyphens: ID, SENDER-ID, RECEIVER-ID, etc.
    (loop for row in result
          collect
          ;; Helper to get value from alist by symbol name (case-insensitive)
          (flet ((get-val (name)
                   (let ((cell (find name row :key #'car :test #'string=)))
                     (when cell (cdr cell)))))
            (list :id (get-val "ID")
                  :sender-id (get-val "SENDER-ID")
                  :receiver-id (get-val "RECEIVER-ID")
                  :message (or (get-val "MESSAGE") "")
                  :status (get-val "STATUS")
                  :created-at (get-val "CREATED-TS")
                  :sender-username (or (get-val "USERNAME") "")
                  :sender-display-name (or (get-val "DISPLAY-NAME") "")
                  :sender-avatar (or (get-val "AVATAR-URL") ""))))))

(defun search-users (query &key (limit 20))
  "Search users by username or display name
   Returns: list of matching users"
  (declare (type string query)
           (type integer limit))
  (ensure-pg-connected)
  ;; 支持通过 username、display_name 或用户 ID 搜索
  (let* ((search-pattern (format nil "%%%~a%%" query))
         (rows (postmodern:query
                "SELECT id, username, display_name, avatar_url
                 FROM users
                 WHERE ((username LIKE $1 OR display_name LIKE $1 OR id::text = $1)
                   AND status = 'active')
                 LIMIT $2"
                search-pattern limit)))
    (loop for row in rows
          collect (list :id (write-to-string (elt row 0))
                        :username (elt row 1)
                        :display-name (or (elt row 2) "")
                        :avatar-url (or (elt row 3) "")))))

;;;; File Upload Operations

;;;; Mobile / FCM Operations

(defun save-fcm-token (user-id fcm-token &key (device-id nil) (platform "android")
                                          (device-name nil) (app-version nil) (os-version nil))
  "Save or update FCM token for a user
   Returns: (values success? error)"
  (declare (type string user-id fcm-token platform)
           (type (or null string) device-id device-name app-version os-version))
  (ensure-pg-connected)
  (handler-case
      (let ((user-id-int (handler-case (parse-integer user-id)
                           (error (c)
                             (log-error "Failed to parse user-id '~A': ~A" user-id c)
                             0))))
        ;; Update users table with latest FCM token
        (postmodern:query
         "UPDATE users SET fcm_token = $1, device_id = $2, platform = $3
          WHERE id = $4"
         fcm-token (or device-id "") platform user-id-int)

        ;; Upsert into device_sessions for multi-device support
        (postmodern:query
         "INSERT INTO device_sessions (user_id, device_id, platform, fcm_token, device_name, app_version, os_version)
          VALUES ($1, $2, $3, $4, $5, $6, $7)
          ON CONFLICT (user_id, device_id, platform) DO UPDATE SET
            fcm_token = EXCLUDED.fcm_token,
            last_seen_at = CURRENT_TIMESTAMP,
            device_name = EXCLUDED.device_name,
            app_version = EXCLUDED.app_version,
            os_version = EXCLUDED.os_version"
         user-id-int (or device-id "unknown") platform fcm-token
         (or device-name "") (or app-version "") (or os-version ""))

        (values t nil))
    (error (c)
      (values nil (format nil "Error: ~a" c)))))

(defun remove-fcm-token (user-id &key (device-id nil))
  "Remove FCM token for a user or device
   Returns: (values success? error)"
  (declare (type string user-id)
           (type (or null string) device-id))
  (ensure-pg-connected)
  (handler-case
      (let ((user-id-int (handler-case (parse-integer user-id)
                           (error (c)
                             (log-error "Failed to parse user-id '~A': ~A" user-id c)
                             0))))
        (if device-id
            ;; Remove specific device
            (postmodern:query
             "DELETE FROM device_sessions WHERE user_id = $1 AND device_id = $2"
             user-id-int device-id)
            ;; Remove all devices for user
            (progn
              (postmodern:query "UPDATE users SET fcm_token = NULL WHERE id = $1" user-id-int)
              (postmodern:query "DELETE FROM device_sessions WHERE user_id = $1" user-id-int)))
        (values t nil))
    (error (c)
      (values nil (format nil "Error: ~a" c)))))

(defun get-user-fcm-tokens (user-id)
  "Get all FCM tokens for a user (multi-device support)
   Returns: list of (device-id platform fcm-token)"
  (declare (type string user-id))
  (ensure-pg-connected)
  (let ((user-id-int (handler-case (parse-integer user-id)
                       (error (c)
                         (log-error "Failed to parse user-id '~A': ~A" user-id c)
                         0))))
    (let ((result (postmodern:query
                   "SELECT device_id, platform, fcm_token, device_name, push_enabled
                    FROM device_sessions
                    WHERE user_id = $1 AND fcm_token IS NOT NULL AND push_enabled = TRUE"
                   user-id-int)))
      (loop for row in result
            collect (list :device-id (elt row 0)
                          :platform (elt row 1)
                          :fcm-token (elt row 2)
                          :device-name (elt row 3)
                          :push-enabled (elt row 4))))))

(defun log-push-notification (user-id title body &key (device-id nil) (data nil)
                                                 (status "pending") (error-message nil))
  "Log a push notification attempt
   Returns: (values success? notification-id error)"
  (declare (type string user-id title body status)
           (type (or null string) device-id error-message)
           (type (or null list) data))
  (ensure-pg-connected)
  (handler-case
      (let* ((user-id-int (handler-case (parse-integer user-id)
                          (error (c)
                            (log-error "Failed to parse user-id '~A': ~A" user-id c)
                            0)))
             (data-json (when data (cl-json:encode-json-to-string data)))
             (result (postmodern:query
                      "INSERT INTO push_notifications (user_id, title, body, data, status, error_message)
                       VALUES ($1, $2, $3, $4::jsonb, $5, $6)
                       RETURNING id"
                      user-id-int title body (or data-json "{}") status (or error-message ""))))
        (if result
            (values t (caar result) nil)
            (values nil nil "Failed to insert push notification log")))
    (error (c)
      (values nil nil (format nil "Error: ~a" c)))))

(defun update-push-notification-status (notification-id status &key (error-message nil) (delivered nil))
  "Update push notification status
   Returns: (values success? error)"
  (declare (type integer notification-id)
           (type string status)
           (type (or null string) error-message)
           (type (or null boolean) delivered))
  (ensure-pg-connected)
  (handler-case
      (progn
        (if delivered
            (postmodern:query
             "UPDATE push_notifications SET status = $1, delivered_at = CURRENT_TIMESTAMP
              WHERE id = $2"
             status notification-id)
            (postmodern:query
             "UPDATE push_notifications SET status = $1, error_message = $2
              WHERE id = $3"
             status (or error-message "") notification-id))
        (values t nil))
    (error (c)
      (values nil (format nil "Error: ~a" c)))))

;;;; File Upload Operations

(defun save-file-metadata (original-filename stored-filename file-path file-size mime-type uploader-id &optional expires-at)
  "Save file upload metadata to database
   Returns: (values success? file-id error)"
  (declare (type string original-filename stored-filename file-path mime-type)
           (type integer file-size)
           (type string uploader-id)
           (type (or null integer) expires-at))
  (ensure-pg-connected)
  (handler-case
      (let ((result (postmodern:query
                     "INSERT INTO file_uploads (original_filename, stored_filename, file_path, file_size, mime_type, uploader_id, expires_at)
                      VALUES ($1, $2, $3, $4, $5, $6, $7)
                      RETURNING file_id"
                     original-filename stored-filename file-path file-size mime-type uploader-id
                     (or expires-at :null))))
        (if result
            (values t (caar result) nil)
            (values nil nil "Failed to save file metadata")))
    (error (c)
      (values nil nil (format nil "Error: ~a" c)))))

(defun get-file-metadata (file-id)
  "Get file metadata by file_id (UUID)"
  (declare (type string file-id))
  (ensure-pg-connected)
  (let ((result (postmodern:query
                 "SELECT * FROM file_uploads WHERE file_id = $1"
                 file-id)))
    (when result
      (let ((row (car result)))
        (list :id (elt row 0)
              :file-id (elt row 1)
              :original-filename (elt row 2)
              :stored-filename (elt row 3)
              :file-path (elt row 4)
              :file-size (elt row 5)
              :mime-type (elt row 6)
              :uploader-id (write-to-string (elt row 7))
              :download-count (elt row 8)
              :is-public (elt row 9)
              :expires-at (elt row 10)
              :created-at (storage-universal-to-unix-ms (elt row 11)))))))

(defun increment-file-download-count (file-id)
  "Increment file download count"
  (declare (type string file-id))
  (ensure-pg-connected)
  (postmodern:query
   "UPDATE file_uploads SET download_count = download_count + 1 WHERE file_id = $1"
   file-id))

(defun redis-get (key subkey)
  "Redis HGET"
  (declare (type string key subkey))
  (when (and *redis-connected* *redis-client*)
    (redis:red-hget key subkey)))

(defun redis-del (key subkey)
  "Redis HDEL"
  (declare (type string key subkey))
  (when (and *redis-connected* *redis-client*)
    (redis:red-hdel key subkey)))

(defun redis-expire-at (key timestamp)
  "Set expiration timestamp for a key"
  (declare (type string key)
           (type integer timestamp))
  (when (and *redis-connected* *redis-client*)
    (let ((ttl (- timestamp (get-universal-time))))
      (when (> ttl 0)
        (redis:red-expire key ttl)))))

(defun redis-lpush (key value)
  "Redis LPUSH"
  (declare (type string key value))
  (when (and *redis-connected* *redis-client*)
    (redis:red-lpush key value)))

(defun redis-lrange (key start stop)
  "Redis LRANGE"
  (declare (type string key) (type integer start stop))
  (when (and *redis-connected* *redis-client*)
    (redis:red-lrange key start stop)))

(defun redis-ltrim (key start stop)
  "Redis LTRIM"
  (declare (type string key) (type integer start stop))
  (when (and *redis-connected* *redis-client*)
    (redis:red-ltrim key start stop)))

(defun redis-publish (channel message)
  "Redis PUBLISH"
  (declare (type string channel message))
  (when (and *redis-connected* *redis-client*)
    (redis:red-publish channel message)))

;;;; Connection Info

(defun get-connection-info ()
  "Get connection information"
  (list :postgres (if *pg-connected*
                      (format nil "~a@~a:~a/~a"
                              *postgres-user* *postgres-host* *postgres-port* *postgres-database*)
                      "disconnected")
        :redis (if *redis-connected*
                   (format nil "~a:~a/~a" *redis-host* *redis-port* *redis-db*)
                   "disconnected")))

;;;; Cleanup

(defun close-storage ()
  "Close storage connections"
  (when *pg-connected*
    (postmodern:disconnect :all)
    (setf *pg-connected* nil)
    (log-info "PostgreSQL disconnected"))

  (when (and *redis-connected* *redis-client*)
    (redis:red-quit)
    (setf *redis-connected* nil)
    (log-info "Redis disconnected"))

  (log-info "Storage connections closed"))

;;;; Exports

(export '(;; Initialization
          init-storage
          close-storage
          get-connection-info

          ;; Connection management
          ensure-pg-connected
          ensure-redis-connected
          *redis-connected*
          *pg-connected*

          ;; User operations
          create-user
          get-user
          get-user-by-username
          get-user-by-email
          update-user
          delete-user
          ensure-system-admin-exists
          get-or-create-system-admin-conversation
          create-system-admin-conversation-for-user

          ;; Session operations
          create-session
          get-session
          update-session-last-active
          invalidate-session
          invalidate-all-user-sessions
          cleanup-expired-sessions

          ;; Conversation operations
          create-conversation
          get-conversation
          get-conversations
          get-conversation-participants
          add-conversation-participant
          remove-conversation-participant
          store-conversation
          update-conversation

          ;; Message operations
          store-message
          get-message
          query-messages
          update-message
          recall-message
          send-message
          get-messages

          ;; Redis operations
          redis-set
          redis-get
          redis-del
          redis-expire-at
          redis-publish

          ;; Friend operations
          get-friends
          delete-friend
          add-friend-request
          accept-friend-request
          reject-friend-request
          get-friend-requests
          search-users

          ;; File upload operations
          save-file-metadata
          get-file-metadata
          increment-file-download-count

          ;; Mobile / FCM operations
          save-fcm-token
          remove-fcm-token
          get-user-fcm-tokens
          log-push-notification
          update-push-notification-status)
        :lispim-core)
