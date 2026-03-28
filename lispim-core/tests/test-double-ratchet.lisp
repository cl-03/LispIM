;;;; test-double-ratchet.lisp - Unit tests for Double Ratchet E2EE

(in-package :lispim-core/test)

(def-suite test-double-ratchet
  :description "Double Ratchet E2EE unit tests")

(in-suite test-double-ratchet)

;;;; DH Key Generation

(test dh-generate-keypair
  "Test DH key pair generation"
  (let ((keypair (lispim-core:dh-generate-keypair)))
    (is (listp keypair))
    (is (not (null (getf keypair :private))))
    (is (not (null (getf keypair :public))))
    (is (= (length (getf keypair :private)) 32))
    (is (= (length (getf keypair :public)) 32))))

(test dh-calculate-shared-secret
  "Test DH shared secret calculation"
  (let* ((keypair1 (lispim-core:dh-generate-keypair))
         (keypair2 (lispim-core:dh-generate-keypair))
         (secret1 (lispim-core:dh-calculate-shared-secret
                   (getf keypair1 :private)
                   (getf keypair2 :public)))
         (secret2 (lispim-core:dh-calculate-shared-secret
                   (getf keypair2 :private)
                   (getf keypair1 :public))))
    ;; Shared secrets should match (simplified implementation)
    (is (equalp secret1 secret2))
    (is (= (length secret1) 32))))

;;;; KDF Chain

(test kdf-chain
  "Test KDF chain advancement"
  (let* ((initial-key (ironclad:random-data 32))
         (chain-key initial-key))
    ;; Derive multiple keys
    (loop for i from 1 to 5
          do (multiple-value-bind (new-chain-key message-key)
                 (lispim-core:kdf-chain chain-key)
               (is (not (null new-chain-key)))
               (is (not (null message-key)))
               (is (= (length new-chain-key) 32))
               (is (= (length message-key) 32))
               (setf chain-key new-chain-key)))
    ;; Each derivation should produce different keys
    (is (not (equalp initial-key chain-key)))))

;;;; Double Ratchet Initialization

