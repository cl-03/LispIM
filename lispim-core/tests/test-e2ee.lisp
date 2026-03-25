;;;; test-e2ee.lisp - E2EE 模块测试

(in-package :lispim-core/test)

(eval-when (:compile-toplevel :load-toplevel :execute)
  (ql:quickload '(:fiveam :lispim-core)))

(in-package :lispim-core/test)

(def-suite :test-e2ee
  :description "E2EE 模块测试套件")

(in-suite :test-e2ee)

;;;; 测试：安全缓冲区创建

(test test-secure-buffer-create
  "测试安全缓冲区创建"
  (let ((buf (lispim-core::make-secure-buffer* 32)))
    (is (not (null (lispim-core::secure-buffer-data buf))))
    (is (= 32 (length (lispim-core::secure-buffer-data buf))))
    (is (typep (lispim-core::secure-buffer-data buf)
               '(simple-array (unsigned-byte 8) (*))))))

;;;; 测试：安全擦除

(test test-secure-erase
  "测试安全擦除功能"
  (let ((data (make-array 32 :element-type '(unsigned-byte 8)
                          :initial-element #xAB)))
    ;; 初始数据应该是 #xAB
    (is (= #xAB (aref data 0)))

    ;; 擦除
    (lispim-core::secure-erase data)

    ;; 擦除后应该是 #x00
    (is (= #x00 (aref data 0)))))

;;;; 测试：密钥对生成

(test test-keypair-generation
  "测试密钥对生成"
  ;; 注意：实际测试需要 libsignal-protocol-c 库
  ;; 这里测试基本结构
  (let* ((private-key (lispim-core::make-secure-buffer* 32))
         (public-key (make-array 32 :element-type '(unsigned-byte 8)))
         (keypair (lispim-core::make-identity-keypair
                  :public-key public-key
                  :private-key private-key)))
    (is (not (null (lispim-core::identity-keypair-public-key keypair))))
    (is (not (null (lispim-core::identity-keypair-private-key keypair))))
    (is (= 32 (length (lispim-core::identity-keypair-public-key keypair))))))

;;;; 测试：Nonce 生成

(test test-nonce-generation
  "测试随机 Nonce 生成"
  (let ((nonce1 (lispim-core::generate-nonce 12))
        (nonce2 (lispim-core::generate-nonce 12)))
    (is (= 12 (length nonce1)))
    (is (= 12 (length nonce2)))
    ;; 两个 nonce 应该不同
    (is (not (equalp nonce1 nonce2)))))

;;;; 测试：密钥存储

(test test-key-store
  "测试密钥存储"
  (let ((store (lispim-core::make-secure-key-store)))
    (is (not (null (lispim-core::secure-key-store-identity-keys store))))
    (is (not (null (lispim-core::secure-key-store-session-keys store))))
    (is (not (null (lispim-core::secure-key-store-archived-keys store))))
    (is (= 0 (lispim-core::secure-key-store-key-version store)))))

;;;; 测试：密钥轮换

(test test-key-rotation
  "测试密钥轮换"
  (let ((store (lispim-core::make-secure-key-store))
        (user-id "test-user"))
    ;; 初始密钥版本应该是 0
    (is (= 0 (lispim-core::secure-key-store-key-version store)))

    ;; 模拟密钥轮换
    (incf (lispim-core::secure-key-store-key-version store))

    ;; 版本应该递增
    (is (= 1 (lispim-core::secure-key-store-key-version store)))))

;;;; 测试：会话管理

(test test-session-management
  "测试会话管理"
  (let* ((local-keypair (lispim-core::make-identity-keypair
                         :public-key (make-array 32 :element-type '(unsigned-byte 8))
                         :private-key (lispim-core::make-secure-buffer* 32)))
         (session (lispim-core::make-e2ee-session
                   :local-identity-keypair local-keypair
                   :remote-public-key (make-array 32 :element-type '(unsigned-byte 8)))))
    (is (not (null (lispim-core::e2ee-session-session-id session))))
    (is (not (null (lispim-core::e2ee-session-local-identity-keypair session))))
    (is (typep (lispim-core::e2ee-session-sending-message-number session) 'integer))))

;;;; 测试：Shamir 秘密共享（简化）

(test test-shamir-simplified
  "测试 Shamir 秘密共享（简化版）"
  ;; 简化测试，实际实现需要有限域运算
  (let ((secret (make-array 32 :element-type '(unsigned-byte 8)
                            :initial-element #x42))
        (n 5)
        (k 3))
    (let ((shares (lispim-core::shamir-split secret n k)))
      (is (= n (length shares)))
      ;; 每个 share 应该是数组
      (dolist (share shares)
        (is (typep share '(simple-array (unsigned-byte 8) (*))))))))

;;;; 运行所有测试

(defun run-e2ee-tests ()
  "运行所有 E2EE 测试"
  (fiveam:run! :test-e2ee))
