# LispIM Web Client

Web PWA 客户端 for LispIM Enterprise - 安全的企业即时通讯系统

## 技术栈

- **React 18** - UI 框架
- **TypeScript** - 类型安全
- **Vite** - 构建工具
- **TailwindCSS** - 样式
- **Zustand** - 状态管理
- **React Router** - 路由
- **Socket.IO** - WebSocket 通信
- **Crypto-JS** - 加密
- **Workbox** - PWA 支持

## 功能特性

### 核心功能
- ✅ 实时消息收发
- ✅ 端到端加密 (E2EE)
- ✅ 多会话管理
- ✅ 消息已读回执
- ✅ 用户在线状态
- ✅ 离线消息同步

### PWA 特性
- ✅ 离线访问
- ✅ 推送通知
- ✅ 添加到主屏幕
- ✅ 响应式设计

### 安全特性
- ✅ AES-256-GCM 加密
- ✅ 密钥轮换
- ✅ 安全存储
- ✅ 内存清理

## 快速开始

### 安装依赖

```bash
npm install
```

### 开发模式

```bash
npm run dev
```

访问 http://localhost:3000

### 构建生产版本

```bash
npm run build
```

### 预览生产构建

```bash
npm run preview
```

### 运行测试

```bash
npm run test
```

## 项目结构

```
web-client/
├── src/
│   ├── components/          # React 组件
│   │   ├── App.tsx
│   │   ├── Chat.tsx
│   │   ├── Login.tsx
│   │   ├── ConversationList.tsx
│   │   ├── MessageList.tsx
│   │   ├── MessageInput.tsx
│   │   └── UserPanel.tsx
│   ├── store/               # 状态管理
│   │   └── appStore.ts
│   ├── hooks/               # 自定义 Hooks
│   ├── utils/               # 工具函数
│   │   ├── websocket.ts
│   │   ├── crypto.ts
│   │   └── message.ts
│   ├── types/               # TypeScript 类型
│   │   └── index.ts
│   ├── main.tsx
│   ├── App.tsx
│   ├── App.css
│   └── index.css
├── public/
│   └── manifest.webmanifest
├── index.html
├── package.json
├── tsconfig.json
├── tailwind.config.js
├── postcss.config.js
└── vite.config.ts
```

## 环境变量

| 变量 | 说明 | 默认值 |
|------|------|--------|
| `VITE_WS_URL` | WebSocket 服务器地址 | `ws://localhost:3000` |
| `VITE_API_URL` | API 服务器地址 | `http://localhost:3000/api` |

## 与后端集成

### WebSocket 协议

```typescript
// 连接
const ws = new LispIMWebSocket({
  url: 'ws://localhost:3000',
  token: 'jwt-token'
})
await ws.connect()

// 发送消息
ws.sendMessage(conversationId, 'Hello, World!')

// 接收消息
ws.on('message', (data) => {
  console.log('收到消息:', data)
})

// 已读回执
ws.readMessage(messageId)

// 订阅会话
ws.subscribe(conversationId)
```

## 加密说明

本客户端实现端到端加密：

1. **密钥生成**: 使用 Crypto-JS 生成随机密钥对
2. **密钥交换**: 使用简化的 Diffie-Hellman 协议
3. **消息加密**: AES-256-GCM
4. **密钥轮换**: 每 7 天自动轮换
5. **安全存储**: IndexedDB 加密存储

## 浏览器支持

- Chrome (推荐)
- Firefox
- Safari
- Edge

## 注意事项

1. 开发环境需要后端服务器运行
2. PWA 功能需要 HTTPS (生产环境)
3. 某些加密功能需要现代浏览器支持

## License

MIT
