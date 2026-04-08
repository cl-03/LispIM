;;;; package.lisp - UI Package definition

(defpackage :lispim-client/ui
  (:use :cl :lispim-client)
  (:export
   ;; Frames
   #:open-login-frame
   #:open-main-frame
   #:open-ai-settings-frame
   #:close-login-frame
   #:close-main-frame
   #:close-ai-settings-frame
   ;; Commands
   #:com-login
   #:com-logout
   #:com-send-message
   #:com-select-conversation
   #:com-load-messages
   #:com-save-ai-settings
   #:com-cancel-ai-settings
   #:com-load-ai-config))
