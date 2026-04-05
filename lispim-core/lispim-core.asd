;;;; lispim-core.asd - LispIM Core System Definition
;;;;
;;;; LispIM Enterprise - Cloud Native, AI Native, Privacy First IM Platform
;;;; Author: LispIM Team
;;;; License: MIT
;;;; Updated: 2026-03-22

(asdf:defsystem :lispim-core
  :version "0.1.0"
  :author "LispIM Team"
  :license "MIT"
  :description "LispIM Enterprise - Cloud Native, AI Native, Privacy First IM Platform"
  :long-description "
    LispIM is a modern instant messaging platform built with Common Lisp.
    Features:
    - WebSocket-based real-time communication
    - End-to-end encryption (E2EE)
    - Redis & PostgreSQL storage
    - OpenClaw AI integration
    - Horizontal scalability
  "
  :homepage "https://github.com/lispim/lispim"
  :bug-tracker "https://github.com/lispim/lispim/issues"
  :source-control (:url "https://github.com/lispim/lispim"
                          :connection "scm:git:https://github.com/lispim/lispim.git")
  :in-order-to ((asdf:test-op (asdf:test-op :lispim-core/test)))
  :depends-on (:hunchentoot
               :cl-json
               :postmodern
               :cl-redis
               :bordeaux-threads
               :uuid
               :babel
               :salza2
               :local-time
               :log4cl
               :ironclad
               :trivia
               :alexandria
               :serapeum
               :flexi-streams
               :str
               :drakma
               :cl-ppcre)
  :pathname "src/"
  :serial t
  :encoding :utf-8
  :components ((:file "package")
               (:file "conditions" :depends-on ("package"))
               (:file "utils" :depends-on ("package" "conditions"))
               (:file "snowflake" :depends-on ("package" "utils" "conditions"))
               (:file "db-migration" :depends-on ("package" "utils" "conditions"))
               (:file "storage" :depends-on ("package" "utils" "db-migration" "conditions"))
               (:file "auth" :depends-on ("package" "utils" "snowflake" "storage" "conditions"))
               (:file "gateway" :depends-on ("package" "utils" "snowflake" "auth" "conditions"))
               (:file "module" :depends-on ("package" "utils" "conditions"))
               ;; Markdown module (富文本支持) - needed for gateway translation APIs
               (:file "markdown" :depends-on ("package" "utils" "conditions"))
               ;; Translation module (消息翻译) - needed for gateway translation APIs
               (:file "translation" :depends-on ("package" "utils" "markdown" "conditions"))
               (:file "message-status" :depends-on ("package" "utils" "storage" "conditions"))
               (:file "message-encoding" :depends-on ("package" "utils" "conditions"))
               (:file "message-compression" :depends-on ("package" "utils" "message-encoding" "conditions"))
               (:file "connection-pool" :depends-on ("package" "utils" "conditions"))
               (:file "multi-level-cache" :depends-on ("package" "utils" "conditions"))
               (:file "offline-queue" :depends-on ("package" "utils" "storage" "conditions"))
               (:file "sync" :depends-on ("package" "utils" "storage" "conditions"))
               (:file "message-queue" :depends-on ("package" "utils" "storage" "conditions"))
               (:file "cluster" :depends-on ("package" "utils" "storage" "conditions"))
               (:file "double-ratchet" :depends-on ("package" "utils" "conditions"))
               (:file "cdn-storage" :depends-on ("package" "utils" "conditions"))
               (:file "db-replica" :depends-on ("package" "utils" "storage" "conditions"))
               (:file "message-dedup" :depends-on ("package" "utils" "conditions"))
               (:file "rate-limiter" :depends-on ("package" "utils" "conditions"))
               (:file "fulltext-search" :depends-on ("package" "utils" "storage" "conditions"))
               (:file "message-reply" :depends-on ("package" "utils" "storage" "conditions"))
               ;; New modules (optimized features)
               (:file "middleware" :depends-on ("package" "utils" "rate-limiter" "conditions"))
               (:file "room" :depends-on ("package" "utils" "gateway" "conditions"))
               (:file "commands" :depends-on ("package" "utils" "conditions"))
               (:file "reactions" :depends-on ("package" "utils" "storage" "conditions"))
               (:file "online-cache" :depends-on ("package" "utils" "room" "conditions"))
               ;; Location and QR modules (扫一扫，附近的人)
               (:file "location" :depends-on ("package" "utils" "storage" "conditions"))
               (:file "qr" :depends-on ("package" "utils" "storage" "conditions"))
               ;; Moments module (朋友圈)
               (:file "moment" :depends-on ("package" "utils" "storage" "conditions"))
               ;; Contacts module (通讯录)
               (:file "contact" :depends-on ("package" "utils" "storage" "conditions"))
               ;; File Transfer module (大文件传输)
               (:file "file-transfer" :depends-on ("package" "utils" "storage" "conditions"))
               ;; Group module (群聊)
               (:file "group" :depends-on ("package" "utils" "storage" "conditions"))
               ;; Favorites module (收藏夹)
               (:file "favorites" :depends-on ("package" "utils" "storage" "conditions"))
               ;; Call module (语音/视频通话)
               (:file "call" :depends-on ("package" "utils" "storage" "conditions"))
               ;; Poll module (群投票)
               (:file "poll" :depends-on ("package" "utils" "storage" "conditions"))
               ;; Notification module (通知推送)
               (:file "notification" :depends-on ("package" "utils" "storage" "conditions"))
               ;; Webhook module
               (:file "webhook" :depends-on ("package" "utils" "storage" "conditions"))
               ;; Privacy module (隐私增强)
               (:file "privacy" :depends-on ("package" "utils" "storage" "conditions"))
               ;; New features (2026-04-04)
               (:file "voice-messages" :depends-on ("package" "utils" "storage" "conditions"))
               (:file "user-status" :depends-on ("package" "utils" "storage" "reactions" "conditions"))
               (:file "chat-folders" :depends-on ("package" "utils" "storage" "conditions"))
               (:file "group-channels" :depends-on ("package" "utils" "storage" "reactions" "conditions"))
               ;; Core modules with new dependencies
               (:file "chat" :depends-on ("package" "utils" "auth" "storage" "message-status" "message-encoding" "message-compression" "connection-pool" "multi-level-cache" "offline-queue" "message-queue" "cluster" "room" "commands" "poll" "notification" "privacy" "markdown" "translation" "voice-messages" "user-status" "chat-folders" "group-channels" "conditions"))
               (:file "e2ee" :depends-on ("package" "utils" "conditions" "double-ratchet"))
               (:file "oc-adapter" :depends-on ("package" "utils" "conditions"))
               (:file "observability" :depends-on ("package" "utils" "conditions" "module"))
               (:file "server" :depends-on ("package" "module" "chat" "e2ee" "storage" "observability" "auth" "gateway" "middleware" "room" "commands" "reactions" "online-cache" "voice-messages" "user-status" "chat-folders" "group-channels" "conditions"))))

