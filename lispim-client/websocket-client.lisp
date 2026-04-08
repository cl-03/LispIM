;;;; websocket-client.lisp - WebSocket Client Implementation
;;;;
;;;; Pure Common Lisp WebSocket client using usocket and cl+ssl
;;;; Implements RFC 6455 WebSocket protocol

(in-package :lispim-client)

;;;; WebSocket Constants

(defconstant +websocket-guid+ "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
  "WebSocket GUID for handshake")

(defconstant +op-text+  #b0001 "Text frame opcode")
(defconstant +op-binary+ #b0010 "Binary frame opcode")
(defconstant +op-close+ #b0000 "Close frame opcode")
(defconstant +op-ping+  #b1000 "Ping frame opcode")
(defconstant +op-pong+  #b1001 "Pong frame opcode")

;;;; Client Structure

(defstruct client
  "LispIM WebSocket Client"
  (host "localhost" :type string)
  (port 3000 :type integer)
  (socket nil)
  (stream nil)
  (connected nil :type boolean)
  (token nil :type (or null string))
  (user-id nil :type (or null string))
  (username nil :type (or null string))
  (message-callback nil)
  (presence-callback nil)
  (notification-callback nil)
  (receiver-thread nil)
  (heartbeat-thread nil)
  (heartbeat-interval 30 :type integer))

;;;; WebSocket Handshake

(defun generate-websocket-key ()
  "Generate a random Sec-WebSocket-Key (16 bytes base64 encoded)"
  (let ((key-bytes (make-array 16 :element-type '(unsigned-byte 8))))
    (dotimes (i 16)
      (setf (aref key-bytes i) (random 256)))
    (cl-base64:usb8-array-to-base64-string key-bytes)))

(defun websocket-handshake (client stream)
  "Perform WebSocket handshake"
  (let* ((key (generate-websocket-key))
         (host (client-host client))
         (port (client-port client))
         (lf (code-char 10))
         (request (concatenate 'string
                               "GET / HTTP/1.1" (string lf)
                               "Host: " host ":" (princ-to-string port) (string lf)
                               "Upgrade: websocket" (string lf)
                               "Connection: Upgrade" (string lf)
                               "Sec-WebSocket-Key: " key (string lf)
                               "Sec-WebSocket-Version: 13" (string lf)
                               "Sec-WebSocket-Protocol: lispim" (string lf)
                               (string lf)))
         (octets (flexi-streams:string-to-octets request)))
    (log-debug "Handshake request: ~a" request)
    (write-sequence octets stream)
    (finish-output stream)
    (log-debug "Handshake sent, waiting for response...")
    ;; Read response line by line until empty line
    (let ((response-line "")
          (header-line "")
          (byte nil))
      ;; Read first line (status line)
      (loop
        (setf byte (read-byte stream nil nil))
        (cond
          ((null byte)
           (log-error "Server closed connection during handshake")
           (error "Server closed connection during handshake"))
          ((= byte 10)
           (return))
          ((= byte 13))
          (t
           (setf response-line (concatenate 'string response-line (string (code-char byte)))))))
      (log-debug "Got response line: ~a" response-line)
      (unless (search "101" response-line)
        (log-error "WebSocket handshake failed: ~a" response-line)
        (error "WebSocket handshake failed: ~a" response-line))
      ;; Read headers until empty line
      (loop
        (setf header-line "")
        (loop
          (setf byte (read-byte stream nil nil))
          (when (null byte)
            (log-error "Unexpected EOF while reading headers")
            (error "Unexpected EOF while reading headers"))
          (cond
            ((= byte 10)
             (return))
            ((= byte 13))
            (t
             (setf header-line (concatenate 'string header-line (string (code-char byte)))))))
        ;; Empty header line = end of headers
        (when (string= header-line "")
          (log-debug "Headers finished")
          (return-from websocket-handshake t))
        (log-debug "Header: ~a" header-line)))
    (log-info "WebSocket handshake successful")
    t))

;;;; WebSocket Frame Encoding

(defun encode-websocket-frame (data &key (opcode +op-text+) (mask-p t))
  "Encode data as WebSocket frame"
  (let* ((text-bytes (flexi-streams:string-to-octets data))
         (payload-length (length text-bytes))
         (mask-key (if mask-p
                       (let ((key (make-array 4 :element-type '(unsigned-byte 8))))
                         (dotimes (i 4)
                           (setf (aref key i) (random 256)))
                         key)
                       nil))
         (header-size (+ 2
                         (cond ((< payload-length 126) 0)
                               ((< payload-length 65536) 2)
                               (t 8))
                         (if mask-p 4 0)))
         (frame (make-array (+ header-size payload-length)
                            :element-type '(unsigned-byte 8)))
         (idx 0))
    ;; First byte: FIN + opcode
    (setf (aref frame idx) (logior #b10000000 opcode))
    (incf idx)
    ;; Second byte: MASK + length
    (let ((len-byte (if mask-p #b10000000 0)))
      (cond
        ((< payload-length 126)
         (setf (aref frame idx) (logior len-byte payload-length)))
        ((< payload-length 65536)
         (setf (aref frame idx) (logior len-byte 126))
         (incf idx)
         (setf (aref frame idx) (ldb (byte 8 8) payload-length))
         (incf idx)
         (setf (aref frame idx) (ldb (byte 8 0) payload-length)))
        (t
         (setf (aref frame idx) (logior len-byte 127))
         (incf idx)
         (dotimes (i 8)
           (setf (aref frame idx) (ldb (byte 8 (- 56 (* i 8))) payload-length))
           (incf idx)))))
    (incf idx)
    ;; Mask key
    (when mask-key
      (dotimes (i 4)
        (setf (aref frame idx) (aref mask-key i))
        (incf idx)))
    ;; Payload (masked if needed)
    (dotimes (i payload-length)
      (let ((byte (aref text-bytes i)))
        (if mask-key
            (setf (aref frame idx) (logxor byte (aref mask-key (mod i 4))))
            (setf (aref frame idx) byte)))
      (incf idx))
    frame))

;;;; JSON utilities

(defun json-alist-to-plist (alist)
  "Convert JSON alist (string keys) to plist (keyword keys)"
  (cond
    ((null alist) nil)
    ((consp alist)
     (let ((result nil))
       (dolist (pair alist)
         (when (consp pair)
           (let* ((key (car pair))
                  (val (cdr pair))
                  (kw-key (if (stringp key)
                              (intern (string-upcase key) :keyword)
                              key))
                  (kw-val (if (listp val)
                              (json-alist-to-plist val)
                              val)))
             (push kw-key result)
             (push kw-val result))))
       (nreverse result)))
    (t alist)))

;;;; WebSocket Frame Decoding

(defun decode-websocket-frame (stream)
  "Decode a WebSocket frame from stream, returns (values payload opcode)"
  (handler-case
      (let* ((byte1 (read-byte stream))
             (fin (plusp (logand byte1 #b10000000)))
             (opcode (logand byte1 #b00001111))
             (byte2 (read-byte stream))
             (mask-p (plusp (logand byte2 #b10000000)))
             (len (logand byte2 #b01111111))
             (payload-length
              (cond
                ((< len 126) len)
                ((= len 126)
                 (let ((b1 (read-byte stream))
                       (b2 (read-byte stream)))
                   (logior (ash b1 8) b2)))
                (t
                 (let ((len 0))
                   (dotimes (i 8)
                     (setf len (logior (ash len 8) (read-byte stream))))
                   len))))
             (mask-key (when mask-p
                         (let ((key (make-array 4 :element-type '(unsigned-byte 8))))
                           (dotimes (i 4)
                             (setf (aref key i) (read-byte stream)))
                           key)))
             (payload (make-array payload-length :element-type '(unsigned-byte 8))))
        (read-sequence payload stream)
        ;; Unmask if needed
        (when mask-key
          (dotimes (i payload-length)
            (setf (aref payload i)
                  (logxor (aref payload i) (aref mask-key (mod i 4))))))
        ;; Convert to string for text frames
        (let ((result (if (or (= opcode +op-text+)
                              (= opcode +op-pong+)
                              (= opcode +op-ping+))
                          (flexi-streams:octets-to-string payload)
                          payload)))
          (values result opcode fin)))
    (error (c)
      (log-error "WebSocket frame decode error: ~a" c)
      (values nil +op-close+ t))))

;;;; Connection Management

(defun connect (client &key (timeout 30))
  "Connect to LispIM server via WebSocket"
  (declare (type client client)
           (type integer timeout))

  (let ((host (client-host client))
        (port (client-port client)))

    (log-info "Connecting to ~a:~a..." host port)

    (handler-case
        (progn
          ;; Create TCP connection
          (let* ((socket (usocket:socket-connect host port :element-type '(unsigned-byte 8)))
                 (stream (usocket:socket-stream socket)))
            (declare (ignore timeout)) ;; Future: use timeout for connection

            (log-info "TCP connected, starting handshake...")

            ;; Perform WebSocket handshake
            (websocket-handshake client stream)

            (setf (client-socket client) socket
                  (client-stream client) stream
                  (client-connected client) t)

            (log-info "Connected to ~a:~a" host port)

            ;; Start message receiver thread
            (start-receiver-thread client)

            ;; Start heartbeat thread
            (start-heartbeat-thread client)

            t))

      (error (c)
        (log-error "Connection failed: ~a" c)
        (setf (client-connected client) nil)
        (error 'client-connection-error
               :host host
               :port port
               :message (princ-to-string c))))))

(defun disconnect (client)
  "Disconnect from server"
  (declare (type client client))

  (when (client-connected client)
    (log-info "Disconnecting...")

    ;; Stop receiver thread
    (when (client-receiver-thread client)
      (bordeaux-threads:destroy-thread (client-receiver-thread client)))

    ;; Stop heartbeat thread
    (when (client-heartbeat-thread client)
      (bordeaux-threads:destroy-thread (client-heartbeat-thread client)))

    ;; Close socket
    (when (client-socket client)
      (handler-case
          (usocket:socket-close (client-socket client))
        (error () nil)))

    (setf (client-connected client) nil
          (client-socket client) nil
          (client-stream client) nil)

    (log-info "Disconnected")))

(defun client-connected-p (client)
  "Check if client is connected"
  (declare (type client client))
  (client-connected client))

;;;; Message Sending

(defun send-message (client message)
  "Send a message to server via WebSocket"
  (declare (type client client))

  (unless (client-connected client)
    (error 'client-error :message "Not connected"))

  (let ((stream (client-stream client))
        (json (cl-json:encode-json-to-string message)))

    ;; Encode as WebSocket text frame and send
    (let ((frame (encode-websocket-frame json :opcode +op-text+ :mask-p t)))
      (write-sequence frame stream)
      (finish-output stream))))

(defun make-message (type &rest args)
  "Create a message hash-table"
  (let ((msg (make-hash-table :test 'equal)))
    (setf (gethash "type" msg) type)
    (loop for (key value) on args by #'cddr
          do (setf (gethash (string-downcase (string key)) msg) value))
    msg))

;;;; Message Receiving

(defun read-message (client)
  "Read a message from server via WebSocket (blocking)"
  (declare (type client client))

  (let ((stream (client-stream client)))
    (unless stream
      (return-from read-message nil))

    (handler-case
        (multiple-value-bind (payload opcode fin) (decode-websocket-frame stream)
          (declare (ignore fin))

          (cond
            ((null payload)
             nil)
            ((= opcode +op-close+)
             (log-info "Received close frame")
             nil)
            ((= opcode +op-ping+)
             ;; Respond with pong
             (let ((pong-frame (encode-websocket-frame payload :opcode +op-pong+ :mask-p t)))
               (write-sequence pong-frame stream)
               (finish-output stream))
             nil)
            ((= opcode +op-pong+)
             ;; Heartbeat response, ignore
             nil)
            ((= opcode +op-text+)
             ;; Parse JSON payload and convert alist to plist
             (let ((parsed (cl-json:decode-json-from-string payload)))
               (json-alist-to-plist parsed)))
            (t
             (log-debug "Unknown opcode: ~a" opcode)
             nil)))

      (error (c)
        (log-error "Read error: ~a" c)
        nil))))

;;;; Receiver Thread

(defun start-receiver-thread (client)
  "Start background thread to receive messages"
  (declare (type client client))

  (setf (client-receiver-thread client)
        (bordeaux-threads:make-thread
         (lambda ()
           (loop while (client-connected client)
                 do (handler-case
                        (let ((msg (read-message client)))
                          (when msg
                            (process-incoming-message client msg)))
                      (error (c)
                        (log-error "Receiver error: ~a" c)
                        (sleep 1)))))
         :name "LispIM-Receiver")))

(defun process-incoming-message (client message)
  "Process an incoming message"
  (declare (type client client))

  (let ((type (getf message :type)))
    (log-debug "Processing message type: ~a (type: ~a)" type (type-of type))
    (cond
      ((string-equal type "MESSAGE_RECEIVED")
       (when (client-message-callback client)
         (funcall (client-message-callback client) message)))

      ((string-equal type "AUTHRESPONSE")
       (log-info "Authentication response received: ~a" (getf message :payload)))

      ((string-equal type "PRESENCE")
       (when (client-presence-callback client)
         (funcall (client-presence-callback client) message)))

      ((string-equal type "NOTIFICATION")
       (when (client-notification-callback client)
         (funcall (client-notification-callback client) message)))

      ((string-equal type "PONG")
       ;; Heartbeat response, ignore
       )

      (t
       (log-debug "Unknown message type: ~a" type)))))

;;;; Heartbeat

(defun start-heartbeat-thread (client)
  "Start background thread for heartbeat using WebSocket Ping frames"
  (declare (type client client))

  (setf (client-heartbeat-thread client)
        (bordeaux-threads:make-thread
         (lambda ()
           (loop while (client-connected client)
                 do (sleep (client-heartbeat-interval client))
                    (handler-case
                        (let ((stream (client-stream client)))
                          (when stream
                            (let ((ping-frame (encode-websocket-frame "" :opcode +op-ping+ :mask-p t)))
                              (write-sequence ping-frame stream)
                              (finish-output stream))))
                      (error (c)
                        (log-error "Heartbeat failed: ~a" c)))))
         :name "LispIM-Heartbeat")))

;;;; Callbacks

(defun set-message-callback (client callback)
  "Set callback for incoming messages"
  (declare (type client client)
           (type function callback))
  (setf (client-message-callback client) callback))

(defun set-presence-callback (client callback)
  "Set callback for presence updates"
  (declare (type client client)
           (type function callback))
  (setf (client-presence-callback client) callback))

(defun set-notification-callback (client callback)
  "Set callback for notifications"
  (declare (type client client)
           (type function callback))
  (setf (client-notification-callback client) callback))
