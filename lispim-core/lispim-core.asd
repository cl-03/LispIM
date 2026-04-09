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
               (:file "types" :depends-on ("package" "conditions"))
               (:file "utils" :depends-on ("package" "conditions" "types"))
               (:file "macros" :depends-on ("package" "utils" "conditions" "types"))
               (:file "snowflake" :depends-on ("package" "utils" "conditions" "types"))
               (:file "db-migration" :depends-on ("package" "utils" "conditions" "types"))
               (:file "storage" :depends-on ("package" "utils" "db-migration" "conditions" "types"))
               (:file "auth" :depends-on ("package" "utils" "snowflake" "storage" "conditions" "types"))
               ;; Module system
               (:file "module" :depends-on ("package" "utils" "conditions" "types"))
               ;; Markdown and Translation
               (:file "markdown" :depends-on ("package" "utils" "conditions" "types"))
               (:file "translation" :depends-on ("package" "utils" "markdown" "conditions" "types"))
               ;; Message handling
               (:file "message-status" :depends-on ("package" "utils" "storage" "conditions" "types"))
               (:file "message-encoding" :depends-on ("package" "utils" "conditions" "types"))
               (:file "message-compression" :depends-on ("package" "utils" "message-encoding" "conditions" "types"))
               (:file "message-reply" :depends-on ("package" "utils" "storage" "conditions" "types"))
               ;; Infrastructure
               (:file "connection-pool" :depends-on ("package" "utils" "conditions" "types"))
               (:file "multi-level-cache" :depends-on ("package" "utils" "conditions" "types"))
               (:file "offline-queue" :depends-on ("package" "utils" "storage" "conditions" "types"))
               (:file "sync" :depends-on ("package" "utils" "storage" "conditions" "types"))
               (:file "message-queue" :depends-on ("package" "utils" "storage" "conditions" "types"))
               (:file "cluster" :depends-on ("package" "utils" "storage" "conditions" "types"))
               (:file "double-ratchet" :depends-on ("package" "utils" "conditions" "types"))
               (:file "cdn-storage" :depends-on ("package" "utils" "conditions" "types"))
               (:file "db-replica" :depends-on ("package" "utils" "storage" "conditions" "types"))
               (:file "message-dedup" :depends-on ("package" "utils" "conditions" "types"))
               (:file "rate-limiter" :depends-on ("package" "utils" "conditions" "types"))
               (:file "fulltext-search" :depends-on ("package" "utils" "storage" "conditions" "types"))
               ;; New modules
               (:file "middleware" :depends-on ("package" "utils" "rate-limiter" "conditions" "types"))
               (:file "room" :depends-on ("package" "utils" "conditions" "types"))
               (:file "commands" :depends-on ("package" "utils" "conditions" "types"))
               (:file "reactions" :depends-on ("package" "utils" "storage" "conditions" "types"))
               (:file "online-cache" :depends-on ("package" "utils" "room" "conditions" "types"))
               ;; Location and QR
               (:file "location" :depends-on ("package" "utils" "storage" "conditions" "types"))
               (:file "qr" :depends-on ("package" "utils" "storage" "conditions" "types"))
               ;; Moments
               (:file "moment" :depends-on ("package" "utils" "storage" "conditions" "types"))
               ;; Contacts
               (:file "contact" :depends-on ("package" "utils" "storage" "conditions" "types"))
               ;; File Transfer
               (:file "file-transfer" :depends-on ("package" "utils" "storage" "conditions" "types"))
               ;; Group
               (:file "group" :depends-on ("package" "utils" "storage" "conditions" "types"))
               ;; Favorites
               (:file "favorites" :depends-on ("package" "utils" "storage" "conditions" "types"))
               ;; Call
               (:file "call" :depends-on ("package" "utils" "storage" "conditions" "types"))
               ;; Poll
               (:file "poll" :depends-on ("package" "utils" "storage" "conditions" "types"))
               ;; Notification
               (:file "notification" :depends-on ("package" "utils" "storage" "conditions" "types"))
               ;; Webhook
               (:file "webhook" :depends-on ("package" "utils" "storage" "conditions" "types"))
               ;; Privacy
               (:file "privacy" :depends-on ("package" "utils" "storage" "conditions" "types"))
               ;; Voice messages
               (:file "voice-messages" :depends-on ("package" "utils" "storage" "conditions" "types"))
               ;; User status
               (:file "user-status" :depends-on ("package" "utils" "storage" "reactions" "conditions" "types"))
               ;; Chat folders
               (:file "chat-folders" :depends-on ("package" "utils" "storage" "conditions" "types"))
               ;; Group channels
               (:file "group-channels" :depends-on ("package" "utils" "storage" "reactions" "conditions" "types"))
               ;; Plugin system
               (:file "plugin" :depends-on ("package" "utils" "storage" "conditions" "types"))
               ;; Link metadata
               (:file "linkmeta" :depends-on ("package" "utils" "storage" "plugin" "conditions" "types"))
               ;; Panel system
               (:file "panel" :depends-on ("package" "utils" "storage" "plugin" "conditions" "types"))
               ;; OAuth
               (:file "oauth" :depends-on ("package" "utils" "storage" "auth" "conditions" "types"))
               ;; Gateway forward declarations - declares functions called in gateway but defined later
               (:file "gateway-forward-decls" :depends-on ("package" "conditions" "types"))
               ;; Gateway - after all modules it depends on
               (:file "gateway" :depends-on ("package" "utils" "snowflake" "auth" "storage" "module" "markdown" "translation" "message-status" "message-encoding" "message-compression" "message-reply" "connection-pool" "multi-level-cache" "offline-queue" "sync" "message-queue" "cluster" "double-ratchet" "cdn-storage" "db-replica" "message-dedup" "rate-limiter" "fulltext-search" "middleware" "room" "commands" "reactions" "online-cache" "location" "qr" "moment" "contact" "file-transfer" "group" "favorites" "call" "poll" "notification" "webhook" "privacy" "voice-messages" "user-status" "chat-folders" "group-channels" "plugin" "linkmeta" "panel" "oauth" "gateway-forward-decls" "conditions" "types"))
               ;; Chat
               (:file "chat" :depends-on ("package" "utils" "auth" "storage" "message-status" "message-encoding" "message-compression" "connection-pool" "multi-level-cache" "offline-queue" "message-queue" "cluster" "room" "commands" "poll" "notification" "privacy" "markdown" "translation" "voice-messages" "user-status" "chat-folders" "group-channels" "linkmeta" "panel" "oauth" "gateway" "conditions" "types"))
               ;; E2EE
               (:file "e2ee" :depends-on ("package" "utils" "conditions" "double-ratchet" "types"))
               ;; OC Adapter
               (:file "oc-adapter" :depends-on ("package" "utils" "conditions" "types"))
               ;; AI Config
               (:file "ai-config" :depends-on ("package" "utils" "storage" "oc-adapter" "conditions" "types"))
               ;; AI Skills
               (:file "ai-skills" :depends-on ("package" "utils" "storage" "ai-config" "chat" "conditions" "types"))
               ;; Observability
               (:file "observability" :depends-on ("package" "utils" "conditions" "module" "types"))
               ;; Server
               (:file "server" :depends-on ("package" "module" "chat" "e2ee" "storage" "observability" "auth" "gateway" "middleware" "room" "commands" "reactions" "online-cache" "voice-messages" "user-status" "chat-folders" "group-channels" "ai-config" "ai-skills" "conditions" "types"))))

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
               (:file "test-privacy" :depends-on ("test-package"))
               ;; AI Config tests
               (:file "test-ai-config" :depends-on ("test-package")))
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
