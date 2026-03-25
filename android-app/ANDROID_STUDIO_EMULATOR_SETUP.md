# Android Studio 模拟器配置指南

## 当前状态

后端服务器已运行：http://localhost:8443
健康检查：`curl http://localhost:8443/healthz` → OK

## 问题说明

Android Studio 模拟器需要安装 Hypervisor 驱动才能运行。当前状态：
- Hyper-V：已启用
- Windows Hypervisor Platform：已启用
- **Android Emulator Hypervisor 驱动：未安装**

## 解决方案

### 方案 1：安装 Android Emulator Hypervisor 驱动（推荐）

1. 打开 Android Studio
2. 进入 `Tools` → `SDK Manager`
3. 选择 `SDK Tools` 标签
4. 勾选 `Android Emulator`
5. 点击 `Apply` 安装
6. **重启电脑**

或者从 SDK 目录手动安装驱动：
```
D:\Claude\Android\extras\intel\Hardware_Accelerated_Execution_Manager\
运行：intelhaxm-android.exe
```

### 方案 2：使用逍遥模拟器（立即可用）

逍遥模拟器不需要额外驱动，已经配置好：

1. 启动逍遥模拟器
2. 连接 ADB：
```bash
adb connect 127.0.0.1:21503
```

3. 安装 APK：
```bash
cd /d/Claude/LispIM/android-app
./gradlew installDebug
```

4. 启动应用：
```bash
adb shell am start -n com.lispim.client/.MainActivity
```

5. 配置服务器地址：`http://192.168.50.74:8443`

### 方案 3：使用物理 Android 设备

1. 在手机上启用开发者选项和 USB 调试
2. 用 USB 连接电脑
3. 运行：
```bash
adb devices  # 验证连接
./gradlew installDebug  # 安装 APK
```

4. 配置服务器地址：`http://192.168.50.74:8443`（确保手机和电脑在同一局域网）

## 快速启动脚本

已创建 `start_emulator.bat`，双击即可启动模拟器：
```
D:\Claude\LispIM\android-app\start_emulator.bat
```

**注意**：首次运行前需要安装 Hypervisor 驱动并重启系统。

## 测试账号

- **用户名**: testuser
- **密码**: testpass

## 服务器地址配置

| 环境 | 服务器地址 |
|------|-----------|
| Android Studio 模拟器 | http://10.0.2.2:8443 |
| 逍遥模拟器 | http://192.168.50.74:8443 |
| 物理设备（同一局域网）| http://192.168.50.74:8443 |

## 验证步骤

1. 确保后端服务器运行：
```bash
curl http://localhost:8443/healthz
```

2. 检查设备连接：
```bash
/d/Claude/Android/platform-tools/adb devices
```

3. 安装 APK：
```bash
cd /d/Claude/LispIM/android-app
./gradlew installDebug
```

4. 启动应用：
```bash
adb shell am start -n com.lispim.client/.MainActivity
```

5. 在应用中配置服务器地址并登录

## 常见问题

### 模拟器启动失败
- 检查 Hyper-V 是否启用：`Get-WindowsOptionalFeature -FeatureName Microsoft-Hyper-V -Online`
- 检查 HypervisorPlatform 是否启用：`Get-WindowsOptionalFeature -FeatureName HypervisorPlatform -Online`
- 重启电脑

### 设备离线 (offline)
- 重启 ADB：`adb kill-server && adb start-server`
- 冷启动模拟器：`emulator -avd Pixel_6_Pro_API_34 -no-snapshot-load`

### 安装失败
- 确保设备已解锁
- 确保 APK 已编译：`./gradlew assembleDebug`
