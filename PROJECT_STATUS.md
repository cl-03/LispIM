# LispIM 项目状态

**最后更新时间:** 2026-03-23 15:30
**会话 ID:** e764385e-0eb9-4705-9d92-324689dc92fa

---

## 当前工作状态

### ✅ 已完成的功能

#### 后端 API (Lisp/PostgreSQL)
1. **用户管理 API**
   - `GET /api/v1/users/me` - 获取当前用户信息 ✓
   - `PUT /api/v1/users/profile` - 更新用户资料 ✓
   - `GET /api/v1/users/search?q=<query>` - 搜索用户 ✓

2. **认证 API**
   - `POST /api/v1/auth/login` - 登录 ✓
   - `POST /api/v1/auth/logout` - 登出 ✓

3. **好友管理 API** (本次会话完成)
   - `GET /api/v1/friends` - 获取好友列表 ✓
   - `POST /api/v1/friends/add` - 发送好友请求 ✓
   - `GET /api/v1/friends/requests` - 获取好友请求列表 ✓
   - `POST /api/v1/friends/accept` - 接受好友请求 ✓
   - `POST /api/v1/friends/reject` - 拒绝好友请求 ✓

4. **会话管理 API**
   - `GET /api/v1/chat/conversations` - 获取会话列表 ✓
   - `POST /api/v1/chat/conversations/create` - 创建会话 ✓

5. **文件上传 API**
   - `POST /api/v1/upload` - 上传文件 ✓
   - `GET /api/v1/files/<file-id>` - 获取文件 ✓

#### 前端客户端

**Web Client** (web-client/)
- Vite + React + TypeScript 构建
- 静态资源已编译到 `dist/` 目录
- 通过后端 Hunchentoot 服务器托管在端口 4321
- 访问地址：http://localhost:4321/

**Android Client** (android-app/)
- Kotlin + Jetpack Compose
- 已实现底部导航栏（消息、联系人、发现、我）
- 好友列表、添加好友界面已创建

#### 数据库 (PostgreSQL)
- 表：`users`, `messages`, `conversations`, `friend_requests`, `friends`, `file_uploads`
- 迁移文件：`migrations/001-init.sql`, `migrations/002-friend-system.up.sql`

---

## 本次会话修复的问题

### 1. `/api/v1/friends/requests` 返回错误数据
**问题:** `get-friend-requests` 函数使用 Postmodern `:alists` 模式时，键名匹配失败
**原因:** 搜索键用小写带下划线（`"sender_id"`），实际键是大写带连字符（`SENDER-ID`）
**修复:** 修改 `src/storage.lisp` 第 1025-1031 行，使用正确的键名：
```lisp
(list :id (get-val "ID")
      :sender-id (get-val "SENDER-ID")
      :receiver-id (get-val "RECEIVER-ID")
      :message (or (get-val "MESSAGE") "")
      :status (get-val "STATUS")
      :created-at (get-val "CREATED-TS")
      :sender-username (or (get-val "USERNAME") "")
      :sender-display-name (or (get-val "DISPLAY-NAME") "")
      :sender-avatar (or (get-val "AVATAR-URL") ""))
```

### 2. `/api/v1/friends/accept` 数据库错误 42601
**问题:** PostgreSQL 不支持在单个 prepared statement 中执行多个 SQL 命令
**修复:** 修改 `src/storage.lisp` `accept-friend-request` 函数，使用 `postmodern:with-transaction` 分别执行三个查询：
```lisp
(postmodern:with-transaction ()
  (postmodern:query "UPDATE friend_requests SET status = 'accepted'..." request-id)
  (postmodern:query "INSERT INTO friends (user_id, friend_id, status) SELECT..." request-id)
  (postmodern:query "INSERT INTO friends (user_id, friend_id, status) SELECT..." request-id))
```

### 3. Web Client 资源文件 404
**问题:** `index.html` 引用 `/assets/index-B9tXf7.js` 但实际文件是 `index-B9tXf7RX.js`
**修复:** 更新 `web-client/dist/index.html` 中的文件名引用

---

## 快速启动指南

### 启动后端服务器
```bash
cd D:/Claude/LispIM/lispim-core

# 方法 1: 使用 SBCL 直接加载
sbcl --load start.lisp

# 方法 2: 清除缓存后启动（推荐用于代码修改后）
rm -rf "$HOME/AppData/Local/cache/common-lisp/sbcl-2.5.8-win-x64/D/Claude/LispIM/"
sbcl --load start.lisp
```

