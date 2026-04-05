# LispIM 全平台评估与优化报告

## 概述

本报告对 LispIM 项目的 Web 应用、Android 移动端和桌面应用进行了全面评估，基于"纯 Common Lisp 开发"原则提出优化建议。

---

## 第一部分：Web 应用评估与优化

### 1.1 当前架构分析

#### 前端技术栈
- **框架**: React 18 + TypeScript + Vite
- **状态管理**: Zustand (appStore.ts)
- **样式**: TailwindCSS
- **WebSocket**: 原生 WebSocket API
- **HTTP 客户端**: Fetch API

#### 后端技术栈
- **框架**: Hunchentoot (Common Lisp)
- **协议**: WebSocket + HTTP/REST API v1
- **数据库**: PostgreSQL + Redis

### 1.2 发现的问题

#### ❌ 问题 1: WebSocket 认证流程不统一
**文件**: `web-client/src/utils/websocket.ts`
```typescript
// 当前实现 - Token 在连接后发送
private sendAuth(): void {
    const authMessage: WSMessage<AuthPayload> = {
        type: WS_MSG_TYPE.AUTH,
        payload: { token: this.config.token, userId: this.config.userId }
    }
    this.socket?.send(JSON.stringify(authMessage))
}
```

**问题**: 认证在连接建立后发送，存在短暂未认证窗口期。

**建议**: 使用 WebSocket 子协议在握手时认证：
```typescript
// 优化方案 - 握手时认证
const ws = new WebSocket(
    wsUrl,
    ['lispim-v1', `Bearer:${token}`]  // 子协议携带 token
);
```

---

#### ❌ 问题 2: 消息序列号未使用
**文件**: `web-client/src/utils/websocket.ts`
```typescript
export interface WSMessage {
    type: string
    payload: T
    version: string
    timestamp: number
    messageId?: string  // 有 messageId 但没有 sequence
}
```

**问题**: 后端使用 Snowflake ID + 序列号，但前端未实现序列号验证。

**建议**: 增加序列号验证：
```typescript
export interface WSMessage {
    type: string;
    payload: T;
    sequence: number;  // 新增序列号
    timestamp: number;
}

// 验证序列号连续性
private lastSequence: number = 0;
private verifySequence(sequence: number): boolean {
    if (sequence <= this.lastSequence) {
        console.warn('Out of order message:', sequence);
        return false;
    }
    this.lastSequence = sequence;
    return true;
}
```

---

#### ❌ 问题 3: 缺少离线消息同步机制
**文件**: `web-client/src/utils/api-client.ts`

**问题**: 未实现增量同步 API 调用，用户刷新后可能丢失消息。

**建议**: 添加同步方法：
```typescript
// 新增同步 API
async getIncrementalMessages(
    anchorSeq: number,
    batchSize: number = 50
): Promise<ApiResponse<SyncMessagesResponse>> {
    return this.get(`/api/v1/sync/messages?anchor_seq=${anchorSeq}&batch_size=${batchSize}`);
}

async getIncrementalConversations(
    anchorSeq: number
): Promise<ApiResponse<SyncConversationsResponse>> {
    return this.get(`/api/v1/sync/conversations?anchor_seq=${anchorSeq}`);
}
```

---

#### ❌ 问题 4: Store 结构简单，缺少持久化
**文件**: `web-client/src/store/appStore.ts`

```typescript
// 当前实现 - 内存存储
export const useAppStore = create<AppState & AppActions>()(
    (set) => ({
        ws: null,  // 刷新后丢失
        token: localStorage.getItem('token') ?? '',  // 部分持久化
        // ...
    })
);
```

**建议**: 完整持久化：
```typescript
// 优化方案 - 使用 Zustand persist 中间件
import { create } from 'zustand'
import { persist, createJSONStorage } from 'zustand/middleware'

export const useAppStore = create<AppState & AppActions>()(
    persist(
        (set, get) => ({
            // ... 状态
        }),
        {
            name: 'lispim-storage',
            storage: createJSONStorage(() => localStorage),
            partialize: (state) => ({
                token: state.token,
                userId: state.userId,
                lastSyncAnchor: state.lastSyncAnchor
            })
        }
    )
);
```

---

### 1.3 纯 Common Lisp 优化建议

#### ✅ 建议 1: 使用 CLSS (Common Lisp Style Sheets)

替代 TailwindCSS，实现纯 Lisp 样式：

```lisp
;; 在 server.lisp 中提供 CSS 生成
(define-css-route ("/styles/main.css")
  (generate-stylesheet
   (css-rule ".message-bubble"
     :background-color "#e3f2fd"
     :border-radius "16px"
     :padding "8px 12px")
   (css-rule ".message-bubble.me"
     :background-color "#1976d2"
     :color "white")))
```

---

#### ✅ 建议 2: 使用 Parenscript 生成 JavaScript

用 Common Lisp 编写前端逻辑：

