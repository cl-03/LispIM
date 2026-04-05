# LispIM 部署文档

## 编译状态

✅ **lispim-core 编译成功** (SBCL 2.5.8)

所有核心模块已通过编译验证：
- 认证系统 (auth.lisp)
- 网关服务 (gateway.lisp)
- 消息存储 (storage.lisp)
- 聊天系统 (chat.lisp)
- 房间管理 (room.lisp)
- 命令系统 (commands.lisp)
- 消息反应 (reactions.lisp)
- 在线缓存 (online-cache.lisp)
- 中间件管道 (middleware.lisp)
- E2EE 加密 (double-ratchet.lisp)
- 消息队列 (message-queue.lisp)
- 集群同步 (cluster.lisp)

## 目录

1. [快速开始](#快速开始)
2. [Docker 部署](#docker 部署推荐)
3. [本地部署](#本地部署)
4. [Windows 部署](#windows 部署)
5. [配置说明](#配置说明)
6. [故障排除](#故障排除)
7. [验证部署](#验证部署)

---

## 快速开始

### 一键部署（推荐）

**使用 Docker Compose**:
```bash
# 克隆仓库
git clone https://github.com/lispim/lispim.git
cd lispim

# 启动所有服务
docker-compose up -d

# 访问服务
# Web 前端：http://localhost:5173
# API 网关：http://localhost:3000
```

**Windows 用户**:
```powershell
# 双击运行或在 PowerShell 中执行
.\quick-start.ps1 -Init   # 首次初始化
.\quick-start.ps1 -Start  # 启动服务
```

或运行批处理文件：
```cmd
start.bat
```

---

## Docker 部署（推荐）

### 前置条件

- Docker Desktop (Windows/macOS) 或 Docker Engine 20+ (Linux)
- Docker Compose 2.0+

### 启动服务

```bash
# 启动基础服务（数据库、Redis、后端）
docker-compose up -d

# 启动包括前端开发服务器
docker-compose --profile dev up -d

# 启动包括监控工具
docker-compose --profile monitoring --profile tools up -d
```

### 服务端口

| 服务 | 端口 | 说明 |
|------|------|------|
| Web 前端 | 5173 | Vite 开发服务器 |
| API 网关 | 3000 | HTTP/WebSocket |
| PostgreSQL | 5432 | 数据库 |
| Redis | 6379 | 缓存 |
| MinIO | 9000/9001 | 对象存储 |
| Adminer | 8080 | 数据库管理 |
| Redis Commander | 8081 | Redis 管理 |
| Prometheus | 9090 | 监控指标 |
| Grafana | 3001 | 仪表盘 |

### 停止服务

```bash
# 停止所有服务
docker-compose down

# 停止并删除数据（谨慎使用）
docker-compose down -v
```

---

## 本地部署

### Linux/macOS

#### 1. 安装依赖

```bash
# macOS
brew install sbcl postgresql redis node

# Ubuntu/Debian
sudo apt update
sudo apt install -y sbcl postgresql redis-server nodejs npm
```

#### 2. 安装 Quicklisp

```bash
curl -O https://beta.quicklisp.org/quicklisp.lisp
sbcl --non-interactive \
    --load quicklisp.lisp \
    --eval '(quicklisp-quickstart:install)' \
    --eval '(ql:add-to-init-file)' \
    --quit
rm quicklisp.lisp
```

#### 3. 初始化数据库

```bash
sudo -u postgres psql << EOF
CREATE DATABASE lispim;
CREATE USER lispim WITH PASSWORD 'Clsper03';
GRANT ALL PRIVILEGES ON DATABASE lispim TO lispim;
EOF

# 运行迁移
cd lispim-core
for f in migrations/*.up.sql; do
    psql -U lispim -d lispim -f "$f"
done
```

#### 4. 启动服务

```bash
# 启动 Redis
redis-server --daemonize yes

# 启动后端
export DATABASE_URL="postgresql://lispim:Clsper03@localhost:5432/lispim"
export REDIS_URL="redis://localhost:6379/0"
cd lispim-core
sbcl --non-interactive --load src/server.lisp \
     --eval "(lispim-core:start-server)" \
     --eval "(loop while lispim-core:*server-running* do (sleep 1))"

# 启动前端（新终端）
cd web-client
npm install
npm run dev
```

---

## Windows 部署

### 1. 使用 Chocolatey 安装依赖

```powershell
# 以管理员身份运行 PowerShell
choco install -y sbcl postgresql redis nodejs git
```

### 2. 安装 Quicklisp

```powershell
Invoke-WebRequest -Uri "https://beta.quicklisp.org/quicklisp.lisp" -OutFile "quicklisp.lisp"
sbcl --non-interactive `
     --load quicklisp.lisp `
     --eval "(quicklisp-quickstart:install)" `
     --eval "(ql:add-to-init-file)" `
     --quit
Remove-Item quicklisp.lisp
```

### 3. 初始化数据库

```powershell
$env:PGPASSWORD = "postgres"
psql -U postgres -h localhost -c "CREATE DATABASE lispim;"
psql -U postgres -h localhost -c "CREATE USER lispim WITH PASSWORD 'Clsper03';"
psql -U postgres -h localhost -c "GRANT ALL PRIVILEGES ON DATABASE lispim TO lispim;"

# 运行迁移
cd lispim-core
Get-ChildItem migrations\*.up.sql | ForEach-Object {
    psql -U lispim -d lispim -h localhost -f $_.FullName
}
```

### 4. 启动服务

```powershell
# 使用快速启动脚本
.\quick-start.ps1

# 或手动启动
$env:DATABASE_URL = "postgresql://lispim:Clsper03@localhost:5432/lispim"
$env:REDIS_URL = "redis://localhost:6379/0"
cd lispim-core
sbcl --non-interactive `
     --load src/server.lisp `
     --eval "(lispim-core:start-server)"
```

---

## 配置说明

### 环境变量

| 变量 | 说明 | 默认值 |
|------|------|--------|
| `DATABASE_URL` | PostgreSQL 连接字符串 | `postgresql://lispim:Clsper03@localhost:5432/lispim` |
| `REDIS_URL` | Redis 连接字符串 | `redis://localhost:6379/0` |
| `LISPIM_HOST` | 监听地址 | `0.0.0.0` |
| `LISPIM_PORT` | 监听端口 | `3000` |
| `LOG_LEVEL` | 日志级别 | `info` |
| `OPENCLAW_ENDPOINT` | OpenClaw AI 端点 | 空 |
| `OPENCLAW_API_KEY` | OpenClaw API 密钥 | 空 |

### .env 文件示例

在项目根目录创建 `.env` 文件：

```bash
# 数据库
DATABASE_URL=postgresql://lispim:Clsper03@localhost:5432/lispim

# Redis
REDIS_URL=redis://localhost:6379/0

# 服务器
LISPIM_HOST=0.0.0.0
LISPIM_PORT=3000
LOG_LEVEL=info

# OpenClaw AI（可选）
# OPENCLAW_ENDPOINT=https://api.openclaw.com
# OPENCLAW_API_KEY=your-api-key
```

---

## 故障排除

### 1. SBCL 无法启动

**错误**: `The system "lispim-core" is not found`

**解决**:
```bash
cd lispim-core
sbcl --load lispim-core.asd
```

### 2. 数据库连接失败

**错误**: `connection refused to host: 127.0.0.1, port: 5432`

**解决**:
```bash
# 检查 PostgreSQL 是否运行
# Linux
sudo systemctl status postgresql
sudo systemctl restart postgresql

# Windows
Get-Service postgresql*
Restart-Service postgresql*
```

### 3. Redis 连接失败

**错误**: `Failed to connect to Redis`

**解决**:
```bash
# 检查 Redis
redis-cli ping

# 启动 Redis
redis-server
```

### 4. 端口被占用

**错误**: `Address already in use`

**解决**:
```bash
# 查找占用进程
# Linux/macOS
lsof -i :3000

# Windows
netstat -ano | findstr :3000

# 修改变量使用其他端口
export LISPIM_PORT=3001
```

### 5. Docker 容器启动失败

**错误**: `container exited with code 1`

**解决**:
```bash
# 查看日志
docker-compose logs sbcl
docker-compose logs postgres

# 重新构建
docker-compose build --no-cache
docker-compose up -d
```

### 6. Quicklisp 下载失败

**错误**: `Failed to download dependency`

**解决**:
```bash
# 清除缓存
rm -rf ~/quicklisp/dists/

# 使用国内镜像（中国）
sbcl --eval '(ql:quickload :lispim-core :prompt nil)'
```

### 7. Lisp 编译错误

**错误**: `COMPILE-FILE-ERROR` 或 `READ error`

**解决**:
```bash
# 清除 fasl 缓存
rm -rf ~/quicklisp/local-projects/lispim-core/src/*.fasl

# 重新编译
sbcl --non-interactive --eval "(ql:quickload :lispim-core :force t)"
```

**验证编译**:
```bash
# 应该输出 "Loading 'lispim-core'" 并无错误
sbcl --non-interactive --eval "(ql:quickload :lispim-core)" 2>&1 | grep -E "(ERROR|failed|success)"
```

---

## 验证部署

### 健康检查

```bash
# API 健康检查
curl http://localhost:3000/healthz

# 预期输出
{"status":"healthy"}
```

### 测试注册

```bash
curl -X POST http://localhost:3000/api/v1/auth/register \
  -H "Content-Type: application/json" \
  -d '{"method":"username","username":"test","password":"test123"}'
```

### 测试登录

```bash
curl -X POST http://localhost:3000/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"test","password":"test123"}'
```

### WebSocket 测试

在浏览器控制台运行：
```javascript
const ws = new WebSocket('ws://localhost:3000/ws');
ws.onopen = () => console.log('Connected!');
ws.onmessage = (e) => console.log('Message:', e.data);
```

---

## 性能优化

### 数据库索引

```sql
CREATE INDEX CONCURRENTLY IF NOT EXISTS
    idx_messages_conversation ON messages(conversation_id);
CREATE INDEX CONCURRENTLY IF NOT EXISTS
    idx_messages_created ON messages(created_at);
```

### Redis 配置

```bash
redis-cli CONFIG SET maxmemory 256mb
redis-cli CONFIG SET maxmemory-policy allkeys-lru
```

---

*最后更新：2026-04-02*
*LispIM Version: 0.1.0*
