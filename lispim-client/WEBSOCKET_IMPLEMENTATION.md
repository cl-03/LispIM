# WebSocket 实现报告

**日期**: 2026-04-08
**状态**: 完成

## 概述

使用 `cl-websocket` 库实现了完整的 WebSocket 协议支持，替换了之前的简化实现。

## 主要改进

### 1. 完整的 WebSocket 协议支持

**之前（简化实现）**：
- 手动实现 WebSocket 握手（不完整）
- 原始 TCP socket 通信
- 无帧格式处理
- 无错误处理

**现在（cl-websocket）**：
- 完整的 WebSocket 握手
- 自动帧格式化和解析
- 支持文本和二进制消息
- 完整的错误处理
- Ping/Pong 支持

### 2. URL 解析

使用 `quri` 库进行 URL 解析：

```lisp
(defun parse-ws-url (url)
  "解析 WebSocket URL"
  (let ((parsed (quri:uri url)))
    (list (quri:uri-scheme parsed)
          (quri:uri-host parsed)
          (or (quri:uri-port parsed)
              (if (equal (quri:uri-scheme parsed) "wss") 443 80))
          (quri:uri-path parsed))))
```

支持：
- `ws://` 和 `wss://` 协议
- 自动端口推断（80/443）
- 路径解析

### 3. 连接管理

```lisp
(defun websocket-client-connect (client url &key (token nil))
  "连接到 WebSocket 服务器"
  (let ((http-url (ws-url-to-http url))
        (headers (当 token 时添加认证头)))
    (cl-websocket:make-websocket-client
     http-url
     :headers headers
     :on-message #'handle-incoming-message
     :on-open #'on-connected
     :on-close #'on-disconnected
     :on-error #'on-error)))
```

### 4. 消息处理

```lisp
;; 发送文本消息
(defun websocket-client-send-message (client type payload)
  (cl-websocket:send-text
   (websocket-client-ws-client client)
   (cl-json:encode-json-to-string `(:type ,type :payload ,payload))))

;; 发送二进制数据
(defun websocket-client-send-binary (client data)
  (cl-websocket:send-binary
   (websocket-client-ws-client client)
   data))
```

### 5. 回调系统

```lisp
(make-websocket-client
 :on-message (lambda (msg) ...)    ; 收到消息
 :on-connected (lambda () ...)     ; 连接成功
 :on-disconnected (lambda () ...)  ; 断开连接
 :on-error (lambda (err) ...))     ; 发生错误
```

### 6. 重连机制

```lisp
(defun websocket-client-reconnect (client url &key (max-retries 5) (retry-delay 2))
  "带重试逻辑的重连"
  (loop while (< retries max-retries) do
    (websocket-client-connect client url)
    ...))
```

### 7. Keep-Alive

```lisp
(defun websocket-client-keep-alive (client &key (interval 30))
  "启动背景 Ping 线程"
  (bt:make-thread
   (lambda ()
     (loop while (websocket-client-connected-p client) do
       (sleep interval)
       (websocket-client-ping client)))))
```

## 新增 API

### 连接管理
- `websocket-client-connect` - 连接
- `websocket-client-disconnect` - 断开
- `websocket-client-reconnect` - 重连

### 消息发送
- `websocket-client-send-message` - 发送结构化消息
- `websocket-client-send-raw` - 发送原始文本
- `websocket-client-send-binary` - 发送二进制数据

### Keep-Alive
- `websocket-client-ping` - 发送 Ping
- `websocket-client-keep-alive` - 启动自动 Ping

### 工具函数
- `websocket-client-state` - 获取状态
- `print-websocket-status` - 打印状态
- `parse-ws-url` - 解析 URL
- `ws-url-to-http` - URL 转换

## 依赖更新

```lisp
:depends-on (:mcclim
             :dexador
             :cl-json
             :bordeaux-threads
             :usocket
             :babel
             :ironclad
             :cl-base64
             :log4cl
             :cl-websocket    ; 新增
             :quri)           ; 新增
