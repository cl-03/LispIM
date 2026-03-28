# LispIM Phase 7 集成文档

**更新日期：** 2026-03-26
**版本：** v0.1.0

---

## 概述

Phase 7 实现了两个新功能模块，并已集成到 LispIM 核心系统中：

1. **全文搜索模块** (`fulltext-search.lisp`)
2. **消息回复/引用模块** (`message-reply.lisp`)

本文档说明如何在服务器、客户端和 API 层面使用这些新功能。

---

## 服务器集成

### 1. 模块初始化

在 `server.lisp` 的 `init-server` 函数中，已添加以下初始化代码：

```lisp
;; 初始化全文搜索
(init-search "localhost" 6379)

;; 初始化消息去重
(init-message-dedup :window-size 10000 :window-ttl 3600 :bloom-size 1000000)

;; 启动去重清理工作线程
(start-dedup-cleanup-worker)

;; 初始化速率限制
(init-rate-limiting :default-rate 100 :default-burst 200)
```

### 2. 模块清理

在 `stop-server` 函数中，已添加以下清理代码：

```lisp
;; 停止全文搜索
(shutdown-fulltext-search)

;; 停止消息去重清理工作线程
(stop-dedup-cleanup-worker)
```

### 3. 数据库迁移

运行数据库迁移以创建必要的表：

```bash
# 执行迁移
psql -U lispim -d lispim -f migrations/006-message-reply.up.sql

# 或者使用迁移工具
./run-migrations.sh
```

**迁移内容：**
- `message_replies` 表 - 存储回复关系
- `notifications` 表 - 支持回复通知
- `messages.reply_count` 列 - 缓存回复数量

**回滚：**
```bash
psql -U lispim -d lispim -f migrations/006-message-reply.down.sql
```

---

## API 集成

### 全文搜索 API

#### GET /api/v1/search

搜索消息、联系人或会话。

**请求参数：**
| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| q | string | 是 | 搜索关键词 |
| type | string | 否 | 搜索类型：`all` / `messages` / `contacts` / `conversations`，默认 `all` |
| limit | integer | 否 | 结果数量限制，默认 20 |
| conversationId | string | 否 | 限定在特定会话中搜索 |

**请求示例：**
```http
GET /api/v1/search?q=项目讨论&type=messages&limit=20 HTTP/1.1
Authorization: Bearer {token}
```

**响应示例：**
```json
{
  "success": true,
  "message": "Search completed",
  "data": {
    "messages": [
      {
        "id": "msg-123",
        "conversation_id": "conv-456",
        "sender_id": "user-789",
        "content": "关于项目的讨论",
        "created_at": 1711425600
      }
    ],
    "contacts": [...],
    "conversations": [...]
  }
}
```

**客户端集成示例（TypeScript）：**
```typescript
interface SearchRequest {
  q: string;
  type?: 'all' | 'messages' | 'contacts' | 'conversations';
  limit?: number;
  conversationId?: string;
}

interface SearchResponse {
  success: boolean;
  data: {
    messages?: Message[];
    contacts?: Contact[];
    conversations?: Conversation[];
  };
}

async function search(query: SearchRequest): Promise<SearchResponse> {
  const params = new URLSearchParams({
    q: query.q,
    type: query.type || 'all',
    limit: (query.limit || 20).toString(),
  });
  if (query.conversationId) {
    params.append('conversationId', query.conversationId);
  }

  const response = await fetch(`/api/v1/search?${params}`, {
    headers: { 'Authorization': `Bearer ${token}` }
  });
  return response.json();
}
```

---

### 消息回复 API

#### POST /api/v1/messages/:id/reply

发送回复消息。

**路径参数：**
| 参数 | 类型 | 说明 |
|------|------|------|
| id | string | 被回复的消息 ID |

**请求体：**
```json
{
  "content": "这是回复内容",
  "conversationId": "conv-123",
  "quoteContent": "引用的原文",
  "quoteType": "text"
}
```

**请求示例：**
```http
POST /api/v1/messages/msg-456/reply HTTP/1.1
Authorization: Bearer {token}
Content-Type: application/json

{
  "content": "我同意你的看法",
  "conversationId": "conv-123",
  "quoteContent": "原文内容...",
  "quoteType": "text"
}
```

