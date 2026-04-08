# LispIM McCLIM 客户端实现报告

**日期**: 2026-04-08
**状态**: 基础架构完成

## 实现概述

成功创建了纯 Common Lisp 桌面客户端的基础架构，使用 McCLIM 作为 GUI 框架。

## 已实现组件

### 1. 核心客户端 (client.lisp)

```
lispim-client 类
├── api-client: HTTP API 客户端
├── websocket: WebSocket 客户端
├── auth-manager: 认证管理器
└── state: 客户端状态
```

**主要函数**:
- `make-lispim-client` - 创建客户端实例
- `client-connect` / `client-disconnect` - 连接管理
- `client-login` / `client-logout` - 认证
- `client-send-message` - 发送消息
- `client-get-messages` - 获取消息
- `client-mark-read` - 标记已读

### 2. API 客户端 (api-client.lisp)

**功能**:
- REST API 调用封装
- Token 认证
- 错误处理

**API 端点**:
| 函数 | 方法 | 端点 | 描述 |
|------|------|------|------|
| `api-client-login` | POST | `/api/v1/auth/login` | 登录 |
| `api-client-logout` | POST | `/api/v1/auth/logout` | 登出 |
| `api-client-get-me` | GET | `/api/v1/users/me` | 获取当前用户 |
| `api-client-get-conversations` | GET | `/api/v1/conversations` | 获取会话列表 |
| `api-client-get-messages` | GET | `/api/v1/conversations/:id/messages` | 获取消息 |
| `api-client-send-message` | POST | `/api/v1/conversations/:id/messages` | 发送消息 |
| `api-client-mark-read` | POST | `/api/v1/messages/:id/read` | 标记已读 |
| `api-client-get-friends` | GET | `/api/v1/contacts/friends` | 获取好友列表 |
| `api-client-send-friend-request` | POST | `/api/v1/contacts/friend-request` | 发送好友请求 |
| `api-client-accept-friend-request` | POST | `/api/v1/contacts/friend-request/:id/accept` | 接受好友请求 |

### 3. WebSocket 客户端 (websocket-client.lisp)

**功能**:
- WebSocket 连接管理
- 实时消息推送
- 背景监听线程

**回调**:
- `:on-message` - 收到消息时调用
- `:on-connected` - 连接成功时调用
- `:on-disconnected` - 断开连接时调用

### 4. 认证管理器 (auth-manager.lisp)

**功能**:
- 登录/登出管理
- Token 存储
- 用户信息管理

### 5. 状态管理 (client-state.lisp)

**状态存储**:
- `conversations` - 会话列表
- `messages` - 消息历史（按会话 ID 哈希）
- `users` - 用户信息缓存
- `friends` - 好友列表

### 6. McCLIM UI (ui/)

#### Login Frame (login-frame.lisp)

```
┌─────────────────────────┐
│   LispIM - Login        │
│                         │
│   Username: [_______]   │
│   Password: [_______]   │
│                         │
│      [  Login  ]        │
│                         │
│   Status: __________    │
└─────────────────────────┘
```

#### Main Frame (main-frame.lisp)

```
┌──────────┬────────────────────┬──────────┐
│          │                    │          │
│ 会话列表 │     消息视图       │ 用户信息 │
│          │                    │          │
│ - Conv 1 │ - Msg 1            │ Username │
│ - Conv 2 │ - Msg 2            │ Status   │
│ - Conv 3 │ - Msg 3            │          │
│          │                    │          │
│          ├────────────────────┤          │
│          │ 消息输入：[_______]│          │
│          └────────────────────┴──────────┘
└──────────┴────────────────────────────────┘
```

### 7. 工具函数 (utils.lisp)

**字符串转换**:
- `kebab-to-camel-case` - kebab-case → camelCase
- `camel-to-kebab-case` - camelCase → kebab-case

**JSON 处理**:
- `json-to-plist` - JSON → 属性列表
- `plist-to-json` - 属性列表 → JSON

**时间转换**:
- `unix-to-universal-time` - Unix 时间戳 → Universal Time
- `universal-to-unix-time` - Universal Time → Unix 时间戳
- `format-timestamp` - 格式化时间戳

### 8. 测试 (tests/test-client.lisp)

**测试覆盖**:
- 工具函数测试
- API 客户端创建测试
- 认证管理器创建测试
- 状态管理测试

## 文件结构

```
lispim-client/
├── lispim-client.asd           # ASDF 系统定义
├── src/
│   ├── package.lisp            # 包定义
│   ├── utils.lisp              # 工具函数
│   ├── api-client.lisp         # HTTP API 客户端
│   ├── websocket-client.lisp   # WebSocket 客户端
│   ├── auth-manager.lisp       # 认证管理
│   ├── client-state.lisp       # 状态管理
│   ├── client.lisp             # 主客户端
│   └── ui/
│       ├── package.lisp        # UI 包定义
│       ├── login-frame.lisp    # 登录界面
│       └── main-frame.lisp     # 主界面
├── tests/
│   └── test-client.lisp        # 客户端测试
├── load-system.lisp            # 加载脚本
├── run-client.lisp             # 运行脚本
├── start-client.lisp           # 启动脚本
├── README.md                   # 项目文档
└── QUICKSTART.md               # 快速启动指南
```

## 依赖项

| 依赖 | 用途 |
|------|------|
| mcclim | GUI 框架 |
| dexador | HTTP 客户端 |
| cl-json | JSON 编码/解码 |
| bordeaux-threads | 线程支持 |
| usocket | Socket 通信 |
| babel | 字符编码 |
| split-sequence | 字符串分割 |

## 待实现功能

### 短期目标
1. **WebSocket 协议完善** - 当前是简化实现，需要完整的 WebSocket 握手和帧处理
2. **错误处理增强** - 更详细的活动错误日志
3. **Token 刷新** - 自动刷新过期 token

### 中期目标
1. **通知系统** - 系统托盘通知
2. **文件上传** - 图片/文件发送
3. **群组聊天** - 群组管理 UI
4. **搜索功能** - 消息搜索

### 长期目标
1. **离线消息** - 本地消息存储
2. **多账号支持** - 账号切换
3. **主题系统** - 可定制 UI 主题
4. **插件系统** - 扩展功能

## OpenAI/Claude API 集成

用户提到的"像 Telegram 那样配置 OpenAI API"功能需要：

1. **配置界面** - 在设置中添加 API key 配置
2. **聊天机器人** - AI 助手对话
3. **消息处理** - 将消息发送到 AI API
4. **响应显示** - 显示 AI 回复

### 实现建议

```lisp
;; AI 配置
(defclass ai-config ()
  ((api-key :accessor ai-api-key :initarg :api-key)
   (api-endpoint :accessor ai-api-endpoint :initform "https://api.openai.com/v1")
   (model :accessor ai-model :initform "gpt-4")))

;; AI 技能
(defun ai-process-message (config message)
  "Send message to AI and get response"
  ;; Call OpenAI/Claude API
  )
```

## 下一步

1. 测试与 LispIM Core 服务器的连接
2. 完善 WebSocket 实现（考虑使用 cl-websocket 库）
3. 添加 AI API 配置功能
4. 运行集成测试

## 总结

基础架构已完成，包括：
- ✅ 核心客户端类
- ✅ HTTP API 客户端
- ✅ WebSocket 客户端（简化版）
- ✅ 认证管理
- ✅ 状态管理
- ✅ McCLIM UI 框架
- ✅ 测试框架

可以开始进行实际连接测试和功能完善了。
