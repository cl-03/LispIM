# LispIM Phase 7 浏览器测试指南

## 当前状态

### ✅ 已完成
1. **后端代码编译成功** - 所有 Phase 7 API handler 已正确定义和编译
2. **前端开发服务器运行中** - http://localhost:3001
3. **测试页面已创建** - http://localhost:3001/test-phase7.html

### ❌ 后端服务器未运行
后端需要以下依赖才能启动：
- PostgreSQL 数据库 (端口 5432)
- Redis 服务器 (端口 6379)

---

## 测试方法

### 方法 1：使用测试页面（推荐）

1. **打开测试页面**
   ```
   http://localhost:3001/test-phase7.html
   ```

2. **配置 API 地址**
   - API 服务器地址：`http://localhost:3000`
   - Token: （登录后自动填充）

3. **测试步骤**
   - 先测试登录获取 Token
   - 然后测试各个 API 端点

---

### 方法 2：使用浏览器控制台直接测试

打开浏览器访问 http://localhost:3001，然后在控制台执行：

```javascript
// 配置
const API_URL = 'http://localhost:3000';
let TOKEN = '';

// 1. 登录
async function login() {
  const resp = await fetch(`${API_URL}/api/v1/auth/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ username: 'testuser', password: 'password123' })
  });
  const result = await resp.json();
  if (result.success) {
    TOKEN = result.data.token;
    console.log('✅ 登录成功，Token:', TOKEN);
  } else {
    console.log('❌ 登录失败:', result);
  }
}

// 2. 测试全文搜索
async function testSearch() {
  const resp = await fetch(`${API_URL}/api/v1/search?q=测试&type=all`, {
    headers: { 'Authorization': `Bearer ${TOKEN}` }
  });
  const result = await resp.json();
  console.log('🔍 搜索结果:', result);
}

// 3. 测试获取回复列表
async function testGetReplies(messageId) {
  const resp = await fetch(`${API_URL}/api/v1/messages/${messageId}/replies`, {
    headers: { 'Authorization': `Bearer ${TOKEN}` }
  });
  const result = await resp.json();
  console.log('💬 回复列表:', result);
}

// 4. 测试获取回复链
async function testGetReplyChain(messageId) {
  const resp = await fetch(`${API_URL}/api/v1/messages/${messageId}/reply-chain`, {
    headers: { 'Authorization': `Bearer ${TOKEN}` }
  });
  const result = await resp.json();
  console.log('🔗 回复链:', result);
}

// 5. 测试获取线程
async function testGetThread(rootId) {
  const resp = await fetch(`${API_URL}/api/v1/threads/${rootId}`, {
    headers: { 'Authorization': `Bearer ${TOKEN}` }
  });
  const result = await resp.json();
  console.log('🧵 线程信息:', result);
}

// 运行测试
await login();
```

---

### 方法 3：使用 curl 命令测试

```bash
# 1. 登录
curl -X POST http://localhost:3000/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"testuser","password":"password123"}'

# 保存返回的 token

# 2. 全文搜索
curl "http://localhost:3000/api/v1/search?q=hello&type=messages" \
  -H "Authorization: Bearer <your-token>"

# 3. 获取消息回复
curl http://localhost:3000/api/v1/messages/<msg-id>/replies \
  -H "Authorization: Bearer <your-token>"

# 4. 获取回复链
curl http://localhost:3000/api/v1/messages/<msg-id>/reply-chain \
  -H "Authorization: Bearer <your-token>"

# 5. 获取线程信息
curl http://localhost:3000/api/v1/threads/<root-id> \
  -H "Authorization: Bearer <your-token>"

# 6. 发送回复消息
curl -X POST http://localhost:3000/api/v1/messages/<msg-id>/reply \
  -H "Authorization: Bearer <your-token>" \
  -H "Content-Type: application/json" \
  -d '{"content":"这是回复","conversationId":"1"}'
```

---

## Phase 7 API 端点列表

### 全文搜索 API
| 方法 | 端点 | 说明 |
|------|------|------|
| GET | `/api/v1/search?q={query}&type={type}` | 搜索消息/联系人/会话 |

**参数说明：**
- `q`: 搜索关键词（必填）
- `type`: 搜索类型 `all` | `messages` | `contacts` | `conversations`
- `limit`: 结果数量限制（可选，默认 20）
- `conversationId`: 限定在特定会话中搜索（可选）

---

### 消息回复 API
| 方法 | 端点 | 说明 |
|------|------|------|
| POST | `/api/v1/messages/:id/reply` | 发送回复消息 |
| GET | `/api/v1/messages/:id/replies` | 获取消息的所有回复 |
| GET | `/api/v1/messages/:id/reply-chain` | 获取回复链（从根到当前） |
| GET | `/api/v1/threads/:root-id` | 获取完整线程信息 |

**POST /api/v1/messages/:id/reply 请求体：**
```json
{
  "content": "回复内容",
  "conversationId": "1",
  "quoteContent": "引用的原文",
  "quoteType": "text"
}
```

---

## 测试结果验证

### 编译测试（已通过）
```
========================================
  Phase 7 API Handler 测试
========================================
测试 api-search-handler...
  [PASS] api-search-handler 已定义
测试 api-reply-message-handler...
  [PASS] api-reply-message-handler 已定义
测试 api-get-replies-handler...
  [PASS] api-get-replies-handler 已定义
测试 api-get-reply-chain-handler...
  [PASS] api-get-reply-chain-handler 已定义
测试 api-get-thread-handler...
  [PASS] api-get-thread-handler 已定义
测试 fulltext-search 函数...
  [PASS] fulltext-search 已定义
测试 create-message-reply 函数...
  [PASS] create-message-reply 已定义
测试 get-reply-chain 函数...
  [PASS] get-reply-chain 已定义
测试 get-message-replies 函数...
  [PASS] get-message-replies 已定义
测试 get-reply-thread 函数...
  [PASS] get-reply-thread 已定义

========================================
  结果：10 通过，0 失败
========================================
```

---

## 启动后端服务器（可选）

如需完整测试，需要启动后端服务器：

```bash
# 1. 确保 PostgreSQL 运行
# 连接字符串：postgresql://lispim:Clsper03@127.0.0.1:5432/lispim

# 2. 确保 Redis 运行
# 连接字符串：redis://127.0.0.1:6379/0

# 3. 启动 LispIM 后端
cd D:\Claude\LispIM\lispim-core
sbcl --load run-server.lisp

# 服务器将监听 http://localhost:3000
```

---

## 常见问题

### Q: CORS 错误
A: 后端已配置 `Access-Control-Allow-Origin: *`，如仍有问题检查浏览器扩展

### Q: 401 Unauthorized
A: 检查 Token 是否有效，确保登录成功

### Q: 404 Not Found
A: 确认后端路由已注册，检查 URL 拼写

### Q: 后端无法启动
A: 检查 PostgreSQL 和 Redis 是否正常运行
