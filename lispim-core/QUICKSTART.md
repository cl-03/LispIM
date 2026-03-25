# LispIM 快速开始指南

## 一键启动

### Windows

双击运行 `start-dev.bat` 或在命令行执行：

```batch
.\start-dev.bat
```

### Linux / macOS

```bash
# 启动 Docker 服务
docker-compose up -d

# 启动 LispIM
sbcl --load lispim-backend-app.lisp --eval "(lispim-backend-app:main)"
```

---

## 访问地址

| 服务 | 地址 |
|------|------|
| **LispIM** | http://localhost:4321 |
| **邮件测试** | http://localhost:8025 |
| **数据库管理** | http://localhost:8080 |
| **对象存储** | http://localhost:9001 |
| **Redis 管理** | http://localhost:8081 |

---

## 测试账号

- 用户名：`admin`
- 密码：`admin123`

---

## 停止服务

```batch
.\stop-dev.bat
```

---

## 常见问题

### 查看邮件验证码

开发环境下所有邮件都会发送到 MailHog：
1. 访问 http://localhost:8025
2. 查看最新邮件

### 查看短信验证码

开发模式下短信会打印到服务器日志：
```
【测试模式】验证码：123456 (目标：13800138000)
```

---

详细文档请查看 [DEVELOPMENT.md](DEVELOPMENT.md)
