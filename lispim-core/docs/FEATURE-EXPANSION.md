# LispIM 功能扩展总结

**日期**: 2026-04-03  
**阶段**: 通知推送、消息置顶、群投票功能实现

---

## 本次新增功能

### 1. 通知推送系统 (Notification System) ✅

#### 后端实现 (`notification.lisp`)
- **桌面通知推送**
  - FCM (Firebase Cloud Messaging) 集成
  - WebSocket 实时通知
  - 通知偏好设置
  - 免打扰模式 (Quiet Mode)
  - 通知历史记录 (7 天保留)

- **通知类型**
  - 消息通知 (`:message`)
  - 通话通知 (`:call`)
  - 好友申请通知 (`:friend-request`)
  - 系统通知 (`:system`)
  - 群组通知 (`:group`)

- **免打扰模式**
  - 可配置时间段 (默认 22:00-08:00)
  - 智能检查机制
  - 偏好设置独立开关

#### 数据结构
```lisp
(defstruct user-notification
  "用户通知结构"
  (id 0 :type integer)
  (user-id "" :type string)
  (type :message :type (member :message :call :friend-request :system :group))
  (title "" :type string)
  (content "" :type string)
  (data (make-hash-table :test 'equal) :type hash-table)
  (priority :normal :type (member :low :normal :high))
  (created-at (get-universal-time) :type integer)
  (read-p nil :type boolean)
  (delivered-p nil :type boolean))

(defstruct notification-preferences
  "用户通知偏好设置"
  (user-id "" :type string)
  (enable-desktop t :type boolean)
  (enable-sound t :type boolean)
  (enable-badge t :type boolean)
  (message-notifications t :type boolean)
  (call-notifications t :type boolean)
  (friend-request-notifications t :type boolean)
  (group-notifications t :type boolean)
  (quiet-mode nil :type boolean)
  (quiet-start "22:00" :type string)
  (quiet-end "08:00" :type string))
```

#### API 接口
| 方法 | 端点 | 功能 |
|------|------|------|
| GET | `/api/v1/notifications/preferences` | 获取通知偏好 |
| PUT | `/api/v1/notifications/preferences` | 更新通知偏好 |
| GET | `/api/v1/notifications` | 获取通知列表 |
| POST | `/api/v1/notifications/:id/read` | 标记通知为已读 |
| POST | `/api/v1/notifications/read-all` | 全部标记已读 |
| POST | `/api/v1/device/fcm-token` | 注册 FCM Token |
| DELETE | `/api/v1/device/fcm-token` | 移除 FCM Token |
| GET | `/api/v1/device/fcm-token` | 获取 FCM Token 列表 |

---

### 2. 消息置顶功能 (Message Pinning) ✅

#### 后端实现 (`chat.lisp`)
- **置顶/取消置顶**
  - `pin-message`: 置顶消息
  - `unpin-message`: 取消置顶
  - `get-pinned-messages`: 获取置顶消息列表
  - `is-message-pinned`: 检查消息置顶状态

- **数据库支持**
  - `messages` 表新增字段：`is_pinned`, `pinned_at`, `pinned_by`
  - 新增 `pinned_messages` 表：记录置顶历史 and 排序

#### Migration 007
```sql
-- 新增消息置顶字段
ALTER TABLE messages ADD COLUMN is_pinned BOOLEAN DEFAULT FALSE;
ALTER TABLE messages ADD COLUMN pinned_at TIMESTAMP WITH TIME ZONE;
ALTER TABLE messages ADD COLUMN pinned_by BIGINT REFERENCES users(id);

-- 置顶记录表
CREATE TABLE pinned_messages (
    id BIGSERIAL PRIMARY KEY,
    message_id BIGINT NOT NULL REFERENCES messages(id),
    conversation_id BIGINT NOT NULL REFERENCES conversations(id),
    pinned_by BIGINT NOT NULL REFERENCES users(id),
    pinned_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    unpinned_at TIMESTAMP WITH TIME ZONE,
    unpinned_by BIGINT REFERENCES users(id),
    pin_order INTEGER DEFAULT 0
);
```

#### API 接口
| 方法 | 端点 | 功能 |
|------|------|------|
| GET | `/api/v1/conversations/:id/pinned-messages` | 获取置顶消息 |
| POST | `/api/v1/messages/:id/pin` | 置顶消息 |
| POST | `/api/v1/messages/:id/unpin` | 取消置顶 |

---

