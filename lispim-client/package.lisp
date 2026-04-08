;;;; package.lisp - LispIM Client Package Definition

(defpackage :lispim-client
  (:use :cl :alexandria)
  (:export
   ;; Client lifecycle
   #:make-client
   #:connect
   #:disconnect
   #:client-connected-p
   #:client-host
   #:client-port
   #:client-token
   #:client-user-id

   ;; Authentication
   #:login
   #:register
   #:logout

   ;; Chat operations
   #:send-message
   #:get-messages
   #:get-conversations
   #:mark-as-read

   ;; Presence
   #:get-online-users
   #:get-user-status

   ;; Message callbacks
   #:set-message-callback
   #:set-presence-callback
   #:set-notification-callback

   ;; Conditions
   #:client-error
   #:client-connection-error
   #:client-auth-error))
