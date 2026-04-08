# LispIM 自动登录客户端 - 快速启动指南

## 一键启动

### Windows

```batch
# 使用默认配置 (admin/password@localhost:3000)
start-auto-login.bat

# 自定义配置
start-auto-login.bat username password host port
```

### Linux/macOS

```bash
# 使用默认配置 (admin/password@localhost:3000)
./start-auto-login.sh

# 自定义配置
./start-auto-login.sh username password host port
```

### 示例

```bash
# 默认登录
./start-auto-login.sh

# 使用特定账号
./start-auto-login.sh myuser mypass

# 连接远程服务器
./start-auto-login.sh user pass 192.168.1.100 3000
```

---

## 手动启动 (SBCL)

```bash
# 进入客户端目录
cd lispim-client

# 启动 SBCL 并加载自动登录
sbcl --load auto-login-client.lisp
```

---

## 修改默认配置

编辑 `client-config.lisp` 文件：

```lisp
;;;; 服务器配置
(defparameter *server-host* "localhost"
  "LispIM 服务器地址")

(defparameter *server-port* 3000
  "LispIM 服务器端口")

;;;; 登录凭证
(defparameter *username* "admin"
  "用户名")

(defparameter *password* "password"
  "密码")
```

---

## 启动后的命令

成功登录后，可以使用以下命令：

```lisp
;; 发送消息
(send "conversation-id" "Hello!")

;; 获取会话列表
(conversations)

;; 获取消息
(messages "conversation-id")

;; 查看在线用户
(online-users)

;; 查看用户状态
(status "user-id")

;; 断开连接
(disconnect)
```

---

## 编程方式使用

```lisp
;; 加载客户端
(load "auto-login-client.lisp")

;; 自定义配置并连接
(setf *username* "myuser"
      *password* "mypass"
      *server-host* "localhost"
      *server-port* 3000)

;; 执行自动登录
(auto-connect-and-login)

;; 现在可以使用所有命令
(send "conv-123" "Hello!")
```

---

## 回调消息

当收到消息时，会自动显示：

```
📨 [MESSAGE_RECEIVED] user-123: Hello!

👤 [PRESENCE] {"userId": "user-456", "status": "online"}

🔔 [NOTIFICATION] New message in conversation conv-123
```

---

## 故障排查

### 连接失败

```
ERROR: Connection failed: Connection failed to localhost:3000
```

**解决方案:**
1. 确保服务器正在运行
2. 检查端口是否正确
3. 使用 `docker-compose ps` 查看服务状态

### 登录失败

```
ERROR: Login failed: Authentication error
```

**解决方案:**
1. 检查用户名密码是否正确
2. 确认用户已注册
3. 查看服务器日志

### Quicklisp 加载失败

```
ERROR: Failed to load Quicklisp
```

**解决方案:**
```lisp
;; 安装 Quicklisp
curl -o quicklisp.lisp https://beta.quicklisp.org/quicklisp.lisp
```

---

## 退出客户端

```lisp
;; 在 REPL 中输入
(disconnect)

;; 或直接退出 SBCL
(sb-ext:quit)
```

---

## 高级配置

### 启用调试消息

```lisp
(setf *show-debug-messages* t)
```

### 禁用通知

```lisp
(setf *show-notifications* nil)
```

### 修改心跳间隔

```lisp
(setf *heartbeat-interval* 60)  ; 60 秒
```

---

**最后更新**: 2026-04-06