**响应示例：**
```json
{
  "success": true,
  "message": "Reply sent successfully",
  "data": {
    "messageId": "msg-789"
  }
}
```

---

#### GET /api/v1/messages/:id/replies

获取消息的所有回复。

**路径参数：**
| 参数 | 类型 | 说明 |
|------|------|------|
| id | string | 消息 ID |

**查询参数：**
| 参数 | 类型 | 说明 |
|------|------|------|
| limit | integer | 回复数量限制，默认 100 |

**请求示例：**
```http
GET /api/v1/messages/msg-456/replies?limit=50 HTTP/1.1
Authorization: Bearer {token}
```

**响应示例：**
```json
{
  "success": true,
  "data": {
    "replies": [
      {
        "id": "msg-789",
        "content": "回复内容",
        "sender_id": "user-123",
        "sender_username": "张三",
        "created_at": 1711425700,
        "depth": 1
      }
    ],
    "count": 2
  }
}
```

---

#### GET /api/v1/messages/:id/reply-chain

获取从根消息到指定消息的回复链。

**路径参数：**
| 参数 | 类型 | 说明 |
|------|------|------|
| id | string | 消息 ID |

**请求示例：**
```http
GET /api/v1/messages/msg-789/reply-chain HTTP/1.1
Authorization: Bearer {token}
```

**响应示例：**
```json
{
  "success": true,
  "data": {
    "chain": ["msg-123", "msg-456", "msg-789"],
    "length": 3
  }
}
```

---

#### GET /api/v1/threads/:root-id

获取完整线程信息。

**路径参数：**
| 参数 | 类型 | 说明 |
|------|------|------|
| root-id | string | 根消息 ID |

**请求示例：**
```http
GET /api/v1/threads/msg-123 HTTP/1.1
Authorization: Bearer {token}
```

**响应示例：**
```json
{
  "success": true,
  "data": {
    "thread": {
      "rootMessageId": "msg-123",
      "replyCount": 5,
      "latestReplyId": "msg-789",
      "latestReplyAt": 1711426000,
      "participants": ["user-1", "user-2", "user-3"]
    }
  }
}
```

---

## 客户端集成

### Web 客户端（React/TypeScript）

#### 搜索功能组件

```typescript
// components/SearchPanel.tsx
import React, { useState, useEffect } from 'react';

interface SearchResult {
  messages?: Message[];
  contacts?: Contact[];
  conversations?: Conversation[];
}

export function SearchPanel() {
  const [query, setQuery] = useState('');
  const [results, setResults] = useState<SearchResult | null>(null);
  const [loading, setLoading] = useState(false);

  const handleSearch = async (searchQuery: string) => {
    setLoading(true);
    try {
      const response = await fetch(`/api/v1/search?q=${encodeURIComponent(searchQuery)}`);
      const data = await response.json();
      setResults(data.data);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="search-panel">
      <input
        type="text"
        value={query}
        onChange={(e) => setQuery(e.target.value)}
        onKeyDown={(e) => e.key === 'Enter' && handleSearch(query)}
        placeholder="搜索消息、联系人、会话..."
      />
      {loading && <div>搜索中...</div>}
      {results && (
        <div className="search-results">
          {results.messages?.map(msg => (
            <div key={msg.id} className="message-result">
              <Highlight text={msg.content} query={query} />
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
```

#### 消息回复组件

```typescript
// components/MessageReply.tsx
import React, { useState } from 'react';

interface ReplyProps {
  messageId: string;
  conversationId: string;
  onReplySuccess: (messageId: string) => void;
}

export function MessageReply({ messageId, conversationId, onReplySuccess }: ReplyProps) {
  const [content, setContent] = useState('');
  const [showQuote, setShowQuote] = useState(true);

  const handleReply = async () => {
    try {
      const response = await fetch(`/api/v1/messages/${messageId}/reply`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${token}`,
        },
        body: JSON.stringify({
          content,
          conversationId,
          quoteContent: showQuote ? originalMessage.content : undefined,
          quoteType: 'text',
        }),
      });
      const data = await response.json();
      if (data.success) {
        onReplySuccess(data.data.messageId);
        setContent('');
      }
    } catch (error) {
      console.error('Reply failed:', error);
    }
  };

  return (
    <div className="message-reply">
      {showQuote && (
        <div className="quote-preview">
          <div className="quote-header">回复：{originalMessage.senderName}</div>
          <div className="quote-content">{originalMessage.content}</div>
        </div>
      )}
      <textarea
        value={content}
        onChange={(e) => setContent(e.target.value)}
        placeholder="回复消息..."
      />
      <button onClick={handleReply}>发送</button>
    </div>
  );
}
```

#### 回复链显示组件

```typescript
// components/ReplyChain.tsx
import React, { useEffect, useState } from 'react';

