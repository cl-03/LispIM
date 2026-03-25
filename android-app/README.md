# LispIM Android Client

LispIM Enterprise Android mobile client - a real-time messaging application.

## Project Structure

```
android-app/
├── app/
│   ├── src/
│   │   └── main/
│   │       ├── java/com/lispim/client/
│   │       │   ├── MainActivity.kt          # Main entry point
│   │       │   ├── LispIMApplication.kt     # Application class
│   │       │   ├── data/
│   │       │   │   ├── ApiClient.kt         # HTTP API client (Ktor)
│   │       │   │   ├── WebSocketClient.kt   # WebSocket client (Ktor)
│   │       │   │   ├── PreferencesManager.kt # DataStore preferences
│   │       │   │   └── Repository.kt         # Data repository
│   │       │   ├── model/
│   │       │   │   └── Models.kt             # Data models
│   │       │   ├── ui/
│   │       │   │   ├── screens/
│   │       │  
 │   │   ├── LoginScreen.kt
│   │       │   │   │   ├── HomeScreen.kt
│   │       │   │   │   └── ConversationScreen.kt
│   │       │   │   ├── navigation/
│   │       │   │   │   ├── Screen.kt
│   │       │   │   │   └── AppNavigation.kt
│   │       │   │   ├── viewmodels/
│   │       │   │   │   ├── LoginViewModel.kt
│   │       │   │   │   ├── HomeViewModel.kt
│   │       │   │   │   └── ConversationViewModel.kt
│   │       │   │   └── theme/
│   │       │   │       └── Theme.kt
│   │       │   └── service/
│   │       │       └── WebSocketService.kt   # Foreground service (TODO)
│   │       ├── res/
│   │       │   ├── values/
│   │       │   │   ├── strings.xml
│   │       │   │   ├── colors.xml
│   │       │   │   └── themes.xml
│   │       │   ├── xml/
│   │       │   │   ├── backup_rules.xml
│   │       │   │   └── data_extraction_rules.xml
│   │       │   ├── drawable/
│   │       │   │   └── ic_launcher_foreground.xml
│   │       │   └── mipmap-*/
│   │       │       └── ic_launcher.xml
│   │       └── AndroidManifest.xml
│   └── build.gradle.kts
├── gradle/
│   └── wrapper/
│       └── gradle-wrapper.properties
├── build.gradle.kts
├── settings.gradle.kts
├── gradlew
└── gradlew.bat
```

## Technology Stack

- **Language**: Kotlin 1.9.20
- **UI Framework**: Jetpack Compose with Material 3
- **HTTP Client**: Ktor 2.3.6
- **WebSocket**: Ktor WebSockets
- **Serialization**: Kotlinx Serialization
- **Coroutines**: Kotlinx Coroutines
- **Dependency Injection**: Manual (Hilt can be added later)
- **Local Storage**: Jetpack DataStore
- **Logging**: kotlin-logging + logback-android

## Features

### Implemented
- Login/Logout with token-based authentication
- WebSocket connection for real-time messaging
- Conversation list view
- Chat screen with message bubbles
- Message sending via WebSocket
- Read receipts via WebSocket
- Connection status indicator

### Backend API Compatibility

This client is designed to work with the LispIM backend (lispim-core):

- **Authentication**: `/api/auth/login` - POST with username/password
- **WebSocket**: `ws://host:8443/ws?token=xxx`
- **Messages**: Matches gateway.lisp protocol (message:send, message:read, conversation:subscribe)

## Building

### Prerequisites

1. Android Studio Hedgehog (2023.1.1) or later
2. JDK 17
3. Android SDK 34

### Steps

1. Open the `android-app` folder in Android Studio
2. Sync Gradle files
3. Run on emulator or device

```bash
# Using command line
./gradlew assembleDebug
# APK will be in app/build/outputs/apk/debug/
```

## Configuration

Edit `LispIMApplication.kt` to change default server:

```kotlin
companion object {
    const val DEFAULT_SERVER_URL = "http://your-server:8443"
    const val DEFAULT_WS_URL = "ws://your-server:8443/ws"
}
```

## Architecture

The app follows MVVM architecture with Repository pattern:

```
UI (Compose) → ViewModel → Repository → API Client / WebSocket Client
                ↑              ↓
           StateFlow      Preferences
```

## Protocol Reference

### WebSocket Messages

```json
// Send message
{
  "type": "message:send",
  "payload": {
    "conversation_id": 123,
    "content": "Hello",
    "message_type": "text"
  },
  "timestamp": 1234567890
}

// Read receipt
{
  "type": "message:read",
  "payload": {
    "message_id": 456,
    "timestamp": 1234567890
  },
  "timestamp": 1234567890
}

// Subscribe to conversation
{
  "type": "conversation:subscribe",
  "payload": {
    "conversation_id": 123
  },
  "timestamp": 1234567890
}

// Heartbeat
{
  "type": "heartbeat",
  "payload": {
    "timestamp": 1234567890
  },
  "timestamp": 1234567890
}
```

## Status

- [x] Project structure
- [x] Authentication flow
- [x] WebSocket client
- [x] Basic UI (Login, Home, Conversation)
- [ ] Foreground service for background connection
- [ ] Push notifications (FCM)
- [ ] Message attachments
- [ ] Group conversations
- [ ] E2EE support