```

## 测试

### 单元测试
- `test-ws-client-creation` - 客户端创建
- `test-ws-url-parsing` - URL 解析
- `test-ws-url-to-http` - URL 转换
- `test-ws-state` - 状态管理

### 集成测试
- `test-ws-connect` - 连接测试
- `test-ws-reconnect` - 重连测试
- `test-ws-send-message` - 消息发送测试

运行测试：
```lisp
(run-websocket-tests :integration t)
```

## WebSocket 消息格式

### 客户端发送
```json
{
  "type": "MESSAGE",
  "payload": {
    "content": "Hello",
    "conversationId": 1
  }
}
```

### 服务器推送
```json
{
  "type": "NEW_MESSAGE",
  "payload": {
    "id": 123,
    "content": "Hello",
    "senderId": 1,
    "senderName": "user1",
    "conversationId": 1,
    "createdAt": 1774420971000
  }
}
```

### 支持的消息类型
- `NEW_MESSAGE` - 新消息
- `MESSAGE_READ` - 消息已读
- `USER_STATUS` - 用户状态变更
- `AI_RESPONSE` - AI 响应
- `NOTIFICATION` - 系统通知
- `AI_CONFIG_UPDATED` - AI 配置更新

## 错误处理

```lisp
(handler-case
    (websocket-client-connect client url)
  (cl-websocket:websocket-error (e)
    (format t "WebSocket error: ~A~%" e))
  (error (e)
    (format t "General error: ~A~%" e)))
```

## 性能优化

1. **背景监听线程** - 不阻塞主线程
2. **Keep-Alive** - 防止连接超时
3. **自动重连** - 网络波动时自动恢复
4. **消息回调** - 异步处理消息

## 与之前实现的对比

| 功能 | 简化实现 | cl-websocket 实现 |
|------|----------|------------------|
| 握手 | 不完整 | 完整 |
| 帧格式 | 无 | 自动处理 |
| 二进制支持 | 无 | 支持 |
| Ping/Pong | 无 | 支持 |
| 错误处理 | 简单 | 完整 |
| URL 解析 | 硬编码 | quri 库 |
| 重连 | 无 | 支持 |
| Keep-Alive | 无 | 支持 |

## 使用方法

### 基本使用
```lisp
;; 创建客户端
(defvar *ws* (make-websocket-client
              :on-message (lambda (msg) (format t "Received: ~A~%" msg))
              :on-connected (lambda () (format t "Connected~%"))
              :on-disconnected (lambda () (format t "Disconnected~%"))))

;; 连接
(websocket-client-connect *ws* "ws://127.0.0.1:3000/ws" :token "your-token")

;; 发送消息
(websocket-client-send-message *ws* "PING" '(:test t))

;; 断开
(websocket-client-disconnect *ws*)
```

### 高级使用
```lisp
;; 带重连的连接
(websocket-client-reconnect *ws* "ws://127.0.0.1:3000/ws"
                            :max-retries 5
                            :retry-delay 2)

;; 启动 Keep-Alive
(websocket-client-keep-alive *ws* :interval 30)

;; 发送二进制数据
(websocket-client-send-binary *ws* #(1 2 3 4 5))
```

## 下一步

1. **WSS 支持** - 测试加密连接
2. **消息队列** - 断线时消息缓存
3. **压缩** - WebSocket 压缩扩展
4. **多连接** - 同时连接多个服务器

## 总结

使用 `cl-websocket` 库完成了完整的 WebSocket 协议实现：
- ✅ 完整的握手和帧处理
- ✅ 文本和二进制消息支持
- ✅ Ping/Pong Keep-Alive
- ✅ 自动重连机制
- ✅ 完整的错误处理
- ✅ 单元测试和集成测试

可以开始进行实际的消息推送测试了。