# LispIM Android 客户端

LispIM Enterprise Android 客户端 - 基于 Kotlin + Jetpack Compose 的即时通讯应用

## 技术栈

- **语言**: Kotlin 1.9.20
- **UI 框架**: Jetpack Compose + Material 3
- **依赖注入**: Hilt 2.48.1
- **本地数据库**: Room 2.6.1
- **网络**: Retrofit + OkHttp
- **WebSocket**: OkHttp WebSocket
- **本地存储**: DataStore Preferences
- **推送通知**: Firebase Cloud Messaging (FCM)
- **架构模式**: MVVM + Repository

## 项目结构

```
app/src/main/java/com/lispim/app/
├── data/
│   ├── api/                    # Retrofit API 接口
│   │   ├── ApiProvider.kt
│   │   └── LispIMApiService.kt
│   ├── local/                  # Room 本地数据库
│   │   ├── dao/
│   │   │   ├── ConversationDao.kt
│   │   │   └── MessageDao.kt
│   │   ├── entity/
│   │   │   ├── ConversationEntity.kt
│   │   │   └── MessageEntity.kt
│   │   ├── LispIMDatabase.kt
│   │   └── StorageManager.kt
│   ├── model/                  # 数据模型
│   │   └── Models.kt
│   ├── repository/             # 数据仓库
│   │   ├── LispIMRepository.kt
│   │   └── ChatRepository.kt
│   └── websocket/              # WebSocket 管理
│       ├── LispIMWebSocketManager.kt
│       └── WebSocketManager.kt
├── di/                         # Hilt 依赖注入模块
│   ├── ApiModule.kt
│   ├── ChatRepositoryModule.kt
│   ├── DatabaseModule.kt
│   ├── RepositoryModule.kt
│   ├── StorageModule.kt
│   └── WebSocketModule.kt
├── service/                    # Android Services
│   └── LispIMMessagingService.kt
├── ui/
│   ├── navigation/             # 导航
│   │   ├── MainScreen.kt
│   │   └── Navigation.kt
│   ├── screens/                # 屏幕组件
│   │   ├── chat/
│   │   │   └── ChatScreen.kt
│   │   ├── contacts/
│   │   │   └── ContactsScreen.kt
│   │   ├── discover/
│   │   │   └── DiscoverScreen.kt
│   │   ├── login/
│   │   │   └── LoginScreen.kt
│   │   ├── profile/
│   │   │   └── ProfileScreen.kt
│   │   └── register/
│   │       └── RegisterScreen.kt
│   ├── theme/                  # Material 3 主题
│   │   ├── Color.kt
│   │   ├── Theme.kt
│   │   └── Type.kt
│   └── viewmodel/              # ViewModels
│       ├── ChatViewModel.kt
│       └── LoginViewModel.kt
├── LispIMApplication.kt        # Application 入口
└── MainActivity.kt             # 主 Activity
```

## 快速开始

### 1. 环境要求

- Android Studio Hedgehog (2023.1.1) 或更高版本
- JDK 17
- Android SDK 34 (API 34)
- 最低支持 Android 8.0 (API 26)

### 2. 配置 Firebase

1. 访问 [Firebase Console](https://console.firebase.google.com/)
2. 创建新项目或选择现有项目
3. 添加 Android 应用，包名：`com.lispim.app`
4. 下载 `google-services.json` 并替换 `app/google-services.json`
5. 启用 Cloud Messaging (FCM)

### 3. 配置后端服务器地址

编辑 `app/src/main/java/com/lispim/app/data/api/ApiProvider.kt`:

```kotlin
private const val BASE_URL = "http://YOUR_SERVER_IP:3000/api/v1/"
```

编辑 `app/src/main/java/com/lispim/app/data/websocket/LispIMWebSocketManager.kt`:

```kotlin
private const val WS_URL = "ws://YOUR_SERVER_IP:3000/ws"
```

### 4. 构建并运行

```bash
# 在项目根目录执行
./gradlew assembleDebug
```

或在 Android Studio 中点击 Run 按钮。

## 功能特性

### 已完成

- [x] 用户登录/注册
- [x] WebSocket 实时通信
- [x] 消息发送/接收
- [x] 本地消息缓存 (Room)
- [x] 连接状态指示
- [x] 输入状态指示
- [x] FCM 推送通知支持
- [x] 自动重连机制
- [x] Token 自动登录

### 待开发

- [ ] 联系人管理
- [ ] 文件/图片发送
- [ ] 语音/视频消息
- [ ] 消息撤回
- [ ] 群聊支持
- [ ] 深色模式切换
- [ ] 个人资料编辑
- [ ] 设置页面

## API 协议

### 认证 API

| 方法 | 端点 | 描述 |
|------|------|------|
| POST | `/api/v1/auth/login` | 用户登录 |
| POST | `/api/v1/auth/register` | 用户注册 |
| POST | `/api/v1/auth/logout` | 用户登出 |
| GET | `/api/v1/users/me` | 获取当前用户信息 |

### 聊天 API

| 方法 | 端点 | 描述 |
|------|------|------|
| GET | `/api/v1/chat/conversations` | 获取会话列表 |
| GET | `/api/v1/chat/conversations/{id}/messages` | 获取消息历史 |
| POST | `/api/v1/chat/conversations/{id}/messages` | 发送消息 |
| POST | `/api/v1/chat/conversations/{id}/read` | 标记已读 |

### WebSocket 协议

协议版本：`lispim-v1`

**消息格式**:
```json
{
  "type": "message_type",
  "data": { ... },
  "ack": "message_id"
}
```

**消息类型**:
- `auth` - 认证
- `chat` - 聊天消息
- `ack` - 消息确认
- `ping/pong` - 心跳
- `presence` - 在线状态
- `typing` - 输入状态

## 开发计划

参考主项目 [Phase 6 开发计划](../../../.claude/plans/compiled-mixing-crown.md)

## 许可证

MIT License
