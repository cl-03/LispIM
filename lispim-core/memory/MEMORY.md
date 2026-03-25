# LispIM 项目记忆

## 项目结构
- **后端:** Common Lisp (SBCL) + Hunchentoot HTTP 服务器
- **数据库:** PostgreSQL + Redis
- **客户端:** Android (Kotlin/Jetpack Compose), Tauri, Web

## 桌面应用（已创建）

### 启动方式
1. **双击启动:** `LispIM Backend.lnk`
2. **批处理:** `LispIM_backend.bat`
3. **PowerShell:** `LispIM_backend.ps1`
4. **直接启动:** `start-server.bat`

### 文件位置
- 主目录：`D:\Claude\LispIM\lispim-core\`
- 启动脚本：`run-server.lisp`

### 服务信息
- **端口:** 3000
- **健康检查:** `http://localhost:3000/healthz`
- **登录 API:** `POST /api/v1/auth/login`

### 测试账号
- **用户名:** `testuser`
- **密码:** `testpass`
- **用户 ID:** 10002

## Android 测试

### 模拟器配置
- **设备:** SM-S9010 (Samsung Galaxy S22)
- **Android 版本:** 9
- **网络地址:** `10.0.2.2:3000` (模拟器访问宿主机)

### 快速命令

#### 1. 构建 APK
```bash
cd /d/Claude/LispIM/android-app
./gradlew assembleDebug
```
APK 位置：`app/build/outputs/apk/debug/app-debug.apk`

#### 2. 安装到模拟器
```bash
/d/Claude/Android/platform-tools/adb install app/build/outputs/apk/debug/app-debug.apk
```

#### 3. 运行测试
```bash
./gradlew connectedAndroidTest
```

### 测试代码位置
`android-app/app/src/androidTest/java/com/lispim/client/LoginTest.kt`

## 认证修复 (已完成)

### 问题
`INVALID-UTF8-CONTINUATION-BYTE` 错误 - `babel:octets-to-string` 将随机盐值字节转换为 UTF-8 字符串失败

### 修复
`src/auth.lisp:83-84` - hash-password 函数返回盐值为十六进制字符串而非 UTF-8

### 测试状态
- Android 登录测试：✅ PASSED (多次运行)
- 测试用例：`LoginTest.testLoginWithValidCredentials`
- 会话创建成功，返回 token

## 快速启动清单

### 桌面应用方式
1. 双击 `LispIM Backend.lnk`
2. 或运行 `LispIM_backend.bat`

### 命令行方式
1. `cd /d/Claude/LispIM/lispim-core`
2. `/d/SBCL/sbcl.exe --core /d/SBCL/sbcl.core --load run-server.lisp`
3. 验证：`curl http://localhost:3000/healthz`

## 关键文件
- `src/auth.lisp` - 认证逻辑 (PBKDF2 密码验证)
- `src/gateway.lisp` - HTTP API 端点
- `run-server.lisp` - 服务器启动脚本
- `LispIM_backend.bat` - 桌面应用启动脚本
- `LispIM Backend.lnk` - 桌面快捷方式
