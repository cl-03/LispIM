;;;; ai-settings.lisp - AI Settings Panel using McCLIM

(in-package :lispim-client/ui)

;; ============================================================================
;; AI Settings Frame
;; ============================================================================

(define-application-frame ai-settings-frame ()
  ((client :accessor frame-client
           :initarg :client
           :documentation "LispIM client instance")
   (ai-config :accessor frame-ai-config
              :initform nil
              :documentation "Current AI config"))
  (:panes
   ;; AI Enable/Disable toggle
   (ai-enabled :toggle-button
               "Enable AI"
               :value nil
               :documentation "Enable/disable AI assistant")

   ;; Backend selection
   (backend-selector :dropdown-pane
                     :items '("openclaw" "openai" "claude" "local")
                     :value "openclaw"
                     :label "AI Backend:"
                     :documentation "Select AI backend")

   ;; Model selection
   (model-selector :dropdown-pane
                   :items '("gpt-4" "gpt-3.5-turbo" "claude-3" "local-model")
                   :value "gpt-4"
                   :label "Model:"
                   :documentation "Select AI model")

   ;; Personality selection
   (personality-selector :dropdown-pane
                         :items '("assistant" "creative" "precise" "friendly" "teacher" "coder")
                         :value "assistant"
                         :label "Personality:"
                         :documentation "Select AI personality")

   ;; Context length slider
   (context-length :slider-pane
                   :value 4096
                   :min-value 512
                   :max-value 32768
                   :label "Context Length:"
                   :documentation "AI context length")

   ;; Streaming toggle
   (streaming-enabled :toggle-button
                      "Enable Streaming"
                      :value t
                      :documentation "Enable streaming responses")

   ;; Budget limit
   (budget-limit :text-field-pane
                 :value "100.0"
                 :label "Monthly Budget (USD):"
                 :documentation "Monthly budget limit")

   ;; Save button
   (save-button :push-button
                "Save Settings"
                :documentation "Save AI settings")

   ;; Cancel button
   (cancel-button :push-button
                  "Cancel"
                  :documentation "Cancel changes")

   ;; Status display
   (status :output-pane
           :value ""
           :documentation "Status message"))

  (:layouts
   (default
    (vertically ()
      (make-pane 'accepting-values-pane
                 :display-function 'draw-ai-settings-header
                 :height 50)
      ai-enabled
      (spacer () (make-instance 'spacer :height 10))
      backend-selector
      (spacer () (make-instance 'spacer :height 10))
      model-selector
      (spacer () (make-instance 'spacer :height 10))
      personality-selector
      (spacer () (make-instance 'spacer :height 10))
      context-length
      (spacer () (make-instance 'spacer :height 10))
      streaming-enabled
      (spacer () (make-instance 'spacer :height 10))
      budget-limit
      (spacer () (make-instance 'spacer :height 20))
      (horizontally ()
        save-button
        (spacer () (make-instance 'spacer :width 20))
        cancel-button)
      (spacer () (make-instance 'spacer :height 10))
      status)))

  (:command-table (ai-settings-frame))

  (:top-level (ai-settings-frame-top-level)))

;; ============================================================================
;; Display functions
;; ============================================================================

(defun draw-ai-settings-header (frame pane)
  "Draw AI settings header"
  (with-text-style (pane (:size :large :weight :bold))
    (draw-text* pane "AI Assistant Settings" 10 10))
  (with-text-style (pane (:size :small))
    (draw-text* pane "Configure your AI assistant preferences" 10 30)))

;; ============================================================================
;; Frame management
;; ============================================================================

(defvar *ai-settings-frame* nil
  "Current AI settings frame instance")

(defun open-ai-settings-frame (client)
  "Open the AI settings frame"
  (let ((frame (make-application-frame 'ai-settings-frame :client client)))
    (setf *ai-settings-frame* frame)
    (run-frame-top-level frame)))

(defun close-ai-settings-frame ()
  "Close the AI settings frame"
  (when *ai-settings-frame*
    (frame-top-level-exit *ai-settings-frame*)
    (setf *ai-settings-frame* nil)))
