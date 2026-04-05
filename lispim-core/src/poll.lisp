;;;; poll.lisp - 群投票模块
;;;;
;;;; 提供以下功能：
;;;; 1. 创建投票
;;;; 2. 投票选项管理
;;;; 3. 投票/取消投票
;;;; 4. 投票结果查询
;;;; 5. 结束投票

(in-package :lispim-core)

;;;; 依赖声明

(eval-when (:compile-toplevel :load-toplevel :execute)
  (ql:quickload '(:postmodern :cl-json)))

;;;; 数据结构

(defstruct group-poll
  "群投票结构"
  (id 0 :type integer)
  (group-id 0 :type integer)
  (created-by "" :type string)
  (title "" :type string)
  (description "" :type string)
  (multiple-choice nil :type boolean)
  (allow-suggestions nil :type boolean)
  (anonymous-voting nil :type boolean)
  (end-at nil :type (or null integer))
  (status :active :type (member :active :ended :archived))
  (created-at 0 :type integer)
  (ended-at nil :type (or null integer)))

(defstruct poll-option
  "投票选项结构"
  (id 0 :type integer)
  (poll-id 0 :type integer)
  (text "" :type string)
  (vote-count 0 :type integer))

(defstruct poll-vote
  "投票记录结构"
  (id 0 :type integer)
  (poll-id 0 :type integer)
  (option-id 0 :type integer)
  (voter-id "" :type string)
  (created-at 0 :type integer))

;;;; 数据库初始化

(defun ensure-poll-tables-exist ()
  "确保投票相关表存在（由 migration 创建）"
  (log-info "Poll tables check completed"))

;;;; 创建投票

(defun create-poll (group-id title created-by &key description multiple-choice allow-suggestions anonymous-voting end-at options)
  "创建新的投票"
  (declare (type integer group-id)
           (type string title created-by)
           (type (or null string) description)
           (type (or null boolean) multiple-choice allow-suggestions anonymous-voting)
           (type (or null integer) end-at)
           (type (or null list) options))
  (ensure-pg-connected)

  (let ((poll-id (postmodern:query
                  "INSERT INTO group_polls
                   (group_id, created_by, title, description, multiple_choice,
                    allow_suggestions, anonymous_voting, end_at, status)
                   VALUES ($1, (SELECT id FROM users WHERE username = $2), $3, $4, $5, $6, $7,
                           NULLIF(to_timestamp($8), 0), 'active')
                   RETURNING id"
                  group-id created-by title
                  (or description "")
                  (if multiple-choice t nil)
                  (if allow-suggestions t nil)
                  (if anonymous-voting t nil)
                  end-at)))
    (when poll-id
      (let ((pid (caar poll-id)))
        ;; 添加选项
        (when options
          (dolist (opt-text options)
            (postmodern:query
             "INSERT INTO poll_options (poll_id, text) VALUES ($1, $2)"
             pid opt-text)))
        ;; 返回投票信息
        (get-poll pid)))))

(defun get-poll (poll-id)
  "获取投票详情"
  (declare (type integer poll-id))
  (ensure-pg-connected)

  (let ((row (postmodern:query
              "SELECT p.id, p.group_id, u.username, p.title, p.description,
                      p.multiple_choice, p.allow_suggestions, p.anonymous_voting,
                      p.end_at, p.status, p.created_at, p.ended_at
               FROM group_polls p
               JOIN users u ON p.created_by = u.id
               WHERE p.id = $1"
              poll-id)))
    (when row
      (let ((r (car row)))
        (list :id (elt r 0)
              :groupId (elt r 1)
              :createdBy (elt r 2)
              :title (elt r 3)
              :description (elt r 4)
              :multipleChoice (elt r 5)
              :allowSuggestions (elt r 6)
              :anonymousVoting (elt r 7)
              :endAt (if (elt r 8) (storage-universal-to-unix-ms (elt r 8)) nil)
              :status (elt r 9)
              :createdAt (storage-universal-to-unix-ms (elt r 10))
              :endedAt (if (elt r 11) (storage-universal-to-unix-ms (elt r 11)) nil)
              :options (get-poll-options pid)
              :results (get-poll-results pid))))))

(defun get-poll-options (poll-id)
  "获取投票选项"
  (declare (type integer poll-id))
  (ensure-pg-connected)

  (let ((rows (postmodern:query
               "SELECT id, text, vote_count FROM poll_options WHERE poll_id = $1 ORDER BY id"
               poll-id)))
    (loop for row in rows
          collect (list :id (elt row 0)
                        :text (elt row 1)
                        :voteCount (elt row 2)))))

(defun get-poll-results (poll-id)
  "获取投票结果（含统计）"
  (declare (type integer poll-id))
  (ensure-pg-connected)

  (let ((rows (postmodern:query
               "SELECT * FROM get_poll_results($1)"
               poll-id)))
    (loop for row in rows
          collect (list :optionId (elt row 0)
                        :text (elt row 1)
                        :voteCount (elt row 2)
                        :percentage (elt row 3)
                        :voters (elt row 4)))))

;;;; 投票操作

(defun cast-vote (poll-id option-id voter-id)
  "投出一票"
  (declare (type integer poll-id option-id)
           (type string voter-id))
  (ensure-pg-connected)

  ;; 检查投票状态
  (let* ((poll (get-poll poll-id)))
    (unless poll
      (error "Poll not found"))
    (unless (string= (getf poll :status) "active")
      (error "Poll is not active")))

  ;; 检查是否已投票
  (let ((existing (postmodern:query
                   "SELECT id FROM poll_votes WHERE poll_id = $1 AND voter_id = (SELECT id FROM users WHERE username = $2)"
                   poll-id voter-id)))
    (when existing
      ;; 如果已投票，先删除原有投票
      (postmodern:query
       "DELETE FROM poll_votes WHERE poll_id = $1 AND voter_id = (SELECT id FROM users WHERE username = $2)"
       poll-id voter-id)
      ;; 重新计算选项票数
      (recalculate-vote-count poll-id)))

  ;; 添加新投票
  (postmodern:query
   "INSERT INTO poll_votes (poll_id, option_id, voter_id)
    VALUES ($1, $2, (SELECT id FROM users WHERE username = $3))"
   poll-id option-id voter-id)

  ;; 更新选项票数
  (postmodern:query
   "UPDATE poll_options SET vote_count = vote_count + 1 WHERE id = $1"
   option-id)

  (log-info "Vote cast: poll=~a, option=~a, voter=~a" poll-id option-id voter-id)
  t)

(defun recalculate-vote-count (poll-id)
  "重新计算选项票数"
  (declare (type integer poll-id))
  (ensure-pg-connected)

  (postmodern:query
   "UPDATE poll_options po
    SET vote_count = (SELECT COUNT(*) FROM poll_votes pv WHERE pv.option_id = po.id)
    WHERE po.poll_id = $1"
   poll-id)
  t)

;;;; 结束投票

(defun end-poll (poll-id user-id)
  "结束投票"
  (declare (type integer poll-id)
           (type string user-id))
  (ensure-pg-connected)

  (let ((result (postmodern:query
                 "SELECT end_poll($1, (SELECT id FROM users WHERE username = $2))"
                 poll-id user-id)))
    (when (caar result)
      (log-info "Poll ~a ended by ~a" poll-id user-id)
      t)))

;;;; 投票查询

(defun get-group-polls (group-id &key (status "active"))
  "获取群聊中的投票列表"
  (declare (type integer group-id)
           (type string status))
  (ensure-pg-connected)

  (let ((rows (postmodern:query
               "SELECT p.id, p.title, p.status, p.created_at, p.end_at,
                       u.username as created_by,
                       (SELECT COUNT(*) FROM poll_votes pv WHERE pv.poll_id = p.id) as vote_count
                FROM group_polls p
                JOIN users u ON p.created_by = u.id
                WHERE p.group_id = $1 AND p.status = $2
                ORDER BY p.created_at DESC"
               group-id status)))
    (loop for row in rows
          collect (list :id (elt row 0)
                        :title (elt row 1)
                        :status (elt row 2)
                        :createdAt (storage-universal-to-unix-ms (elt row 3))
                        :endAt (if (elt row 4) (storage-universal-to-unix-ms (elt row 4)) nil)
                        :createdBy (elt row 5)
                        :voteCount (elt row 6)))))

;;;; 导出

(export '(;; Structures
          group-poll
          make-group-poll
          poll-option
          make-poll-option
          poll-vote
          make-poll-vote
          ;; Database
          ensure-poll-tables-exist
          ;; Create/Edit
          create-poll
          get-poll
          get-poll-options
          get-poll-results
          ;; Vote
          cast-vote
          end-poll
          ;; Query
          get-group-polls
          recalculate-vote-count))
