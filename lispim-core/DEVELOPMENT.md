# LispIM 开发环境指南

## 快速开始

### 1. 前置要求

- [Docker Desktop](https://www.docker.com/products/docker-desktop/) - 用于运行数据库和服务
- [SBCL 2.5.8+](http://www.sbcl.org/) - Common Lisp 实现
- [Quicklisp](https://www.quicklisp.org/) - Common Lisp 库管理器

### 2. 一键启动（Windows）

双击运行 `start-dev.bat` 或在命令行执行：

```batch
.\start-dev.bat
```

这会自动：
- 启动 PostgreSQL、Redis、MinIO、MailHog 等服务
- 启动 LispIM 服务器
- 打开浏览器访问 http://localhost:4321

### 3. 手动启动

```bash
# 启动 Docker 服务
docker-compose up -d

# 等待服务就绪（约 10 秒）
sleep 10

# 启动 LispIM
sbcl --load lispim-backend-app.lisp --eval "(lispim-backend-app:main)"
```

### 4. 停止服务

```batch
# Windows
.\stop-dev.bat

# 或手动执行
docker-compose down
```

---

## 服务访问地址

| 服务 | 地址 | 用途 |
|------|------|------|
| **LispIM Web** | http://localhost:4321 | 主应用 |
| **MailHog** | http://localhost:8025 | 邮件测试 |
| **MinIO Console** | http://localhost:9001 | 对象存储管理 |
| **Adminer** | http://localhost:8080 | 数据库管理 |
| **Redis Commander** | http://localhost:8081 | Redis 管理 |

---

## 开发模式特性

### 邮件发送

开发环境下，所有邮件都会发送到 MailHog，而不是真实邮箱。

**查看邮件：** 访问 http://localhost:8025

### 短信验证码

开发模式下，验证码会打印到服务器日志，格式：

```
【测试模式】验证码：123456 (目标：13800138000)
```

### 数据库管理

**使用 Adminer：**
1. 访问 http://localhost:8080
2. 系统：PostgreSQL
3. 服务器：postgres
4. 用户名：lispim
5. 密码：Clsper03
6. 数据库：lispim

---

## 配置说明

### 环境变量文件

复制 `.env.example` 为 `.env`：

```bash
copy .env.example .env
```

### 主要配置项

```bash
# 服务器端口
LISPIM_PORT=4321

# 数据库连接
DATABASE_URL=postgresql://lispim:Clsper03@localhost:5432/lispim

# Redis 连接
REDIS_URL=redis://localhost:6379/0

# 日志级别
LOG_LEVEL=debug  # debug, info, warn, error
```

---

## 生产环境配置

### 1. 使用真实邮件服务

修改 `.env`：

```bash
SMTP_HOST=smtp.qq.com
SMTP_PORT=587
SMTP_USER=your-email@qq.com
SMTP_PASSWORD=your-auth-code  # QQ 邮箱授权码
```

### 2. 使用阿里云短信

```bash
SMS_PROVIDER=aliyun
SMS_ALIYUN_ACCESS_KEY=your-key
SMS_ALIYUN_ACCESS_SECRET=your-secret
SMS_ALIYUN_SIGN_NAME=你的签名
SMS_ALIYUN_TEMPLATE_CODE=SMS_模板码
```

### 3. 内网穿透（Cloudflare Tunnel）

```bash
# 安装 cloudflared
winget install cloudflare.cloudflared

# 创建并运行隧道
cloudflared tunnel create lispim
cloudflared tunnel route dns lispim im.yourdomain.com
cloudflared tunnel run lispim --url http://localhost:4321
```

---

## 常见问题

### Q: Docker 服务启动失败？

A: 检查端口是否被占用：
```bash
netstat -ano | findstr :5432
netstat -ano | findstr :6379
```

### Q: LispIM 编译失败？

A: 清除缓存后重试：
```bash
# 删除 FASL 文件
del /s *.fasl

# 删除 Quicklisp 缓存
rmdir /s /q C:\Users\%USERNAME%\quicklisp\dists\quicklisp\installed\systems\lispim-core
```

### Q: 数据库连接失败？

A: 检查 Docker 容器状态：
```bash
docker ps -a
docker logs lispim-postgres
```

### Q: 如何重置数据库？

A: 删除并重建容器：
```bash
docker-compose down -v  # -v 会删除数据卷
docker-compose up -d
```

---

## 测试账号

- 用户名：`admin`
- 密码：`admin123`

---

## 目录结构

```
lispim-core/
├── docker/
│   └── postgres/
│       └── init.sql       # 数据库初始化脚本
├── src/
│   ├── package.lisp       # 包定义
│   ├── conditions.lisp    # 条件系统
│   ├── utils.lisp         # 工具函数
│   ├── server.lisp        # 服务器入口
│   └── ...
├── docker-compose.yml     # Docker 配置
├── .env.example          # 环境变量模板
├── start-dev.bat         # 启动脚本
├── stop-dev.bat          # 停止脚本
└── README.md             # 本文档
```

---

## 下一步

1. 修改 `.env` 配置
2. 运行 `start-dev.bat` 启动服务
3. 访问 http://localhost:4321 测试
4. 查看 MailHog 验证邮件发送

祝你开发愉快！
