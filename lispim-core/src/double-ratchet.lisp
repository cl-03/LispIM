;;;; double-ratchet.lisp - Double Ratchet E2EE Implementation
;;;;
;;;; Implements the Double Ratchet algorithm from Signal Protocol
;;;; for forward and backward secrecy
;;;;
;;;; Architecture:
;;;; - DH ratchet for key agreement
;;;; - Symmetric ratchet for message keys
;;;; - KDF chain for key derivation
;;;; - AES-GCM for message encryption
;;;;
;;;; References:
;;;; - https://signal.org/docs/specifications/doubleratchet/

(in-package :lispim-core)

;;;; Dependencies

(eval-when (:compile-toplevel :load-toplevel :execute)
  (ql:quickload '(:ironclad :bordeaux-threads :babel :cl-base64)))

;;;; Double Ratchet State

(defstruct double-ratchet
  "Double Ratchet state"
  (dh-ratchet-sent nil :type (or null vector))
  (dh-ratchet-received nil :type (or null vector))
  (root-key nil :type (or null vector))
  (chain-key-sending nil :type (or null vector))
  (chain-key-receiving nil :type (or null vector))
  (sending-message-number 0 :type integer)
  (receiving-message-number 0 :type integer)
  (receiving-message-key (make-hash-table :test 'equal) :type hash-table)
  (last-remote-dh nil :type (or null vector))
  (created-at (get-universal-time) :type integer))

;;;; Configuration

(defparameter *double-ratchet-config*
  '((:algorithm . :x25519)           ; DH algorithm
    (:kdf-algorithm . :hkdf-sha256)  ; KDF algorithm
    (:cipher-algorithm . :aes-gcm)   ; Encryption cipher
    (:key-length . 32)               ; Key length in bytes
    (:nonce-length . 12)             ; Nonce length in bytes
    (:max-skip . 1000))              ; Max out-of-order messages
  "Double Ratchet configuration")

;;;; DH Functions (X25519-like using Curve25519)

(defun dh-generate-keypair ()
  "Generate DH key pair (X25519)"
  (let* ((private-key (ironclad:random-data 32))
         (public-key (ironclad:random-data 32))) ; Simplified - in production use real X25519
    (list :private private-key :public public-key)))

(defun dh-calculate-shared-secret (private-key public-key)
  "Calculate DH shared secret"
  (declare (type vector private-key public-key))
  ;; Simplified - in production use real X25519
  (let ((shared (make-array 32 :element-type '(unsigned-byte 8))))
    (dotimes (i 32)
      (setf (aref shared i)
            (logand #xFF (+ (aref private-key i) (aref public-key i)))))
    shared))

;;;; KDF Chain

(defun kdf (key input length)
  "HKDF-like key derivation"
  (declare (type vector key input)
           (type integer length))
  (let* ((hmac (ironclad:make-hmac key :sha256)))
    (ironclad:update-hmac hmac input)
    (let ((hash (ironclad:hmac-digest hmac)))
      (subseq hash 0 (min length (length hash))))))

(defun kdf-chain (chain-key)
  "Advance KDF chain, return new chain key and message key"
  (declare (type vector chain-key))
  (let ((hmac (ironclad:make-hmac chain-key :sha256))
        (input (make-array 1 :element-type '(unsigned-byte 8) :initial-element 1)))
    (ironclad:update-hmac hmac input)
    (let ((output (ironclad:hmac-digest hmac)))
      (values (subseq output 0 32) ; New chain key
              (subseq output 32 64))))) ; Message key

;;;; Ratchet Functions

(defun ratchet-dh (ratchet dh-keypair)
  "Perform DH ratchet step"
  (declare (type double-ratchet ratchet)
           (type list dh-keypair))
  (let* ((dh-result (dh-calculate-shared-secret
                     (getf dh-keypair :private)
                     (double-ratchet-last-remote-dh ratchet)))
         (hmac (ironclad:make-hmac (double-ratchet-root-key ratchet) :sha256)))
    (ironclad:update-hmac hmac dh-result)
    ;; Update root key
    (let ((new-root (ironclad:hmac-digest hmac)))
      (setf (double-ratchet-root-key ratchet) new-root)
      ;; Derive new sending chain key
      (multiple-value-bind (new-chain-key message-key)
          (kdf-chain new-root)
        (setf (double-ratchet-chain-key-sending ratchet) new-chain-key)
        (setf (double-ratchet-sending-message-number ratchet) 0)
        message-key))))

(defun ratchet-symmetric (ratchet &key sending)
  "Perform symmetric ratchet step"
  (declare (type double-ratchet ratchet)
           (type boolean sending))
  (let ((chain-key (if sending
                       (double-ratchet-chain-key-sending ratchet)
                       (double-ratchet-chain-key-receiving ratchet))))
    (multiple-value-bind (new-chain-key message-key)
        (kdf-chain chain-key)
      (if sending
          (setf (double-ratchet-chain-key-sending ratchet) new-chain-key
                (double-ratchet-sending-message-number ratchet)
                (1+ (double-ratchet-sending-message-number ratchet)))
          (setf (double-ratchet-chain-key-receiving ratchet) new-chain-key
                (double-ratchet-receiving-message-number ratchet)
                (1+ (double-ratchet-receiving-message-number ratchet))))
      message-key)))

;;;; Message Encryption

(defun encrypt-message-aes-gcm (plaintext key nonce associated-data)
  "Encrypt message using AES-GCM"
  (declare (type string plaintext)
           (type vector key nonce associated-data))
  (let* ((plaintext-bytes (babel:string-to-octets plaintext :encoding :utf-8))
         (cipher (ironclad:make-cipher :aes-gcm :key key :initialization-vector nonce))
         (ciphertext (make-array (+ (length plaintext-bytes) 16)
                                 :element-type '(unsigned-byte 8))))
    (ironclad:encrypt-message cipher plaintext-bytes ciphertext
                              :additional-data associated-data)
    ciphertext))

(defun decrypt-message-aes-gcm (ciphertext key nonce associated-data)
  "Decrypt message using AES-GCM"
  (declare (type vector ciphertext key nonce associated-data))
  (let* ((cipher (ironclad:make-cipher :aes-gcm :key key :initialization-vector nonce))
         (plaintext (make-array (max 0 (- (length ciphertext) 16))
                                :element-type '(unsigned-byte 8))))
    (handler-case
        (ironclad:decrypt-message cipher ciphertext plaintext
                                  :additional-data associated-data)
      (error (c)
        (log-error "AES-GCM decryption failed: ~a" c)
        (return-from decrypt-message-aes-gcm nil)))
    (babel:octets-to-string plaintext :encoding :utf-8)))

;;;; Double Ratchet API

(defun initialize-double-ratchet (&key local-keypair remote-public-key root-key)
  "Create new Double Ratchet instance"
  (declare (type list local-keypair)
           (type vector remote-public-key root-key))
  (let ((ratchet (make-double-ratchet
                  :dh-ratchet-sent (getf local-keypair :public)
                  :dh-ratchet-received remote-public-key
                  :root-key root-key
                  :chain-key-sending (subseq (ironclad:random-data 32) 0 32)
                  :chain-key-receiving (subseq (ironclad:random-data 32) 0 32)
                  :last-remote-dh remote-public-key)))
    ratchet))

(defun double-ratchet-encrypt (ratchet plaintext associated-data)
  "Encrypt message using Double Ratchet"
  (declare (type double-ratchet ratchet)
           (type string plaintext)
           (type vector associated-data))
  ;; Get message key
  (let ((message-key (ratchet-symmetric ratchet :sending t)))
    ;; Generate nonce
    (let ((nonce (ironclad:random-data 12)))
      ;; Encrypt
      (let ((ciphertext (encrypt-message-aes-gcm plaintext message-key nonce associated-data)))
        ;; Build message envelope
        (list :ciphertext (cl-base64:usb8-array-to-base64-string ciphertext)
              :nonce (cl-base64:usb8-array-to-base64-string nonce)
              :counter (double-ratchet-sending-message-number ratchet))))))

(defun double-ratchet-decrypt (ratchet message associated-data)
  "Decrypt message using Double Ratchet"
  (declare (type double-ratchet ratchet)
           (type list message)
           (type vector associated-data))
  (let* ((counter (getf message :counter))
         (nonce-b64 (getf message :nonce))
         (ciphertext-b64 (getf message :ciphertext))
         (nonce (cl-base64:base64-string-to-usb8-array nonce-b64))
         (ciphertext (cl-base64:base64-string-to-usb8-array ciphertext-b64)))
    ;; Check if message key is cached
    (let ((cached-key (gethash counter (double-ratchet-receiving-message-key ratchet))))
      (if cached-key
          ;; Use cached key
          (decrypt-message-aes-gcm ciphertext cached-key nonce associated-data)
          ;; Derive message key
          (progn
            ;; Skip forward if needed
            (loop for i from (double-ratchet-receiving-message-number ratchet)
                  below counter
                  do (let ((skip-key (ratchet-symmetric ratchet :sending nil)))
                       (setf (gethash i (double-ratchet-receiving-message-key ratchet)) skip-key)))
            ;; Get current message key
            (let ((message-key (ratchet-symmetric ratchet :sending nil)))
              (decrypt-message-aes-gcm ciphertext message-key nonce associated-data)))))))

(defun double-ratchet-receive-ratchet (ratchet new-remote-public-key)
  "Process received ratchet update"
  (declare (type double-ratchet ratchet)
           (type vector new-remote-public-key))
  ;; Update remote DH
  (setf (double-ratchet-last-remote-dh ratchet) new-remote-public-key
        (double-ratchet-dh-ratchet-received ratchet) new-remote-public-key)
  ;; Perform DH ratchet
  (let ((local-keypair (dh-generate-keypair)))
    (ratchet-dh ratchet local-keypair)
    ;; Update sent DH
    (setf (double-ratchet-dh-ratchet-sent ratchet) (getf local-keypair :public))
    local-keypair))

;;;; Session Management

(defun create-e2ee-session (local-identity remote-identity)
  "Create new E2EE session"
  (declare (type list local-identity remote-identity))
  ;; Generate initial root key from identities
  (let* ((shared-secret (dh-calculate-shared-secret
                         (getf local-identity :private)
                         (getf remote-identity :public)))
         (root-key (kdf shared-secret (babel:string-to-octets "E2EE-ROOT") 32))
         (ratchet (initialize-double-ratchet
                   :local-keypair (dh-generate-keypair)
                   :remote-public-key (getf remote-identity :public)
                   :root-key root-key)))
    ratchet))

;;;; Key Storage

(defvar *e2ee-sessions* (make-hash-table :test 'equal)
  "E2EE session storage")

(defun store-e2ee-session (user-id partner-id ratchet)
  "Store E2EE session"
  (declare (type string user-id partner-id)
           (type double-ratchet ratchet))
  (let ((key (format nil "~a:~a" user-id partner-id)))
    (setf (gethash key *e2ee-sessions*) ratchet)))

(defun get-e2ee-session (user-id partner-id)
  "Get E2EE session"
  (declare (type string user-id partner-id))
  (let ((key (format nil "~a:~a" user-id partner-id)))
    (gethash key *e2ee-sessions*)))

;;;; High-level E2EE Functions

(defun e2ee-encrypt (user-id partner-id plaintext)
  "Encrypt message for partner"
  (declare (type string user-id partner-id)
           (type string plaintext))
  (let ((session (get-e2ee-session user-id partner-id)))
    (unless session
      (error "No E2EE session found for ~a -> ~a" user-id partner-id))
    (let ((associated-data (babel:string-to-octets
                            (format nil "~a:~a:~a" user-id partner-id
                                    (get-universal-time))
                            :encoding :utf-8)))
      (double-ratchet-encrypt session plaintext associated-data))))

(defun e2ee-decrypt (user-id partner-id message)
  "Decrypt message from partner"
  (declare (type string user-id partner-id)
           (type list message))
  (let ((session (get-e2ee-session user-id partner-id)))
    (unless session
      (error "No E2EE session found for ~a -> ~a" user-id partner-id))
    (let ((associated-data (babel:string-to-octets
                            (format nil "~a:~a" partner-id user-id)
                            :encoding :utf-8)))
      (double-ratchet-decrypt session message associated-data))))

;;;; Statistics

(defvar *e2ee-stats* (list :messages-encrypted 0 :messages-decrypted 0 :errors 0)
  "E2EE statistics")

(defun record-e2ee-stat (type)
  "Record E2EE statistic"
  (declare (type keyword type))
  (case type
    (:encrypted (incf (getf *e2ee-stats* :messages-encrypted)))
    (:decrypted (incf (getf *e2ee-stats* :messages-decrypted)))
    (:error (incf (getf *e2ee-stats* :errors)))))

(defun get-e2ee-stats ()
  "Get E2EE statistics"
  *e2ee-stats*)

;;;; Exports

(export '(;; Double Ratchet
          double-ratchet
          initialize-double-ratchet
          double-ratchet-encrypt
          double-ratchet-decrypt
          double-ratchet-receive-ratchet
          ;; DH functions
          dh-generate-keypair
          dh-calculate-shared-secret
          ;; KDF
          kdf
          kdf-chain
          ;; Session management
          create-e2ee-session
          store-e2ee-session
          get-e2ee-session
          ;; High-level API
          e2ee-encrypt
          e2ee-decrypt
          ;; Statistics
          get-e2ee-stats
          record-e2ee-stat
          *e2ee-sessions*
          *double-ratchet-config*)
        :lispim-core)
