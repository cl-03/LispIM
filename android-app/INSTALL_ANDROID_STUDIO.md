# Android Studio 安装与项目打开指南

## 当前状态

⚠️ **Android Studio 未安装在本系统上**

项目代码已准备就绪，位于：`D:\Claude\LispIM\android-app`

---

## 步骤 1：下载 Android Studio

### 官方下载地址
- **国际**: https://developer.android.com/studio
- **国内镜像**: https://developer.android.google.cn/studio

### 推荐版本
- **Android Studio Hedgehog** (2023.1.1) 或更新版本
- **文件大小**: 约 1.1 GB

### 国内下载加速
由于网络限制，建议使用以下镜像：

1. **清华大学镜像**: https://mirrors.tuna.tsinghua.edu.cn/android-studio/
2. **阿里云镜像**: https://mirrors.aliyun.com/android-studio/

---

## 步骤 2：安装 Android Studio

1. **运行安装程序** (android-studio-*.exe)

2. **安装选项**（推荐配置）:
   - ☑ Android Studio
   - ☑ Android Virtual Device
   - 安装路径：`D:\Program Files\Android\Android Studio`

3. **SDK 组件设置**:
   - SDK 路径：`D:\Claude\Android` (已存在)
   - 确认 SDK 包含：
     - ✅ Android SDK Platform 34
     - ✅ Android SDK Build-Tools 34.0.0
     - ✅ Android SDK Platform-Tools
     - ✅ Android Emulator

4. **完成安装**

---

## 步骤 3：首次启动配置

1. **启动 Android Studio**

2. **导入设置** (首次启动):
   - 选择 "Do not import settings"
   - 点击 OK

3. **安装向导**:
   - 选择 "Standard" 安装类型
   - 选择 UI 主题（推荐 Dark）
   - 点击 Finish

4. **SDK 验证**:
   - Tools → SDK Manager
   - 确认已安装：
     - Android SDK Platform 34
     - Android SDK Build-Tools 34.0.0
     - Android SDK Platform-Tools

---

## 步骤 4：打开 LispIM 项目

### 方法 A：通过欢迎界面
1. 启动 Android Studio
2. 点击 **Open** (或 File → Open)
3. 导航到：`D:\Claude\LispIM\android-app`
4. 点击 **OK**

### 方法 B：通过菜单
1. File → Open
2. 导航到：`D:\Claude\LispIM\android-app`
3. 选择文件夹
4. 点击 **OK**

---

## 步骤 5：Gradle 同步

打开项目后，Android Studio 会自动：

1. **下载 Gradle Wrapper**
   - 首次需要联网下载
   - 如果失败，见下方"Gradle 问题排查"

2. **同步项目**
   - 等待底部状态栏显示：
   ```
   Gradle sync finished
   ```

3. **下载依赖**
   - Ktor、Compose、Material 等库
   - 首次同步可能需要几分钟

---

## 步骤 6：运行应用

### 使用模拟器
1. **创建虚拟设备**:
   - Tools → Device Manager
   - Create Virtual Device
   - 选择：Pixel 8
   - 系统镜像：API 34
   - 点击 Finish

2. **运行应用**:
   - 点击工具栏绿色播放按钮
   - 选择虚拟设备
   - 等待应用启动

### 使用真机
1. **启用开发者选项**:
   - 手机设置 → 关于手机
   - 连续点击"版本号"7 次
   - 返回设置 → 开发者选项
   - 启用"USB 调试"

2. **连接手机**:
   - USB 连接电脑
   - 授权 USB 调试

3. **运行应用**:
   - 点击绿色播放按钮
   - 选择你的设备

---

## 问题排查

### Gradle 下载失败

**现象**: "Could not resolve all files"

**解决**:
1. Tools → SDK Manager
2. SDK Tools 标签
3. 勾选 Android SDK Command-line Tools
4. 点击 Apply 安装
5. 重启 Android Studio

### SDK 路径错误

**现象**: "SDK not found"

**解决**:
1. 打开 `local.properties`
2. 确认内容：
   ```
   sdk.dir=D\:\\Claude\\Android
   ```
3. 如果路径不对，修改为实际的 SDK 路径

### JDK 配置

Android Studio 自带 JDK，无需额外配置。如需手动设置：
1. File → Project Structure → SDK Location
2. JDK location: Android Studio 内置 JDK

### 依赖下载失败

**现象**: "Could not resolve dependencies"

**解决** - 修改 `app/build.gradle.kts`，添加国内镜像：

```kotlin
// 在 repositories 块添加
repositories {
    maven { url = uri("https://maven.aliyun.com/repository/google") }
    maven { url = uri("https://maven.aliyun.com/repository/public") }
    google()
    mavenCentral()
}
```

---

## 项目结构确认

打开项目后，确认以下文件存在：

```
android-app/
├── app/src/main/java/com/lispim/client/
│   ├── MainActivity.kt              ✅
│   ├── LispIMApplication.kt         ✅
│   ├── data/                        ✅
│   ├── model/                       ✅
│   ├── ui/                          ✅
│   └── service/                     ✅
├── app/build.gradle.kts             ✅
├── build.gradle.kts                 ✅
└── settings.gradle.kts              ✅
```

---

## 快速参考

### 常用操作
| 操作 | 快捷键/菜单 |
|------|-------------|
| 运行应用 | Shift + F10 |
| 调试应用 | Shift + F9 |
| 构建 APK | Build → Build Bundle(s)/APK(s) → Build APK(s) |
| 清理项目 | Build → Clean Project |
| 重新构建 | Build → Rebuild Project |
| 同步 Gradle | File → Sync Project with Gradle Files |

### APK 输出位置
```
app/build/outputs/apk/debug/app-debug.apk
```

---

## 下一步

安装并运行成功后：
1. 修改登录界面的服务器地址为实际后端地址
2. 测试登录功能
3. 测试 WebSocket 消息收发
4. 测试聊天功能

---

**项目准备状态**: ✅ 代码完成，等待 Android Studio 安装
**最后更新**: 2026-03-17