interface ReplyChainProps {
  messageId: string;
}

export function ReplyChain({ messageId }: ReplyChainProps) {
  const [chain, setChain] = useState<string[]>([]);

  useEffect(() => {
    fetch(`/api/v1/messages/${messageId}/reply-chain`)
      .then(res => res.json())
      .then(data => setChain(data.data.chain));
  }, [messageId]);

  return (
    <div className="reply-chain">
      {chain.map((id, index) => (
        <div key={id} className={`chain-item depth-${index}`}>
          → 消息 {id}
        </div>
      ))}
    </div>
  );
}
```

---

### Android 客户端（Kotlin）

#### 搜索 API 集成

```kotlin
// data/api/SearchApi.kt
data class SearchRequest(
    val q: String,
    val type: String = "all",
    val limit: Int = 20,
    val conversationId: String? = null
)

data class SearchResponse(
    val success: Boolean,
    val data: SearchResult
)

data class SearchResult(
    val messages: List<Message>?,
    val contacts: List<Contact>?,
    val conversations: List<Conversation>?
)

interface SearchApi {
    @GET("api/v1/search")
    suspend fun search(
        @Query("q") query: String,
        @Query("type") type: String = "all",
        @Query("limit") limit: Int = 20,
        @Query("conversationId") conversationId: String? = null
    ): SearchResponse
}
```

#### 回复 API 集成

```kotlin
// data/api/ReplyApi.kt
data class ReplyRequest(
    val content: String,
    val conversationId: String,
    val quoteContent: String? = null,
    val quoteType: String = "text"
)

data class ReplyResponse(
    val success: Boolean,
    val data: ReplyData
)

data class ReplyData(
    val messageId: String
)

interface ReplyApi {
    @POST("api/v1/messages/{messageId}/reply")
    suspend fun reply(
        @Path("messageId") messageId: String,
        @Body request: ReplyRequest
    ): ReplyResponse

    @GET("api/v1/messages/{messageId}/replies")
    suspend fun getReplies(
        @Path("messageId") messageId: String,
        @Query("limit") limit: Int = 100
    ): GetRepliesResponse

    @GET("api/v1/messages/{messageId}/reply-chain")
    suspend fun getReplyChain(
        @Path("messageId") messageId: String
    ): ReplyChainResponse

    @GET("api/v1/threads/{rootId}")
    suspend fun getThread(
        @Path("rootId") rootId: String
    ): ThreadResponse
}
```

#### ViewModel 集成

```kotlin
// viewmodel/ChatViewModel.kt
class ChatViewModel @Inject constructor(
    private val replyApi: ReplyApi,
    private val searchApi: SearchApi
) : ViewModel() {

    private val _searchResults = MutableLiveData<SearchResult>()
    val searchResults: LiveData<SearchResult> = _searchResults

    private val _replies = MutableLiveData<List<Message>>()
    val replies: LiveData<List<Message>> = _replies

    fun search(query: String, type: String = "all") {
        viewModelScope.launch {
            try {
                val response = searchApi.search(query, type)
                _searchResults.value = response.data
            } catch (e: Exception) {
                // Handle error
            }
        }
    }

    fun sendReply(messageId: String, conversationId: String, content: String) {
        viewModelScope.launch {
            try {
                val response = replyApi.reply(
                    messageId,
                    ReplyRequest(content, conversationId)
                )
                // Handle success
            } catch (e: Exception) {
                // Handle error
            }
        }
    }

    fun loadReplies(messageId: String) {
        viewModelScope.launch {
            try {
                val response = replyApi.getReplies(messageId)
                _replies.value = response.data.replies
            } catch (e: Exception) {
                // Handle error
            }
        }
    }
}
```

---

## 数据库结构

### message_replies 表

```sql
CREATE TABLE message_replies (
    id BIGSERIAL PRIMARY KEY,
    message_id VARCHAR(64) NOT NULL UNIQUE,       -- 回复消息 ID
    reply_to_id VARCHAR(64) NOT NULL,             -- 被回复的消息 ID
    conversation_id VARCHAR(64) NOT NULL,         -- 会话 ID
    sender_id VARCHAR(64) NOT NULL,               -- 回复者用户 ID
    quote_content TEXT,                           -- 引用内容预览
    quote_type VARCHAR(32) DEFAULT 'text',        -- 引用内容类型
    depth INTEGER NOT NULL DEFAULT 0,             -- 回复深度
    created_at INTEGER NOT NULL                   -- 创建时间戳
);

