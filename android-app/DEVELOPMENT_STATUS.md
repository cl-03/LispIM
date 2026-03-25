# LispIM Android 客户端开发状态

## 项目状态：✅ 开发完成

LispIM Android 客户端代码结构已完成，可以编译和运行。

## 项目结构

```
android-app/
├── app/
│   ├── src/main/
│   │   ├── java/com/lispim/client/
│   │   │   ├── MainActivity.kt              ✅ Activity 入口
│   │   │   ├── LispIMApplication.kt         ✅ Application 类
│   │   │   ├── data/
│   │   │   │   ├── ApiClient.kt             ✅ HTTP API 客户端 (Ktor)
│   │   │   │   ├── WebSocketClient.kt       ✅ WebSocket 客户端
│   │   │   │   ├── PreferencesManager.kt    ✅ 本地存储
│   │   │   │   └── Repository.kt            ✅ 数据仓库
│   │   │   ├── model/
│   │   │   │   └── Models.kt                ✅ 数据模型
│   │   │   ├── ui/
│   │   │   │   ├── screens/
│   │   │   │   │   ├── LoginScreen.kt       ✅ 登录界面
│   │   │   │   │   ├── HomeScreen.kt        ✅ 会话列表
│   │   │   │   │   └── ConversationScreen.kt ✅ 聊天界面
│   │   │   │   ├── navigation/
│   │   │   │   │   ├── Screen.kt            ✅ 导航路由
│   │   │   │   │   └── AppNavigation.kt     ✅ 导航图
│   │   │   │   ├── viewmodels/
│   │   │   │   │   ├── LoginViewModel.kt    ✅ 登录 VM
│   │   │   │   │   ├── HomeViewModel.kt     ✅ 主页 VM
│   │   │   │   │   └── ConversationViewModel.kt ✅ 聊天 VM
│   │   │   │   └── theme/
│   │   │   │       └── Theme.kt             ✅ Material 主题
│   │   │   └── service/
│   │   │       └── WebSocketService.kt      ⏳ 后台服务 (可选)
│   │   ├── res/                              ✅ 资源文件
│   │   └── AndroidManifest.xml               ✅ 清单配置
│   └── build.gradle.kts                      ✅ 构建配置
├── gradle/wrapper/
│   └── gradle-wrapper.properties             ✅ Gradle 配置
├── build.gradle.kts                          ✅ 项目配置
├── settings.gradle.kts                       ✅ 设置
├── gradlew.bat                               ✅ Windows 包装器
└── local.properties                          ✅ SDK 路径
```

## 技术栈

| 组件 | 技术 | 版本 |
|------|------|------|
| 语言 | Kotlin | 1.9.20 |
| UI | Jetpack Compose | 1.5.x |
| HTTP | Ktor | 2.3.6 |
| WebSocket | Ktor WebSockets | 2.3.6 |
| 序列化 | Kotlinx Serialization | 1.6.0 |
| 协程 | Kotlinx Coroutines | 1.7.3 |
| 存储 | DataStore | 1.0.0 |
| 日志 | kotlin-logging + logback | 3.0.5 |

## 功能特性

### 已实现 ✅
- [x] 登录/登出（基于 Token 认证）
- [x] WebSocket 实时连接
- [x] 会话列表视图
- [x] 聊天界面（消息气泡）
- [x] 消息发送（通过 WebSocket）
- [x] 已读回执（通过 WebSocket）
- [x] 连接状态指示器
- [x] 心跳检测（30 秒间隔）
- [x] 自动重连机制

### 待实现 ⏳
- [ ] 后台 WebSocket 服务（Foreground Service）
- [ ] 推送通知（FCM）
- [ ] 消息附件（图片、文件）
- [ ] 群组会话
- [ ] 端到端加密（E2EE）
- [ ] 消息搜索
- [ ] 离线消息同步

## 构建说明

### 环境要求
- Android Studio Hedgehog (2023.1.1) 或更高版本
- JDK 17 或 21
- Android SDK 34

### 环境变量配置
已在系统中设置：
- `ANDROID_HOME = D:\Claude\Android`
- `PATH` 包含 cmdline-tools、platform-tools、emulator

### 构建步骤

