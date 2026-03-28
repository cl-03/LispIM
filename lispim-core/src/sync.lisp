;;;; sync.lisp - Client Incremental Sync
;;;;
;;;; Implements incremental synchronization protocol based on sequence numbers
;;;; for efficient offline sync and reduced traffic
;;;;
;;;; Architecture:
;;;; - Sequence-based delta sync
;;;; - Per-user sync anchor tracking
;;;; - Conflict resolution (last-write-wins)
;;;; - Batch fetching with pagination

(in-package :lispim-core)

;;;; Dependencies

(eval-when (:compile-toplevel :load-toplevel :execute)
  (ql:quickload '(:bordeaux-threads :cl-json :postmodern)))

;;;; Sync Configuration

(defparameter *sync-config*
  '((:max-batch-size . 100)       ; Max messages per sync batch
    (:default-batch-size . 50)    ; Default batch size
    (:max-anchor-age . 604800)    ; Max anchor age (7 days in seconds)
    (:conflict-resolution :last-write-wins)) ; Conflict resolution strategy
  "Incremental sync configuration")

;;;; Sync Anchor

(defstruct sync-anchor
  "Sync anchor tracking user's sync position"
  (user-id "" :type string)
  (message-seq 0 :type integer)
  (conversation-seq 0 :type integer)
  (last-sync-at 0 :type integer)
  (device-id "" :type string)
  (updated-at 0 :type integer))

;;;; Sync State

(defvar *sync-anchors* (make-hash-table :test 'equal)
  "In-memory sync anchor cache")
(defvar *sync-anchors-lock* (bordeaux-threads:make-lock "sync-anchors-lock")
  "Sync anchors lock")

;;;; Sequence Number Management

(defun get-next-message-seq ()
  "Get next message sequence number"
  (let ((key "sync:seq:message"))
    (handler-case
        (progn
          (redis:connect :host "localhost" :port 6379)
          (redis:red-incr key))
      (error (c)
        (log-debug "Failed to increment message seq: ~a" c)
        ;; Fallback to snowflake
        (generate-message-id)))))

(defun get-next-conversation-seq ()
  "Get next conversation sequence number"
  (let ((key "sync:seq:conversation"))
    (handler-case
        (progn
          (redis:connect :host "localhost" :port 6379)
          (redis:red-incr key))
      (error (c)
        (log-debug "Failed to increment conversation seq: ~a" c)
        (generate-conversation-id)))))

(defun get-current-message-seq ()
  "Get current max message sequence number"
  (handler-case
      (progn
        (redis:connect :host "localhost" :port 6379)
        (let ((val (redis:red-get "sync:seq:message")))
          (if val (parse-integer val) 0)))
    (error (c)
      (log-debug "Failed to get message seq: ~a" c)
      0)))

;;;; Sync Anchor Operations

(defun get-sync-anchor (user-id &optional (device-id "default"))
  "Get sync anchor for user"
  (declare (type string user-id device-id))
  (let ((key (format nil "~a:~a" user-id device-id)))
    (bordeaux-threads:with-lock-held ((*sync-anchors-lock*))
      (or (gethash key *sync-anchors*)
          (load-sync-anchor-from-db user-id device-id)))))

(defun set-sync-anchor (user-id message-seq conversation-seq &key (device-id "default"))
  "Set sync anchor for user"
  (declare (type string user-id device-id)
           (type integer message-seq conversation-seq))
  (let ((key (format nil "~a:~a" user-id device-id))
        (anchor (make-sync-anchor
                 :user-id user-id
                 :message-seq message-seq
                 :conversation-seq conversation-seq
                 :last-sync-at (get-universal-time)
                 :device-id device-id
                 :updated-at (get-universal-time))))
    (bordeaux-threads:with-lock-held ((*sync-anchors-lock*))
      (setf (gethash key *sync-anchors*) anchor)
      (save-sync-anchor-to-db anchor)
      anchor)))

(defun load-sync-anchor-from-db (user-id &optional (device-id "default"))
  "Load sync anchor from database"
  (declare (type string user-id device-id))
  (handler-case
      (let ((result (postmodern:query
                     "SELECT message_seq, conversation_seq, last_sync_at FROM sync_anchors
                      WHERE user_id = :user-id AND device_id = :device-id"
                     :user-id user-id :device-id device-id :alists t)))
        (if (and result (> (length result) 0))
            (let ((row (first result)))
              (make-sync-anchor
               :user-id user-id
               :message-seq (getf row :message-seq 0)
               :conversation-seq (getf row :conversation-seq 0)
               :last-sync-at (getf row :last-sync-at 0)
               :device-id device-id
               :updated-at (get-universal-time)))
            ;; No anchor found, create new
            (make-sync-anchor
             :user-id user-id
             :message-seq 0
             :conversation-seq 0
             :last-sync-at 0
             :device-id device-id
             :updated-at (get-universal-time))))
    (error (c)
      (log-debug "Failed to load sync anchor: ~a" c)
      (make-sync-anchor
       :user-id user-id
       :message-seq 0
       :conversation-seq 0
       :device-id device-id
       :updated-at (get-universal-time)))))

(defun save-sync-anchor-to-db (anchor)
  "Save sync anchor to database"
  (declare (type sync-anchor anchor))
  (handler-case
      (postmodern:query
       "INSERT INTO sync_anchors (user_id, device_id, message_seq, conversation_seq, last_sync_at)
        VALUES (:user-id, :device-id, :message-seq, :conversation-seq, :last-sync-at)
        ON CONFLICT (user_id, device_id) DO UPDATE
        SET message_seq = :message-seq,
            conversation_seq = :conversation-seq,
            last_sync_at = :last-sync-at"
       :user-id (sync-anchor-user-id anchor)
       :device-id (sync-anchor-device-id anchor)
       :message-seq (sync-anchor-message-seq anchor)
       :conversation-seq (sync-anchor-conversation-seq anchor)
       :last-sync-at (sync-anchor-last-sync-at anchor))
    (error (c)
      (log-error "Failed to save sync anchor: ~a" c))))

;;;; Incremental Sync API

(defun sync-messages (user-id anchor-seq &key (batch-size 50) device-id conversation-id)
  "Get messages incrementally since anchor"
  (declare (type string user-id)
           (type integer anchor-seq)
           (type integer batch-size)
           (type string device-id)
           (type (or null integer) conversation-id))
  (let ((limit (min batch-size (cdr (assoc :max-batch-size *sync-config*)))))
    (handler-case
        (let* ((query
                (if conversation-id
                    ;; Sync specific conversation
                    "SELECT m.*, mc.seq as msg_seq
                     FROM messages m
                     JOIN message_conversations mc ON m.id = mc.message_id
                     WHERE mc.conversation_id = :conv-id
                       AND mc.seq > :anchor-seq
                       AND (m.sender_id = :user-id OR m.recipient_id = :user-id)
                     ORDER BY mc.seq ASC
                     LIMIT :limit"
                    ;; Sync all messages
                    "SELECT m.*, mc.seq as msg_seq
                     FROM messages m
                     JOIN message_conversations mc ON m.id = mc.message_id
                     WHERE (m.sender_id = :user-id OR m.recipient_id = :user-id)
                       AND mc.seq > :anchor-seq
                     ORDER BY mc.seq ASC
                     LIMIT :limit"))
               (results (postmodern:query query
                              :user-id user-id
                              :anchor-seq anchor-seq
                              :conv-id (or conversation-id 0)
                              :limit limit
                              :alists t))
               (messages (mapcar #'row-to-message results))
               (max-seq (if results
                            (reduce #'max messages
                                    :key (lambda (m)
                                           (cdr (assoc :msg-seq (postmodern:query
                                                                 "SELECT seq FROM message_conversations WHERE message_id = :id"
                                                                 :id (message-id m)
                                                                 :alists t))))
                                    :initial-value anchor-seq)
                            anchor-seq)))
          ;; Update sync anchor
          (when (> max-seq anchor-seq)
            (set-sync-anchor user-id max-seq
                             (sync-anchor-conversation-seq
                              (get-sync-anchor user-id device-id))
                             :device-id device-id))
          (list :messages messages
                :new-anchor max-seq
                :has-more (= (length messages) limit)
                :synced-at (get-universal-time)))
      (error (c)
        (log-error "Sync messages failed: ~a" c)
        (list :error (format nil "Sync failed: ~a" c)
              :messages nil
              :new-anchor anchor-seq
              :has-more nil)))))

(defun sync-conversations (user-id anchor-seq &key (batch-size 50) device-id)
  "Get conversations incrementally since anchor"
  (declare (type string user-id)
           (type integer anchor-seq)
           (type integer batch-size)
           (type string device-id))
  (let ((limit (min batch-size (cdr (assoc :max-batch-size *sync-config*)))))
    (handler-case
        (let* ((query
                "SELECT c.*, cc.seq as conv_seq
                 FROM conversations c
                 JOIN conversation_changes cc ON c.id = cc.conversation_id
                 WHERE cc.user_id = :user-id
                   AND cc.seq > :anchor-seq
                 ORDER BY cc.seq ASC
                 LIMIT :limit")
               (results (postmodern:query query
                              :user-id user-id
                              :anchor-seq anchor-seq
                              :limit limit
                              :alists t))
               (conversations (mapcar #'row-to-conversation results))
               (max-seq (if results
                            (reduce #'max results :key #'cdr :initial-value anchor-seq)
                            anchor-seq)))
          ;; Update sync anchor
          (when (> max-seq anchor-seq)
            (set-sync-anchor user-id
                             (sync-anchor-message-seq
                              (get-sync-anchor user-id device-id))
                             max-seq
                             :device-id device-id))
          (list :conversations conversations
                :new-anchor max-seq
                :has-more (= (length conversations) limit)
                :synced-at (get-universal-time)))
      (error (c)
        (log-error "Sync conversations failed: ~a" c)
        (list :error (format nil "Sync failed: ~a" c)
              :conversations nil
              :new-anchor anchor-seq
              :has-more nil)))))

;;;; Full Sync (for new devices or expired anchor)

(defun full-sync (user-id &key (batch-size 100) device-id)
  "Perform full sync for user (new device or expired anchor)"
  (declare (type string user-id)
           (type integer batch-size)
           (type string device-id))
  (log-info "Full sync for user ~a (device: ~a)" user-id device-id)
  (handler-case
      (progn
        ;; Get all conversations for user
        (let ((conversations (get-conversations user-id))
              (message-seq (get-current-message-seq)))
          ;; Update anchor to current
          (set-sync-anchor user-id message-seq 0 :device-id device-id)
          (list :conversations conversations
                :new-anchor message-seq
                :full-sync t
                :synced-at (get-universal-time))))
    (error (c)
      (log-error "Full sync failed: ~a" c)
      (list :error (format nil "Full sync failed: ~a" c)
            :conversations nil
            :full-sync t))))

;;;; Sync Request Handler

(defun handle-sync-request (request-data)
  "Handle client sync request"
  (declare (type list request-data))
  (let* ((user-id (getf request-data :user-id))
         (device-id (getf request-data :device-id "default"))
         (sync-type (getf request-data :type :messages))
         (anchor (getf request-data :anchor 0))
         (batch-size (getf request-data :batch-size
                           (cdr (assoc :default-batch-size *sync-config*))))
         (conversation-id (getf request-data :conversation-id)))
    (cond
      ;; Check if full sync needed
      ((or (zerop anchor)
           (anchor-expired-p user-id anchor))
       (full-sync user-id :batch-size batch-size :device-id device-id))
      ;; Incremental sync
      ((eq sync-type :conversations)
       (sync-conversations user-id anchor :batch-size batch-size :device-id device-id))
      (t
       (sync-messages user-id anchor :batch-size batch-size
                      :device-id device-id :conversation-id conversation-id)))))

(defun anchor-expired-p (user-id anchor)
  "Check if sync anchor is expired"
  (declare (type string user-id)
           (type integer anchor))
  (let ((anchor-obj (get-sync-anchor user-id)))
    (if anchor-obj
        (> (- (get-universal-time) (sync-anchor-last-sync-at anchor-obj))
           (cdr (assoc :max-anchor-age *sync-config*)))
        t)))

;;;; Conflict Resolution

(defun resolve-sync-conflict (local-message remote-message)
  "Resolve conflict between local and remote message"
  (declare (type list local-message remote-message))
  (let ((strategy (cdr (assoc :conflict-resolution *sync-config*))))
    (case strategy
      (:last-write-wins
       ;; Compare timestamps, newer wins
       (let ((local-time (cdr (assoc :created-at local-message)))
             (remote-time (cdr (assoc :created-at remote-message))))
         (if (>= local-time remote-time)
             local-message
             remote-message)))
      (:server-wins
       ;; Server always wins
       remote-message)
      (:client-wins
       ;; Client always wins
       local-message)
      (t
       ;; Default: last-write-wins
       (resolve-sync-conflict local-message remote-message)))))

;;;; Helper Functions

(defun row-to-message (row)
  "Convert database row to message plist"
  (list :id (getf row :id)
        :conversation-id (getf row :conversation-id)
        :sender-id (getf row :sender-id)
        :content (getf row :content)
        :message-type (getf row :message-type)
        :created-at (getf row :created-at)
        :seq (getf row :msg-seq)))

(defun row-to-conversation (row)
  "Convert database row to conversation plist"
  (list :id (getf row :id)
        :name (getf row :name)
        :type (getf row :type)
        :participants (getf row :participants)
        :last-message-id (getf row :last-message-id)
        :updated-at (getf row :updated-at)
        :seq (getf row :conv-seq)))

;;;; Database Migration

(defun ensure-sync-anchors-table ()
  "Ensure sync_anchors table exists"
  (handler-case
      (postmodern:query
       "CREATE TABLE IF NOT EXISTS sync_anchors (
          id SERIAL PRIMARY KEY,
          user_id VARCHAR(255) NOT NULL,
          device_id VARCHAR(255) NOT NULL DEFAULT 'default',
          message_seq BIGINT NOT NULL DEFAULT 0,
          conversation_seq BIGINT NOT NULL DEFAULT 0,
          last_sync_at BIGINT NOT NULL DEFAULT 0,
          updated_at BIGINT NOT NULL DEFAULT 0,
          UNIQUE (user_id, device_id)
        )")
    (error (c)
      (log-error "Failed to create sync_anchors table: ~a" c))))

(defun init-sync ()
  "Initialize sync module"
  (ensure-sync-anchors-table)
  (log-info "Sync module initialized"))

;;;; Statistics

(defvar *sync-stats* (list :total-syncs 0 :incremental-syncs 0 :full-syncs 0 :errors 0)
  "Sync statistics")
(defvar *sync-stats-lock* (bordeaux-threads:make-lock "sync-stats-lock")
  "Sync stats lock")

(defun record-sync (sync-type success-p)
  "Record sync statistics"
  (declare (type keyword sync-type)
           (type boolean success-p))
  (bordeaux-threads:with-lock-held ((*sync-stats-lock*))
    (incf (getf *sync-stats* :total-syncs))
    (cond
      ((eq sync-type :incremental)
       (incf (getf *sync-stats* :incremental-syncs)))
      ((eq sync-type :full)
       (incf (getf *sync-stats* :full-syncs))))
    (unless success-p
      (incf (getf *sync-stats* :errors)))))

(defun get-sync-stats ()
  "Get sync statistics"
  (bordeaux-threads:with-lock-held ((*sync-stats-lock*))
    *sync-stats*))

;;;; Exports

(export '(;; Sync configuration
          *sync-config*
          ;; Sync anchor
          sync-anchor
          make-sync-anchor
          get-sync-anchor
          set-sync-anchor
          ;; Incremental sync
          sync-messages
          sync-conversations
          full-sync
          handle-sync-request
          ;; Conflict resolution
          resolve-sync-conflict
          ;; Initialization
          init-sync
          ensure-sync-anchors-table
          ;; Statistics
          get-sync-stats
          record-sync
          *sync-stats*)
        :lispim-core)
