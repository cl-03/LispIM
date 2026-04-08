;;;; package.lisp - LispIM Client Package Definition

(defpackage :lispim-client
  (:use :cl)
  (:export
   ;; Client
   #:*client-version*
   #:*server-url*
   #:client
   #:make-lispim-client
   #:client-connect
   #:client-disconnect
   #:client-login
   #:client-logout
   #:client-get-conversations
   #:client-send-message
   #:client-mark-read
   #:client-get-messages
   #:start-client
   #:stop-client
   #:run
   ;; API Client
   #:api-client
   #:make-api-client
   #:api-client-base-url
   #:api-client-token
   #:api-client-timeout
   #:api-client-headers
   #:api-call
   #:api-client-login
   #:api-client-logout
   #:api-client-get-conversations
   #:api-client-get-messages
   #:api-client-send-message
   #:api-client-mark-message-read
   #:api-client-get-user-profile
   ;; WebSocket Client
   #:websocket-client
   #:make-websocket-client
   #:websocket-client-ws-client
   #:websocket-client-stream
   #:websocket-client-connected-p
   #:websocket-client-on-message-callback
   #:websocket-client-on-connected-callback
   #:websocket-client-on-disconnected-callback
   #:websocket-client-on-error-callback
   #:websocket-client-connect
   #:websocket-client-disconnect
   #:websocket-client-send-message
   #:websocket-client-send-raw
   #:websocket-client-send-binary
   #:websocket-client-reconnect
   #:websocket-client-ping
   #:websocket-client-keep-alive
   #:websocket-client-state
   #:print-websocket-status
   #:handle-incoming-message
   ;; Auth Manager
   #:auth-manager
   #:make-auth-manager
   #:auth-manager-api-client
   #:auth-manager-current-user
   #:auth-manager-token
   #:auth-manager-token-expires-at
   #:auth-manager-login-user
   #:auth-manager-logout-user
   #:auth-manager-current-user
   #:auth-manager-is-authenticated-p
   #:auth-manager-get-token
   #:auth-manager-refresh-token-if-needed
   ;; Client State
   #:client-state
   #:make-client-state
   #:state-current-conversation
   #:state-conversations
   #:state-messages
   #:state-users
   #:state-add-conversation
   #:state-set-conversations
   #:state-get-messages
   #:state-add-message
   #:state-add-user
   ;; Utils
   #:plist-get
   #:plist-set
   #:json-to-plist
   #:plist-to-json
   #:unix-to-universal-time
   #:universal-to-unix-time
   #:format-timestamp))

(defpackage :lispim-client/test
  (:use :cl)
  (:export
   #:run-all-tests
   #:test-api-client
   #:test-websocket
   #:test-auth))