### 3. 群投票功能 (Group Polls) ✅

#### 后端实现 (`poll.lisp` - 新增文件)
- **投票管理**
  - `create-poll`: 创建投票
  - `get-poll`: 获取投票详情
  - `cast-vote`: 投票
  - `end-poll`: 结束投票
  - `get-poll-results`: 获取投票结果
  - `get-group-polls`: 获取群投票列表

- **投票特性**
  - 多选投票 (`multiple_choice`)
  - 允许建议新选项 (`allow_suggestions`)
  - 匿名投票 (`anonymous_voting`)
  - 可设置截止时间 (`end_at`)
  - 自动统计百分比

#### Migration 008
```sql
-- 投票表
CREATE TABLE group_polls (
    id BIGSERIAL PRIMARY KEY,
    group_id BIGINT NOT NULL REFERENCES conversations(id),
    created_by BIGINT NOT NULL REFERENCES users(id),
    title VARCHAR(255) NOT NULL,
    description TEXT,
    multiple_choice BOOLEAN DEFAULT FALSE,
    allow_suggestions BOOLEAN DEFAULT FALSE,
    anonymous_voting BOOLEAN DEFAULT FALSE,
    end_at TIMESTAMP WITH TIME ZONE,
    status VARCHAR(20) DEFAULT 'active'
);

-- 选项表
CREATE TABLE poll_options (
    id BIGSERIAL PRIMARY KEY,
    poll_id BIGINT NOT NULL REFERENCES group_polls(id),
    text VARCHAR(255) NOT NULL,
    vote_count INTEGER DEFAULT 0
);

-- 投票记录表
CREATE TABLE poll_votes (
    id BIGSERIAL PRIMARY KEY,
    poll_id BIGINT NOT NULL REFERENCES group_polls(id),
    option_id BIGINT NOT NULL REFERENCES poll_options(id),
    voter_id BIGINT NOT NULL REFERENCES users(id),
    UNIQUE (poll_id, voter_id, option_id)
);
```

#### API 接口
| 方法 | 端点 | 功能 |
|------|------|------|
| GET | `/api/v1/groups/:id/polls` | 获取群投票列表 |
| POST | `/api/v1/groups/:id/polls` | 创建投票 |
| GET | `/api/v1/polls/:id` | 获取投票详情 |
| POST | `/api/v1/polls/:id/vote` | 投票 |
| POST | `/api/v1/polls/:id/end` | 结束投票 |

---

## 文件清单

### 新建文件 (Backend)
| 文件 | 行数 | 功能 |
|------|------|------|
| `lispim-core/src/notification.lisp` | ~500 | 通知推送模块 |
| `lispim-core/src/poll.lisp` | ~300 | 群投票模块 |
| `lispim-core/migrations/007-message-pinning.up.sql` | ~50 | 消息置顶迁移 |
| `lispim-core/migrations/007-message-pinning.down.sql` | ~10 | 消息置顶回滚 |
| `lispim-core/migrations/008-group-polls.up.sql` | ~80 | 群投票迁移 |
| `lispim-core/migrations/008-group-polls.down.sql` | ~10 | 群投票回滚 |

### 修改文件 (Backend)
| 文件 | 修改内容 |
|------|----------|
| `lispim-core/src/server.lisp` | 添加 notification 和 poll 初始化 |
| `lispim-core/src/gateway.lisp` | 添加 20+ 新 API 端点 |
| `lispim-core/src/chat.lisp` | 添加消息置顶函数 |
| `lispim-core/lispim-core.asd` | 添加 poll 和 notification 模块 |
| `lispim-core/src/package.lisp` | 导出新增函数 |

### 新建文件 (Frontend)
| 文件 | 行数 | 功能 |
|------|------|------|
| `web-client/src/types/index.ts` | +50 | 新增 TypeScript 类型定义 |

### 修改文件 (Frontend)
| 文件 | 修改内容 |
|------|----------|
| `web-client/src/utils/api-client.ts` | 添加 15+ API 方法 |
| `web-client/src/types/index.ts` | 添加类型定义 |

---

## API 端点统计

### 通知系统 (8 个)
- `/api/v1/notifications/preferences` (GET/PUT)
- `/api/v1/notifications` (GET)
- `/api/v1/notifications/:id/read` (POST)
- `/api/v1/notifications/read-all` (POST)
- `/api/v1/device/fcm-token` (POST/DELETE/GET)

