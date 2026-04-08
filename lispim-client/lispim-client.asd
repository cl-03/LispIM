;;;; lispim-client.asd - ASDF System Definition for LispIM Client
;;;;
;;;; Pure Common Lisp desktop client using McCLIM

(asdf:defsystem :lispim-client
  :version "0.1.0"
  :author "LispIM Team"
  :license "MIT"
  :description "Pure Common Lisp desktop client using McCLIM"
  :depends-on (:mcclim
               :dexador
               :cl-json
               :bordeaux-threads
               :usocket
               :babel
               :ironclad
               :cl-base64
               :log4cl
               :quri)
  ;; Optional dependencies (install with ql:quickload if needed):
  ;; :cl-websocket - for full WebSocket protocol support
  :pathname "src/"
  :components ((:file "package")
               (:file "utils" :depends-on ("package"))
               (:file "api-client" :depends-on ("package" "utils"))
               (:file "websocket-client" :depends-on ("package" "utils"))
               (:file "auth-manager" :depends-on ("package" "api-client"))
               (:file "client-state" :depends-on ("package"))
               (:file "client" :depends-on ("package" "api-client" "websocket-client" "auth-manager" "client-state"))
               ;; UI module - commented out until McCLIM issues are resolved
               ;; (:module "ui"
               ;;  :pathname "ui/"
               ;;  :serial t
               ;;  :components ((:file "package")
               ;;               (:file "login-frame" :depends-on ("package"))
               ;;               (:file "main-frame" :depends-on ("package"))
               ;;               (:file "ai-settings" :depends-on ("package")))
               ;;  :depends-on ("package" "client"))
               ;; Test module
               (:module "test"
                :pathname "../tests/"
                :serial t
                :components ((:file "test-websocket")
                             (:file "test-client"))))
  :perform (asdf:test-op (o c) (uiop:symbol-call :lispim-client/test :run-all-tests)))

(asdf:defsystem :lispim-client/test
  :depends-on (:lispim-client)
  :pathname "tests/"
  :serial t
  :components ((:file "test-websocket")
               (:file "test-client")))