```lisp
;; websocket.lisp
(defun generate-websocket-client ()
  "生成 WebSocket 客户端 JS"
  (ps:ps
   (defclass LispIMWebSocket (nil)
     ((socket nil)
      (config nil)
      (handlers (ps:new))))
   
   (defun connect (url token)
     (setf this.socket (ps:new WebSocket url))
     (setf (.-onopen this.socket) 
           (lambda () (send-auth token))))))
```

---

#### ✅ 建议 3: 使用 Whopp 构建系统

纯 Lisp 构建工具：
```lisp
;; 在 lispim-web.asd 中
(defsystem :lispim-web
  :depends-on (:parenscript :clss :cl-who)
  :build-operation "whopp-build"
  :entry-point "lispim-web:build")
```

---

## 第二部分：Android 移动端评估与优化

### 2.1 当前架构分析

#### 技术栈
- **语言**: Kotlin
- **架构**: MVVM + Repository + Hilt DI
- **UI**: Jetpack Compose + Material 3
- **网络**: Retrofit + OkHttp WebSocket
- **本地存储**: Room Database

### 2.2 发现的问题

#### ❌ 问题 1: WebSocket 重连机制简单
**文件**: `LispIMWebSocketManager.kt`
```kotlin
private fun scheduleReconnect() {
    if (reconnectAttempts >= MAX_RECONNECT_ATTEMPTS) {
        // 超过 5 次直接失败
        _connectionState.value = ConnectionState.Error(...)
        return
    }
    reconnectJob?.cancel()
    reconnectJob = messageScope.launch {
        delay(RECONNECT_DELAY)  // 固定 5 秒
        reconnectAttempts++
        authToken?.let { connect(it) }
    }
}
```

**问题**: 
- 固定延迟不合理
- 没有指数退避
- 网络状态未检测

**建议**: 指数退避 + 网络检测：
```kotlin
private fun scheduleReconnect() {
    reconnectJob?.cancel()
    reconnectJob = messageScope.launch {
        // 指数退避：1s, 2s, 4s, 8s, 16s, max 30s
        val delay = min(
            RECONNECT_DELAY * (1L shl reconnectAttempts),
            MAX_RECONNECT_DELAY
        )
        delay(delay)
        
        // 检查网络
        if (!isNetworkAvailable()) {
            Log.w(TAG, "No network, waiting...")
            return@launch
        }
        
        reconnectAttempts++
        authToken?.let { connect(it) }
    }
}
```

---

#### ❌ 问题 2: 消息去重未实现
**文件**: `handleIncomingMessage`
```kotlin
private fun handleIncomingMessage(text: String) {
    val json = gson.fromJson(text, Map::class.java)
    val type = json["type"] as? String ?: return
    // 直接处理，未检查是否重复
}
```

**问题**: 网络重传会导致重复消息。

**建议**: 使用消息 ID 去重：
```kotlin
private val seenMessageIds = LruCache<String, Long>(1000)
private val MESSAGE_TTL = 5 * 60 * 1000L // 5 分钟

private fun handleIncomingMessage(text: String) {
    val json = gson.fromJson(text, Map::class.java)
    val messageId = json["data"]?.get("id") as? String ?: return
    
    // 检查是否重复
    if (seenMessageIds.get(messageId) != null) {
        Log.d(TAG, "Duplicate message: $messageId")
        return
    }
    
    seenMessageIds.put(messageId, System.currentTimeMillis())
    // 处理消息...
}
```

---

#### ❌ 问题 3: Room 实体缺少索引
**文件**: `MessageDao.kt`
```kotlin
@Entity(tableName = "messages")
data class MessageEntity(
    @PrimaryKey val id: String,
    val conversationId: String,  // 无索引
    val senderId: String,
    val createdAt: Long,  // 无索引
    // ...
)
```

**建议**: 添加索引：
```kotlin
@Entity(
    tableName = "messages",
    indices = [
        Index("conversationId"),  // 会话查询
        Index("createdAt"),        // 时间排序
        Index("conversationId", "createdAt")  // 复合索引
    ]
)
data class MessageEntity(...)
```

---

### 2.3 纯 Common Lisp 优化建议

#### ⚠️ 注意：Android 原生开发必须使用 Kotlin/Java

对于 Android 移动端，"纯 Common Lisp"原则应理解为：
1. **后端 API 保持纯 Common Lisp**
2. **协议设计遵循 Lisp 风格**
3. **可考虑使用 CL 嵌入方案**（如 ABCL）

---

#### ✅ 建议 1: 使用 ABCL (Armed Bear Common Lisp)

在 Android 中嵌入 Common Lisp：

```kotlin
// LispIMWebSocketManager.kt 中调用 Lisp
import org.armedbear.lisp.{Interpreter, Lisp}

class LispIMWebSocketManager {
    private val lisp: Interpreter = Interpreter.createInstance()
    
    init {
        // 加载 Lisp 代码
        lisp.eval("(load \"websocket-handler.lisp\")")
    }
    
    fun handleIncomingMessage(text: String) {
        lisp.eval("(handle-incoming-message \"$text\")")
    }
}
```

---

#### ✅ 建议 2: 协议使用 S-表达式

