# 扫一扫添加好友功能说明

## 功能概述

用户可以通过扫描 QR 码添加好友，支持以下三种方式：
1. **摄像头实时扫描** - 使用设备摄像头扫描二维码
2. **相册图片上传** - 从相册选择包含二维码的图片
3. **手动输入** - 手动输入二维码内容

## 前端实现

### 组件位置
`web-client/src/components/ScanModal.tsx`

### 主要功能

#### 1. 摄像头扫描
- 自动启动后置摄像头
- 显示扫描框和扫描线动画
- 支持手动输入二维码内容

#### 2. 图片上传扫描
- 点击"相册"按钮选择图片
- 上传图片到服务器
- 调用后端 API 识别二维码
- 显示识别结果

#### 3. 添加好友
- 扫描成功后显示用户信息
- 点击"添加为好友"发送好友请求
- 显示精美的 Toast 通知
- 自动关闭弹窗

### API 调用流程

```typescript
// 1. 上传图片
const uploadResponse = await api.uploadFile(file, file.name)
const imageUrl = uploadResponse.data.url

// 2. 扫描二维码
const scanResponse = await api.post('/api/v1/qr/scan-image', { imageUrl })

// 3. 发送好友请求
const friendRequestResponse = await api.sendFriendRequest(userId, '您好，我扫了您的二维码')
```

## 后端实现

### API 端点

#### 1. 扫描二维码 (`/api/v1/qr/scan`)
```lisp
POST /api/v1/qr/scan
Content-Type: application/json

{
  "qrJson": "{...}"  // QR 码 JSON 内容
}

Response:
{
  "success": true,
  "user": {
    "id": "123",
    "username": "testuser",
    "displayName": "测试用户",
    "avatar": ""
  }
}
```

#### 2. 扫描图片二维码 (`/api/v1/qr/scan-image`)
```lisp
POST /api/v1/qr/scan-image
Content-Type: application/json

{
  "imageUrl": "/api/v1/files/xxx"  // 上传后的图片 URL
}

Response:
{
  "success": true,
  "user": {
    "id": "123",
    "username": "testuser",
    "displayName": "测试用户",
    "avatar": ""
  }
}
```

#### 3. 发送好友申请 (`/api/v1/contacts/friend-request/send`)
```lisp
POST /api/v1/contacts/friend-request/send
Content-Type: application/json

{
  "receiverId": "123",
  "message": "您好，我扫了您的二维码"
}

Response:
{
  "success": true,
  "data": {
    "requestId": 456
  }
}
```

### 处理流程

1. **图片上传** → `/api/v1/upload`
2. **下载图片** → 从上传 URL 下载到临时文件
3. **QR 识别** → 调用 Python 脚本 `decode_qr.py`
4. **验证 QR** → 验证签名和时间戳
5. **返回用户信息** → 扫描成功返回用户资料
6. **发送请求** → 创建好友申请记录

## Python QR 解码脚本

### 位置
`lispim-core/scripts/decode_qr.py`

### 依赖
```bash
pip install pyzbar Pillow
```

### 使用方法
```bash
python decode_qr.py image.png
```

### 输出
- 成功：输出 QR 码 JSON 内容到 stdout
- 失败：输出空字符串或错误信息到 stderr

## QR 码格式

```json
{
  "type": "user_profile",
  "userId": "用户 ID",
  "username": "用户名",
  "timestamp": 1234567890,
  "signature": "HMAC-SHA256 签名"
}
```

### 验证规则
1. **类型验证** - 必须是 `user_profile`
2. **签名验证** - 使用 HMAC-SHA256 验证
3. **时间戳验证** - 24 小时内有效

## 用户体验优化

### Toast 通知
- **成功**：绿色渐变背景，带勾选图标，2 秒后自动消失
- **失败**：红色渐变背景，带错误图标，3 秒后自动消失

### 动画效果
- `animate-scale-up` - 弹窗弹出动画
- 渐变背景 - `from-green-500 to-emerald-600`
- 阴影效果 - `shadow-[0_10px_40px_rgba(...)]`
- 边框发光 - `border border-green-400/30`

### 状态反馈
1. **扫描中** - 显示"正在识别二维码..."加载提示
2. **扫描成功** - 显示用户信息卡片
3. **扫描失败** - 显示"无效的二维码或已过期"
4. **发送成功** - 显示"好友请求已发送"Toast
5. **发送失败** - 显示具体错误原因

## 测试场景

### 测试步骤

1. **准备测试 QR 码**
```python
import qrcode
qr_data = '{"type":"user_profile","userId":"166266346143744000","username":"testuser","timestamp":1234567890,"signature":"abc123"}'
qr = qrcode.make(qr_data)
qr.save('test_qr.png')
```

2. **测试摄像头扫描**
- 打开扫一扫弹窗
- 将 QR 码对准扫描框
- 验证是否显示用户信息

3. **测试图片上传**
- 点击"相册"按钮
- 选择 QR 码图片
- 验证识别结果

4. **测试好友请求**
- 扫描成功后点击"添加为好友"
- 验证 Toast 提示
- 检查好友申请列表

### 错误处理
- [ ] 图片不是 QR 码 → 显示"无法识别二维码"
- [ ] QR 码过期 → 显示"二维码已过期"
- [ ] 用户不存在 → 显示"用户不存在"
- [ ] 网络错误 → 显示"发送失败，请重试"
- [ ] 已是好友 → 显示"已是好友，无需添加"

## 数据库操作

### 好友申请表
```sql
INSERT INTO friend_requests (sender_id, receiver_id, message, status, created_at)
VALUES ('user1', 'user2', '您好，我扫了您的二维码', 'pending', NOW());
```

### 好友关系表
```sql
INSERT INTO friends (user_id, friend_id, status, created_at)
VALUES ('user1', 'user2', 'pending', NOW());
```

## 注意事项

1. **权限要求** - 需要用户登录后才能使用
2. **摄像头权限** - 首次使用需要授权摄像头
3. **图片大小** - 建议上传图片不超过 5MB
4. **QR 码有效期** - 24 小时
5. **好友申请限制** - 同一用户每天最多发送 10 次申请

## 相关文件

- 前端组件：`web-client/src/components/ScanModal.tsx`
- 后端处理：`lispim-core/src/gateway.lisp` (QR 处理和好友申请)
- QR 服务：`lispim-core/src/qr.lisp` (QR 生成和验证)
- Python 脚本：`lispim-core/scripts/decode_qr.py`
- API 客户端：`web-client/src/utils/api-client.ts`
