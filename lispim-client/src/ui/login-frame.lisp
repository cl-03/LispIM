;;;; login-frame.lisp - Login Frame using McCLIM

(in-package :lispim-client/ui)

;; ============================================================================
;; Login Frame Application
;; ============================================================================

(define-application-frame login-frame ()
  ((client :accessor frame-client
           :initarg :client
           :documentation "LispIM client instance"))
  (:panes
   (title :title-pane
          "LispIM - Login"
          :align-x :center
          :align-y :center)
   
   (username :text-field-pane
             :value ""
             :label "Username:"
             :documentation "Username input field")
   
   (password :text-field-pane
             :value ""
             :label "Password:"
             :documentation "Password input field")
   
   (status :output-pane
           :value ""
           :align-x :center
           :documentation "Status message display")
   
   (login-button :push-button
                 "Login"
                 :documentation "Login button"))
   
  (:layouts
   (default
    (vertically ()
      (title)
      (spacer () (make-instance 'spacer :width 20 :height 20))
      username
      (spacer () (make-instance 'spacer :width 20 :height 10))
      password
      (spacer () (make-instance 'spacer :width 20 :height 20))
      login-button
      (spacer () (make-instance 'spacer :width 20 :height 20))
      status)))

  (:command-table (login-frame))
  
  (:top-level (login-frame-top-level)))

;; ============================================================================
;; Commands
;; ============================================================================

(define-command (com-login) ()
  "Login with provided credentials"
  (let* ((frame *application-frame*)
         (client (frame-client frame))
         (username (frame-value frame 'username))
         (password (frame-value frame 'password))
         (status-pane (find-pane-from-instance frame 'status)))
    
    (when (and (string/= username "") (string/= password ""))
      ;; Clear status
      (setf (sheet-text status-pane) "Logging in...")
      
      ;; Attempt login
      (multiple-value-bind (success result)
          (client-login client username password)
        (if success
            (progn
              (setf (sheet-text status-pane) "Login successful!")
              ;; Open main frame
              (open-main-frame client))
            (setf (sheet-text status-pane)
                  (format nil "Login failed: ~A" result)))))))

(define-command (com-cancel) ()
  "Cancel login"
  (frame-top-level-exit *application-frame*))

;; ============================================================================
;; Top-level loop
;; ============================================================================

(defun login-frame-top-level (frame)
  "Main event loop for login frame"
  (with-input-context (frame)
    (keyboard)
    (do ()
        ((frame-top-level-exit-p frame))
      (handle-event frame (next-event)))))

;; ============================================================================
;; Frame management
;; ============================================================================

(defvar *login-frame* nil
  "Current login frame instance")

(defun open-login-frame (client)
  "Open the login frame"
  (let ((frame (make-application-frame 'login-frame :client client)))
    (setf *login-frame* frame)
    (run-frame-top-level frame)))

(defun close-login-frame ()
  "Close the login frame"
  (when *login-frame*
    (frame-top-level-exit *login-frame*)
    (setf *login-frame* nil)))
