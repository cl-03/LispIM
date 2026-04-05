# LispIM 本地部署指南

本指南帮助你在本地计算机上完整部署 LispIM 即时通信系统，包括后端、Web 前端、数据库和缓存服务。

---

## 系统要求

### 最低配置
- **CPU**: 4 核心
- **内存**: 4GB
- **磁盘**: 10GB 可用空间
- **操作系统**: Windows 10/11, macOS 10.15+, Linux

### 推荐配置
- **CPU**: 8 核心
- **内存**: 8GB
- **磁盘**: 20GB SSD
- **操作系统**: Windows 11, macOS 12+, Ubuntu 22.04+

---

## 方式一：Docker Compose 部署（推荐）

### 1. 安装 Docker

**Windows/macOS**:
1. 访问 https://www.docker.com/products/docker-desktop
2. 下载并安装 Docker Desktop
3. 启动 Docker Desktop

**Linux (Ubuntu)**:
```bash
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER
```

### 2. 克隆项目

```bash
git clone https://github.com/lispim/lispim.git
cd lispim
```

### 3. 启动服务

```bash
# 启动所有服务（数据库、Redis、后端、监控）
docker-compose up -d

# 查看日志
docker-compose logs -f

# 查看特定服务日志
docker-compose logs -f sbcl
docker-compose logs -f postgres
```

### 4. 访问服务

| 服务 | 地址 | 说明 |
|------|------|------|
| Web 前端 | http://localhost:3000 | 主界面 |
| API 网关 | http://localhost:3000/api/v1 | REST API |
| WebSocket | ws://localhost:3000/ws | 实时通信 |
| Prometheus | http://localhost:9090 | 监控指标 |
| Grafana | http://localhost:3001 | 仪表盘 (admin/admin) |
| Adminer | http://localhost:8080 | 数据库管理 |
| Redis Commander | http://localhost:8081 | Redis 可视化管理 |

### 5. 停止服务

```bash
# 停止所有服务
docker-compose down

# 停止并删除数据卷（谨慎使用）
docker-compose down -v
```

---

## 方式二：本地直接部署

### Windows 部署

#### 1. 安装依赖

**安装 SBCL (Steel Bank Common Lisp)**:
```powershell
# 使用 Chocolatey
choco install sbcl

# 或从官网下载：http://www.sbcl.org/platform.html
```

**安装 PostgreSQL**:
```powershell
# 使用 Chocolatey
choco install postgresql

# 或使用官方安装包：https://www.postgresql.org/download/windows/
```

**安装 Redis**:
```powershell
# 使用 Chocolatey
choco install redis-64

# 或使用 Windows 子系统 (WSL2) 运行 Linux Redis
wsl sudo apt install redis-server
```

**安装 Quicklisp (Lisp 包管理器)**:
```powershell
# 下载 Quicklisp
curl -O https://beta.quicklisp.org/quicklisp.lisp

# 安装 Quicklisp
sbcl --non-interactive ^
    --load quicklisp.lisp ^
    --eval "(quicklisp-quickstart:install)" ^
    --eval "(ql:add-to-init-file)" ^
    --quit

del quicklisp.lisp
```

#### 2. 初始化数据库

```powershell
# 创建数据库
psql -U postgres -c "CREATE DATABASE lispim;"
psql -U postgres -c "CREATE USER lispim WITH PASSWORD 'Clsper03';"
psql -U postgres -c "GRANT ALL PRIVILEGES ON DATABASE lispim TO lispim;"

# 运行迁移脚本
psql -U lispim -d lispim -f lispim-core\migrations\001-initial-schema.up.sql
psql -U lispim -d lispim -f lispim-core\migrations\002-friend-system.up.sql
psql -U lispim -d lispim -f lispim-core\migrations\003-mobile-support.up.sql
psql -U lispim -d lispim -f lispim-core\migrations\004-message-status-tracking.up.sql
psql -U lispim -d lispim -f lispim-core\migrations\005-incremental-sync.up.sql
psql -U lispim -d lispim -f lispim-core\migrations\006-message-reply.up.sql
```

#### 3. 启动后端服务

```powershell
# 设置环境变量
$env:DATABASE_URL = "postgresql://lispim:Clsper03@localhost:5432/lispim"
$env:REDIS_URL = "redis://localhost:6379/0"
$env:LISPIM_HOST = "0.0.0.0"
$env:LISPIM_PORT = "3000"

# 启动 SBCL 服务器
cd lispim-core
sbcl --non-interactive `
     --load src/server.lisp `
     --eval "(lispim-core:start-server)"
```

#### 4. 启动 Web 前端

```powershell
# 安装 Node.js 依赖
cd web-client
npm install

# 启动开发服务器
npm run dev

# 或构建生产版本
npm run build
```

---

### Linux/macOS 部署

#### 1. 安装依赖

```bash
# macOS (使用 Homebrew)
brew install sbcl postgresql redis node

# Ubuntu/Debian
sudo apt update
sudo apt install -y sbcl postgresql redis-server nodejs npm curl

# 安装 Quicklisp
curl -O https://beta.quicklisp.org/quicklisp.lisp
sbcl --non-interactive \
    --load quicklisp.lisp \
    --eval '(quicklisp-quickstart:install)' \
    --eval '(ql:add-to-init-file)' \
    --quit
rm quicklisp.lisp
```

#### 2. 初始化数据库