(asdf:defsystem :lispim-core/test
  :version "0.1.0"
  :author "LispIM Team"
  :license "MIT"
  :description "LispIM Core - Test Suite"
  :depends-on (:fiveam
               :lispim-core)
  :pathname "tests/"
  :encoding :utf-8
  :components ((:file "test-package")
               (:file "test-snowflake" :depends-on ("test-package"))
               (:file "test-gateway" :depends-on ("test-package"))
               (:file "test-module" :depends-on ("test-package"))
               (:file "test-chat" :depends-on ("test-package"))
               (:file "test-e2ee" :depends-on ("test-package"))
               (:file "test-message-status" :depends-on ("test-package" "test-chat"))
               (:file "test-message-encoding" :depends-on ("test-package" "test-chat"))
               (:file "test-multi-level-cache" :depends-on ("test-package"))
               (:file "test-offline-queue" :depends-on ("test-package"))
               (:file "test-sync" :depends-on ("test-package"))
               (:file "test-message-queue" :depends-on ("test-package"))
               (:file "test-cluster" :depends-on ("test-package"))
               (:file "test-double-ratchet" :depends-on ("test-package"))
               (:file "test-cdn-storage" :depends-on ("test-package"))
               (:file "test-db-replica" :depends-on ("test-package"))
               (:file "test-message-dedup" :depends-on ("test-package"))
               (:file "test-rate-limiter" :depends-on ("test-package"))
               (:file "test-fulltext-search" :depends-on ("test-package"))
               (:file "test-message-reply" :depends-on ("test-package"))
               ;; New modules tests
               (:file "test-new-features" :depends-on ("test-package"))
               (:file "test-privacy" :depends-on ("test-package")))
  :perform (asdf:test-op (o c)
    (uiop:symbol-call :fiveam :run! '(or :lispim-core/test :all))))

(asdf:defsystem :lispim-core/backend-app
  :version "0.1.0"
  :author "LispIM Team"
  :license "MIT"
  :description "LispIM Backend Desktop Application"
  :depends-on (:lispim-core)
  :pathname ""
  :entry-point "lispim-backend-app:main"
  :components ((:file "lispim-backend-app")))

;; Build configuration
(defparameter *lispim-version* "0.1.0")
(defparameter *lispim-build-date* (get-universal-time))