服务器启动后监听端口：**4321**

### 健康检查
```bash
curl http://localhost:4321/healthz
# 响应：OK
```

### 测试 API
```bash
# 获取当前用户信息
curl http://localhost:4321/api/v1/users/me -H "Authorization: Bearer test-token-12345"

# 获取好友列表
curl http://localhost:4321/api/v1/friends -H "Authorization: Bearer test-token-12345"

# 搜索用户
curl "http://localhost:4321/api/v1/users/search?q=test" -H "Authorization: Bearer test-token-12345"
```

### Web Client
浏览器访问：**http://localhost:4321/**

---

## 关键文件清单

### 后端核心文件
| 文件 | 说明 |
|------|------|
| `lispim-core/src/package.lisp` | 包定义和配置结构 |
| `lispim-core/src/gateway.lisp` | HTTP API 路由和处理器 |
| `lispim-core/src/storage.lisp` | 数据库操作函数 |
| `lispim-core/src/auth.lisp` | 认证和会话管理 |
| `lispim-core/src/chat.lisp` | 消息和会话逻辑 |
| `lispim-core/src/server.lisp` | 服务器启动入口 |
| `lispim-core/start.lisp` | SBCL 加载脚本 |

### 前端文件
| 文件 | 说明 |
|------|------|
| `web-client/dist/` | Web 客户端编译产物 |
| `android-app/app/src/main/java/com/lispim/` | Android 源码 |

### 数据库
| 文件 | 说明 |
|------|------|
| `lispim-core/migrations/001-init.sql` | 初始表结构 |
| `lispim-core/migrations/002-friend-system.up.sql` | 好友系统迁移 |

---

## 待办事项

### 高优先级
- [ ] 修复 `api-add-friend-handler` 括号匹配问题（可能有额外的闭合括号）
- [ ] 测试完整的跨平台消息（Web ↔ Android）
- [ ] 实现文件上传功能的完整测试

### 中优先级
- [ ] 添加好友删除功能
- [ ] 实现群组聊天功能
- [ ] 完善消息类型（图片、语音、视频、文件）的 UI 展示

### 低优先级
- [ ] 添加用户头像上传功能
- [ ] 实现消息已读未读状态
- [ ] 添加在线状态显示

---

## 测试账户

| 用户名 | 密码 | 说明 |
|--------|------|------|
| admin | admin123 | 管理员账户（需确认密码） |
| testapi | - | API 测试账户 |
| apitest | - | API 测试账户 2 |

**Session Token:** `test-token-12345`（用于 API 测试）

---

## 注意事项

1. **SBCL 进程管理:** 重启服务器前务必杀死所有 SBCL 进程，否则可能使用旧代码
   ```bash
   powershell -Command "Get-Process sbcl | Stop-Process -Force"
   ```

2. **编译缓存:** 修改代码后清除 fasl 缓存
   ```bash
   rm -rf "$HOME/AppData/Local/cache/common-lisp/sbcl-2.5.8-win-x64/D/Claude/LispIM/"
   ```

3. **数据库连接:** PostgreSQL 配置
   - Host: 127.0.0.1
   - Port: 5432
   - Database: lispim
   - User: lispim
   - Password: Clsper03

4. **API 认证:** 所有需要认证的端点在请求头中添加
   ```
   Authorization: Bearer <session-token>
   ```

---

## 项目架构

```
D:\Claude\LispIM\
├── lispim-core/          # Lisp 后端核心
│   ├── src/
│   │   ├── package.lisp      # 包定义
│   │   ├── conditions.lisp   # 条件系统
│   │   ├── gateway.lisp      # HTTP 网关
│   │   ├── storage.lisp      # 数据存储
│   │   ├── auth.lisp         # 认证
│   │   ├── chat.lisp         # 聊天逻辑
│   │   └── server.lisp       # 服务器
│   ├── migrations/       # 数据库迁移
│   └── start.lisp        # 启动脚本
├── web-client/           # React Web 客户端
│   └── dist/             # 编译产物
├── android-app/          # Android 客户端
│   └── app/src/main/     # Kotlin 源码
└── BACKEND_API_SUMMARY.md  # API 文档
```

---

**下次启动时:** 阅读此文档，执行快速启动指南中的命令即可继续工作。