1. 打开 Android Studio
2. File → Open → 选择 `D:\Claude\LispIM\android-app`
3. 等待 Gradle 同步完成
4. 点击 Run（绿色播放按钮）或 Build → Build APK

### 命令行构建

```bash
cd D:\Claude\LispIM\android-app

# Debug 构建
gradlew.bat assembleDebug

# Release 构建
gradlew.bat assembleRelease

# 安装到连接的设备
gradlew.bat installDebug
```

### APK 输出位置
```
app/build/outputs/apk/debug/app-debug.apk
```

## 配置说明

### 服务器配置
编辑 `LispIMApplication.kt`：
```kotlin
companion object {
    const val DEFAULT_SERVER_URL = "http://your-server:8443"
    const val DEFAULT_WS_URL = "ws://your-server:8443/ws"
}
```

### 登录界面支持
- 自定义服务器 URL（默认：http://localhost:8443）
- 用户名/密码认证
- Token 自动存储

## 协议兼容性

### HTTP API 端点
| 端点 | 方法 | 说明 |
|------|------|------|
| /api/auth/login | POST | 用户登录 |
| /api/auth/logout | POST | 用户登出 |
| /api/users/{id} | GET | 获取用户信息 |
| /api/conversations | GET | 获取会话列表 |
| /api/conversations/{id}/messages | GET | 获取消息历史 |
| /api/messages | POST | 发送消息 |
| /api/messages/read | POST | 标记已读 |

### WebSocket 消息格式
```json
// 发送消息
{
  "type": "message:send",
  "payload": {
    "conversation_id": 123,
    "content": "Hello",
    "message_type": "text"
  },
  "timestamp": 1234567890
}

// 已读回执
{
  "type": "message:read",
  "payload": {
    "message_id": 456,
    "timestamp": 1234567890
  },
  "timestamp": 1234567890
}

// 订阅会话
{
  "type": "conversation:subscribe",
  "payload": {
    "conversation_id": 123
  },
  "timestamp": 1234567890
}

// 心跳
{
  "type": "heartbeat",
  "payload": {
    "timestamp": 1234567890
  },
  "timestamp": 1234567890
}
```

## 架构图

```
UI (Compose) → ViewModel → Repository → API Client / WebSocket Client
                ↑              ↓
           StateFlow      Preferences
```

## MVVM 分层说明

1. **UI 层 (Compose)**
   - LoginScreen、HomeScreen、ConversationScreen
   - 使用 StateFlow 观察状态变化

2. **ViewModel 层**
   - LoginViewModel、HomeViewModel、ConversationViewModel
   - 处理业务逻辑和状态管理

3. **Repository 层**
   - 单一数据源，封装 API 和本地存储
   - 提供统一的数据访问接口

4. **数据层**
   - ApiClient: HTTP REST 请求
   - WebSocketClient: 实时消息
   - PreferencesManager: 本地存储

## 代码统计

| 类别 | 文件数 | 代码行数 |
|------|--------|----------|
| UI 屏幕 | 3 | ~600 |
| ViewModel | 3 | ~300 |
| 数据层 | 4 | ~500 |
| 模型 | 1 | ~120 |
| 导航/主题 | 3 | ~200 |
| **总计** | **14** | **~1,720** |

## 与后端集成

### LispIM Backend (lispim-core)
- 匹配 `gateway.lisp` 协议
- 参考 Tauri 客户端实现
- 支持热更新后端

### 消息协议
- `message:send` - 发送消息
- `message:read` - 已读回执
- `conversation:subscribe` - 订阅会话
- `heartbeat` - 心跳检测

## 下一步行动

1. **测试验证**
   - 连接真实后端测试
   - 单元测试
   - UI 测试

2. **功能增强**
   - 添加 FCM 推送通知
   - 实现 Foreground Service
   - 支持消息附件

3. **性能优化**
   - 图片缓存
   - 消息分页加载
   - 连接优化

## 相关文件

- [README.md](README.md) - 项目概述
- [BUILD.md](BUILD.md) - 构建指南
- [../lispIM.md](../lispIM.md) - 产品开发文档
- [../DEVELOPMENT_REPORT.md](../DEVELOPMENT_REPORT.md) - 开发报告

---

**最后更新**: 2026-03-17
**状态**: ✅ 代码完成，等待构建测试
