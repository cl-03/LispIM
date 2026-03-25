;;; Check Hunchentoot parameter handling
(require 'asdf)
(ql:quickload :hunchentoot :silent t)

;; Look at the macro expansion
(format t "~%Hunchentoot define-easy-handler lambda list:~%")
(describe 'hunchentoot:define-easy-handler)

;; Try to find documentation on path parameters
(format t "~%Looking at easy-handler parameter syntax...~%")

;; The URI pattern with :param creates a parameter that can be accessed
;; For wildcards, the syntax is different

(ql:quickload :cl-who :silent t)

;; Check if there's a way to accept path parameters
(format t "~nTrying to understand parameter binding...~%")

;; In Hunchentoot, for URI "/foo/:id", the :id is NOT automatically bound
;; You need to use a different approach

(sb-ext:quit)
