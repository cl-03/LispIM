;;;; package.lisp - LispIM 核心包定义
;;;;
;;;; 定义系统包、导出公共 API、定义条件系统

(defpackage :lispim-core/conditions
  (:use :cl)
  (:export
   ;; Base conditions
   #:lispim-error
   #:lispim-warning
   #:lispim-serious-condition
   ;; Connection errors
   #:connection-error
   #:connection-timeout
   #:connection-closed
   #:connection-not-found
   #:connection-lost
   ;; Authentication errors
   #:auth-error
   #:auth-token-expired
   #:auth-invalid-credentials
   #:auth-account-locked
   #:auth-token-invalid
   ;; Message errors
   #:message-error
   #:message-not-found
   #:message-send-failed
   #:message-recall-timeout
   #:message-too-long
   #:message-rate-limited
   ;; Conversation errors
   #:conversation-error
   #:conversation-not-found
   #:conversation-access-denied
   #:conversation-full
   ;; Module errors
   #:module-error
   #:module-load-failed
   #:module-health-check-failed
   #:module-not-found
   ;; E2EE errors
   #:e2ee-error
   #:e2ee-decrypt-failed
   #:e2ee-key-not-found
   #:e2ee-session-expired
   ;; Storage errors
   #:storage-error
   #:storage-not-found
   #:storage-write-failed
   #:storage-quota-exceeded
   ;; Network errors
   #:network-error
   #:network-timeout
   #:network-unreachable
   ;; WebSocket errors
   #:websocket-error
   #:websocket-connection-failed
   #:websocket-message-error
   ;; Restarts
   #:with-retry-restart
   #:with-retry-with-delay-restart
   #:with-use-value-restart
   #:with-skip-restart
   #:with-abort-connection-restart
   #:with-reconnect-restart
   #:with-enter-debugger-restart
   ;; Accessors
   #:condition-message
   #:condition-context
   #:condition-data
   #:condition-connection-id
   #:condition-reason
   #:condition-timeout-duration
   #:connection-id
   #:condition-user-id
   #:condition-ip-address
   #:condition-expired-at
   #:condition-attempted-username
   #:condition-locked-until
   #:condition-failed-attempts
   #:condition-message-id
   #:condition-conversation-id
   #:condition-length
   #:condition-max-length
   #:condition-retry-after
   #:condition-session-id
   #:condition-module-name
   #:condition-check-name
   #:condition-dependencies
   #:condition-key
   #:condition-storage-type
   #:condition-used
   #:condition-quota
   #:condition-host
   #:condition-port
   #:condition-operation
   #:condition-url
   #:condition-ws-message
   #:condition-status-code
   #:condition-attempted-reconnect
   #:condition-current-members
   #:condition-max-members
   #:condition-elapsed
   #:condition-max-elapsed
   #:condition-key-type))

(defpackage :lispim-core
  (:use :cl :alexandria :serapeum :local-time)
  (:import-from :lispim-core/conditions
                ;; Base conditions
                #:lispim-error
                #:lispim-warning
                #:lispim-serious-condition
                ;; Connection errors
                #:connection-error
                #:connection-timeout
                #:connection-closed
                #:connection-not-found
                #:connection-lost
                ;; Authentication errors
                #:auth-error
                #:auth-token-expired
                #:auth-invalid-credentials
                #:auth-account-locked
                #:auth-token-invalid
                ;; Message errors
                #:message-error
                #:message-not-found
                #:message-send-failed
                #:message-recall-timeout
                #:message-too-long
                #:message-rate-limited
                ;; Conversation errors
                #:conversation-error
                #:conversation-not-found
                #:conversation-access-denied
                #:conversation-full
                ;; Module errors
                #:module-error
                #:module-load-failed
                #:module-health-check-failed
                #:module-not-found
                ;; E2EE errors
                #:e2ee-error
                #:e2ee-decrypt-failed
                #:e2ee-key-not-found
                #:e2ee-session-expired
                ;; Storage errors
                #:storage-error
                #:storage-not-found
                #:storage-write-failed
                #:storage-quota-exceeded
                ;; Network errors
                #:network-error
                #:network-timeout
                #:network-unreachable
                ;; WebSocket errors
                #:websocket-error
                #:websocket-connection-failed
                #:websocket-message-error
                ;; Accessors
                #:condition-message
                #:condition-context
                #:condition-data
                #:condition-connection-id
                #:condition-reason
                #:condition-timeout-duration
                #:condition-user-id
                #:condition-ip-address
                #:condition-expired-at
                #:condition-attempted-username
                #:condition-locked-until
                #:condition-failed-attempts
                #:condition-message-id
                #:condition-conversation-id
                #:condition-length
                #:condition-max-length
                #:condition-retry-after
                #:condition-session-id
                #:condition-module-name
                #:condition-check-name
                #:condition-dependencies
                #:condition-key
                #:condition-storage-type
                #:condition-used
                #:condition-quota
                #:condition-host
                #:condition-port
                #:condition-operation
                #:condition-url
                #:condition-ws-message
                #:condition-status-code
                #:condition-attempted-reconnect
                #:condition-current-members
                #:condition-max-members
                #:condition-elapsed
                #:condition-max-elapsed
                #:condition-key-type)
  (:export
   ;; Server lifecycle
   #:start-server
   #:stop-server
   #:restart-server
   #:init-server
   #:*server-running*
   #:*server-start-time*
   #:*config*
   #:make-config
   #:load-config-from-env
   #:main
   ;; Current user context
   #:*current-user-id*
   ;; Config accessors
   #:config-host
   #:config-port
   #:config-database-url
   #:config-redis-url
   #:config-ssl-cert
   #:config-ssl-key
   #:config-oc-endpoint
   #:config-oc-api-key
   #:config-log-level
   #:config-max-connections
   #:config-heartbeat-interval
   #:config-heartbeat-timeout
   ;; Auth
   #:authenticate
   #:authenticate-token
   #:verify-token
   #:register-user
   #:register-by-phone
   #:register-by-email
   #:send-phone-code
   #:send-email-code
   #:create-session
   #:get-session
   #:invalidate-session
   #:get-user-by-username
   #:auth-result
   #:auth-result-success
   #:auth-result-user-id
   #:auth-result-username
   #:auth-result-token
   #:auth-result-error
   ;; Server lifecycle
   #:start-server
   #:stop-server
   #:*server-running*
   #:*server-start-time*
   #:*config*
   #:make-config
   ;; Gateway
   #:start-gateway
   #:stop-gateway
   #:*gateway-port*
   #:*gateway-host*
   #:get-connection
   #:register-connection
   #:unregister-connection
   #:get-user-connections
   #:start-heartbeat-monitor
   #:stop-heartbeat-monitor
   ;; Chat
   #:send-message
   #:get-history
   #:mark-as-read
   #:recall-message
   #:broadcast-message
   ;; Module management
   #:load-module
   #:unload-module
   #:reload-module
   #:list-modules
   #:get-module-status
   ;; Observability
   #:init-observability
   #:shutdown-observability
   #:register-health-check
   #:check-all-health
   #:get-metrics
   #:with-trace-span
   #:with-profiling
   #:register-alert
   #:handle-healthz
   #:handle-readyz
   #:handle-metrics
   ;; Utils
   #:now-unix
   #:now-unix-ms
   #:string-uuid
   #:lispim-string-contains-p
   #:lispim-string-empty-p
   #:lispim-string-present-p
   #:lispim-copy-hash-table
   #:lispim-hash-table-keys
   #:lispim-hash-table-values
   #:lispim-hash-table-alist
   #:lispim-hash-table-merge
   #:lispim-hash-table-filter
   ;; Conditions
   #:lispim-error
   #:connection-error
   #:auth-error
   #:message-error
   #:module-error
   #:e2ee-error
   ;; Snowflake
   #:generate-snowflake-id
   #:parse-snowflake-id
   #:snowflake-to-string
   #:string-to-snowflake
   #:reset-snowflake
   #:generate-message-id
   #:generate-user-id
   #:generate-conversation-id
   ;; Storage
   #:store-message
   #:get-message
   #:update-message
   #:store-conversation
   #:update-conversation
   #:query-messages
   #:create-user
   #:get-user
   #:get-user-by-username
   #:get-or-create-direct-conversation
   #:get-or-create-system-admin-conversation
   #:create-system-admin-conversation-for-user
   #:ensure-system-admin-exists
   #:get-conversations
   #:get-friends
   #:add-friend-request
   #:accept-friend-request
   #:get-friend-requests
   #:search-users
   #:update-user
   #:save-file-metadata
   #:get-file-metadata
   ;; Mobile / FCM
   #:save-fcm-token
   #:remove-fcm-token
   #:get-user-fcm-tokens))

(in-package :lispim-core)

;;;; 配置结构

(defstruct config
  "LispIM 服务器配置"
  (host "0.0.0.0" :type string)
  (port 4321 :type integer)
  (database-url "" :type string)
  (redis-url "" :type string)
  (ssl-cert nil :type (or null pathname))
  (ssl-key nil :type (or null pathname))
  (oc-endpoint "" :type string)
  (oc-api-key "" :type string)
  (log-level :info :type keyword)
  (max-connections 10000 :type integer)
  (heartbeat-interval 30 :type integer)
  (heartbeat-timeout 90 :type integer))

;;;; 全局配置

(defvar *config* (make-config)
  "全局配置对象")

(defvar *server-running* nil
  "服务器运行状态")

;;;; 网关配置

(defparameter *gateway-port* 3000
  "网关监听端口")

(defparameter *gateway-host* "0.0.0.0"
  "网关监听地址")
