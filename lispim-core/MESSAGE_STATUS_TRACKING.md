# 消息状态追踪系统

**版本：** 0.1.0
**创建日期：** 2026-03-26
**状态：** 已完成

---

## 概述

LispIM 现在集成了完整的消息状态追踪系统，参考 WhatsApp 的设计模式，实现 5 状态消息生命周期管理：

```
PENDING → SENDING → SENT → DELIVERED → READ
                              ↓
                           FAILED (with auto-retry)
```

---

## 核心特性

### 1. 5 状态消息生命周期

| 状态 | 代码 | 描述 | 触发条件 |
|------|------|------|----------|
| `:pending` | 0 | 消息待发送 | 消息创建时 |
| `:sending` | 1 | 发送中 | 开始推送给在线用户 |
| `:sent` | 2 | 已发送 | 成功推送给至少一个在线用户 |
| `:delivered` | 3 | 已送达 | 接收方客户端返回 ACK |
| `:read` | 4 | 已读 | 接收方打开消息 |
| `:failed` | 5 | 失败 | 推送失败，等待重试 |

### 2. 自动重试机制

- **最大重试次数：** 3 次
- **重试策略：** 指数退避（5s, 15s, 45s）
- **后台工作线程：** 自动处理重试队列

### 3. ACK 确认机制

- **超时时间：** 30 秒（可配置）
- **回调支持：** 完全确认时触发回调
- **多级 ACK：** 支持 received/delivered/read 三种确认

---

## 数据库变更

### 新增列（Migration 004）

```sql
-- messages 表新增列
ALTER TABLE messages ADD COLUMN status INTEGER DEFAULT 1;     -- 消息状态
ALTER TABLE messages ADD COLUMN retry_count INTEGER DEFAULT 0; -- 重试次数
ALTER TABLE messages ADD COLUMN last_error TEXT;              -- 最后错误信息
ALTER TABLE messages ADD COLUMN delivered_to TEXT[] DEFAULT '{}'; -- 送达用户列表
```

### 索引优化

```sql
CREATE INDEX idx_messages_status ON messages(status);
CREATE INDEX idx_messages_retry_count ON messages(retry_count) WHERE status = 5;
CREATE INDEX idx_messages_delivered_to ON messages USING GIN (delivered_to);
```

### 辅助函数

```sql
-- 按状态查询消息
SELECT * FROM get_messages_by_status(conv_id, status, limit);

-- 获取失败待重试消息
SELECT * FROM get_failed_messages_for_retry(max_retries);
```

---

## API 使用

### 发送消息（自动状态追踪）

```lisp
(in-package :lispim-core)

;; 发送消息，自动设置状态为 :sending
(let ((msg (send-message conversation-id "Hello, World!" :type :text)))
  (format t "Message sent with ID: ~a~%" (message-id msg)))
```

### 查询消息状态

```lisp
;; 获取消息状态信息
(let ((status-info (get-message-status message-id)))
  (when status-info
    (format t "Status: ~a~%" (message-status-info-status status-info))
    (format t "Retry count: ~a~%" (message-status-info-retry-count status-info))
    (format t "Delivered to: ~a~%" (message-status-info-delivered-to status-info))))
```

### 更新消息状态

```lisp
;; 手动更新状态（通常由系统自动处理）
(update-message-status message-id :delivered
                       :delivered-to (vector "user1" "user2"))

(update-message-status message-id :failed
                       :error-message "Connection timeout")
```

### ACK 确认

```lisp
;; 客户端收到消息后发送 ACK
;; WebSocket 消息格式：
{
  "type": "message-received",
  "payload": {
    "message-id": "1234567890",
    "ack-type": "received"  // 或 "delivered" / "read"
  }
}

;; 服务端自动处理 ACK 并更新状态
```

---

## 后台重试工作线程

### 启动/停止

```lisp
;; 服务器启动时自动启动（在 server.lisp 中）
(start-retry-worker)

;; 服务器停止时自动停止
(stop-retry-worker)
```

