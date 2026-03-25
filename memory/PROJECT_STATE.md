# LispIM Project State

**Last Updated:** 2026-03-23 15:30
**Session ID:** e764385e-0eb9-4705-9d92-324689dc92fa

## Current Status

所有好友管理 API 已完成并测试通过：
- ✅ `GET /api/v1/friends` - 获取好友列表
- ✅ `POST /api/v1/friends/add` - 发送好友请求
- ✅ `GET /api/v1/friends/requests` - 获取好友请求列表
- ✅ `POST /api/v1/friends/accept` - 接受好友请求
- ✅ `POST /api/v1/friends/reject` - 拒绝好友请求
- ✅ `GET /api/v1/users/search` - 搜索用户

## 本次会话修复的问题

### 1. `/api/v1/friends/requests` 返回错误数据
**问题:** `get-friend-requests` 函数使用 Postmodern `:alists` 模式时，键名匹配失败
**原因:** 搜索键用小写带下划线（`"sender_id"`），实际键是大写带连字符（`SENDER-ID`）
**修复:** 修改 `src/storage.lisp` 第 1025-1031 行，使用正确的键名

### 2. `/api/v1/friends/accept` 数据库错误 42601
**问题:** PostgreSQL 不支持在单个 prepared statement 中执行多个 SQL 命令
**修复:** 修改 `src/storage.lisp` `accept-friend-request` 函数，使用 `postmodern:with-transaction` 分别执行三个查询

### 3. Web Client 资源文件 404
**问题:** `index.html` 引用 `/assets/index-B9tXf7.js` 但实际文件是 `index-B9tXf7RX.js`
**修复:** 更新 `web-client/dist/index.html` 中的文件名引用

## 快速启动

### 启动后端服务器
```bash
cd D:/Claude/LispIM/lispim-core
sbcl --load start.lisp
```

### 健康检查
```bash
curl http://localhost:4321/healthz
```

### 测试账户
- Session Token: `test-token-12345`

## 待办事项

### 高优先级
- [ ] 测试完整的跨平台消息（Web ↔ Android）
- [ ] 实现文件上传功能的完整测试

### 中优先级
- [ ] 添加好友删除功能
- [ ] 实现群组聊天功能
- [ ] 完善消息类型（图片、语音、视频、文件）的 UI 展示

### 低优先级
- [ ] 添加用户头像上传功能
- [ ] 实现消息已读未读状态
- [ ] 添加在线状态显示

## 注意事项

1. **SBCL 进程管理:** 重启服务器前务必杀死所有 SBCL 进程
   ```bash
   powershell -Command "Get-Process sbcl | Stop-Process -Force"
   ```

2. **编译缓存:** 修改代码后清除 fasl 缓存
   ```bash
   rm -rf "$HOME/AppData/Local/cache/common-lisp/sbcl-2.5.8-win-x64/D/Claude/LispIM/"
   ```

3. **数据库连接:** PostgreSQL 配置
   - Host: 127.0.0.1
   - Port: 5432
   - Database: lispim
   - User: lispim
   - Password: Clsper03
