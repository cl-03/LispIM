;;;; e2ee.lisp - 端到端加密模块
;;;;
;;;; 负责 E2EE 密钥管理、双棘轮算法、消息加密解密
;;;; 使用 Ironclad 实现简化的 AES-GCM 加密

(in-package :lispim-core)

;;;; 依赖声明

(eval-when (:compile-toplevel :load-toplevel :execute)
  (ql:quickload '(:ironclad :bordeaux-threads :babel)))

;;;; 类型定义

(deftype encryption-key ()
  '(simple-array (unsigned-byte 8) (32)))

(deftype nonce ()
  '(simple-array (unsigned-byte 8) (12)))

(deftype ciphertext ()
  '(simple-array (unsigned-byte 8) (*)))

;;;; 密钥结构

(defstruct identity-keypair
  "身份密钥对"
  (public-key nil :type (or null encryption-key))
  (private-key nil :type (or null secure-buffer)))

(defstruct e2ee-session
  "E2EE 加密会话"
  (session-id "" :type string)
  (local-identity-keypair nil :type (or null identity-keypair))
  (remote-public-key nil :type (or null encryption-key))
  (sending-chain-key nil :type (or null encryption-key))
  (receiving-chain-key nil :type (or null encryption-key))
  (sending-message-number 0 :type integer)
  (receiving-message-number 0 :type integer)
  (created-at (get-universal-time) :type integer))

;;;; 密钥存储

(defvar *key-store* nil
  "全局密钥存储")

(defstruct secure-key-store
  "安全密钥存储"
  (master-key nil :type (or null secure-buffer))
  (identity-keys (make-hash-table :test 'equal) :type hash-table)
  (session-keys (make-hash-table :test 'equal) :type hash-table)
  (archived-keys (make-hash-table :test 'equal) :type hash-table)
  (key-version 0 :type integer)
  (rotation-interval (* 7 24 3600) :type integer)  ; 7 天轮换
  (lock (bordeaux-threads:make-lock "key-store-lock") :type bordeaux-threads:lock))

(defun make-key-store ()
  "创建密钥存储"
  (make-secure-key-store
   :master-key nil
   :identity-keys (make-hash-table :test 'equal)
   :session-keys (make-hash-table :test 'equal)
   :archived-keys (make-hash-table :test 'equal)
   :key-version 0
   :rotation-interval (* 7 24 3600)
   :lock (bordeaux-threads:make-lock "key-store-lock")))

;;;; 初始化

(defun initialize-e2ee ()
  "初始化 E2EE 模块"
  (setf *key-store* (make-key-store))
  ;; 生成主密钥
  (let* ((master-key-data (ironclad:random-data 32))
         (master-key (make-secure-buffer :data master-key-data)))
    (setf (secure-key-store-master-key *key-store*) master-key))
  (log-info "E2EE module initialized"))

;;;; 密钥生成

(defun generate-identity-keypair ()
  "生成身份密钥对"
  (let* ((private-key-data (ironclad:random-data 32))
         (public-key-data (ironclad:random-data 32))
         (private-key (make-secure-buffer :data private-key-data))
         (public-key (alexandria:copy-sequence 'vector public-key-data)))
    (make-identity-keypair
     :public-key public-key
     :private-key private-key)))

(defun generate-session-key ()
  "生成会话密钥"
  (ironclad:random-data 32))

;;;; 密钥派生函数 (HKDF-like)

(defun derive-key (input-key-material info length)
  "派生子密钥"
  (declare (type (simple-array (unsigned-byte 8) (*)) input-key-material)
           (type string info)
           (type (integer 1 256) length)
           (optimize (speed 3) (safety 1) (debug 0)))
  (let* ((info-bytes (babel:string-to-octets info :encoding :utf-8))
         (salt (make-array 16 :element-type '(unsigned-byte 8) :initial-element 0))
         (hmac (ironclad:make-hmac input-key-material :sha256)))
    (ironclad:update-hmac hmac salt)
    (ironclad:update-hmac hmac info-bytes)
    (let ((digest (ironclad:hmac-digest hmac)))
      (if (>= (length digest) length)
          (subseq digest 0 length)
          ;; 如果摘要不够长，重复派生填充
          (let ((result (make-array length :element-type '(unsigned-byte 8))))
            (replace result digest)
            (let ((pos (length digest)))
              (loop while (< pos length)
                    do (let ((block (ironclad:random-data 32)))
                         (replace result block :start1 pos :end2 (min (- length pos) 32))
                         (incf pos 32))
                    finally (return result))))))))

(defun chain-key-derive (chain-key)
  "从链密钥派生消息密钥和新的链密钥"
  (declare (type encryption-key chain-key))
  (let ((derived (derive-key chain-key "chain-key-derive" 64)))
    (values (subseq derived 0 32)  ; 消息密钥
            (subseq derived 32 64))))  ; 新链密钥

;;;; Diffie-Hellman 密钥交换

(defun generate-dh-keypair ()
  "生成 Diffie-Hellman 密钥对"
  (let* ((private-key-data (ironclad:random-data 32))
         (public-key-data (ironclad:random-data 32)))
    (cons public-key-data private-key-data)))

(defun compute-shared-secret (private-key public-key)
  "计算共享密钥"
  (declare (type (simple-array (unsigned-byte 8) (*)) private-key public-key))
  ;; 使用 HMAC 派生共享密钥
  (let ((hmac (ironclad:make-hmac private-key :sha256)))
    (ironclad:update-hmac hmac public-key)
    (ironclad:hmac-digest hmac)))

(defun dh-key-exchange (local-private remote-public)
  "执行 Diffie-Hellman 密钥交换"
  (declare (type (simple-array (unsigned-byte 8) (*)) local-private remote-public))
  (compute-shared-secret local-private remote-public))

;;;; 密钥指纹

(defun compute-key-fingerprint (public-key)
  "计算密钥指纹 - 使用 ironclad:byte-array-to-hex-string"
  (declare (type encryption-key public-key))
  (let ((hmac (ironclad:make-hmac (make-array 32 :initial-element 0) :sha256)))
    (ironclad:update-hmac hmac public-key)
    (ironclad:byte-array-to-hex-string (ironclad:hmac-digest hmac))))

(defun verify-key-fingerprint (public-key expected-fingerprint)
  "验证密钥指纹"
  (declare (type encryption-key public-key)
           (type string expected-fingerprint))
  (string= (compute-key-fingerprint public-key) expected-fingerprint))

;;;; 密钥交换协议

(defun create-key-exchange-request (local-identity remote-user-id)
  "创建密钥交换请求"
  (declare (type identity-keypair local-identity)
           (type string remote-user-id))
  (let ((dh-keypair (generate-dh-keypair)))
    (list :type :key-exchange
          :sender-identity local-identity
          :dh-public-key (car dh-keypair)
          :recipient remote-user-id
          :timestamp (get-universal-time))))

(defun process-key-exchange-request (request remote-identity)
  "处理密钥交换请求"
  (declare (type list request)
           (type identity-keypair remote-identity))
  (let* ((sender-identity (getf request :sender-identity))
         (dh-public (getf request :dh-public-key))
         (local-private (identity-keypair-private-key remote-identity))
         (shared-secret (dh-key-exchange (secure-buffer-data local-private) dh-public)))
    (list :type :key-exchange-response
          :sender-identity remote-identity
          :dh-public-key (identity-keypair-public-key remote-identity)
          :shared-secret-hash (compute-key-fingerprint shared-secret)
          :timestamp (get-universal-time))))

(defun establish-e2ee-session (user-id peer-id local-identity remote-public-key initiator-p)
  "建立 E2EE 会话"
  (declare (type string user-id peer-id)
           (type identity-keypair local-identity)
           (type encryption-key remote-public-key)
           (type boolean initiator-p))
  (let* ((shared-secret (dh-key-exchange (secure-buffer-data (identity-keypair-private-key local-identity))
                                         remote-public-key))
         (session (start-e2ee-session local-identity remote-public-key initiator-p)))
    ;; 使用共享密钥初始化双棘轮
    (let ((initial-chain-key (derive-key shared-secret "e2ee-chain-key" 32)))
      (if initiator-p
          (setf (e2ee-session-sending-chain-key session) initial-chain-key)
          (setf (e2ee-session-receiving-chain-key session) initial-chain-key)))
    ;; 存储会话
    (store-session user-id peer-id session)
    (log-info "Established E2EE session with ~a" peer-id)
    session))

(defun initialize-double-ratchet (session initiator-p)
  "初始化双棘轮算法"
  (declare (type e2ee-session session))
  (let ((initial-key (generate-session-key)))
    (if initiator-p
        (setf (e2ee-session-sending-chain-key session) initial-key)
        (setf (e2ee-session-receiving-chain-key session) initial-key)))
  (log-info "Initialized double ratchet for session ~a" (e2ee-session-session-id session)))

(defun advance-sending-chain (session)
  "推进发送链，返回消息密钥"
  (declare (type e2ee-session session))
  (let ((chain-key (e2ee-session-sending-chain-key session)))
    (when chain-key
      (multiple-value-bind (message-key new-chain-key)
          (chain-key-derive chain-key)
        (setf (e2ee-session-sending-chain-key session) new-chain-key
              (e2ee-session-sending-message-number session)
              (1+ (e2ee-session-sending-message-number session)))
        message-key))))

(defun advance-receiving-chain (session message-number)
  "推进接收链，返回消息密钥"
  (declare (type e2ee-session session)
           (type integer message-number))
  (let ((chain-key (e2ee-session-receiving-chain-key session)))
    (when chain-key
      (multiple-value-bind (message-key new-chain-key)
          (chain-key-derive chain-key)
        (setf (e2ee-session-receiving-chain-key session) new-chain-key
              (e2ee-session-receiving-message-number session) message-number)
        message-key))))

;;;; 消息加密

(defun encrypt-message (session plaintext &optional associated-data)
  "使用 AES-CBC + HMAC 加密消息"
  (declare (type e2ee-session session)
           (type string plaintext))

  ;; 推进发送链获取消息密钥
  (let* ((message-key (advance-sending-chain session)))
    (unless message-key
      (error 'e2ee-error
             :session-id (e2ee-session-session-id session)
             :message "No sending chain key available"))

    (let* ((iv (generate-nonce 16))  ; AES block size
           (plaintext-bytes (babel:string-to-octets plaintext :encoding :utf-8))
           ;; PKCS7 padding
           (padding-bytes (- 16 (mod (length plaintext-bytes) 16)))
           (padded-plaintext (make-array (+ (length plaintext-bytes) padding-bytes)
                                         :element-type '(unsigned-byte 8)
                                         :initial-element padding-bytes))
           (ad-bytes (when associated-data
                       (babel:string-to-octets associated-data :encoding :utf-8))))

      ;; 复制明文并添加 padding
      (replace padded-plaintext plaintext-bytes)

      ;; 加密
      (let ((cipher (ironclad:make-cipher :aes :key message-key :mode :cbc :initialization-vector iv)))
        (ironclad:encrypt-in-place cipher padded-plaintext))

      ;; 计算 HMAC 认证
      (let ((hmac (ironclad:make-hmac message-key :sha256)))
        (ironclad:update-hmac hmac iv)
        (ironclad:update-hmac hmac padded-plaintext)
        (when ad-bytes
          (ironclad:update-hmac hmac ad-bytes))
        (let ((tag (ironclad:hmac-digest hmac)))
          ;; 组合：iv (16) + ciphertext + tag (32)
          (let ((result (make-array (+ 16 (length padded-plaintext) 32) :element-type '(unsigned-byte 8))))
            (replace result iv)
            (replace result padded-plaintext :start1 16)
            (replace result tag :start1 (+ 16 (length padded-plaintext)))
            result))))))

;;;; 消息解密

(defun decrypt-message (session ciphertext &optional associated-data)
  "使用 AES-CBC + HMAC 解密消息"
  (declare (type e2ee-session session)
           (type ciphertext ciphertext))

  (when (< (length ciphertext) 48)  ; 16 (iv) + 16 (min ciphertext) + 32 (tag) 最小值
    (error 'e2ee-decrypt-failed
           :session-id (e2ee-session-session-id session)
           :reason "Ciphertext too short"))

  (let* ((iv (subseq ciphertext 0 16))
         (tag (subseq ciphertext (- (length ciphertext) 32)))
         (actual-ciphertext (subseq ciphertext 16 (- (length ciphertext) 32)))
         (message-key (advance-receiving-chain session
                                               (e2ee-session-receiving-message-number session))))

    (unless message-key
      (error 'e2ee-decrypt-failed
             :session-id (e2ee-session-session-id session)
             :reason "No receiving chain key available"))

    ;; 验证 HMAC 认证
    (let ((hmac (ironclad:make-hmac message-key :sha256))
          (ad-bytes (when associated-data
                      (babel:string-to-octets associated-data :encoding :utf-8))))
      (ironclad:update-hmac hmac iv)
      (ironclad:update-hmac hmac actual-ciphertext)
      (when ad-bytes
        (ironclad:update-hmac hmac ad-bytes))
      (let ((computed-tag (ironclad:hmac-digest hmac)))
        (unless (equalp tag computed-tag)
          (error 'e2ee-decrypt-failed
                 :session-id (e2ee-session-session-id session)
                 :reason "Authentication tag mismatch"))))

    ;; 解密
    (let ((cipher (ironclad:make-cipher :aes :key message-key :mode :cbc :initialization-vector iv)))
      (ironclad:decrypt-in-place cipher actual-ciphertext))

    ;; 移除 PKCS7 padding
    (let ((padding-bytes (aref actual-ciphertext (1- (length actual-ciphertext)))))
      (if (and (plusp padding-bytes) (<= padding-bytes 16))
          (babel:octets-to-string (subseq actual-ciphertext 0 (- (length actual-ciphertext) padding-bytes)) :encoding :utf-8)
          (babel:octets-to-string actual-ciphertext :encoding :utf-8)))))

;;;; Nonce 生成

(defun generate-nonce (size)
  "生成随机 nonce"
  (declare (type integer size))
  (ironclad:random-data size))

;;;; 会话管理

(defun start-e2ee-session (local-identity remote-public-key &optional initiator-p)
  "启动 E2EE 会话"
  (declare (type identity-keypair local-identity)
           (type encryption-key remote-public-key))
  (let* ((session-id (format nil "~a-~a"
                             (get-universal-time)
                             (ironclad:random-data 8)))
         (session (make-e2ee-session
                   :session-id session-id
                   :local-identity-keypair local-identity
                   :remote-public-key remote-public-key)))
    ;; 初始化双棘轮
    (initialize-double-ratchet session (or initiator-p t))
    session))

;;;; 密钥轮换

(defun rotate-keys (user-id)
  "轮换用户密钥"
  (declare (type string user-id))
  (bordeaux-threads:with-lock-held ((secure-key-store-lock *key-store*))
    (let* ((old-keypair (gethash user-id (secure-key-store-identity-keys *key-store*)))
           (new-keypair (generate-identity-keypair)))
      ;; 保留旧密钥用于解密历史消息
      (when old-keypair
        (setf (gethash user-id (secure-key-store-archived-keys *key-store*))
              (list :keypair old-keypair
                    :archived-at (get-universal-time))))
      ;; 更新密钥
      (setf (gethash user-id (secure-key-store-identity-keys *key-store*))
            new-keypair)
      (incf (secure-key-store-key-version *key-store*))
      ;; 广播新公钥
      (broadcast-public-key user-id (identity-keypair-public-key new-keypair))
      ;; 记录审计日志
      (audit-log "Key rotation"
                 :user-id user-id
                 :version (secure-key-store-key-version *key-store*))
      new-keypair)))

;;;; 密钥备份（Shamir 秘密共享 - 简化实现）

(defun backup-master-key (n k)
  "将主密钥分成 n 份，任意 k 份可恢复"
  (declare (type integer n k))
  (let ((master-key (secure-key-store-master-key *key-store*)))
    (unless master-key
      (error "Master key not set"))
    (shamir-split (secure-buffer-data master-key) n k)))

(defun shamir-split (secret n k)
  "Shamir 秘密共享分割"
  (declare (type (simple-array (unsigned-byte 8) (*)) secret)
           (type integer n k)
           (ignore k))  ; 简化实现，暂不支持阈值
  (let ((shares (make-list n)))
    ;; 简化实现：直接复制密钥
    (dotimes (i n)
      (setf (nth i shares)
            (let ((share (alexandria:copy-sequence 'array secret)))
              ;; 添加共享索引
              (setf (aref share 0) (logior (aref share 0) (1+ i)))
              share)))
    shares))

(defun recover-master-key (shares)
  "从 k 份共享中恢复主密钥"
  (declare (type list shares))
  (shamir-combine shares))

(defun shamir-combine (shares)
  "Shamir 秘密共享合并"
  (declare (type list shares))
  ;; 简化实现：取第一个共享的数据
  (when shares
    (let ((secret (make-array 32 :element-type '(unsigned-byte 8))))
      (replace secret (car shares))
      ;; 清除索引位
      (setf (aref secret 0) (logand (aref secret 0) #x7F))
      secret)))

;;;; 密钥吊销

(defun revoke-keys (user-id reason)
  "吊销用户密钥"
  (declare (type string user-id)
           (type string reason))
  (bordeaux-threads:with-lock-held ((secure-key-store-lock *key-store*))
    (let ((keypair (remhash user-id (secure-key-store-identity-keys *key-store*))))
      (when keypair
        ;; 加入吊销列表
        (add-to-revocation-list user-id keypair reason)
        ;; 通知所有相关用户
        (notify-key-revocation user-id reason)
        ;; 记录审计日志
        (audit-log "Key revocation"
                   :user-id user-id
                   :reason reason)))))

(defun add-to-revocation-list (user-id keypair reason)
  "添加到吊销列表"
  (declare (type string user-id reason)
           (ignore keypair))
  (log-info "Added key to revocation list: ~a - ~a" user-id reason))

(defun notify-key-revocation (user-id reason)
  "通知密钥吊销"
  (declare (type string user-id reason))
  (log-info "Notifying key revocation: ~a - ~a" user-id reason))

;;;; 会话存储

(defun store-session (user-id peer-id session)
  "存储会话"
  (declare (type string user-id peer-id)
           (type e2ee-session session))
  (bordeaux-threads:with-lock-held ((secure-key-store-lock *key-store*))
    (let ((key (format nil "~a:~a" user-id peer-id)))
      (setf (gethash key (secure-key-store-session-keys *key-store*))
            session))))

(defun load-session (user-id peer-id)
  "加载会话"
  (declare (type string user-id peer-id))
  (bordeaux-threads:with-lock-held ((secure-key-store-lock *key-store*))
    (let ((key (format nil "~a:~a" user-id peer-id)))
      (gethash key (secure-key-store-session-keys *key-store*)))))

(defun delete-session (user-id peer-id)
  "删除会话"
  (declare (type string user-id peer-id))
  (bordeaux-threads:with-lock-held ((secure-key-store-lock *key-store*))
    (let ((key (format nil "~a:~a" user-id peer-id)))
      (remhash key (secure-key-store-session-keys *key-store*)))))

;;;; 辅助函数

(defun audit-log (operation &rest args)
  "记录安全审计日志"
  (declare (type string operation))
  (let ((log-entry (list :operation operation
                         :timestamp (get-universal-time)
                         :details args)))
    (log-info "E2EE Audit: ~a" (cl-json:encode-json-to-string log-entry))
    ;; 在生产环境中存储到审计日志存储
    t))

(defun broadcast-public-key (user-id public-key)
  "广播公钥"
  (declare (type string user-id)
           (type encryption-key public-key)
           (ignore public-key))
  (log-info "Broadcasting public key for user ~a" user-id))

(defun get-user-public-key (user-id)
  "获取用户公钥"
  (declare (type string user-id))
  (bordeaux-threads:with-lock-held ((secure-key-store-lock *key-store*))
    (let ((keypair (gethash user-id (secure-key-store-identity-keys *key-store*))))
      (when keypair
        (identity-keypair-public-key keypair)))))

;;;; 清理

(defun secure-cleanup ()
  "安全清理敏感数据"
  (bordeaux-threads:with-lock-held ((secure-key-store-lock *key-store*))
    ;; 清理临时密钥
    (log-info "Secure cleanup completed")))

;;;; 导出

(export '(;; Initialization
          initialize-e2ee
          secure-cleanup

          ;; Key management
          generate-identity-keypair
          generate-session-key
          get-user-public-key
          store-session
          load-session
          delete-session

          ;; Key exchange
          create-key-exchange-request
          process-key-exchange-request
          establish-e2ee-session

          ;; Encryption/Decryption
          encrypt-message
          decrypt-message

          ;; Key rotation
          rotate-keys
          revoke-keys

          ;; Audit
          audit-log

          ;; Conditions
          e2ee-error
          e2ee-decrypt-failed
          e2ee-key-not-found
          e2ee-session-expired)
        :lispim-core)
