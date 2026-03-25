# 逍遥模拟器测试配置指南

## 网络配置

### 宿主机（你的电脑）
- **IP 地址:** 192.168.50.74
- **服务器端口:** 8443
- **防火墙:** 已添加规则允许 8443 端口

### 逍遥模拟器
逍遥模拟器与宿主机在同一局域网，需要使用宿主机实际 IP 地址。

## 测试步骤

### 步骤 1: 启动逍遥模拟器
1. 打开逍遥模拟器
2. 等待完全启动到主屏幕
3. 确保模拟器可以上网

### 步骤 2: 连接 ADB（可选）
```bash
# 查看逍遥模拟器窗口标题获取端口
# 通常端口是 21503, 21513, 21523 等

# 尝试连接
adb connect 127.0.0.1:21503
adb connect 127.0.0.1:21513
adb connect 127.0.0.1:21523

# 验证连接
adb devices
```

### 步骤 3: 安装 APK
```bash
adb install app/build/outputs/apk/debug/app-debug.apk
```

### 步骤 4: 配置服务器地址
**在登录界面：**
1. 打开 LispIM 应用
2. 在 **Server URL** 字段输入：`http://192.168.50.74:8443`
3. **Username:** `testuser`
4. **Password:** `testpass`
5. 点击 **Login**

### 步骤 5: 验证登录
查看服务器日志确认登录成功：
```bash
tail -f /d/Claude/LispIM/lispim-core/server_test.log
```

## 常见问题

### 无法连接服务器
1. 确认服务器运行：`curl http://192.168.50.74:8443/healthz`
2. 检查防火墙：`netsh advfirewall show rule name="LispIM Server"`
3. 确认模拟器可以 ping 通宿主机

### ADB 无法连接
1. 查看逍遥模拟器设置中的 ADB 端口
2. 在模拟器系统设置中启用 USB 调试
3. 使用正确的端口号连接

### 登录失败
1. 确认服务器地址正确（使用 192.168.50.74，不是 10.0.2.2 或 localhost）
2. 确认账号密码正确
3. 检查服务器日志

## 快速测试命令

```bash
# 1. 编译 APK
cd /d/Claude/LispIM/android-app && ./gradlew assembleDebug

# 2. 安装到模拟器（需要先连接 ADB）
adb install app/build/outputs/apk/debug/app-debug.apk

# 3. 测试服务器（从宿主机）
curl http://192.168.50.74:8443/healthz

# 4. 查看服务器日志
tail -f server_test.log
```
