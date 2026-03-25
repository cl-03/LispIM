# LispIM 后端 API 总结

## 新增 API 端点 (2026-03-23)

### 用户管理 API

#### GET /api/v1/users/me
获取当前登录用户信息。

**请求头:**
```
Authorization: Bearer <token>
```

**响应:**
```json
{
  "success": true,
  "data": {
    "id": "123456",
    "username": "testuser",
    "displayName": "测试用户",
    "email": "test@example.com",
    "avatar": ""
  }
}
```

#### PUT /api/v1/users/profile
更新当前用户资料。

**请求:**
```json
{
  "displayName": "新DisplayName",
  "avatar": "https://example.com/avatar.jpg"
}
```

**响应:**
```json
{
  "success": true,
  "data": {
    "id": "123456",
    "username": "testuser",
    "displayName": "新 DisplayName",
    "email": "test@example.com",
    "avatar": "https://example.com/avatar.jpg"
  }
}
```

### 好友管理 API

#### GET /api/v1/friends
获取用户好友列表。

**请求头:**
```
Authorization: Bearer <token>
```

**响应:**
```json
{
  "success": true,
  "data": [
    {
      "id": "789012",
      "username": "friend1",
      "displayName": "好友一",
      "email": "friend1@example.com",
      "phone": "13800138000",
      "avatarUrl": "https://example.com/avatar1.jpg",
      "friendStatus": "accepted",
      "friendSince": 1711123456789
    }
  ]
}
```

#### POST /api/v1/friends/add
发送好友请求。

**请求:**
```json
{
  "friendId": "789012",
  "message": "你好，想加你为好友"
}
```

**响应:**
```json
{
  "success": true,
  "message": "Friend request sent",
  "data": {
    "requestId": 12345
  }
}
```

#### GET /api/v1/friends/requests
获取好友请求列表。

**响应:**
```json
{
  "success": true,
  "data": [
    {
      "id": 12345,
      "senderId": "789012",
      "receiverId": "123456",
      "message": "你好，想加你为好友",
      "status": "pending",
      "createdAt": 1711123456789,
      "senderUsername": "friend1",
      "senderDisplayName": "好友一",
      "senderAvatar": "https://example.com/avatar1.jpg"
    }
  ]
}
```

#### POST /api/v1/friends/accept
接受好友请求。

**请求:**
```json
{
  "requestId": 12345
}
```

**响应:**
```json
{
  "success": true,
  "message": "Friend request accepted"
}
```

### 用户搜索 API

#### GET /api/v1/users/search?q=<query>&limit=<limit>
搜索用户。

**参数:**
- `q`: 搜索关键词（用户名或显示名称）
- `limit`: 返回结果数量限制（可选，默认 20）

**响应:**
```json
{
  "success": true,
  "data": [
    {
      "id": "789012",
      "username": "friend1",
      "displayName": "好友一",
      "avatarUrl": "https://example.com/avatar1.jpg"
    }
  ]
}
```

### 会话管理 API

#### POST /api/v1/chat/conversations/create
创建或获取与指定用户的直接对话。

**请求:**
```json
{
  "participantId": "789012"
}
```

**响应:**
```json
{
  "success": true,
  "data": {
    "id": "9876543210",
    "type": "direct",
    "name": null,
    "avatar": null,
    "participants": ["123456", "789012"],
    "createdAt": 1711123456789,
    "updatedAt": 1711123456789
  }
}
```

### 文件上传 API

#### POST /api/v1/upload
上传文件。

**请求类型:** `multipart/form-data`

**表单字段:**
- `file`: 文件内容
- `filename`: 文件名（可选）

**响应:**
```json
{
  "success": true,
  "data": {
    "fileId": "uuid-string",
    "filename": "original.txt",
    "url": "/api/v1/files/uuid-string",
    "size": 1024
  }
}
```

#### GET /api/v1/files/<file-id>
获取文件。

**响应:** 返回文件二进制内容

## 数据库迁移

### 新增表

#### friends
好友关系表。

```sql
CREATE TABLE friends (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(id),
    friend_id BIGINT NOT NULL REFERENCES users(id),
    status VARCHAR(50) DEFAULT 'pending',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (user_id, friend_id)
);
```

#### friend_requests
好友请求表。

```sql
CREATE TABLE friend_requests (
    id BIGSERIAL PRIMARY KEY,
    sender_id BIGINT NOT NULL REFERENCES users(id),
    receiver_id BIGINT NOT NULL REFERENCES users(id),
    message TEXT,
    status VARCHAR(50) DEFAULT 'pending',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    responded_at TIMESTAMP WITH TIME ZONE
);
```

#### file_uploads
文件上传元数据表。

```sql
CREATE TABLE file_uploads (
    id BIGSERIAL PRIMARY KEY,
    file_id UUID DEFAULT uuid_generate_v4() UNIQUE NOT NULL,
    original_filename VARCHAR(255) NOT NULL,
    stored_filename VARCHAR(255) NOT NULL,
    file_path VARCHAR(500) NOT NULL,
    file_size BIGINT NOT NULL,
    mime_type VARCHAR(100) NOT NULL,
    uploader_id BIGINT NOT NULL REFERENCES users(id),
    download_count INTEGER DEFAULT 0,
    is_public BOOLEAN DEFAULT FALSE,
    expires_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
```

## 存储层新增函数

### 好友操作
- `get-friends(user-id &optional (status "accepted"))` - 获取好友列表
- `add-friend-request(sender-id receiver-id &optional message)` - 发送好友请求
- `accept-friend-request(request-id)` - 接受好友请求
- `reject-friend-request(request-id)` - 拒绝好友请求
- `get-friend-requests(user-id &optional (status "pending"))` - 获取好友请求列表
- `search-users(query &key (limit 20))` - 搜索用户

### 文件操作
- `save-file-metadata(original-filename stored-filename file-path file-size mime-type uploader-id &optional expires-at)` - 保存文件元数据
- `get-file-metadata(file-id)` - 获取文件元数据
- `increment-file-download-count(file-id)` - 增加文件下载次数

### 会话操作
- `get-or-create-direct-conversation(user-id-1 user-id-2)` - 获取或创建两人直接对话

## 已完成的功能

- [x] 好友管理（列表、添加、请求、接受）
- [x] 用户搜索
- [x] 文件上传
- [x] 用户资料更新
- [x] 创建直接对话
- [x] 获取当前用户信息

## API 测试状态

所有新增 API 端点已注册到路由，等待完整测试验证。
