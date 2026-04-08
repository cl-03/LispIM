;;;; websocket-client.lisp - WebSocket Client (usocket fallback)
;;;;
;;;; This is a fallback implementation when cl-websocket is not available.
;;;; For full WebSocket protocol support, install cl-websocket:
;;;;   (ql:quickload :cl-websocket)

(in-package :lispim-client)

;; ============================================================================
;; WebSocket Client class
;; ============================================================================

(defclass websocket-client ()
  ((stream :accessor websocket-client-stream
           :initform nil
           :documentation "WebSocket stream")
   (connected-p :accessor websocket-client-connected-p
                :initform nil
                :documentation "Connection status")
   (on-message-callback :accessor websocket-client-on-message-callback
                        :initarg :on-message
                        :initform nil
                        :documentation "Callback for incoming messages")
   (on-connected-callback :accessor websocket-client-on-connected-callback
                          :initarg :on-connected
                          :initform nil
                          :documentation "Callback when connected")
   (on-disconnected-callback :accessor websocket-client-on-disconnected-callback
                             :initarg :on-disconnected
                             :initform nil
                             :documentation "Callback when disconnected")
   (on-error-callback :accessor websocket-client-on-error-callback
                      :initarg :on-error
                      :initform nil
                      :documentation "Callback for errors")
   (listener-thread :accessor websocket-client-listener-thread
                    :initform nil
                    :documentation "Thread for listening to messages")
   (url :accessor websocket-client-url
        :initform nil
        :documentation "Current WebSocket URL"))
  (:documentation "WebSocket client for real-time message push (usocket fallback)"))

(defun make-websocket-client (&key (on-message nil)
                                   (on-connected nil)
                                   (on-disconnected nil)
                                   (on-error nil))
  "Create a new WebSocket client instance"
  (make-instance 'websocket-client
                 :on-message on-message
                 :on-connected on-connected
                 :on-disconnected on-disconnected
                 :on-error on-error))

;; ============================================================================
;; URL parsing
;; ============================================================================

(defun parse-ws-url (url)
  "Parse WebSocket URL into components
   Returns: (scheme host port path)
   Example: ws://localhost:3000/ws => (\"ws\" \"localhost\" 3000 \"/ws\")"
  (let ((parsed (quri:uri url)))
    (list (quri:uri-scheme parsed)
          (quri:uri-host parsed)
          (or (quri:uri-port parsed)
              (if (equal (quri:uri-scheme parsed) "wss") 443 80))
          (quri:uri-path parsed))))

(defun ws-url-to-http (ws-url)
  "Convert WebSocket URL to HTTP URL for request"
  (let ((parsed (quri:uri ws-url)))
    ;; For logging/debugging
    (quri:render-uri parsed)))

;; ============================================================================
;; Connection management (stub implementation)
;; ============================================================================

(defun websocket-client-connect (client url &key (token nil))
  "Connect to WebSocket server (stub - requires cl-websocket for full support)"
  (declare (ignore token))
  (format t "~%; WARNING: cl-websocket not installed.~%")
  (format t "For full WebSocket support, run: (ql:quickload :cl-websocket)~%")

  (setf (websocket-client-url client) url)

  ;; For now, just mark as "connected" in stub mode
  ;; Real implementation requires cl-websocket library
  (setf (websocket-client-connected-p client) nil)

  (values nil "cl-websocket library not installed. Install with (ql:quickload :cl-websocket)"))

(defun websocket-client-disconnect (client)
  "Disconnect from WebSocket server"
  (handler-case
      (progn
        ;; Stop listener thread
        (when (websocket-client-listener-thread client)
          (bt:destroy-thread (websocket-client-listener-thread client))
          (setf (websocket-client-listener-thread client) nil))

        ;; Close stream
        (when (websocket-client-stream client)
          (close (websocket-client-stream client))
          (setf (websocket-client-stream client) nil))

        ;; Update state
        (setf (websocket-client-connected-p client) nil
              (websocket-client-url client) nil)

        ;; Call disconnected callback
        (when (websocket-client-on-disconnected-callback client)
          (funcall (websocket-client-on-disconnected-callback client)))

        (values t "Disconnected"))
    (error (e)
      (values nil (format nil "Disconnect error: ~A" e)))))

;; ============================================================================
;; Message handling
;; ============================================================================

(defun handle-incoming-message (client message)
  "Handle an incoming WebSocket message"
  (when (websocket-client-on-message-callback client)
    (funcall (websocket-client-on-message-callback client) message)))

(defun websocket-client-send-message (client type payload)
  "Send a message through WebSocket"
  (if (websocket-client-connected-p client)
      (handler-case
          (let ((message (cl-json:encode-json-to-string
                          `(:type ,type :payload ,payload))))
            ;; Stub - would need real WebSocket stream
            (declare (ignore message))
            (values nil "Not connected - cl-websocket required"))
          (error (e)
            (values nil (format nil "Send error: ~A" e))))
      (values nil "Not connected - install cl-websocket")))

(defun websocket-client-send-raw (client message-string)
  "Send a raw text message through WebSocket"
  (declare (ignore message-string))
  (if (websocket-client-connected-p client)
      (values nil "Not connected - cl-websocket required")
      (values nil "Not connected - install cl-websocket")))

;; ============================================================================
;; Reconnection support
;; ============================================================================

(defun websocket-client-reconnect (client url &key (token nil) (max-retries 5) (retry-delay 2))
  "Reconnect to WebSocket server with retry logic"
  (declare (ignore client url token max-retries retry-delay))
  (values nil "cl-websocket library not installed"))

(defun websocket-client-send-binary (client data)
  "Send binary data through WebSocket"
  (declare (ignore client data))
  (values nil "cl-websocket library not installed"))

(defun websocket-client-ping (client)
  "Send ping to WebSocket server"
  (declare (ignore client))
  (values nil "cl-websocket library not installed"))

(defun websocket-client-keep-alive (client &key (interval 30))
  "Start keep-alive ping thread"
  (declare (ignore client interval))
  (format t "~%WARNING: Keep-alive requires cl-websocket~%"))

(defun websocket-client-state (client)
  "Get WebSocket client state"
  (list :connected-p (websocket-client-connected-p client)
        :url (websocket-client-url client)
        :has-stream (if (websocket-client-stream client) t nil)
        :has-thread (if (websocket-client-listener-thread client) t nil)
        :note "cl-websocket not installed"))

(defun print-websocket-status (client)
  "Print WebSocket status to stdout"
  (format t "~%=== WebSocket Status ===~%")
  (format t "Connected: ~A~%" (websocket-client-connected-p client))
  (format t "URL: ~A~%" (websocket-client-url client))
  (format t "Stream: ~A~%" (if (websocket-client-stream client) "Yes" "No"))
  (format t "Thread: ~A~%" (if (websocket-client-listener-thread client) "Yes" "No"))
  (format t "NOTE: Install cl-websocket for full functionality~%"))
