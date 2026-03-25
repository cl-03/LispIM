# LispIM Desktop Client

Tauri 桌面客户端 for LispIM Enterprise - 基于 Common Lisp 后端的企业级即时通讯系统

## 技术栈

- **Tauri 1.6** - 桌面应用框架
- **React 18** - UI 框架
- **TypeScript** - 类型安全
- **Rust** - 系统层 (Tauri backend)
- **TailwindCSS** - 样式

## 功能特性

### 桌面特性
- ✅ 系统托盘集成
- ✅ 原生通知
- ✅ 全局快捷键 (Ctrl+Shift+L)
- ✅ 自动更新
- ✅ 原生菜单栏
- ✅ 文件拖放支持

### 跨平台支持
- ✅ Windows 10/11
- ✅ macOS 10.15+
- ✅ Linux (Ubuntu, Debian, Fedora)

## 系统要求

### 开发环境
- Node.js 18+
- Rust 1.70+
- Cargo

### 运行时
- Windows 10+
- macOS 10.15+
- Ubuntu 20.04+

## 安装依赖

```bash
# 安装 Rust (如果未安装)
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

# 安装 Node.js 依赖
npm install

# 安装 Tauri CLI (可选)
npm install -g @tauri-apps/cli
```

## 开发

```bash
# 开发模式 (热重载)
npm run tauri:dev

# 或者仅运行前端
npm run dev
```

## 构建

```bash
# 构建生产版本
npm run tauri:build

# 构建产物位置:
# - src-tauri/target/release/bundle/
#   - .msi (Windows)
#   - .app (macOS)
#   - .deb / .rpm (Linux)
```

## 项目结构

```
tauri-client/
├── src/                      # React 前端 (与 Web 客户端共享)
│   ├── components/
│   ├── store/
│   ├── utils/
│   ├── types/
│   ├── App.tsx
│   └── main.tsx
├── src-tauri/
│   ├── src/
│   │   └── main.rs          # Rust 后端入口
│   ├── icons/               # 应用图标
│   ├── Cargo.toml           # Rust 依赖
│   ├── tauri.conf.json      # Tauri 配置
│   └── build.rs             # 构建脚本
├── package.json
├── tsconfig.json
├── tailwind.config.js
└── vite.config.ts
```

## 原生功能

### 系统托盘

应用最小化到系统托盘，支持:
- 左键点击恢复窗口
- 右键菜单 (显示/退出)

### 全局快捷键

默认快捷键: `Ctrl+Shift+L` (Windows/Linux) / `Cmd+Shift+L` (macOS)
- 快速显示/隐藏窗口

### 原生通知

使用系统原生通知 API:
```typescript
import { sendNotification } from '@tauri-apps/api/notification'

sendNotification({
  title: '新消息',
  body: '张三：你好！',
  icon: '/icon.png'
})
```

## 与 Web 客户端的区别

| 功能 | Web 客户端 | 桌面客户端 |
|------|-----------|-----------|
| PWA 支持 | ✅ | ❌ |
| 系统托盘 | ❌ | ✅ |
| 原生通知 | ❌ (Web Notification) | ✅ |
| 全局快捷键 | ❌ | ✅ |
| 文件访问 | 有限 | ✅ (完整) |
| 离线支持 | ✅ (Service Worker) | ✅ (本地存储) |

## 分发

### Windows
- `.msi` - Windows Installer
- `.exe` - 独立安装程序

### macOS
- `.app` - 应用程序包
- `.dmg` - 磁盘镜像

### Linux
- `.deb` - Debian/Ubuntu
- `.rpm` - Fedora/RHEL
- `.AppImage` - 通用格式

## 代码签名

### Windows
需要证书签名:
```bash
# 在 tauri.conf.json 中配置
"windows": {
  "certificateThumbprint": "YOUR_THUMBPRINT",
  "digestAlgorithm": "sha256",
  "timestampUrl": "http://timestamp.digicert.com"
}
```

### macOS
需要 Apple Developer 证书:
```bash
# Xcode -> Preferences -> Accounts
# 签名身份将在构建时自动选择
```

## 故障排除

### Windows
- 确保安装 Visual Studio Build Tools
- 启用"开发者模式"

### macOS
- 如果遇到"无法打开"错误，在系统设置中允许
- 需要 Apple Silicon 优化，添加 `--target aarch64-apple-darwin`

### Linux
- 安装必要的依赖:
```bash
# Ubuntu/Debian
sudo apt install libwebkit2gtk-4.0-dev \
    build-essential \
    curl \
    wget \
    libssl-dev \
    libgtk-3-dev \
    libayatana-appindicator3-dev \
    librsvg2-dev
```

## License

MIT
