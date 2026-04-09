# LispIM Enterprise

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Common Lisp](https://img.shields.io/badge/Common%20Lisp-SBCL-blue.svg)](http://www.sbcl.org/)
[![Build Status](https://github.com/lispim/lispim-core/workflows/CI/badge.svg)](https://github.com/lispim/lispim-core/actions)

**云原生、AI 原生、隐私优先的企业级即时通讯平台**
**100% Pure Common Lisp - 后端到客户端**

LispIM Enterprise 是全球首款使用 Common Lisp 构建的云原生、AI 原生、隐私优先的企业级即时通讯平台。它利用 Common Lisp 的热更新能力实现零停机演进，通过与 OpenClaw 的深度集成实现智能协作，通过端到端加密实现数据主权。

> 🎉 **新功能**: 现在包含纯 Common Lisp 实现的 WebSocket 客户端！无需 JavaScript，完全使用 Lisp 编写。详见 [lispim-client/](lispim-client/README.md)。

## 核心特性

- 🔥 **零停机热更新** - 业务模块可动态加载/卸载，服务不中断
- 🤖 **AI 系统级集成** - 与 OpenClaw 深度集成，支持流式对话、上下文摘要
- 🔐 **端到端加密** - 基于 Signal 协议，实现前向安全性和后向安全性
- 📊 **完整可观测性** - OpenTelemetry 指标、追踪、日志三大支柱
- 🚀 **高性能架构** - 单实例支持 10,000+ 并发连接，消息延迟 < 100ms

## 技术栈

| 层级 | 技术 |
| :--- | :--- |
| **后端核心** | Common Lisp (SBCL) - 100% 纯 Lisp |
| **WebSocket 客户端** | Common Lisp (usocket, cl+ssl) - 纯 Lisp 实现 |
| **Web 框架** | Hunchentoot |
| **WebSocket** | Hunchentoot WebSocket |
| **数据库** | PostgreSQL + Redis |
| **加密** | Ironclad + Cl+SSL |
| **监控** | OpenTelemetry + Prometheus + Grafana |
| **部署** | Docker + Kubernetes |
| **可选客户端** | React/TypeScript Web, Tauri 桌面，Android 移动 |

## 快速开始

### 方法一：使用 Docker Compose（推荐）

```bash
# 克隆仓库
git clone https://github.com/lispim/lispim.git
cd lispim

# 启动所有服务
docker-compose up -d

# 查看日志
docker-compose logs -f sbcl

# 访问服务
# - Gateway: http://localhost:3000
# - Prometheus: http://localhost:9090
# - Grafana: http://localhost:3000 (admin/admin)
```

### 方法二：使用纯 Lisp 客户端（REPL）

```lisp
;; 加载客户端
(load "lispim-client/run-client.lisp")

;; 连接并登录
(repl-connect :host "localhost" :port 3000)
(repl-login "username" "password")

;; 发送消息
(repl-send "conversation-id" "Hello, LispIM!")
```

### 方法三：命令行客户端

```bash
cd lispim-client
./start-client.sh

# 可用命令
> help
> login username password
> send conversation_id Hello!
> conversations
> online
> quit
```

## 项目结构

```
lispim/
├── README.md                       # 项目总入口
├── QUICKSTART.md                   # 5 分钟快速开始 (docs/guides/)
├── CONTRIBUTING.md                 # 贡献指南
├── docs/                           # 统一文档目录
│   ├── architecture/               # 架构文档
│   ├── api/                        # API 文档
│   ├── deployment/                 # 部署文档
│   ├── development/                # 开发文档
│   └── guides/                     # 使用指南
├── scripts/                        # 构建/启动脚本
├── lispim-core/                    # Lisp 后端核心
│   ├── lispim-core.asd             # ASDF 系统定义
│   ├── src/                        # 源代码 (60+ 模块)
│   │   ├── core/                   # 核心模块
│   │   ├── network/                # 网络模块
│   │   ├── auth/                   # 认证模块
│   │   ├── chat/                   # 聊天模块
│   │   ├── e2ee/                   # 端到端加密
│   │   ├── storage/                # 存储模块
│   │   ├── ai/                     # AI 集成
│   │   ├── plugin/                 # 插件系统
│   │   └── features/               # 功能模块
│   ├── tests/                      # 测试套件
│   ├── migrations/                 # 数据库迁移
│   └── scripts/                    # 构建脚本
├── lispim-client/                  # 纯 Lisp 客户端
│   ├── src/mcclim/                 # McCLIM 桌面客户端
│   ├── src/repl/                   # REPL 客户端
│   └── tests/                      # 客户端测试
├── web-client/                     # Web PWA 客户端 (React + TypeScript)
├── tauri-client/                   # 桌面客户端 (Tauri + Rust)
├── android-client/                 # Android 客户端 (Kotlin)
├── docker/                         # Docker 配置
└── docker-compose.yml              # Docker Compose
```

### 文档导航

- 📚 [文档索引](docs/) - 完整文档目录
- 🏗️ [系统架构](docs/architecture/ARCHITECTURE.md) - 架构设计文档
- 📡 [API 参考](docs/api/API.md) - WebSocket API 文档
- 🚀 [部署指南](docs/deployment/DEPLOYMENT.md) - 生产环境部署
- 📖 [开发文档](docs/development/) - 实现报告和指南

## 快速开始
├── tauri-client/                   # 桌面客户端 (Tauri + Rust)
├── android-client/                 # Android 客户端 (Kotlin)
├── docker/                         # Docker 配置
├── docker-compose.yml              # Docker Compose
├── QUICKSTART.md                   # 5 分钟快速开始
├── ARCHITECTURE.md                 # 系统架构文档
└── README.md                       # 本文件
## API 文档

### WebSocket 连接 (JavaScript)

```javascript
// 连接到服务器
const ws = new WebSocket('ws://localhost:3000');

// 发送消息
ws.send(JSON.stringify({
  type: 'MESSAGE_SEND',
  conversation_id: '123456789',
  content: 'Hello, LispIM!',
  message_type: 'text'
}));

// 接收消息
ws.onmessage = (event) => {
  const message = JSON.parse(event.data);
  console.log('Received:', message);
};
```

### WebSocket 连接 (Common Lisp)

```lisp
;; 使用纯 Lisp 客户端
(load "lispim-client/run-client.lisp")

;; 连接
(repl-connect :host "localhost" :port 3000)

;; 登录
(repl-login "username" "password")

;; 发送消息
(repl-send "123456789" "Hello, LispIM!")

;; 获取消息
(repl-messages "123456789")
```

### HTTP 端点

| 端点 | 说明 |
| :--- | :--- |
| `GET /healthz` | 健康检查 (liveness) |
| `GET /readyz` | 就绪检查 (readiness) |
| `GET /metrics` | Prometheus 指标 |

## 文档导航

- 📘 [QUICKSTART.md](QUICKSTART.md) - 5 分钟快速开始
- 🏗️ [ARCHITECTURE.md](ARCHITECTURE.md) - 系统架构文档
- 📡 [API.md](API.md) - WebSocket API 参考
- 🤝 [CONTRIBUTING.md](CONTRIBUTING.md) - 贡献指南
- 💻 [lispim-client/README.md](lispim-client/README.md) - 纯 Lisp 客户端文档

## 配置

### 环境变量

| 变量 | 说明 | 默认值 |
| :--- | :--- | :--- |
| `DATABASE_URL` | PostgreSQL 连接 URL | `postgresql://localhost:5432/lispim` |
| `REDIS_URL` | Redis 连接 URL | `redis://localhost:6379/0` |
| `LOG_LEVEL` | 日志级别 | `info` |
| `LISPIM_HOST` | 监听地址 | `0.0.0.0` |
| `LISPIM_PORT` | 监听端口 | `3000` |
| `MAX_CONNECTIONS` | 最大连接数 | `10000` |

### 配置文件

```json
{
  "host": "0.0.0.0",
  "port": 3000,
  "database_url": "postgresql://localhost:5432/lispim",
  "redis_url": "redis://localhost:6379/0",
  "ssl_cert": "/path/to/cert.pem",
  "ssl_key": "/path/to/key.pem",
  "oc_endpoint": "https://openclaw.example.com",
  "oc_api_key": "your-api-key",
  "log_level": "info"
}
```

## 开发路线图

- [x] Phase 1: 核心基础设施 (Gateway, Module Manager, Storage)
- [x] Phase 2: 安全与加密 (E2EE, Key Management)
- [x] Phase 3: OpenClaw 集成 (Adapter, Stream, Context)
- [x] Phase 4: 可观测性 (Metrics, Tracing, Health)
- [x] Phase 5: 客户端开发 (Web PWA, Tauri Desktop)
- [x] Phase 6: Android 移动端 (Kotlin + Jetpack Compose) - 基础架构完成
- [ ] Phase 7: iOS 移动端 - 计划中

## 客户端

### McCLIM 桌面客户端 (Pure Lisp - NEW!)

使用纯 Common Lisp 和 McCLIM 框架实现的桌面 GUI 客户端。

```bash
cd lispim-client
# 加载系统并启动
(ql:quickload :lispim-client)
(lispim-client:run)
```

**特性**:
- ✅ 100% 纯 Common Lisp - 无 JavaScript/TypeScript 依赖
- ✅ McCLIM 原生 GUI 界面
- ✅ 实时 WebSocket 消息
- ✅ Token 认证
- ✅ 会话管理
- ✅ 完整的测试套件

详见 [lispim-client/README.md](lispim-client/README.md) 和 [lispim-client/IMPLEMENTATION_REPORT.md](lispim-client/IMPLEMENTATION_REPORT.md)

### Web PWA 客户端

访问 http://localhost:3000 使用 Web 客户端。

```bash
cd web-client
npm install
npm run dev
```

**特性**:
- ✅ PWA 支持 (离线访问、推送通知)
- ✅ 端到端加密
- ✅ 响应式设计
- ✅ 实时消息收发

### 桌面客户端 (Tauri)

```bash
cd tauri-client
npm install
npm run tauri:dev
```

**特性**:
- ✅ 系统托盘集成
- ✅ 原生通知
- ✅ 全局快捷键
- ✅ 跨平台 (Windows/macOS/Linux)

### Android 客户端 (Kotlin + Jetpack Compose)

```bash
cd android-client
# 使用 Android Studio 打开项目
# 或使用命令行构建
./gradlew assembleDebug
```

**特性**:
- ✅ Material 3 设计
- ✅ WebSocket 实时通信
- ✅ 本地消息缓存 (Room)
- ✅ FCM 推送通知
- ✅ 自动重连机制
- ✅ 登录/注册认证

**配置 Firebase**:
1. 访问 [Firebase Console](https://console.firebase.google.com/)
2. 创建项目并添加 Android 应用 (包名：`com.lispim.app`)
3. 下载 `google-services.json` 替换 `app/google-services.json`
4. 启用 Cloud Messaging (FCM)

**配置服务器地址**:
- 编辑 `app/src/main/java/com/lispim/app/data/api/ApiProvider.kt`
- 编辑 `app/src/main/java/com/lispim/app/data/websocket/LispIMWebSocketManager.kt`

## 性能指标

| 指标 | 目标值 | 当前值 |
| :--- | :--- | :--- |
| 消息延迟 (P99) | < 100ms | TBD |
| 并发连接数 | > 10,000 | TBD |
| 热更新时间 | < 5 秒 | TBD |
| AI Token 节省 | > 50% | TBD |
| 系统可用性 | > 99.9% | TBD |

## 贡献

欢迎贡献代码、报告问题或提出建议！

1. Fork 本仓库
2. 创建特性分支 (`git checkout -b feature/amazing-feature`)
3. 提交更改 (`git commit -m 'Add amazing feature'`)
4. 推送到分支 (`git push origin feature/amazing-feature`)
5. 开启 Pull Request

## 许可证

MIT License - 详见 [LICENSE](LICENSE)

## 联系方式

- 网站：https://lispim.org
- 邮件：team@lispim.org
- Twitter: @lispim_org

---

**LispIM Enterprise** - 用 Common Lisp 重新定义企业级即时通讯