### 消息置顶 (3 个)
- `/api/v1/conversations/:id/pinned-messages` (GET)
- `/api/v1/messages/:id/pin` (POST)
- `/api/v1/messages/:id/unpin` (POST)

### 群投票 (5 个)
- `/api/v1/groups/:id/polls` (GET/POST)
- `/api/v1/polls/:id` (GET)
- `/api/v1/polls/:id/vote` (POST)
- `/api/v1/polls/:id/end` (POST)

**总计**: 16 个新 API 端点

---

## TypeScript 类型定义

```typescript
// 通知偏好设置
interface NotificationPreferences {
  enableDesktop: boolean
  enableSound: boolean
  enableBadge: boolean
  messageNotifications: boolean
  callNotifications: boolean
  friendRequestNotifications: boolean
  groupNotifications: boolean
  quietMode: boolean
  quietStart: string
  quietEnd: string
}

// 用户通知
interface UserNotification {
  id: number
  type: 'message' | 'call' | 'friend-request' | 'system' | 'group'
  title: string
  content: string
  data: Record<string, unknown>
  priority: 'low' | 'normal' | 'high'
  createdAt: number
  read: boolean
  delivered: boolean
}

// 置顶消息
interface PinnedMessage {
  messageId: number
  content: string
  senderId: string
  type: string
  pinnedAt: number
  pinnedBy: string
  pinnedByUsername: string
}

// 群投票
interface GroupPoll {
  id: number
  groupId: number
  createdBy: string
  title: string
  description?: string
  multipleChoice: boolean
  allowSuggestions: boolean
  anonymousVoting: boolean
  endAt?: number
  status: 'active' | 'ended' | 'archived'
  createdAt: number
  endedAt?: number
  options: PollOption[]
  results: PollResult[]
}

interface PollOption {
  id: number
  text: string
  voteCount: number
}

interface PollResult {
  optionId: number
  text: string
  voteCount: number
  percentage: number
  voters: Array<{ userId: string; username: string }>
}
```

---

## 技术亮点

### 1. 通知推送系统
- **FCM 集成**: 支持跨平台推送 (Android/iOS)
- **WebSocket 实时通知**: 在线用户即时收到通知
- **智能免打扰**: 根据用户配置的时间段自动过滤通知
- **偏好设置**: 细粒度的通知类型控制

### 2. 消息置顶
- **历史追踪**: `pinned_messages` 表记录完整的置顶/取消历史
- **排序支持**: `pin_order` 字段支持自定义置顶顺序
- **性能优化**: 部分索引 (`WHERE is_pinned = TRUE`) 提升查询效率

### 3. 群投票
- **实时统计**: 自动计算百分比和票数
- **灵活配置**: 支持多选、匿名、建议等特性
- **防刷票**: 数据库唯一约束保证一人一票 (或多选)
- **PL/pgSQL 函数**: `get_poll_results` 和 `end_poll` 封装复杂逻辑

---

## 数据库变更

### 新增表
- `pinned_messages`: 消息置顶记录
- `group_polls`: 群投票
- `poll_options`: 投票选项
- `poll_votes`: 投票记录

### 新增字段
- `messages.is_pinned`: 是否置顶
- `messages.pinned_at`: 置顶时间
- `messages.pinned_by`: 置顶操作人

### 新增索引
- `idx_messages_pinned`: 置顶消息查询优化
- `idx_pinned_messages_conversation`: 会话置顶消息索引
- `idx_group_polls_group_id`: 群投票查询索引
- `idx_poll_votes_poll_id`: 投票结果统计索引

---

## 下一步计划

### P1 - 体验优化
- [ ] 通知声音自定义
- [ ] 置顶消息拖拽排序
- [ ] 投票截止自动提醒
- [ ] 通知批量操作

### P2 - 功能扩展
- [ ] 投票图表可视化
- [ ] 通知分类过滤
- [ ] 置顶消息快捷导航
- [ ] 投票结果导出

---

## 测试建议

### 通知系统
1. FCM Token 注册/移除
2. 免打扰模式时间验证
3. 通知偏好设置实时更新
4. WebSocket 推送成功率

### 消息置顶
1. 置顶/取消置顶权限验证
2. 置顶消息顺序验证
3. 并发置顶操作测试
4. 历史记录的准确性

### 群投票
1. 多选投票验证
2. 匿名投票隐私保护
3. 投票统计准确性
4. 截止时间自动结束

---

*功能扩展总结结束*
