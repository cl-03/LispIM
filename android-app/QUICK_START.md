# 快速测试指南

## 当前状态
- **后端服务器**: 运行中 (http://localhost:8443)
- **Android Studio 模拟器**: 需要重启系统后才能使用
- **推荐方案**: 使用逍遥模拟器

## 立即测试（使用逍遥模拟器）

### 步骤 1: 启动逍遥模拟器
1. 打开逍遥模拟器应用
2. 等待完全启动到主屏幕

### 步骤 2: 连接 ADB
```bash
adb connect 127.0.0.1:21503
adb devices
```

### 步骤 3: 安装 APK
```bash
cd /d/Claude/LispIM/android-app
./gradlew installDebug
```

### 步骤 4: 启动应用
```bash
adb shell am start -n com.lispim.client/.MainActivity
```

### 步骤 5: 配置服务器
在应用登录界面输入：
- **Server URL**: `http://192.168.50.74:8443`
- **Username**: `testuser`
- **Password**: `testpass`

---

## 使用 Android Studio 模拟器（需要重启后）

### 重启前准备
确保已启用：
- Hyper-V: 已启用
- Windows Hypervisor Platform: 已启用

### 重启后操作
1. 重启电脑
2. 双击 `start_emulator.bat` 启动模拟器
3. 等待模拟器完全启动（约 2-3 分钟）
4. 验证连接：`adb devices`
5. 安装 APK：`./gradlew installDebug`
6. 配置服务器：`http://10.0.2.2:8443`

---

## 测试账号
- 用户名：testuser
- 密码：testpass

## 服务器地址对照
| 环境 | 地址 |
|------|------|
| 逍遥模拟器 | http://192.168.50.74:8443 |
| Android Studio 模拟器 | http://10.0.2.2:8443 |
| 物理设备 | http://192.168.50.74:8443 |