### 重试队列操作

```lisp
;; 入队失败消息
(enqueue-failed-message message-id conversation-id "Message content" :type :text)

;; 出队待重试消息
(let ((messages (dequeue-failed-messages conversation-id :limit 5)))
  (dolist (msg-data messages)
    ;; 重试发送
    ))

;; 检查是否应该重试
(when (should-retry-message-p message-id)
  ;; 执行重试
  )
```

---

## WebSocket 协议扩展

### 消息格式 v1

```json
// 服务端 → 客户端（消息推送）
{
  "type": "message",
  "message-id": "ws-msg-001",
  "ack-required": true,
  "payload": {
    "id": "1234567890",
    "conversation-id": "9876543210",
    "sender-id": "1",
    "content": "Hello",
    "type": "text",
    "status": "sent"  // 新增：消息状态
  }
}

// 客户端 → 服务端（ACK 确认）
{
  "type": "message-received",
  "payload": {
    "message-id": "1234567890",
    "ack-type": "received"  // received | delivered | read
  }
}
```

---

## 测试

### 运行单元测试

```lisp
;; 加载测试系统
(asdf:load-system :lispim-core/test)

;; 运行消息状态测试
(lispim-core/test/message-status:run-message-status-tests)
```

### 测试用例覆盖

- [x] 状态代码转换（code ↔ keyword）
- [x] 消息状态信息结构
- [x] 重试延迟计算（指数退避）
- [x] 失败消息队列操作
- [x] ACK 追踪创建
- [x] ACK 确认处理
- [x] 完全确认回调

---

## 性能指标

### 目标值

| 指标 | 目标值 | 测量方式 |
|------|--------|----------|
| 状态更新延迟 | < 10ms | 数据库更新耗时 |
| ACK 响应时间 | < 50ms | 客户端确认到状态更新 |
| 重试成功率 | > 80% | 失败消息最终发送成功比例 |
| 消息投递率 | > 99% | 消息成功送达比例 |

---

## 故障排查

### 常见问题

#### 1. 消息一直处于 `:sending` 状态

**原因：** 推送成功但 ACK 超时未返回
**解决：** 检查客户端是否正确发送 ACK

#### 2. 消息频繁重试失败

**原因：** 网络连接问题或目标用户离线
**解决：** 检查日志中的 `last_error` 字段

#### 3. 重试队列堆积

**原因：** 后台工作线程未启动或处理慢
**解决：** 确认 `(start-retry-worker)` 已调用

### 日志查询

```lisp
;; 查询特定消息的状态变更日志
(log-info "Message ~a status: ~a → ~a" message-id old-status new-status)
```

---

## 文件清单

### 新增文件

- `src/message-status.lisp` - 消息状态追踪核心
- `migrations/004-message-status-tracking.up.sql` - 数据库迁移
- `migrations/004-message-status-tracking.down.sql` - 回滚脚本
- `tests/test-message-status.lisp` - 单元测试

### 修改文件

- `src/package.lisp` - 导出新函数
- `src/chat.lisp` - 集成状态追踪到 `send-message`
- `src/gateway.lisp` - ACK 处理集成
- `src/server.lisp` - 启动/停止重试工作线程
- `src/lispim-core.asd` - 添加系统依赖

---

## 下一步计划

### Phase 6.2: 消息压缩
- 实现大消息自动压缩
- 压缩率 > 60%

### Phase 6.3: WebSocket 连接池
- 支持 10,000+ 并发连接
- O(1) 时间复杂度查找

### Phase 6.4: 多实例集群
- Redis Pub/Sub 实例间通信
- 用户路由准确率 100%

---

## 参考资料

- [WhatsApp Architecture](https://www.whatsapp.com/blog/engineering/whats-app-architecture/)
- [Signal Protocol Documentation](https://signal.org/docs/)
- [PostgreSQL Array Types](https://www.postgresql.org/docs/current/arrays.html)

---

*Generated: 2026-03-26*
