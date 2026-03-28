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
   #:get-user-fcm-tokens
   ;; Message Status Tracking
   #:update-message-status
   #:get-message-status
   #:store-message-with-status
   #:status-code-to-keyword
   #:status-keyword-to-code
   #:enqueue-failed-message
   #:dequeue-failed-messages
   #:should-retry-message-p
   #:get-retry-delay
   #:start-retry-worker
   #:stop-retry-worker
   #:create-message-ack
   #:acknowledge-message
   #:check-ack-timeouts
   #:ensure-message-status-column
   ;; Message Encoding
   #:encode-message-tlv
   #:decode-message-tlv
   #:encode-tlv-string
   #:encode-tlv-uint64
   #:encode-tlv-list
   #:decode-tlv-list
   #:encode-message-with-compression
   #:calculate-compression-ratio
   ;; Message Compression
   #:compress-salza2
   #:decompress-salza2
   #:compress-data
   #:decompress-data
   #:should-compress-p
   #:compress-message-if-needed
   #:decompress-message-content
   #:get-compression-ratio
   #:get-compression-stats-report
   ;; Multi-level Cache
   #:init-multi-level-cache
   #:mlc-get
   #:mlc-put
   #:mlc-remove
   #:mlc-clear
   #:mlc-stats
   #:cache-message
   #:get-cached-message
   #:remove-cached-message
   #:cache-user
   #:get-cached-user
   #:cache-conversation
   #:get-cached-conversation
   #:cache-health-check
   #:print-cache-stats
   #:*multi-level-cache*
   #:*bloom-filter*
   ;; Offline Message Queue
   #:init-offline-queue
   #:enqueue-offline-message
   #:dequeue-offline-messages
   #:get-offline-message-count
   #:start-offline-queue-worker
   #:stop-offline-queue-worker
   #:get-offline-queue-stats
   #:print-offline-queue-stats
   #:send-message-with-offline-queue
   #:*offline-queue*
   #:*offline-queue-worker*
   ;; Client Incremental Sync
   #:init-sync
   #:sync-messages
   #:sync-conversations
   #:full-sync
   #:handle-sync-request
   #:get-sync-anchor
   #:set-sync-anchor
   #:resolve-sync-conflict
   #:get-sync-stats
   #:*sync-config*
   #:*sync-stats*
   ;; Redis Streams Message Queue
   #:init-message-queue
   #:enqueue-message
   #:enqueue-message-batch
   #:dequeue-message
   #:dequeue-messages
   #:ack-message
   #:nack-message
   #:start-message-consumer
   #:stop-message-consumer
   #:get-message-queue-stats
   #:print-message-queue-stats
   #:*message-queue*
   #:*message-queue-consumer*
   #:*message-queue-running*
   #:*message-queue-config*
   ;; Multi-instance Cluster
   #:init-cluster
   #:shutdown-cluster
   #:publish-to-cluster
   #:get-user-instance
   #:set-user-instance
   #:user-local-p
   #:send-to-remote-user
   #:get-cluster-stats
   #:print-cluster-stats
   #:*cluster*
   #:*cluster-config*
   ;; Double Ratchet E2EE
   #:make-double-ratchet
   #:double-ratchet-encrypt
   #:double-ratchet-decrypt
   #:double-ratchet-receive-ratchet
   #:create-e2ee-session
   #:store-e2ee-session
   #:get-e2ee-session
   #:e2ee-encrypt
   #:e2ee-decrypt
   #:get-e2ee-stats
   #:record-e2ee-stat
   #:*e2ee-sessions*
   #:*double-ratchet-config*
   ;; E2EE low-level
   #:dh-generate-keypair
   #:dh-calculate-shared-secret
   #:kdf
   #:kdf-chain
   ;; CDN Storage
   #:init-cdn-storage
   #:cdn-upload
   #:cdn-download
   #:cdn-delete
   #:cdn-get-url
   #:cdn-generate-thumbnail
   #:upload-file
   #:download-file
   #:delete-file
   #:generate-cdn-url
   #:generate-thumbnail
   #:get-file-metadata
   #:get-cdn-stats
   #:*cdn-storage*
   #:*cdn-providers*
   #:*cdn-config*
   #:cdn-config-get
   #:get-cdn-provider-config
   ;; DB Replica
   #:init-db-replica
   #:*db-replica*
   #:with-master-db
   #:with-slave-db
   #:get-master-connection
   #:get-slave-connection
   #:db-write
   #:db-read
   #:start-health-check-worker
   #:check-slave-health
   #:recover-slave
   #:get-db-replica-stats
   #:db-init-replica
   #:db-write-row
   #:db-read-row
   #:db-update-row
   #:db-delete-row
   #:shutdown-db-replica
   ;; Message Deduplication
   #:init-message-deduplicator
   #:init-message-dedup
   #:*message-deduplicator*
   #:dedup-check-message
   #:is-duplicate-message-p
   #:generate-message-fingerprint
   #:message-fingerprint-to-string
   #:bloom-filter-add
   #:bloom-filter-contains-p
   #:cleanup-dedup-window
   #:start-dedup-cleanup-worker
   #:stop-dedup-cleanup-worker
   #:dedup-check-message-redis
   #:get-dedup-stats
   #:get-message-dedup-stats
   #:with-idempotent-operation
   #:shutdown-message-dedup
   ;; Rate Limiter
   #:init-rate-limiter
   #:init-rate-limiting
   #:*rate-limiter*
   #:make-token-bucket
   #:token-bucket-try-acquire
   #:token-bucket-get-tokens
   #:make-leaky-bucket
   #:leaky-bucket-try-acquire
   #:make-sliding-window
   #:sliding-window-try-acquire
   #:sliding-window-get-count
   #:make-fixed-window
   #:fixed-window-try-acquire
   #:rate-limit-allow-p
   #:rate-limit-remaining
   #:redis-rate-limit-allow-p
   #:get-preset-limit
   #:check-rate-limit
   #:*preset-rate-limits*
   #:get-rate-limiter-stats
   #:get-rate-limit-stats
   #:cleanup-rate-limiter
   #:shutdown-rate-limiting
   ;; Fulltext Search
   #:init-fulltext-search
   #:init-search
   #:*search-engine*
   #:search
   #:search-messages
   #:search-contacts
   #:search-conversations
   #:highlight-text
   #:highlight-search-result
   #:tokenize-text
   #:build-inverted-index
   #:add-to-index
   #:search-in-index
   #:get-search-stats
   #:start-search-sync-worker
   #:stop-search-sync-worker
   #:shutdown-fulltext-search
   ;; Message Reply
   #:create-reply
   #:get-reply-to-message
   #:get-reply-chain
   #:get-message-replies
   #:get-reply-thread
   #:send-reply-message
   #:generate-quote-preview
   #:format-quote-display
   #:get-cached-reply-thread
   #:cache-reply-thread
   #:get-reply-stats
   #:delete-reply
   #:delete-reply-thread
   #:create-message-reply
   #:get-message-reply-info
   #:*message-reply-config*))

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
