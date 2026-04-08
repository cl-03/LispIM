;;;; client-config.lisp - Client Configuration
;;;;
;;;; Edit this file to set your auto-login credentials

;;;; Server Configuration
(defparameter *server-host* "localhost"
  "LispIM server host")

(defparameter *server-port* 3000
  "LispIM server port")

;;;; Login Credentials
(defparameter *username* "admin"
  "Username for auto-login")

(defparameter *password* "password"
  "Password for auto-login")

;;;; Client Settings
(defparameter *auto-reconnect* t
  "Automatically reconnect on connection loss")

(defparameter *reconnect-delay* 5
  "Seconds to wait before reconnecting")

(defparameter *heartbeat-interval* 30
  "Seconds between heartbeat messages")

;;;; Display Settings
(defparameter *show-debug-messages* nil
  "Show debug messages")

(defparameter *show-presence-updates* t
  "Show presence update notifications")

(defparameter *show-notifications* t
  "Show push notifications")