```bash
# 启动 PostgreSQL
sudo systemctl start postgresql

# 创建数据库和用户
sudo -u postgres psql << EOF
CREATE DATABASE lispim;
CREATE USER lispim WITH PASSWORD 'Clsper03';
GRANT ALL PRIVILEGES ON DATABASE lispim TO lispim;
EOF

# 运行迁移
cd lispim-core
psql -U lispim -d lispim -f migrations/001-initial-schema.up.sql
psql -U lispim -d lispim -f migrations/002-friend-system.up.sql
psql -U lispim -d lispim -f migrations/003-mobile-support.up.sql
psql -U lispim -d lispim -f migrations/004-message-status-tracking.up.sql
psql -U lispim -d lispim -f migrations/005-incremental-sync.up.sql
psql -U lispim -d lispim -f migrations/006-message-reply.up.sql
```

#### 3. 启动后端服务

```bash
# 设置环境变量
export DATABASE_URL="postgresql://lispim:Clsper03@localhost:5432/lispim"
export REDIS_URL="redis://localhost:6379/0"

# 启动 Redis
redis-server --daemonize yes

# 启动 LispIM 服务器
cd lispim-core
sbcl --non-interactive \
     --load src/server.lisp \
     --eval "(lispim-core:start-server)"
```

#### 4. 启动 Web 前端

```bash
cd web-client
npm install
npm run dev
```

---

## 配置文件说明

### 环境变量

创建 `.env` 文件在项目根目录：

```bash
# 数据库配置
DATABASE_URL=postgresql://lispim:Clsper03@localhost:5432/lispim

# Redis 配置
REDIS_URL=redis://localhost:6379/0

# 服务器配置
LISPIM_HOST=0.0.0.0
LISPIM_PORT=3000
LOG_LEVEL=info

# SSL 配置（可选）
# SSL_CERT_PATH=/path/to/cert.pem
# SSL_KEY_PATH=/path/to/key.pem

# OpenClaw AI 配置（可选）
# OPENCLAW_ENDPOINT=https://api.openclaw.com
# OPENCLAW_API_KEY=your-api-key
```

### 后端配置 (lispim-core/src/config.lisp)

```lisp
(defparameter *default-config*
  (make-config
   :host "0.0.0.0"
   :port 3000
   :database-url "postgresql://lispim:Clsper03@localhost:5432/lispim"
   :redis-url "redis://localhost:6379/0"
   :ssl-cert nil
   :ssl-key nil
   :log-level :info
   :max-connections 10000))
```

### 前端配置 (web-client/.env)

```bash
# API 地址
VITE_API_URL=http://localhost:3000/api/v1

# WebSocket 地址
VITE_WS_URL=ws://localhost:3000/ws
```

---

## 常见问题

### 1. SBCL 无法加载 ASDF 系统

**错误**: `The system "lispim-core" is not found.`

**解决**:
```bash
# 确保在正确的目录加载
cd lispim-core
sbcl --load lispim-core.asd
```

### 2. PostgreSQL 连接失败

**错误**: `connection refused`

**解决**:
```bash
# 检查 PostgreSQL 是否运行
sudo systemctl status postgresql

# 重启 PostgreSQL
sudo systemctl restart postgresql

# 检查连接
psql -U lispim -d lispim -h localhost
```

### 3. Redis 连接失败

**错误**: `Failed to connect to Redis`

**解决**:
```bash
# 检查 Redis 是否运行
redis-cli ping

# 启动 Redis
redis-server
```

### 4. 端口被占用

**错误**: `Address already in use`

**解决**:
```bash
# 查找占用端口的进程
lsof -i :3000

# 停止进程
kill -9 <PID>

# 或修改配置使用其他端口
export LISPIM_PORT=3001
```

### 5. Quicklisp 依赖下载失败

**错误**: `Failed to download dependency`

**解决**:
```bash
# 清除缓存
rm -rf ~/quicklisp/dists/

# 重新下载
sbcl --eval "(ql:quickload :lispim-core :force t)"
```

---

## 验证部署

### 1. 健康检查

```bash
# API 健康检查
curl http://localhost:3000/healthz

# 预期输出：{"status": "healthy"}
```

### 2. 测试登录

```bash
# 创建测试用户
curl -X POST http://localhost:3000/api/v1/auth/register \
  -H "Content-Type: application/json" \
  -d '{
    "method": "username",
    "username": "testuser",
    "password": "test123456"
  }'

# 登录测试
curl -X POST http://localhost:3000/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "username": "testuser",
    "password": "test123456"
  }'
```

### 3. WebSocket 测试

打开浏览器控制台，运行：
```javascript
const ws = new WebSocket('ws://localhost:3000/ws');
ws.onopen = () => console.log('Connected!');
ws.onmessage = (e) => console.log('Message:', e.data);
ws.onerror = (e) => console.error('Error:', e);
```

---

## 性能优化建议

### 1. 数据库优化

```sql
-- 创建索引
CREATE INDEX CONCURRENTLY idx_messages_conversation_id ON messages(conversation_id);
CREATE INDEX CONCURRENTLY idx_messages_created_at ON messages(created_at);
CREATE INDEX CONCURRENTLY idx_conversations_user_id ON conversation_participants(user_id);

-- 分析表
ANALYZE messages;
ANALYZE conversations;
```

### 2. Redis 优化

```bash
# 配置 Redis 内存限制
redis-cli CONFIG SET maxmemory 256mb
redis-cli CONFIG SET maxmemory-policy allkeys-lru
```

### 3. SBCL 优化

```lisp
;; 调整 GC 参数
(setf sb-ext:*gc-log-files* 1)
(setf sb-ext:*gc-log-timestamps* t)
```

---

## 下一步

1. **访问 Web 前端**: http://localhost:3000
2. **注册账户**: 点击注册按钮创建账户
3. **开始聊天**: 创建会话并发送消息
4. **配置推送**: 在生产环境配置 Firebase/FCM

---

*最后更新：2026-04-02*
*LispIM Version: 0.1.0*
