;;;; contact.lisp - Contact Management Module
;;;;
;;;; Provides advanced contact management features
;;;; Features: groups, tags, remarks, blacklist, star contacts

(in-package :lispim-core)

;;;; Dependencies

(eval-when (:compile-toplevel :load-toplevel :execute)
  (ql:quickload '(:postmodern :cl-redis :cl-json :bordeaux-threads :uuid)))

;;;; Configuration

(defparameter *max-groups-per-user* 50
  "Maximum number of groups per user")

(defparameter *max-tags-per-contact* 10
  "Maximum number of tags per contact")

;;;; Data Structures

(defstruct contact-group
  "Contact group structure"
  (id 0 :type integer)
  (user-id "" :type string)
  (name "" :type string)
  (order 0 :type integer)
  (created-at 0 :type integer)
  (member-count 0 :type integer))

(defstruct contact-tag
  "Contact tag structure"
  (id 0 :type integer)
  (user-id "" :type string)
  (name "" :type string)
  (color "" :type string)
  (created-at 0 :type integer))

(defstruct contact-remark
  "Contact remark structure"
  (user-id "" :type string)
  (friend-id "" :type string)
  (remark "" :type string)
  (description "" :type string)
  (phone "" :type string)
  (email "" :type string)
  (birthday "")
  (company "")
  (updated-at 0 :type integer))

;;;; Database Operations

(defun ensure-contacts-tables-exist ()
  "Create contact management tables if not exists"
  (ensure-pg-connected)

  ;; Contact groups table
  (postmodern:query
   "CREATE TABLE IF NOT EXISTS contact_groups (
      id BIGSERIAL PRIMARY KEY,
      user_id VARCHAR(255) NOT NULL,
      name VARCHAR(100) NOT NULL,
      sort_order INTEGER DEFAULT 0,
      created_at TIMESTAMPTZ DEFAULT NOW(),
      UNIQUE(user_id, name)
    )")
  (postmodern:query
   "CREATE INDEX IF NOT EXISTS idx_contact_groups_user ON contact_groups(user_id)")

  ;; Contact tags table
  (postmodern:query
   "CREATE TABLE IF NOT EXISTS contact_tags (
      id BIGSERIAL PRIMARY KEY,
      user_id VARCHAR(255) NOT NULL,
      name VARCHAR(50) NOT NULL,
      color VARCHAR(20) DEFAULT '#3B82F6',
      created_at TIMESTAMPTZ DEFAULT NOW(),
      UNIQUE(user_id, name)
    )")
  (postmodern:query
   "CREATE INDEX IF NOT EXISTS idx_contact_tags_user ON contact_tags(user_id)")

  ;; Friend groups mapping table
  (postmodern:query
   "CREATE TABLE IF NOT EXISTS friend_groups (
      user_id VARCHAR(255) NOT NULL,
      friend_id VARCHAR(255) NOT NULL,
      group_id BIGINT REFERENCES contact_groups(id) ON DELETE CASCADE,
      created_at TIMESTAMPTZ DEFAULT NOW(),
      PRIMARY KEY (user_id, friend_id, group_id)
    )")
  (postmodern:query
   "CREATE INDEX IF NOT EXISTS idx_friend_groups_user ON friend_groups(user_id)")
  (postmodern:query
   "CREATE INDEX IF NOT EXISTS idx_friend_groups_friend ON friend_groups(friend_id)")

  ;; Friend tags mapping table
  (postmodern:query
   "CREATE TABLE IF NOT EXISTS friend_tags (
      user_id VARCHAR(255) NOT NULL,
      friend_id VARCHAR(255) NOT NULL,
      tag_id BIGINT REFERENCES contact_tags(id) ON DELETE CASCADE,
      created_at TIMESTAMPTZ DEFAULT NOW(),
      PRIMARY KEY (user_id, friend_id, tag_id)
    )")
  (postmodern:query
   "CREATE INDEX IF NOT EXISTS idx_friend_tags_user ON friend_tags(user_id)")
  (postmodern:query
   "CREATE INDEX IF NOT EXISTS idx_friend_tags_friend ON friend_tags(friend_id)")

  ;; Contact remarks table
  (postmodern:query
   "CREATE TABLE IF NOT EXISTS contact_remarks (
      user_id VARCHAR(255) NOT NULL,
      friend_id VARCHAR(255) NOT NULL,
      remark VARCHAR(100),
      description TEXT,
      phone VARCHAR(50),
      email VARCHAR(100),
      birthday DATE,
      company VARCHAR(200),
      updated_at TIMESTAMPTZ DEFAULT NOW(),
      PRIMARY KEY (user_id, friend_id)
    )")
  (postmodern:query
   "CREATE INDEX IF NOT EXISTS idx_contact_remarks_user ON contact_remarks(user_id)")

  ;; Blacklist table
  (postmodern:query
   "CREATE TABLE IF NOT EXISTS contact_blacklist (
      user_id VARCHAR(255) NOT NULL,
      blocked_id VARCHAR(255) NOT NULL,
      created_at TIMESTAMPTZ DEFAULT NOW(),
      PRIMARY KEY (user_id, blocked_id)
    )")
  (postmodern:query
   "CREATE INDEX IF NOT EXISTS idx_contact_blacklist_user ON contact_blacklist(user_id)")

  ;; Star contacts table
  (postmodern:query
   "CREATE TABLE IF NOT EXISTS contact_stars (
      user_id VARCHAR(255) NOT NULL,
      friend_id VARCHAR(255) NOT NULL,
      created_at TIMESTAMPTZ DEFAULT NOW(),
      PRIMARY KEY (user_id, friend_id)
    )")
  (postmodern:query
   "CREATE INDEX IF NOT EXISTS idx_contact_stars_user ON contact_stars(user_id)")

  (log-info "Contact management tables created"))

;;;; Group Operations

(defun create-contact-group (user-id name &optional (order 0))
  "Create a new contact group"
  (declare (type string user-id name)
           (type integer order))

  ;; Check group limit
  (let ((count (get-user-groups-count user-id)))
    (when (>= count *max-groups-per-user*)
      (return-from create-contact-group (values nil (format nil "Maximum ~a groups allowed" *max-groups-per-user*)))))

  (handler-case
      (let ((result (postmodern:query
                     "INSERT INTO contact_groups (user_id, name, sort_order)
                      VALUES ($1, $2, $3) RETURNING id"
                     user-id name order :alists)))
        (if result
            (let ((id (cdr (assoc :|id| result))))
              (log-info "Created group ~a for user ~a" id user-id)
              (values id nil))
            (values nil "Failed to create group")))
    (error (c)
      (values nil (format nil "Error: ~a" c)))))

(defun get-contact-groups (user-id)
  "Get all contact groups for user"
  (declare (type string user-id))

  (let ((result (postmodern:query
                 "SELECT g.*, COUNT(fg.friend_id) as member_count
                  FROM contact_groups g
                  LEFT JOIN friend_groups fg ON g.id = fg.group_id
                  WHERE g.user_id = $1
                  GROUP BY g.id
                  ORDER BY g.sort_order, g.created_at"
                 user-id :alists)))

    (when result
      (loop for row in result
            collect
            (list :id (cdr (assoc :|id| row))
                  :name (cdr (assoc :|name| row))
                  :order (cdr (assoc :|sort_order| row))
                  :created-at (storage-universal-to-unix (cdr (assoc :|created_at| row)))
                  :member-count (or (cdr (assoc :|member_count| row)) 0))))))

(defun update-contact-group (group-id user-id new-name &optional (new-order nil))
  "Update contact group"
  (declare (type integer group-id)
           (type string user-id new-name))

  (handler-case
      (progn
        (if new-order
            (postmodern:query
             "UPDATE contact_groups SET name = $1, sort_order = $2
              WHERE id = $3 AND user_id = $4"
             new-name new-order group-id user-id)
            (postmodern:query
             "UPDATE contact_groups SET name = $1
              WHERE id = $2 AND user_id = $3"
             new-name group-id user-id))
        (values t nil))
    (error (c)
      (values nil (format nil "Error: ~a" c)))))

(defun delete-contact-group (group-id user-id)
  "Delete contact group"
  (declare (type integer group-id)
           (type string user-id))

  (handlercase
      (progn
        (postmodern:query
         "DELETE FROM contact_groups WHERE id = $1 AND user_id = $2"
         group-id user-id)
        (values t nil))
    (error (c)
      (values nil (format nil "Error: ~a" c)))))

(defun add-friend-to-group (user-id friend-id group-id)
  "Add friend to group"
  (declare (type string user-id friend-id)
           (type integer group-id))

  (handler-case
      (progn
        (postmodern:query
         "INSERT INTO friend_groups (user_id, friend_id, group_id)
          VALUES ($1, $2, $3)
          ON CONFLICT (user_id, friend_id, group_id) DO NOTHING"
         user-id friend-id group-id)
        (values t nil))
    (error (c)
      (values nil (format nil "Error: ~a" c)))))

(defun remove-friend-from-group (user-id friend-id group-id)
  "Remove friend from group"
  (declare (type string user-id friend-id)
           (type integer group-id))

  (postmodern:query
   "DELETE FROM friend_groups
    WHERE user_id = $1 AND friend_id = $2 AND group_id = $3"
   user-id friend-id group-id)

  (values t nil))

(defun get-friend-groups (user-id friend-id)
  "Get groups for a specific friend"
  (declare (type string user-id friend-id))

  (let ((result (postmodern:query
                 "SELECT g.* FROM contact_groups g
                  JOIN friend_groups fg ON g.id = fg.group_id
                  WHERE g.user_id = $1 AND fg.friend_id = $2
                  ORDER BY g.sort_order"
                 user-id friend-id :alists)))

    (when result
      (loop for row in result
            collect
            (list :id (cdr (assoc :|id| row))
                  :name (cdr (assoc :|name| row))
                  :order (cdr (assoc :|sort_order| row)))))))

(defun get-group-members (user-id group-id)
  "Get all friends in a group"
  (declare (type string user-id)
           (type integer group-id))

  (let ((result (postmodern:query
                 "SELECT f.friend_id, u.username, u.display_name, u.avatar_url,
                         f.created_at
                  FROM friend_groups f
                  JOIN users u ON f.friend_id = u.id
                  WHERE f.user_id = $1 AND f.group_id = $2
                  ORDER BY u.display_name"
                 user-id group-id :alists)))

    (when result
      (loop for row in result
            collect
            (list :user-id (cdr (assoc :|friend_id| row))
                  :username (cdr (assoc :|username| row))
                  :display-name (cdr (assoc :|display_name| row))
                  :avatar (cdr (assoc :|avatar_url| row))
                  :added-at (storage-universal-to-unix (cdr (assoc :|created_at| row))))))))

(defun get-user-groups-count (user-id)
  "Get count of groups for user"
  (declare (type string user-id))

  (let ((result (postmodern:query
                 "SELECT COUNT(*) FROM contact_groups WHERE user_id = $1"
                 user-id)))
    (if result
        (parse-integer (svref (car result) 0))
        0)))

;;;; Tag Operations

(defun create-contact-tag (user-id name &optional (color "#3B82F6"))
  "Create a new contact tag"
  (declare (type string user-id name color))

  (handler-case
      (let ((result (postmodern:query
                     "INSERT INTO contact_tags (user_id, name, color)
                      VALUES ($1, $2, $3) RETURNING id"
                     user-id name color :alists)))
        (if result
            (let ((id (cdr (assoc :|id| result))))
              (log-info "Created tag ~a for user ~a" id user-id)
              (values id nil))
            (values nil "Failed to create tag")))
    (error (c)
      (values nil (format nil "Error: ~a" c)))))

(defun get-contact-tags (user-id)
  "Get all contact tags for user"
  (declare (type string user-id))

  (let ((result (postmodern:query
                 "SELECT t.*, COUNT(ft.friend_id) as usage_count
                  FROM contact_tags t
                  LEFT JOIN friend_tags ft ON t.id = ft.tag_id
                  WHERE t.user_id = $1
                  GROUP BY t.id
                  ORDER BY t.created_at"
                 user-id :alists)))

    (when result
      (loop for row in result
            collect
            (list :id (cdr (assoc :|id| row))
                  :name (cdr (assoc :|name| row))
                  :color (cdr (assoc :|color| row))
                  :usage-count (or (cdr (assoc :|usage_count| row)) 0))))))

(defun update-contact-tag (tag-id user-id new-name &optional (new-color nil))
  "Update contact tag"
  (declare (type integer tag-id)
           (type string user-id new-name))

  (handler-case
      (progn
        (if new-color
            (postmodern:query
             "UPDATE contact_tags SET name = $1, color = $2
              WHERE id = $3 AND user_id = $4"
             new-name new-color tag-id user-id)
            (postmodern:query
             "UPDATE contact_tags SET name = $1
              WHERE id = $2 AND user_id = $3"
             new-name tag-id user-id))
        (values t nil))
    (error (c)
      (values nil (format nil "Error: ~a" c)))))

(defun delete-contact-tag (tag-id user-id)
  "Delete contact tag"
  (declare (type integer tag-id)
           (type string user-id))

  (postmodern:query
   "DELETE FROM contact_tags WHERE id = $1 AND user_id = $2"
   tag-id user-id)

  (values t nil))

(defun add-tag-to-friend (user-id friend-id tag-id)
  "Add tag to friend"
  (declare (type string user-id friend-id)
           (type integer tag-id))

  (handler-case
      (progn
        (postmodern:query
         "INSERT INTO friend_tags (user_id, friend_id, tag_id)
          VALUES ($1, $2, $3)
          ON CONFLICT (user_id, friend_id, tag_id) DO NOTHING"
         user-id friend-id tag-id)
        (values t nil))
    (error (c)
      (values nil (format nil "Error: ~a" c)))))

(defun remove-tag-from-friend (user-id friend-id tag-id)
  "Remove tag from friend"
  (declare (type string user-id friend-id)
           (type integer tag-id))

  (postmodern:query
   "DELETE FROM friend_tags
    WHERE user_id = $1 AND friend_id = $2 AND tag_id = $3"
   user-id friend-id tag-id)

  (values t nil))

(defun get-friend-tags (user-id friend-id)
  "Get tags for a specific friend"
  (declare (type string user-id friend-id))

  (let ((result (postmodern:query
                 "SELECT t.* FROM contact_tags t
                  JOIN friend_tags ft ON t.id = ft.tag_id
                  WHERE t.user_id = $1 AND ft.friend_id = $2"
                 user-id friend-id :alists)))

    (when result
      (loop for row in result
            collect
            (list :id (cdr (assoc :|id| row))
                  :name (cdr (assoc :|name| row))
                  :color (cdr (assoc :|color| row)))))))

;;;; Remark Operations

(defun set-contact-remark (user-id friend-id remark &key description phone email birthday company)
  "Set remark and details for a contact"
  (declare (type string user-id friend-id)
           (type (or string null) remark description phone email birthday company))

  (let ((now (get-universal-time)))
    (postmodern:query
     "INSERT INTO contact_remarks
      (user_id, friend_id, remark, description, phone, email, birthday, company, updated_at)
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, to_timestamp($9))
      ON CONFLICT (user_id, friend_id) DO UPDATE
      SET remark = EXCLUDED.remark,
          description = EXCLUDED.description,
          phone = EXCLUDED.phone,
          email = EXCLUDED.email,
          birthday = EXCLUDED.birthday,
          company = EXCLUDED.company,
          updated_at = to_timestamp($9)"
     user-id friend-id
     (or remark "")
     (or description "")
     (or phone "")
     (or email "")
     birthday
     (or company "")
     now))

  (log-info "Set remark for friend ~a by user ~a" friend-id user-id)
  (values t nil))

(defun get-contact-remark (user-id friend-id)
  "Get remark for a contact"
  (declare (type string user-id friend-id))

  (let ((result (postmodern:query
                 "SELECT * FROM contact_remarks
                  WHERE user_id = $1 AND friend_id = $2"
                 user-id friend-id :alists)))

    (when result
      (let ((row (car result)))
        (flet ((get-val (name)
                 (let ((cell (find name row :key #'car :test #'string=)))
                   (when cell (cdr cell)))))
          (list :remark (get-val "REMARK")
                :description (get-val "DESCRIPTION")
                :phone (get-val "PHONE")
                :email (get-val "EMAIL")
                :birthday (get-val "BIRTHDAY")
                :company (get-val "COMPANY")
                :updated-at (storage-universal-to-unix (get-val "UPDATED-AT"))))))))

;;;; Blacklist Operations

(defun add-to-blacklist (user-id blocked-id)
  "Add user to blacklist"
  (declare (type string user-id blocked-id))

  (handler-case
      (progn
        (postmodern:query
         "INSERT INTO contact_blacklist (user_id, blocked_id)
          VALUES ($1, $2)
          ON CONFLICT (user_id, blocked_id) DO NOTHING")
        (values t nil))
    (error (c)
      (values nil (format nil "Error: ~a" c)))))

(defun remove-from-blacklist (user-id blocked-id)
  "Remove user from blacklist"
  (declare (type string user-id blocked-id))

  (postmodern:query
   "DELETE FROM contact_blacklist
    WHERE user_id = $1 AND blocked_id = $2"
   user-id blocked-id)

  (values t nil))

(defun get-blacklist (user-id)
  "Get blacklist for user"
  (declare (type string user-id))

  (let ((result (postmodern:query
                 "SELECT b.blocked_id, u.username, u.display_name, u.avatar_url,
                         b.created_at
                  FROM contact_blacklist b
                  JOIN users u ON b.blocked_id = u.id
                  WHERE b.user_id = $1
                  ORDER BY b.created_at DESC"
                 user-id :alists)))

    (when result
      (loop for row in result
            collect
            (list :user-id (cdr (assoc :|blocked_id| row))
                  :username (cdr (assoc :|username| row))
                  :display-name (cdr (assoc :|display_name| row))
                  :avatar (cdr (assoc :|avatar_url| row))
                  :blocked-at (storage-universal-to-unix (cdr (assoc :|created_at| row))))))))

(defun is-blocked (user-id blocked-id)
  "Check if user is blocked"
  (declare (type string user-id blocked-id))

  (let ((result (postmodern:query
                 "SELECT 1 FROM contact_blacklist
                  WHERE user_id = $1 AND blocked_id = $2"
                 user-id blocked-id)))
    (and result (> (length result) 0))))

;;;; Star Contact Operations

(defun add-star-contact (user-id friend-id)
  "Add contact to starred list"
  (declare (type string user-id friend-id))

  (handler-case
      (progn
        (postmodern:query
         "INSERT INTO contact_stars (user_id, friend_id)
          VALUES ($1, $2)
          ON CONFLICT (user_id, friend_id) DO NOTHING")
        (values t nil))
    (error (c)
      (values nil (format nil "Error: ~a" c)))))

(defun remove-star-contact (user-id friend-id)
  "Remove contact from starred list"
  (declare (type string user-id friend-id))

  (postmodern:query
   "DELETE FROM contact_stars
    WHERE user_id = $1 AND friend_id = $2"
   user-id friend-id)

  (values t nil))

(defun get-star-contacts (user-id)
  "Get starred contacts"
  (declare (type string user-id))

  (let ((result (postmodern:query
                 "SELECT s.friend_id, u.username, u.display_name, u.avatar_url,
                         s.created_at
                  FROM contact_stars s
                  JOIN users u ON s.friend_id = u.id
                  WHERE s.user_id = $1
                  ORDER BY s.created_at DESC"
                 user-id :alists)))

    (when result
      (loop for row in result
            collect
            (list :user-id (cdr (assoc :|friend_id| row))
                  :username (cdr (assoc :|username| row))
                  :display-name (cdr (assoc :|display_name| row))
                  :avatar (cdr (assoc :|avatar_url| row))
                  :starred-at (storage-universal-to-unix (cdr (assoc :|created_at| row))))))))

(defun is-star-contact (user-id friend-id)
  "Check if contact is starred"
  (declare (type string user-id friend-id))

  (let ((result (postmodern:query
                 "SELECT 1 FROM contact_stars
                  WHERE user_id = $1 AND friend_id = $2"
                 user-id friend-id)))
    (and result (> (length result) 0))))

;;;; Search Operations

(defun search-contacts (user-id query &key (limit 20))
  "Search contacts by remark, username, or display name"
  (declare (type string user-id query)
           (type integer limit))

  (let ((search-pattern (format nil "%~a%" query))
        (result (postmodern:query
                 "SELECT DISTINCT f.friend_id,
                         COALESCE(r.remark, u.display_name, u.username) as display_name,
                         u.username,
                         u.avatar_url,
                         u.status
                  FROM friends f
                  JOIN users u ON f.friend_id = u.id
                  LEFT JOIN contact_remarks r ON f.user_id = r.user_id AND f.friend_id = r.friend_id
                  WHERE f.user_id = $1
                    AND f.status = 'accepted'
                    AND (
                      r.remark ILIKE $2 OR
                      u.display_name ILIKE $2 OR
                      u.username ILIKE $2
                    )
                  LIMIT $3"
                 user-id search-pattern limit :alists)))

    (when result
      (loop for row in result
            collect
            (list :user-id (cdr (assoc :|friend_id| row))
                  :display-name (cdr (assoc :|display_name| row))
                  :username (cdr (assoc :|username| row))
                  :avatar (cdr (assoc :|avatar_url| row))
                  :status (cdr (assoc :|status| row)))))))

;;;; Export Functions

(export '(ensure-contacts-tables-exist
          create-contact-group
          get-contact-groups
          update-contact-group
          delete-contact-group
          add-friend-to-group
          remove-friend-from-group
          get-friend-groups
          get-group-members
          create-contact-tag
          get-contact-tags
          update-contact-tag
          delete-contact-tag
          add-tag-to-friend
          remove-tag-from-friend
          get-friend-tags
          set-contact-remark
          get-contact-remark
          add-to-blacklist
          remove-from-blacklist
          get-blacklist
          is-blocked
          add-star-contact
          remove-star-contact
          get-star-contacts
          is-star-contact
          search-contacts
          *max-groups-per-user*
          *max-tags-per-contact*))
