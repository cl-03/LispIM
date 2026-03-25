;;;; package.lisp - OpenClaw Connector 包定义

(defpackage :openclaw-connector
  (:use :cl :alexandria)
  (:export
   ;; Server
   #:start-connector
   #:stop-connector
   #:*connector-running*
   ;; Connection
   #:oc-connect
   #:oc-disconnect
   #:oc-send
   #:oc-receive
   ;; Protocol
   #:make-oc-message
   #:encode-message
   #:decode-message
   #:*oc-protocol-version*
   ;; Handler
   #:register-handler
   #:unregister-handler
   ;; Stream
   #:oc-stream-open
   #:oc-stream-close
   #:oc-stream-send
   #:oc-stream-receive
   ;; Config
   #:*connector-host*
   #:*connector-port*
   #:*connector-api-key*))

(in-package :openclaw-connector)

;;;; 配置

(defparameter *connector-host* "0.0.0.0"
  "Connector 监听地址")

(defparameter *connector-port* 9000
  "Connector 监听端口")

(defparameter *connector-api-key* ""
  "API 密钥（用于认证）")

(defparameter *connector-running* nil
  "Connector 运行状态")

;;;; 协议版本

(defparameter *oc-protocol-version* "1.0"
  "OpenClaw 协议版本")
