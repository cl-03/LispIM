;;;; openclaw-connector.asd - OpenClaw Connector 系统定义
;;;;
;;;; LispIM OpenClaw Connector - 100% Common Lisp 实现

(asdf:defsystem :openclaw-connector-lispim
  :version "0.1.0"
  :author "LispIM Team"
  :license "MIT"
  :description "OpenClaw Connector for LispIM - Pure Common Lisp Implementation"
  :depends-on (:cl-async
               :cl-json
               :drakma
               :usocket
               :bordeaux-threads
               :uuid
               :babel
               :alexandria
               :log4cl)
  :pathname "src/"
  :serial t
  :components ((:file "package")
               (:file "protocol")
               (:file "connector")
               (:file "handler")
               (:file "stream")
               (:file "server")))
