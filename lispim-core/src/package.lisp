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
  (:shadow #:room)
  (:import-from :cl-ppcre :register-groups-bind)
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
   #:register-anonymous-user
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
   #:edit-message
   #:broadcast-message
   #:push-to-online-users
   #:push-to-online-user
   ;; WebSocket Protocol v1
   #:send-ws-message
   #:process-ws-message
   #:receive-from-connection
   #:+ws-msg-auth+
   #:+ws-msg-auth-response+
   #:+ws-msg-message+
   #:+ws-msg-message-received+
   #:+ws-msg-message-delivered+
   #:+ws-msg-message-read+
   #:+ws-msg-ping+
   #:+ws-msg-pong+
   #:+ws-msg-error+
   #:+ws-msg-notification+
   #:+ws-msg-presence+
   #:+ws-msg-typing+
   #:make-ws-message
   #:encode-ws-message
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
   ;; Middleware (new)
   #:middleware-pipeline
   #:middleware-entry
   #:make-pipeline
   #:add-middleware
   #:remove-middleware
   #:enable-middleware
   #:disable-middleware
   #:execute-pipeline
   #:register-default-middleware
   #:clear-all-middleware
   #:list-middleware
   #:get-middleware-status
   #:*websocket-pipeline*
   #:*pipeline-registry*
   #:middleware-pipeline-middlewares
   #:middleware-pipeline-lock
   #:middleware-pipeline-enabled
   #:middleware-entry-name
   #:middleware-entry-handler
   #:middleware-entry-order
   #:middleware-entry-enabled
   ;; Middleware handlers
   #:authentication-middleware
   #:rate-limit-middleware
   #:logging-middleware
   #:compression-middleware
   #:validation-middleware
   ;; Room management (new)
   #:room-id
   #:room-type
   #:room
   #:room-membership
   #:*rooms*
   #:*user-rooms*
   #:*room-online-cache*
   #:*room-online-cache-expire*
   #:create-room
   #:destroy-room
   #:get-room
   #:room-exists-p
   #:create-temporary-room
   #:temporary-room-p
   #:join-room
   #:leave-room
   #:remove-from-room
   #:get-room-members
   #:get-room-member-count
   #:get-user-rooms
   #:is-member-of-room-p
   #:get-user-room-role
   #:set-room-member-role
   #:can-send-message-p
   #:can-kick-member-p
   #:broadcast-to-room
   #:broadcast-to-room-except-sender
   #:get-room-online-members
   #:get-room-online-count
   #:get-room-online-members-cached
   #:get-room-stats
   #:*rooms-created-counter*
   #:*rooms-active-gauge*
   #:cleanup-temporary-rooms
   ;; Commands (new)
   #:define-command
   #:register-command
   #:parse-command
   #:parse-command-args
   #:execute-command
   #:send-command-message
   #:list-commands
   #:get-command-help
   #:get-commands-stats
   #:init-system-commands
   #:*commands-executed-counter*
   #:*commands-stats*
   #:*system-commands*
   #:*command-aliases*
   ;; Reactions (new)
   #:emoji
   #:reaction-id
   #:message-reaction
   #:init-reactions
   #:init-reactions-db
   #:add-reaction
   #:remove-reaction
   #:get-message-reactions
   #:get-message-reaction-count
   #:user-has-reacted-p
   #:get-user-reactions
   #:send-message-with-reaction
   #:cleanup-message-reactions
   #:get-suggested-reactions
   #:*common-emojis*
   #:get-reactions-stats
   #:*message-reactions*
   #:*reactions-counter*
   ;; Room management (new)
   ;; Online cache (new)
   #:get-room-online-members-wrapper
   #:init-online-cache
   #:get-online-cache-stats
   #:online-cache
   #:*online-cache*
   #:*online-cache-worker*
   #:*online-cache-running*
   #:*online-cache-config*
   #:online-cache-get
   #:online-cache-put
   #:online-cache-invalidate
   #:online-cache-clear
   #:compute-members-cache-key
   #:redis-get-online-cache
   #:redis-set-online-cache
   #:start-online-cache-cleanup
   #:stop-online-cache-cleanup
   #:reset-online-cache-stats
   #:shrink-online-cache
   #:cleanup-expired-cache
   #:string-hash
   #:online-cache-hit-rate
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
   #:ensure-default-users-exist
   #:get-conversations
   #:get-friends
   #:delete-friend
   #:add-friend-request
   #:accept-friend-request
   #:reject-friend-request
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
   #:*message-reply-config*
   ;; QR Code Services (扫一扫)
   #:generate-qr-code
   #:decode-and-verify-qr
   #:generate-group-qr-code
   #:*qr-secret-key*
   #:*qr-expiry-seconds*
   ;; Location Services (附近的人)
   #:store-user-location
   #:get-user-location
   #:delete-user-location
   #:get-nearby-users
   #:get-nearby-users-by-city
   #:set-location-privacy
   #:is-location-visible
   #:calculate-distance
   #:*location-ttl*
   #:*nearby-max-results*
   ;; Moments (朋友圈)
   #:ensure-moments-table-exists
   #:create-moment-post
   #:get-moment-post
   #:delete-moment-post
   #:get-moment-feed
   #:get-moment-comments
   #:get-moment-likes
   #:like-moment-post
   #:unlike-moment-post
   #:add-moment-comment
   #:delete-moment-comment
   #:*moment-max-photos*
   #:*moment-feed-page-size*
   #:*moment-ttl*
   ;; Contacts (通讯录)
   #:ensure-contacts-tables-exist
   #:create-contact-group
   #:get-contact-groups
   #:update-contact-group
   #:delete-contact-group
   #:add-friend-to-group
   #:remove-friend-from-group
   #:get-group-members
   #:get-friend-groups
   #:create-contact-tag
   #:get-contact-tags
   #:update-contact-tag
   #:delete-contact-tag
   #:add-tag-to-friend
   #:remove-tag-from-friend
   #:get-friend-tags
   #:set-contact-remark
   #:get-contact-remark
   #:add-to-blacklist
   #:remove-from-blacklist
   #:get-blacklist
   #:is-blocked
   #:add-star-contact
   #:remove-star-contact
   #:get-star-contacts
   #:is-star-contact
   #:search-contacts
   #:*max-contact-groups*
   #:*max-contact-tags*
   ;; File Transfer (大文件传输)
   #:ensure-file-transfer-tables-exist
   #:init-file-transfer
   #:get-file-transfer
   #:update-file-transfer-status
   #:record-file-chunk
   #:get-uploaded-chunks
   #:is-chunk-uploaded-p
   #:delete-file-transfer
   #:update-upload-progress
   #:get-upload-progress
   #:generate-chunk-id
   #:get-chunk-storage-path
   #:get-file-storage-path
   #:calculate-file-hash
   #:merge-file-chunks
   #:start-file-cleanup-worker
   #:stop-file-cleanup-worker
   #:*max-file-size*
   #:*chunk-size*
   #:*file-ttl*
   ;; Group (群聊)
   #:ensure-group-tables-exist
   #:create-group
   #:get-group
   #:update-group
   #:delete-group
   #:add-group-member
   #:remove-group-member
   #:get-group-members
   #:get-user-groups
   #:get-group-member
   #:update-group-member-role
   #:set-member-nickname
   #:set-member-quiet
   #:log-group-admin-action
   #:is-group-owner-p
   #:is-group-admin-p
   #:is-group-member-p
   #:can-invite-p
   ;; Group invite links (群邀请链接)
   #:group-invite-link
   #:make-group-invite-link
   #:group-invite-link-id
   #:group-invite-link-group-id
   #:group-invite-link-code
   #:group-invite-link-created-by
   #:group-invite-link-max-uses
   #:group-invite-link-used-count
   #:group-invite-link-expires-at
   #:group-invite-link-revoked-at
   #:group-invite-link-created-at
   #:generate-invite-code
   #:create-group-invite-link
   #:get-invite-link-by-code
   #:get-invite-link-by-id
   #:validate-invite-link
   #:join-group-via-invite
   #:revoke-invite-link
   #:get-group-invite-links
   #:notify-group-member-joined
   #:get-conversation-id-by-group-id
   ;; Favorites (收藏夹)
   #:ensure-favorites-tables-exist
   #:add-favorite
   #:remove-favorite
   #:get-favorites
   #:get-favorite
   #:update-favorite
   #:create-favorite-category
   #:get-favorite-categories
   #:update-favorite-category
   #:delete-favorite-category
   ;; Call (语音/视频通话)
   #:ensure-call-tables-exist
   #:create-call
   #:get-call
   #:update-call-status
   #:get-user-calls
   #:redis-call-signaling-channel
   #:publish-call-offer
   #:publish-call-answer
   #:publish-ice-candidate
   #:subscribe-call-signaling
   ;; Privacy (隐私增强)
   #:ensure-disappearing-message-tables-exist
   #:*disappearing-message-timers*
   #:*default-disappearing-timer*
   #:*delete-for-everyone-time-limit*
   #:*metadata-minimization-enabled*
   #:*minimal-metadata-retention-period*
   #:disappearing-message-config
   #:make-disappearing-message-config
   #:disappearing-message-config-enabled
   #:disappearing-message-config-timer-seconds
   #:disappearing-message-config-timer-start
   #:set-conversation-disappearing-messages
   #:get-conversation-disappearing-config
   #:schedule-message-deletion
   #:start-disappearing-message-worker
   #:stop-disappearing-message-worker
   #:cleanup-expired-messages
   #:delete-message-for-all
   #:delete-message-for-self
   #:notify-message-deleted
   #:authenticate-minimal
   #:log-minimal-connection-info
   #:cleanup-old-metadata
   #:start-metadata-cleanup-worker
   #:get-privacy-stats
   #:init-privacy-features
   #:shutdown-privacy-features
   ;; Privacy settings
   #:user-privacy-settings
   #:make-user-privacy-settings
   #:user-privacy-settings-hide-online-status
   #:user-privacy-settings-hide-read-receipt
   #:user-privacy-settings-show-profile-photo
   #:user-privacy-settings-show-last-seen
   #:get-user-privacy-settings
   #:set-user-privacy-settings
   #:user-hides-online-status
   #:user-hides-read-receipt
   #:can-show-user-profile-photo
   #:can-show-user-last-seen
   #:clear-user-privacy-settings-cache
   ;; Notification
   #:user-notification
   #:make-user-notification
   #:user-notification-id
   #:user-notification-user-id
   #:user-notification-type
   #:user-notification-title
   #:user-notification-content
   #:user-notification-data
   #:user-notification-priority
   #:user-notification-created-at
   #:user-notification-read-p
   #:user-notification-delivered-p
   #:notification-preferences
   #:make-notification-preferences
   #:notification-preferences-user-id
   #:notification-preferences-enable-desktop
   #:notification-preferences-enable-sound
   #:notification-preferences-enable-badge
   #:notification-preferences-message-notifications
   #:notification-preferences-call-notifications
   #:notification-preferences-friend-request-notifications
   #:notification-preferences-group-notifications
   #:notification-preferences-quiet-mode
   #:notification-preferences-quiet-start
   #:notification-preferences-quiet-end
   #:get-notification-preferences
   #:set-notification-preferences
   #:in-quiet-mode-p
   #:save-fcm-token
   #:remove-fcm-token
   #:get-user-fcm-tokens
   #:create-notification
   #:send-push-notification
   #:get-user-notifications
   #:mark-notification-read
   #:mark-all-notifications-read
   #:init-notification-system
   #:ensure-notification-tables-exist
   ;; Webhook
   #:webhook
   #:make-webhook
   #:webhook-id
   #:webhook-name
   #:webhook-url
   #:webhook-secret
   #:webhook-events
   #:webhook-enabled
   #:webhook-content-type
   #:webhook-headers
   #:webhook-retry-count
   #:webhook-timeout-seconds
   #:webhook-created-at
   #:webhook-updated-at
   #:webhook-last-triggered-at
   #:webhook-success-count
   #:webhook-failure-count
   #:webhook-delivery
   #:make-webhook-delivery
   #:webhook-delivery-id
   #:webhook-delivery-webhook-id
   #:webhook-delivery-event-type
   #:webhook-delivery-payload
   #:webhook-delivery-status
   #:webhook-delivery-attempt
   #:webhook-delivery-response-code
   #:webhook-delivery-response-body
   #:webhook-delivery-error-message
   #:webhook-delivery-created-at
   #:webhook-delivery-delivered-at
   #:create-webhook
   #:get-webhook
   #:get-all-webhooks
   #:update-webhook
   #:delete-webhook
   #:enable-webhook
   #:disable-webhook
   #:trigger-webhook
   #:queue-webhook-delivery
   #:deliver-webhook
   #:retry-webhook-delivery
   #:start-webhook-worker
   #:stop-webhook-worker
   #:get-webhook-stats
   #:get-webhook-deliveries
   #:init-webhook-system
   #:shutdown-webhook-system
   #:ensure-webhook-tables-exist
   ;; Poll
   #:group-poll
   #:make-group-poll
   #:poll-option
   #:make-poll-option
   #:poll-vote
   #:make-poll-vote
   #:ensure-poll-tables-exist
   #:create-poll
   #:get-poll
   #:get-poll-options
   #:get-poll-results
   #:cast-vote
   #:end-poll
   #:get-group-polls
   #:recalculate-vote-count
   ;; Message pinning
   #:pin-message
   #:unpin-message
   #:get-pinned-messages
   #:is-message-pinned
   ;; Markdown
   #:render-markdown
   #:markdown-to-html
   #:render-message-content
   #:parse-markdown-inline
   #:parse-markdown-block
   #:highlight-code
   #:escape-html
   #:*markdown-options*
   #:*max-nesting-level*
   ;; Translation
   #:translate-text
   #:translate-message
   #:translate-batch
   #:detect-language
   #:get-language-name
   #:record-translation
   #:get-translation-history
   #:get-translation-stats
   #:init-translation
   #:*supported-languages*
   #:*translation-options*
   #:*translation-cache*)
  (:export
   ;; Logging
   #:log-message
   #:log-debug
   #:log-info
   #:log-warn
   #:log-error))

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