使用 S-表达式替代 JSON：
```lisp
;; Lisp 风格协议 (suggested)
(message :type chat
         :conversation-id "123"
         :content "Hello"
         :sequence 456
         :timestamp 1712044800)

;; 而非 JSON
{"type":"chat","conversationId":"123","content":"Hello"}
```

---

## 第三部分：桌面应用评估与优化

### 3.1 当前架构分析

#### Tauri 技术栈
- **前端**: React + TypeScript
- **后端 (Rust)**: Tauri + tokio-tungstenite
- **通信**: WebSocket + Tauri Commands

### 3.2 发现的问题

#### ❌ 问题 1: Rust 后端重复实现业务逻辑
**文件**: `tauri-client/src-tauri/src/websocket.rs`
```rust
// Rust 代码中硬编码业务逻辑
pub async fn send_message(&self, conversation_id: i64, content: String) {
    let message = WSMessage {
        r#type: "message:send".to_string(),  // 硬编码
        payload: serde_json::json!({
            "conversation_id": conversation_id,
            "content": content,
            "message_type": "text"
        }),
        // ...
    };
}
```

**问题**: 
- 业务逻辑分散在 Rust 和前端
- 与 Web/移动端不一致

**建议**: Rust 只作为桥接层：
```rust
// 简化：Rust 只负责转发
#[tauri::command]
pub async fn ws_send(
    message_type: String,
    payload: serde_json::Value,
    window: tauri::Window,
) -> Result<(), String> {
    if let Some(client) = window.try_state::<Arc<WSClient>>() {
        let message = WSMessage {
            r#type: message_type,
            payload,
            timestamp: chrono::Utc::now().timestamp_millis(),
        };
        client.send(message).await
    } else {
        Err("WebSocket client not found".to_string())
    }
}
```

---

#### ❌ 问题 2: 缺少自动更新机制
**文件**: `tauri.conf.json`

```json
{
  "tauri": {
    "updater": {
      "active": false  // 未启用
    }
  }
}
```

**建议**: 启用自动更新：
```json
{
  "tauri": {
    "updater": {
      "active": true,
      "dialog": true,
      "endpoints": ["https://api.lispim.org/updates/{target}/{current_version}"],
      "pubkey": "YOUR_PUBKEY"
    }
  }
}
```

---

### 3.3 纯 Common Lisp 优化建议

#### ✅ 建议 1: 使用 Tauri + ABCL 混合架构

```rust
// src-tauri/src/main.rs
use abcl::{Interpreter, Lisp};

struct LispRuntime {
    interp: Interpreter,
}

impl LispRuntime {
    fn new() -> Self {
        let interp = Interpreter::new();
        interp.eval("(load \"core.lisp\")");
        Self { interp }
    }
    
    fn handle_message(&mut self, msg: &str) -> String {
        self.interp.eval(&format!("(handle-message \"{}\")", msg))
            .to_string()
    }
}

// Tauri command
#[tauri::command]
fn lisp_eval(state: State<LispRuntime>, code: String) -> String {
    state.interp.eval(&code)
}
```

---

#### ✅ 建议 2: 使用 ECL (Embeddable CL)

纯 C 接口，更适合 FFI：

```rust
// Cargo.toml
[dependencies]
ecl-sys = "0.1"

// main.rs
use ecl_sys::*;

unsafe {
    cl_boot(0, std::ptr::null());
    cl_eval(c_str_to_string("(format t \"Hello from ECL!~%\")"));
}
```

---

## 第四部分：优先级与建议

### P0（立即实施）

| 问题 | 影响 | 工作量 |
|------|------|--------|
| WebSocket 认证时序 | 安全性 | 低 |
| 消息去重 | 数据一致性 | 低 |
| 离线同步 API | 用户体验 | 中 |

### P1（优先实施）

| 问题 | 影响 | 工作量 |
|------|------|--------|
| Store 持久化 | 用户体验 | 低 |
| Android 重连优化 | 连接稳定性 | 中 |
| Room 索引优化 | 性能 | 低 |

### P2（考虑实施）

| 问题 | 影响 | 工作量 |
|------|------|--------|
| Parenscript 前端 | 纯 Lisp | 高 |
| Tauri + ABCL | 架构统一 | 高 |
| S-表达式协议 | 一致性 | 中 |

---

## 第五部分：总结

### 架构评估总结

| 平台 | 架构健康度 | 纯 Lisp 符合度 | 建议 |
|------|-----------|--------------|------|
| Web | 良好 | 中 | 增强同步、持久化 |
| Android | 良好 | 低 (必须) | 优化重连、去重 |
| Desktop | 中 | 中 | 简化 Rust 层 |

### 核心原则

**"纯 Common Lisp 开发"应理解为**:
1. 后端核心 100% Common Lisp
2. 前端可以使用现代框架，但业务逻辑尽量由后端驱动
3. 协议设计遵循 Lisp 哲学（简单、可扩展）
4. 可选：探索 ABCL/ECL 嵌入方案

---

*评估日期：2026-04-02*
*LispIM Version: 0.1.0*
