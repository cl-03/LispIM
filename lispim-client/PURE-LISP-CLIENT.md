# LispIM Pure Lisp Client

纯 Common Lisp 实现的 WebSocket 客户端，用于连接 LispIM 服务器。

## 快速开始

### 1. 启动服务器

```bash
cd lispim-core
sbcl --load start-server.lisp
```

### 2. 运行测试客户端

```bash
cd lispim-client
sbcl --load test-client.lisp
```

### 3. 交互式使用

```lisp
;; 加载系统
(load "C:/Users/Administrator/quicklisp/setup.lisp")
(ql:quickload :lispim-client)
(use-package :lispim-client)

;; 创建客户端
(defparameter *client* (make-client :host "localhost" :port 3000))

;; 设置回调
(setf (client-message-callback *client*)
      (lambda (msg)
        (let ((type (getf msg :type)))
          (cond
            ((string-equal type "AUTHRESPONSE")
             (format t "Auth: ~a~%" (getf msg :payload)))
            ((string-equal type "MESSAGE_RECEIVED")
             (format t "Message: ~a~%" msg))
          (t
             (format t "Other: ~a~%" type))))))

;; 连接
(connect *client*)

;; 登录
(login *client* "username" "password")

;; 发送消息
(send-chat-message *client* "recipient-id" "Hello, World!")

;; 断开
(disconnect *client*)
```

## API 参考

### 连接管理

- `(make-client &key host port)` - 创建客户端实例
- `(connect client)` - 连接到服务器
- `(disconnect client)` - 断开连接
- `(client-connected-p client)` - 检查是否连接

### 认证

- `(login client username password)` - 登录
- `(register client username password &key email phone)` - 注册
- `(logout client)` - 登出
- `(authenticate-token client token)` - 使用 token 认证

### 消息

- `(send-chat-message client recipient-id content &key content-type)` - 发送聊天消息
- `(send-typing client recipient-id)` - 发送正在输入状态
- `(mark-read client message-id)` - 标记消息已读

### 回调

- `(set-message-callback client callback)` - 设置消息回调
- `(set-presence-callback client callback)` - 设置在线状态回调
- `(set-notification-callback client callback)` - 设置通知回调

## 消息格式

### 发送消息

```lisp
;; 内部消息格式（hash-table）
(make-message "CHAT" :recipient "user-id" :content "Hello")
```

### 接收消息

```lisp
;; 接收到的消息（plist with keyword keys）
(:TYPE "MESSAGE_RECEIVED"
 :PAYLOAD (:SENDER "user-id"
          :CONTENT "Hello"
          :TIMESTAMP 1234567890))
```

## WebSocket 协议

客户端实现 RFC 6455 WebSocket 协议：

1. **握手**: 发送 HTTP Upgrade 请求，接收 101 Switching Protocols
2. **帧格式**: 支持文本帧（opcode=1）、Ping（opcode=9）、Pong（opcode=10）
3. **消息编码**: JSON over WebSocket text frames
4. **心跳**: 自动响应服务器的 Ping 帧

## 依赖

- usocket - TCP 套接字
- bordeaux-threads - 多线程
- cl-base64 - Base64 编码（WebSocket 握手）
- flexi-streams - 字节/字符串转换
- cl+ssl - SSL/TLS 支持
- cl-json - JSON 编码/解码
- ironclad - 加密（用于 WebSocket 握手）

## 故障排除

### 连接失败

检查服务器是否运行在指定端口：
```bash
netstat -an | grep 3000
```

### 认证失败

确保用户名和密码正确，检查服务器日志。

### 消息未收到

检查回调是否正确设置，确认接收线程正在运行。

## 与 Web/Tauri 客户端的区别

纯 Lisp 客户端使用相同的服务端 API，但：

1. **协议**: 使用 JSON over WebSocket（与 Web 客户端相同）
2. **数据结构**: 接收消息转换为 Lisp plist 而非 JavaScript 对象
3. **回调**: 使用 Common Lisp 函数而非事件监听器
4. **线程**: 使用 Bordeaux Threads 而非 JavaScript Promise/async

## 示例应用

参见 `cli.lisp` 和 `repl-client.lisp` 获取完整的交互式客户端示例。
