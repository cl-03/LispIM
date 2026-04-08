# LispIM Pure Common Lisp Client

这是一个使用 McCLIM 的纯 Common Lisp 桌面客户端。

## 依赖

- SBCL 2.5.8+
- McCLIM - GUI 框架
- Dexador - HTTP 客户端
- cl-json - JSON 处理
- bordeaux-threads - 线程支持
- usocket - Socket 通信
- babel - 字符编码
- split-sequence - 字符串分割
- **cl-websocket** - WebSocket 协议（新增）
- **quri** - URL 解析（新增）

## 安装依赖

使用 Quicklisp:

```lisp
(ql:quickload :mcclim)
(ql:quickload :dexador)
(ql:quickload :cl-json)
(ql:quickload :bordeaux-threads)
(ql:quickload :usocket)
(ql:quickload :babel)
(ql:quickload :split-sequence)
(ql:quickload :cl-websocket)  ;; WebSocket 支持
(ql:quickload :quri)          ;; URL 解析
```

## 启动客户端

1. 确保 LispIM Core 服务器正在运行 (默认端口 3000)

2. 加载客户端:

```lisp
(load "load-system.lisp")
```

3. 登录:

```lisp
;; 创建客户端实例
(defvar *client* (make-lispim-client))

;; 登录
(client-login *client* "username" "password")

;; 打开 GUI
(lispim-client/ui:open-login-frame *client*)
```

## 功能

### 认证
- 用户名/密码登录
- Token 管理
- 自动登出

### 消息
- 发送文本消息
- 接收实时消息 (WebSocket)
- 消息已读回执

### 会话
- 会话列表显示
- 切换会话
- 消息历史加载

### 好友
- 好友列表
- 好友状态 (在线/离线)

### AI 助手配置 (类似 Telegram)
- 支持多种 AI 后端：OpenClaw、OpenAI、Claude、本地模型
- 可配置 AI 人设：助手、创意、精确、友好、教师、程序员
- 上下文长度控制 (512-32768 tokens)
- 流式响应支持
- 预算限制管理
- 技能选择：总结、翻译、解释、代码审查、调试等

## API 客户端用法

```lisp
;; 创建 API 客户端
(defvar *api* (make-api-client :base-url "http://127.0.0.1:3000"
                                :token "your-token"))

;; 获取会话
(api-client-get-conversations *api*)

;; 发送消息
(api-client-send-message *api* 1 "Hello, World!")

;; 获取消息
(api-client-get-messages *api* 1 :limit 50)

;; 标记已读
(api-client-mark-read *api* 123)
```

## WebSocket 客户端用法

```lisp
;; 创建 WebSocket 客户端
(defvar *ws* (make-websocket-client
              :on-message (lambda (msg)
                            (format t "Received: ~A~%" msg))
              :on-connected (lambda ()
                              (format t "Connected~%"))
              :on-disconnected (lambda ()
                                 (format t "Disconnected~%"))
              :on-error (lambda (err)
                          (format t "Error: ~A~%" err))))

;; 连接（自动处理 WebSocket 握手）
(websocket-client-connect *ws* "ws://127.0.0.1:3000/ws"
                          :token "your-token")

;; 发送消息
(websocket-client-send-message *ws* "MESSAGE"
                               '(:content "Hello" :conversation-id 1))

;; 发送二进制数据
(websocket-client-send-binary *ws* #(1 2 3 4 5))

;; 启动 Keep-Alive（每 30 秒发送 Ping）
(websocket-client-keep-alive *ws* :interval 30)

;; 断开
(websocket-client-disconnect *ws*)

;; 重连（最多重试 5 次，每次间隔 2 秒）
(websocket-client-reconnect *ws* "ws://127.0.0.1:3000/ws"
                            :max-retries 5
                            :retry-delay 2)
```

**功能特性**:
- ✅ 完整的 WebSocket 协议支持（RFC 6455）
- ✅ 自动握手和帧处理
- ✅ 文本和二进制消息
- ✅ Ping/Pong Keep-Alive
- ✅ 自动重连机制
- ✅ 完整的错误处理

## AI 配置 API

```lisp
;; 获取 AI 配置
(api-client-get-ai-config *api*)

;; 更新 AI 配置
(api-client-update-ai-config *api*
                            :enabled t
                            :backend "openclaw"
                            :model "gpt-4"
                            :personality "assistant"
                            :context-length 4096
                            :streaming-p t
                            :budget-limit 100.0)

;; 获取可用 AI 后端列表
(api-client-get-ai-backends *api*)

;; 获取预算统计
(api-client-get-ai-budget *api*)
```

## 运行测试

```lisp
(asdf:test-system :lispim-client)
;; 或者
(in-package :lispim-client/test)
(run-all-tests)
```

## 项目结构

```
lispim-client/
├── lispim-client.asd       # ASDF 系统定义
├── src/
│   ├── package.lisp        # 包定义
│   ├── utils.lisp          # 工具函数
│   ├── api-client.lisp     # HTTP API 客户端
│   ├── websocket-client.lisp # WebSocket 客户端
│   ├── auth-manager.lisp   # 认证管理
│   ├── client-state.lisp   # 状态管理
│   ├── client.lisp         # 主客户端
│   └── ui/
│       ├── package.lisp        # UI 包定义
│       ├── login-frame.lisp    # 登录界面
│       ├── main-frame.lisp     # 主界面
│       └── ai-settings.lisp    # AI 配置界面
├── tests/
│   └── test-client.lisp    # 客户端测试
├── load-system.lisp        # 加载脚本
├── start-client.lisp       # 启动脚本
└── README.md               # 本文档
```

## 开发说明

### 添加新的 API 端点

在 `api-client.lisp` 中添加函数:

```lisp
(defun api-client-new-endpoint (client &rest args)
  "Description"
  (api-call client :get "/api/v1/new-endpoint"))
```

### 添加新的 UI 组件

在 `ui/` 目录下创建新文件，使用 McCLIM 的 `define-application-frame`:

```lisp
(define-application-frame my-frame ()
  ((client :accessor frame-client :initarg :client))
  (:panes
   (my-pane :output-pane :value ""))
  (:layouts
   (default (vertically () my-pane))))
```

## 许可证

MIT
