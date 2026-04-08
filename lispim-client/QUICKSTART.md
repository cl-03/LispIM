# LispIM Client 快速启动指南

## 前提条件

1. **LispIM Core 服务器正在运行**
   ```bash
   cd ../lispim-core
   sbcl --load start-server.lisp
   ```

2. **Quicklisp 已安装**
   ```lisp
   (load "quicklisp.lisp")
   (quicklisp:quickload :lispim-client)
   ```

## 快速启动

### 方法 1: 使用启动脚本

```bash
cd lispim-client
sbcl --load run-client.lisp
```

然后在 Lisp REPL 中输入:

```lisp
(lispim-client/ui:open-login-frame *client*)
```

### 方法 2: 手动加载

```lisp
;; 加载 Quicklisp
(load "quicklisp.lisp")

;; 加载系统
(quicklisp:quickload :lispim-client)

;; 创建客户端
(in-package :lispim-client)
(defvar *client* (make-lispim-client))

;; 登录
(client-login *client* "username" "password")

;; 打开 GUI
(lispim-client/ui:open-login-frame *client*)
```

## 登录

使用您在 LispIM Core 服务器上注册的账号登录。

默认测试账号:
- 用户名：`testuser`
- 密码：`test123`

## 功能测试

### 发送消息

1. 在会话列表中选择一个会话
2. 在底部输入框输入消息
3. 按 Enter 或点击发送按钮

### 接收消息

消息会通过 WebSocket 实时推送到客户端。

## 故障排查

### 无法连接服务器

确保 LispIM Core 服务器正在运行:

```bash
curl http://127.0.0.1:3000/api/v1/health
```

### McCLIM 显示错误

确保已安装 McCLIM:

```lisp
(quicklisp:quickload :mcclim)
```

### WebSocket 连接失败

检查防火墙设置，确保端口 3000 未被阻止。

## 退出客户端

按 `Ctrl+C` 或关闭 McCLIM 窗口。

## 下一步

- 配置 OpenAI/Claude API 集成
- 添加更多聊天功能
- 自定义主题和样式
