# LispIM 开发环境文件清单

## 核心配置文件

| 文件名 | 用途 | 说明 |
|--------|------|------|
| `docker-compose.yml` | Docker 服务编排 | 定义 PostgreSQL、Redis、MinIO 等容器 |
| `.env.example` | 环境变量模板 | 复制为 `.env` 后使用 |
| `.gitignore` | Git 忽略规则 | 排除 FASL、日志等文件 |

## 数据库脚本

| 文件名 | 用途 | 说明 |
|--------|------|------|
| `docker/postgres/init.sql` | 数据库初始化 | 创建表结构、测试数据 |
| `docker/minio/init.sh` | MinIO 初始化 | 创建存储桶 |

## 启动脚本（Windows）

| 文件名 | 用途 | 使用方法 |
|--------|------|----------|
| `start-dev.bat` | 一键启动 | 双击运行 |
| `stop-dev.bat` | 停止服务 | 双击运行 |
| `check-env.bat` | 环境检查 | 排查问题 |

## Lisp 源代码

| 文件名 | 用途 | 说明 |
|--------|------|------|
| `lispim-backend-app.lisp` | 后端启动器 | 已更新为开发模式 |

## 文档

| 文件名 | 用途 |
|--------|------|
| `QUICKSTART.md` | 快速开始指南 |
| `DEVELOPMENT.md` | 开发环境文档 |
| `零成本测试方案.md` | 零成本方案说明 |
| `README-LOCAL.md` | 本文档 |

---

## 使用流程

### 第一次使用

1. **检查环境**
   ```batch
   check-env.bat
   ```

2. **安装缺失的软件**
   - Docker Desktop
   - SBCL 2.5.8+

3. **配置环境变量**
   ```bash
   copy .env.example .env
   ```

4. **启动服务**
   ```batch
   start-dev.bat
   ```

5. **访问应用**
   - 自动打开浏览器
   - 或手动访问 http://localhost:4321

---

## 服务端口

| 服务 | 端口 | 访问地址 |
|------|------|----------|
| LispIM | 4321 | http://localhost:4321 |
| PostgreSQL | 5432 | localhost:5432 |
| Redis | 6379 | localhost:6379 |
| MinIO API | 9000 | http://localhost:9000 |
| MinIO Console | 9001 | http://localhost:9001 |
| MailHog SMTP | 1025 | localhost:1025 |
| MailHog Web | 8025 | http://localhost:8025 |
| Adminer | 8080 | http://localhost:8080 |
| Redis Commander | 8081 | http://localhost:8081 |

---

## Docker 容器

```yaml
services:
  - lispim-postgres    # PostgreSQL 数据库
  - lispim-redis       # Redis 缓存
  - lispim-minio       # MinIO 对象存储
  - lispim-mailhog     # 邮件测试工具
  - lispim-adminer     # 数据库管理界面
  - lispim-redis-commander  # Redis 管理界面
```

---

## 环境变量说明

### 必需配置

```bash
# 服务器配置
LISPIM_HOST=0.0.0.0
LISPIM_PORT=4321

# 数据库
DATABASE_URL=postgresql://lispim:Clsper03@localhost:5432/lispim

# Redis
REDIS_URL=redis://localhost:6379/0
```

### 可选配置

```bash
# 邮件（生产环境）
SMTP_HOST=smtp.qq.com
SMTP_PORT=587
SMTP_USER=your-email@qq.com
SMTP_PASSWORD=your-auth-code

# 短信（生产环境）
SMS_PROVIDER=aliyun
SMS_ALIYUN_ACCESS_KEY=your-key
SMS_ALIYUN_ACCESS_SECRET=your-secret

# OpenClaw AI
OPENCLAW_ENDPOINT=https://your-openclaw-endpoint
OPENCLAW_API_KEY=your-api-key
```

---

## 故障排除

### 问题 1: Docker 服务无法启动

**检查:**
```batch
check-env.bat
```

**解决:**
1. 确保 Docker Desktop 正在运行
2. 检查端口是否被占用
3. 重启 Docker Desktop

### 问题 2: LispIM 无法连接数据库

**检查:**
```bash
docker-compose ps
```

**解决:**
1. 等待 PostgreSQL 完全启动（约 10 秒）
2. 检查 `.env` 中的数据库配置
3. 查看 PostgreSQL 日志：`docker-compose logs postgres`

### 问题 3: 邮件无法发送

**检查:**
1. 开发环境：MailHog 是否运行
2. 生产环境：SMTP 配置是否正确

**查看邮件:**
http://localhost:8025

### 问题 4: SBCL 编译失败

**清理缓存:**
```bash
# 删除 FASL 文件
del /s *.fasl

# 删除 Quicklisp 缓存
rmdir /s /q %USERPROFILE%\quicklisp\dists\quicklisp\installed\systems\lispim-core
```

---

## 重置环境

### 软重置（保留数据）

```batch
stop-dev.bat
start-dev.bat
```

### 硬重置（删除所有数据）

```bash
# 停止并删除容器和数据卷
docker-compose down -v

# 重新启动
docker-compose up -d

# 启动 LispIM
sbcl --load lispim-backend-app.lisp --eval "(lispim-backend-app:main)"
```

---

## 性能优化

### 增加 Docker 资源

Docker Desktop 设置:
- Settings → Resources → Advanced
- CPUs: 4+
- Memory: 8GB+
- Disk: 50GB+

### SBCL 优化

```lisp
;; 在 REPL 中执行
(compile-all)
```

---

## 备份数据

### 数据库备份

```bash
docker exec lispim-postgres pg_dump -U lispim lispim > backup.sql
```

### 恢复数据库

```bash
docker exec -i lispim-postgres psql -U lispim lispim < backup.sql
```

### MinIO 数据

MinIO 数据存储在 Docker volume 中：
```bash
docker volume ls | grep lispim-core_miniodata
```

---

## 下一步

1. ✅ 运行 `check-env.bat` 检查环境
2. ✅ 运行 `start-dev.bat` 启动服务
3. ✅ 访问 http://localhost:4321
4. ✅ 开始开发

祝你开发顺利！