-- 索引
CREATE INDEX idx_message_replies_reply_to ON message_replies(reply_to_id);
CREATE INDEX idx_message_replies_conversation ON message_replies(conversation_id);
CREATE INDEX idx_message_replies_sender ON message_replies(sender_id);
CREATE INDEX idx_message_replies_depth ON message_replies(depth);
CREATE INDEX idx_message_replies_created ON message_replies(created_at);
```

### notifications 表（扩展）

```sql
CREATE TABLE notifications (
    id VARCHAR(64) PRIMARY KEY,
    user_id VARCHAR(64) NOT NULL,                 -- 接收通知的用户 ID
    type VARCHAR(32) NOT NULL,                    -- 通知类型（'reply' 等）
    related_user_id VARCHAR(64),                  -- 相关用户 ID
    message_id VARCHAR(64),                       -- 相关消息 ID
    conversation_id VARCHAR(64),                  -- 相关会话 ID
    created_at INTEGER NOT NULL,
    is_read BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE INDEX idx_notifications_user ON notifications(user_id);
CREATE INDEX idx_notifications_type ON notifications(type);
```

---

## 配置参数

### fulltext-search.lisp

```lisp
(defparameter *fulltext-search-config*
  '((:index-prefix . "lispim:search:")    ; Redis 索引前缀
    (:min-word-length . 2)                ; 最小词长度
    (:max-results . 100)                  ; 最大结果数
    (:batch-size . 1000)                  ; 索引构建批次大小
    (:sync-interval . 60)))               ; 索引同步间隔（秒）
```

### message-reply.lisp

```lisp
(defparameter *message-reply-config*
  '((:max-reply-depth . 10)               ; 最大回复深度
    (:max-quote-length . 500)             ; 引用最大长度
    (:thread-cache-ttl . 3600)))          ; 线程缓存 TTL
```

---

## 测试

### 单元测试

运行测试：

```bash
sbcl --load tests/test-fulltext-search.lisp
sbcl --load tests/test-message-reply.lisp
```

### API 测试

```bash
# 搜索测试
curl -X GET "http://localhost:3000/api/v1/search?q=测试" \
  -H "Authorization: Bearer $TOKEN"

# 发送回复
curl -X POST "http://localhost:3000/api/v1/messages/$MSG_ID/reply" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"content":"回复内容","conversationId":"conv-123"}'

# 获取回复列表
curl -X GET "http://localhost:3000/api/v1/messages/$MSG_ID/replies" \
  -H "Authorization: Bearer $TOKEN"
```

---

## 性能优化建议

1. **搜索索引预热**
   - 启动时构建完整索引
   - 定期后台同步增量索引

2. **回复线程缓存**
   - 热点线程缓存到 Redis
   - TTL 设置为 3600 秒

3. **数据库查询优化**
   - 使用覆盖索引
   - 分页查询限制结果数量

4. **限流保护**
   - 搜索 API 限流：100 次/分钟
   - 回复 API 限流：60 次/分钟

---

## 故障排除

### 常见问题

1. **搜索无结果**
   - 检查中文分词是否正确
   - 确认索引已构建

2. **回复深度超限**
   - 检查 `:max-reply-depth` 配置
   - 客户端应禁用超过深度的回复按钮

3. **通知不推送**
   - 检查 `notifications` 表是否存在
   - 确认推送服务配置正确

---

*Generated: 2026-03-26*
*Phase 7 Integration Guide*