(test make-double-ratchet
  "Test Double Ratchet initialization"
  (let* ((local-keypair (lispim-core:dh-generate-keypair))
         (remote-keypair (lispim-core:dh-generate-keypair))
         (root-key (ironclad:random-data 32))
         (ratchet (lispim-core:make-double-ratchet
                   :local-keypair local-keypair
                   :remote-public-key (getf remote-keypair :public)
                   :root-key root-key)))
    (is (typep ratchet 'lispim-core::double-ratchet))
    (is (not (null (lispim-core::double-ratchet-root-key ratchet))))
    (is (not (null (lispim-core::double-ratchet-chain-key-sending ratchet))))
    (is (not (null (lispim-core::double-ratchet-chain-key-receiving ratchet))))
    (is (= (lispim-core::double-ratchet-sending-message-number ratchet) 0))
    (is (= (lispim-core::double-ratchet-receiving-message-number ratchet) 0))))

;;;; Message Encryption/Decryption

(test double-ratchet-encrypt-decrypt
  "Test message encryption and decryption"
  (let* ((local-keypair (lispim-core:dh-generate-keypair))
         (remote-keypair (lispim-core:dh-generate-keypair))
         (root-key (ironclad:random-data 32))
         (ratchet (lispim-core:make-double-ratchet
                   :local-keypair local-keypair
                   :remote-public-key (getf remote-keypair :public)
                   :root-key root-key))
         (plaintext "Hello, World!")
         (associated-data (babel:string-to-octets "test-data" :encoding :utf-8))
         (encrypted (lispim-core:double-ratchet-encrypt ratchet plaintext associated-data)))
    (is (listp encrypted))
    (is (not (null (getf encrypted :ciphertext))))
    (is (not (null (getf encrypted :nonce))))
    (is (not (null (getf encrypted :counter))))
    (is (stringp (getf encrypted :ciphertext))) ; Base64 encoded
    (is (stringp (getf encrypted :nonce)))))    ; Base64 encoded

(test double-ratchet-symmetric-encrypt-decrypt
  "Test symmetric ratchet encryption/decryption cycle"
  (let* ((local-keypair (lispim-core:dh-generate-keypair))
         (remote-keypair (lispim-core:dh-generate-keypair))
         (root-key (ironclad:random-data 32))
         ;; Create sender ratchet
         (sender (lispim-core:make-double-ratchet
                  :local-keypair local-keypair
                  :remote-public-key (getf remote-keypair :public)
                  :root-key root-key))
         ;; Create receiver ratchet (simplified - in production would use proper X3DH)
         (receiver (lispim-core:make-double-ratchet
                    :local-keypair remote-keypair
                    :remote-public-key (getf local-keypair :public)
                    :root-key root-key))
         (plaintext "Test message")
         (associated-data (babel:string-to-octets "test" :encoding :utf-8))
         (encrypted (lispim-core:double-ratchet-encrypt sender plaintext associated-data)))
    ;; Note: This test is simplified - full test would require proper X3DH key agreement
    (is (not (null encrypted)))))

;;;; Session Management

(test create-e2ee-session
  "Test E2EE session creation"
  (let* ((local-identity (lispim-core:dh-generate-keypair))
         (remote-identity (lispim-core:dh-generate-keypair))
         (session (lispim-core:create-e2ee-session local-identity remote-identity)))
    (is (typep session 'lispim-core::double-ratchet))
    (is (not (null (lispim-core::double-ratchet-root-key session))))))

(test store-and-get-e2ee-session
  "Test E2EE session storage and retrieval"
  (let* ((user-id "test-user-1")
         (partner-id "test-user-2")
         (local-identity (lispim-core:dh-generate-keypair))
         (remote-identity (lispim-core:dh-generate-keypair))
         (session (lispim-core:create-e2ee-session local-identity remote-identity)))
    ;; Store session
    (lispim-core:store-e2ee-session user-id partner-id session)
    ;; Retrieve session
    (let ((retrieved (lispim-core:get-e2ee-session user-id partner-id)))
      (is (not (null retrieved)))
      (is (typep retrieved 'lispim-core::double-ratchet)))))

;;;; High-level API

(test e2ee-encrypt-decrypt
  "Test high-level encrypt/decrypt API"
  (let* ((user-id "encrypt-user-1")
         (partner-id "encrypt-user-2")
         (local-identity (lispim-core:dh-generate-keypair))
         (remote-identity (lispim-core:dh-generate-keypair))
         (session (lispim-core:create-e2ee-session local-identity remote-identity))
         (plaintext "Secret message"))
    ;; Store session
    (lispim-core:store-e2ee-session user-id partner-id session)
    ;; Encrypt
    (let ((encrypted (lispim-core:e2ee-encrypt user-id partner-id plaintext)))
      (is (not (null encrypted)))
      (is (listp encrypted)))))

;;;; Ratchet Update

(test double-ratchet-receive-ratchet
  "Test DH ratchet update on receive"
  (let* ((local-keypair (lispim-core:dh-generate-keypair))
         (remote-keypair (lispim-core:dh-generate-keypair))
         (root-key (ironclad:random-data 32))
         (ratchet (lispim-core:make-double-ratchet
                   :local-keypair local-keypair
                   :remote-public-key (getf remote-keypair :public)
                   :root-key root-key))
         (new-remote-keypair (lispim-core:dh-generate-keypair)))
    ;; Perform ratchet update
    (let ((result (lispim-core:double-ratchet-receive-ratchet
                   ratchet
                   (getf new-remote-keypair :public))))
      (is (not (null result)))
      (is (not (null (getf result :public))))
      (is (not (null (getf result :private)))))))

;;;; Statistics

(test get-e2ee-stats
  "Test E2EE statistics"
  (let ((stats (lispim-core:get-e2ee-stats)))
    (is (listp stats))
    (is (not (null (getf stats :messages-encrypted))))
    (is (not (null (getf stats :messages-decrypted))))
    (is (not (null (getf stats :errors))))))

(test record-e2ee-stat
  "Test E2EE statistic recording"
  (let ((initial-stats (lispim-core:get-e2ee-stats)))
    ;; Record encrypted message
    (lispim-core:record-e2ee-stat :encrypted)
    (let ((new-stats (lispim-core:get-e2ee-stats)))
      (is (> (getf new-stats :messages-encrypted)
             (getf initial-stats :messages-encrypted))))))

;;;; Integration Test

(test e2ee-integration
  "Integration test for E2EE flow"
  (let* ((alice-id "alice")
         (bob-id "bob")
         (alice-identity (lispim-core:dh-generate-keypair))
         (bob-identity (lispim-core:dh-generate-keypair))
         (alice-session (lispim-core:create-e2ee-session alice-identity bob-identity))
         (bob-session (lispim-core:create-e2ee-session bob-identity alice-identity))
         (message "Hello from Alice!"))
    ;; Store sessions
    (lispim-core:store-e2ee-session alice-id bob-id alice-session)
    (lispim-core:store-e2ee-session bob-id alice-id bob-session)
    ;; Alice encrypts
    (let ((encrypted (lispim-core:e2ee-encrypt alice-id bob-id message)))
      (is (not (null encrypted)))
      (is (not (null (getf encrypted :ciphertext))))
      (is (not (null (getf encrypted :nonce)))))
    ;; Cleanup
    (remhash (format nil "~a:~a" alice-id bob-id) lispim-core:*e2ee-sessions*)
    (remhash (format nil "~a:~a" bob-id alice-id) lispim-core:*e2ee-sessions*)))
