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
               :drakma)
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
               (:file "chat" :depends-on ("package" "utils" "auth" "storage" "conditions"))
               (:file "e2ee" :depends-on ("package" "utils" "conditions"))
               (:file "oc-adapter" :depends-on ("package" "utils" "conditions"))
               (:file "observability" :depends-on ("package" "utils" "conditions" "module"))
               (:file "server" :depends-on ("package" "module" "chat" "e2ee" "storage" "observability" "auth" "conditions"))))

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
               (:file "test-e2ee" :depends-on ("test-package")))
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
