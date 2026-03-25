# LispIM Enterprise

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Common Lisp](https://img.shields.io/badge/Common%20Lisp-SBCL-blue.svg)](http://www.sbcl.org/)
[![Build Status](https://github.com/lispim/lispim-core/workflows/CI/badge.svg)](https://github.com/lispim/lispim-core/actions)

**云原生、AI 原生、隐私优先的企业级即时通讯平台**

LispIM Enterprise 是全球首款使用 Common Lisp 构建的云原生、AI 原生、隐私优先的企业级即时通讯平台。它利用 Common Lisp 的热更新能力实现零停机演进，通过与 OpenClaw 的深度集成实现智能协作，通过端到端加密实现数据主权。

## 核心特性

- 🔥 **零停机热更新** - 业务模块可动态加载/卸载，服务不中断
- 🤖 **AI 系统级集成** - 与 OpenClaw 深度集成，支持流式对话、上下文摘要
- 🔐 **端到端加密** - 基于 Signal 协议，实现前向安全性和后向安全性
- 📊 **完整可观测性** - OpenTelemetry 指标、追踪、日志三大支柱
- 🚀 **高性能架构** - 单实例支持 10,000+ 并发连接，消息延迟 < 100ms

## 技术栈

| 层级 | 技术 |
| :--- | :--- |
| **后端核心** | Common Lisp (SBCL) |
| **Web 框架** | Hunchentoot |
| **WebSocket** | Hunchentoot WebSocket |
| **数据库** | PostgreSQL + Redis |
| **加密** | Ironclad + Cl+SSL |
| **监控** | OpenTelemetry + Prometheus + Grafana |
| **部署** | Docker + Kubernetes |
| **Web 客户端** | React 18 + TypeScript + Vite + TailwindCSS |
| **桌面客户端** | Tauri 1.6 + Rust |
| **移动客户端** | Android (Kotlin + Jetpack Compose) |

## 快速开始

### 使用 Docker Compose（推荐）

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

### 本地开发

```bash
# 安装依赖
# macOS
brew install sbcl postgresql redis

# Ubuntu/Debian
sudo apt-get install sbcl postgresql redis-server

# 初始化数据库
./scripts/start.sh init

# 启动服务
./scripts/start.sh start
```

### 使用 REPL 开发

```bash
cd lispim-core

# 启动 SBCL 并加载系统
sbcl --load lispim-core.asd

# 在 REPL 中
* (ql:quickload :lispim-core)
* (lispim-core:start-server)
```

## 项目结构

```
lispim/
├── lispim-core/                    # Lisp 后端核心
│   ├── lispim-core.asd             # ASDF 系统定义
│   ├── src/                        # 源代码
│   │   ├── package.lisp            # 包定义
│   │   ├── conditions.lisp         # 条件系统
│   │   ├── utils.lisp              # 工具函数
│   │   ├── snowflake.lisp          # 分布式 ID 生成
│   │   ├── gateway.lisp            # WebSocket 网关
│   │   ├── module.lisp             # 热更新引擎
│   │   ├── chat.lisp               # 聊天核心
│   │   ├── e2ee.lisp               # 端到端加密
│   │   ├── oc-adapter.lisp         # OpenClaw 适配器
│   │   ├── storage.lisp            # 数据存储
│   │   ├── observability.lisp      # 可观测性
│   │   └── server.lisp             # 服务器入口
│   ├── tests/                      # 单元测试 (5 个套件，34 个测试)
│   └── Dockerfile
├── openclaw-connector-lispim/      # OpenClaw 连接器 (100% Lisp)
│   ├── openclaw-connector.asd
│   └── src/
├── web-client/                     # Web PWA 客户端 (React + TypeScript)
│   ├── src/
│   │   ├── components/             # React 组件
│   │   ├── store/                  # Zustand 状态管理
│   │   ├── utils/                  # 工具函数 (WebSocket, E2EE)
│   │   └── types/                  # TypeScript 类型
│   ├── package.json
│   └── vite.config.ts
├── tauri-client/                   # 桌面客户端 (Tauri + Rust + React)
├── android-client/                 # Android 客户端 (Kotlin + Jetpack Compose) - Phase 6
│   ├── app/
│   │   ├── src/main/
│   │   │   ├── java/com/lispim/app/
│   │   │   └── res/
│   │   └── build.gradle.kts
│   └── README.md
├── docker/                         # Docker 配置
├── k8s/                            # Kubernetes 配置
├── scripts/                        # 运维脚本
│   ├── start.sh                    # 启动脚本
│   └── init-db.sql                 # 数据库初始化
├── docker-compose.yml
└── README.md
```

## API 文档

### WebSocket 连接

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

### HTTP 端点

| 端点 | 说明 |
| :--- | :--- |
| `GET /healthz` | 健康检查 (liveness) |
| `GET /readyz` | 就绪检查 (readiness) |
| `GET /metrics` | Prometheus 指标 |

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
