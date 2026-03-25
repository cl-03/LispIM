# LispIM Backend 桌面应用

## 快速启动

### 方法 1: 双击快捷方式
双击 `LispIM Backend.lnk` 即可启动后端服务器。

### 方法 2: 运行批处理文件
双击 `LispIM_backend.bat` 启动服务器（后台运行）。

### 方法 3: 直接运行
双击 `start-server.bat` 启动服务器（前台运行，可按 Ctrl+C 停止）。

---

## 启动说明

### 前置条件
确保以下服务已启动：
- **PostgreSQL** (端口 5432)
- **Redis** (端口 6379)

### 服务器信息
启动后可访问：
- **健康检查:** http://localhost:8443/healthz
- **登录 API:** POST http://localhost:8443/api/v1/auth/login

### 测试账号
- **用户名:** testuser
- **密码:** testpass

---

## 文件说明

| 文件名 | 说明 |
|--------|------|
| `LispIM Backend.lnk` | 桌面快捷方式 |
| `LispIM_backend.bat` | 后台启动脚本 |
| `LispIM_backend.ps1` | PowerShell 启动脚本 |
| `start-server.bat` | 前台启动脚本 |
| `run-server.lisp` | Lisp 启动代码 |

---

## 停止服务器

- 如果使用 `start-server.bat` 启动：按 `Ctrl+C` 停止
- 如果使用 `LispIM_backend.bat` 启动：关闭 SBCL 控制台窗口

---

## 常见问题

### 端口被占用
错误信息：`地址已被使用`
解决：确保没有其他实例在运行，或修改配置中的端口。

### 数据库连接失败
错误信息：`连接被拒绝`
解决：确保 PostgreSQL 和 Redis 服务已启动。

### 找不到 SBCL
确保 `D:\SBCL\sbcl.exe` 和 `D:\SBCL\sbcl.core` 存在。
