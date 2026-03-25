# LispIM Android 测试环境配置

## 项目位置
- **后端:** `D:\Claude\LispIM\lispim-core`
- **Android 客户端:** `D:\Claude\LispIM\android-app`

## 后端服务器

### 启动命令
```bash
cd /d/Claude/LispIM/lispim-core
/d/SBCL/sbcl.exe --core /d/SBCL/sbcl.core --load run-server.lisp
```

### 服务信息
- **端口:** 8443
- **健康检查:** `curl http://localhost:8443/healthz`
- **登录 API:** `POST /api/v1/auth/login`

### 测试账号
- **用户名:** `testuser`
- **密码:** `testpass`
- **用户 ID:** 10002

## Android 测试

### 模拟器配置
- **设备:** SM-S9010 (Samsung Galaxy S22)
- **Android 版本:** 9
- **网络地址:** `10.0.2.2:8443` (模拟器访问宿主机)

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

#### 4. 查看测试结果
```bash
cat app/build/outputs/androidTest-results/connected/debug/TEST-SM-S9010\ -\ 9-_app-.xml
```

### 测试代码位置
`android-app/app/src/androidTest/java/com/lispim/client/LoginTest.kt`

## 常见问题

### 登录失败检查
1. 服务器是否运行：`curl http://localhost:8443/healthz`
2. 模拟器网络：`adb shell curl http://10.0.2.2:8443/api/v1/auth/login -H 'Content-Type: application/json' -d '{"username":"testuser","password":"testpass"}'`
3. 查看服务器日志：`tail -f server_test.log`

### ADB 路径
`/d/Claude/Android/platform-tools/adb`

## 关键文件
- `src/auth.lisp` - 认证逻辑 (PBKDF2 密码验证)
- `src/gateway.lisp` - HTTP API 端点
- `run-server.lisp` - 服务器启动脚本
