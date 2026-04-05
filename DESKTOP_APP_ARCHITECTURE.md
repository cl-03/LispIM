# LispIM 桌面应用架构评估与设计

## 概述

本报告评估 LispIM 桌面应用的架构设计，基于 Tailchat 和 Fiora 的桌面客户端实现，提出适合 Common Lisp 生态的解决方案。

---

## 1. 现有桌面应用架构分析

### 1.1 Tailchat 桌面客户端架构

#### 技术栈
- **框架**: Electron 27
- **构建工具**: Webpack + TypeScript
- **包管理**: pnpm
- **打包工具**: electron-builder

#### 架构特点
```
client/desktop/
├── src/
│   ├── main/           # Electron 主进程
│   │   ├── main.ts     # 入口文件
│   │   ├── menu.ts     # 应用菜单
│   │   ├── preload.ts  # 预加载脚本
│   │   ├── screenshots.ts  # 截图功能
│   │   └── inject/     # 注入到 Webview 的脚本
│   │       ├── index.ts
│   │       └── message-handler.ts
│   │   └── lib/
│   │       ├── electron-serve.ts  # 本地服务器
│   │       ├── http.ts            # HTTP 工具
│   │       └── webview-manager.ts # Webview 管理
│   └── renderer/       # Electron 渲染进程
│       ├── App.tsx     # 主应用组件
│       ├── store/      # 状态管理
│       │   └── server.ts  # 多服务器管理
│       └── ServerItem.tsx
├── assets/             # 静态资源
├── electron-builder.yml # 打包配置
└── package.json
```

#### 核心功能
1. **多服务器管理**: 用户可添加多个 Tailchat 服务器实例
2. **Webview 嵌入**: 使用 `<webview>` 标签加载 Web 应用
3. **本地通知**: 桌面通知集成
4. **截图功能**: 屏幕共享和截图
5. **自动更新**: electron-updater

#### 关键代码分析

**主进程入口 (main.ts)**:
```typescript
const webPreferences: Electron.WebPreferences = {
  nodeIntegration: false,        // 禁用 Node 集成 (安全)
  contextIsolation: true,        // 启用上下文隔离
  webSecurity: false,            // 禁用同源策略 (允许跨域)
  preload: path.join(__dirname, 'preload.js')
};

const createMainWindow = async (url: string) => {
  mainWindow = new BrowserWindow({
    width: 1200,
    height: 800,
    webPreferences,
  });
  mainWindow.loadURL(url);  // 加载远程或本地 Web 应用
};
```

**消息处理器 (message-handler.ts)**:
```typescript
// 处理 Tailchat Webview 与 Electron 主进程的通信
export function handleTailchatMessage(
  webContentsId: number,
  message: ElectronMessage
) {
  switch (message.type) {
    case 'NOTIFICATION':
      showDesktopNotification(message.payload);
      break;
    case 'SCREEN_SHARE':
      startScreenShare(webContentsId);
      break;
  }
}
```

---

### 1.2 Fiora 桌面客户端架构

#### 技术栈
- **框架**: Electron
- **打包**: electron-packager

#### 架构特点
- 简单的 Webview 包装器
- 主要功能由 Web 应用提供
- 桌面通知和系统托盘集成

---

## 2. LispIM 桌面应用架构设计

### 2.1 架构选择

基于 LispIM 的技术特点，推荐以下架构方案：

#### 方案 A: Electron + Common Lisp 后端 (推荐)

```
┌─────────────────────────────────────────────────┐
│                   LispIM Desktop                 │
├─────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────────────────┐   │
│  │   Electron  │  │   SBCL Backend          │   │
│  │   Renderer  │  │   (Embedded)            │   │
│  │   (React)   │◄─┤                         │   │
│  │             │  │  - HTTP Server          │   │
│  │             │  │  - WebSocket Server     │   │
│  │             │  │  - Business Logic       │   │
│  └─────────────┘  └─────────────────────────┘   │
│         ▲                        ▲               │
│         │ IPC (Custom Protocol) │                │
│         └────────────────────────┘               │
└─────────────────────────────────────────────────┤
│         PostgreSQL │ Redis                       │
└─────────────────────────────────────────────────┘
```

**优点**:
- 完全离线运行，无需外部服务器
- 数据本地存储，隐私优先
- 单应用完成所有功能
- 适合个人/小团队使用

**缺点**:
- 应用体积较大 (~150MB+)
- 需要管理两个进程 (Electron + SBCL)
- 不适合多用户场景

#### 方案 B: Tauri + Common Lisp 后端

```
┌─────────────────────────────────────────────────┐
│                   LispIM Desktop                 │
├─────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────────────────┐   │
│  │    Tauri    │  │   SBCL Backend          │   │
│  │   Frontend  │  │   (Standalone)          │   │
│  │   (React)   │◄─┤                         │   │
│  │             │  │  - HTTP/WebSocket       │   │
│  └─────────────┘  └─────────────────────────┘   │
└─────────────────────────────────────────────────┘
```

**优点**:
- 更小的应用体积 (~10MB)
- 更好的系统集成
- 内存占用低

**缺点**:
- 需要 Rust 工具链
- Lisp 后端仍需独立运行

#### 方案 C: 纯 Common Lisp + 原生 GUI

```
┌─────────────────────────────────────────────────┐
│                   LispIM Desktop                 │
├─────────────────────────────────────────────────┤
│  ┌─────────────────────────────────────────┐    │
│  │   IUP / LispWorks CAPI / McCLIM         │    │
│  │   (Common Lisp GUI)                     │    │
│  │                                         │    │
│  │  - 纯 Common Lisp 实现                   │    │
│  │  - 直接调用后端 API                      │    │
│  └─────────────────────────────────────────┘    │
└─────────────────────────────────────────────────┘
```

**优点**:
- 100% Common Lisp 实现
- 无需外部依赖
- 最小化架构复杂度

**缺点**:
- GUI 库生态有限
- 外观和体验不如现代框架
- 开发效率较低

---

### 2.2 推荐方案：混合架构

结合 LispIM 的项目目标，推荐**方案 A 的变体**：

#### 生产模式
- Electron 渲染进程加载远程 Web 应用
- 可选嵌入本地 SBCL 后端（单用户模式）
- 或连接远程服务器（多用户模式）

#### 开发模式
- Electron 加载本地 Vite 开发服务器
- SBCL 后端独立运行
- 热重载支持

---

## 3. 详细设计

### 3.1 项目结构

```
desktop-app/
├── electron/               # Electron 主进程
│   ├── src/
│   │   ├── main.ts         # 入口文件
│   │   ├── preload.ts      # 预加载脚本
│   │   ├── menu.ts         # 应用菜单
│   │   ├── tray.ts         # 系统托盘
│   │   ├── notification.ts # 桌面通知
│   │   └── lisp-backend.ts # SBCL 后端管理
│   ├── package.json
│   └── electron-builder.yml
├── lisp-backend/           # Common Lisp 后端
│   ├── backend.asd         # ASDF 系统定义
│   ├── src/
│   │   ├── package.lisp    # 包定义
│   │   ├── server.lisp     # HTTP/WebSocket 服务器
│   │   ├── electron-ipc.lisp # Electron IPC 处理
│   │   ├── storage.lisp    # 本地存储
│   │   └── config.lisp     # 配置管理
│   └── binary/             # 编译后的二进制文件
├── web-client/             # Web 前端 (复用现有)
└── build/                  # 构建输出
```

### 3.2 Electron 主进程设计

#### main.ts - 主入口
```typescript
import { app, BrowserWindow, ipcMain } from 'electron';
import { spawn, ChildProcess } from 'child_process';
import path from 'path';

let mainWindow: BrowserWindow | null = null;
let lispBackend: ChildProcess | null = null;

// 启动 Lisp 后端
function startLispBackend() {
  const backendPath = path.join(
    process.resourcesPath || './lisp-backend',
    'lispim-backend' + (process.platform === 'win32' ? '.exe' : '')
  );
  
  lispBackend = spawn(backendPath, [], {
    cwd: path.dirname(backendPath),
    stdio: ['pipe', 'pipe', 'pipe']
  });
  
  lispBackend.stdout?.on('data', (data) => {
    console.log('[Lisp]', data.toString());
  });
  
  lispBackend.on('exit', (code) => {
    console.log('Lisp backend exited:', code);
  });
}

// 创建主窗口
function createWindow() {
  mainWindow = new BrowserWindow({
    width: 1200,
    height: 800,
    webPreferences: {
      nodeIntegration: false,
      contextIsolation: true,
      preload: path.join(__dirname, 'preload.js')
    }
  });
  
  // 生产模式：加载本地后端
  // 开发模式：加载远程 URL
  if (process.env.NODE_ENV === 'development') {
    mainWindow.loadURL('http://localhost:5173');
  } else {
    mainWindow.loadURL('http://localhost:4321'); // Lisp 后端端口
  }
}

// IPC 处理
ipcMain.handle('send-message', async (event, message) => {
  // 转发消息到 Lisp 后端
  lispBackend?.stdin?.write(JSON.stringify(message) + '\n');
});

ipcMain.handle('get-local-storage', async (event, key) => {
  // 本地存储访问
  return localStorage.getItem(key);
});

app.whenReady().then(() => {
  startLispBackend();
  createWindow();
});
```

### 3.3 Lisp 后端设计

#### electron-ipc.lisp - IPC 通信
```lisp
;;;; electron-ipc.lisp - Electron 与 Lisp 后端通信

(in-package :lispim-core)

;;;; JSON-RPC over STDIO

(defun read-json-message ()
  "从 STDIN 读取 JSON 消息"
  (let ((line (read-line *standard-input* nil nil)))
    (when line
      (cl-json:decode-json-from-string line))))

(defun write-json-response (result)
  "写入 JSON 响应到 STDOUT"
  (let ((json (cl-json:encode-json-to-string result)))
    (format *standard-output* "~a~%" json)
    (finish-output *standard-output*)))

(defun handle-electron-message (message)
  "处理来自 Electron 的消息"
  (let* ((method (getf message :method))
         (params (getf message :params))
         (id (getf message :id)))
    (handler-case
        (let ((result (case method
                        (:get-messages 
                         (get-messages-for-user params))
                        (:send-message
                         (send-message-to-user params))
                        (:get-user-info
                         (get-user-info-by-id params))
                        (t (error "Unknown method: ~a" method)))))
          (write-json-response 
           (list :jsonrpc "2.0"
                 :result result
                 :id id)))
      (error (c)
        (write-json-response
         (list :jsonrpc "2.0"
               :error (format nil "~a" c)
               :id id))))))

(defun run-electron-backend ()
  "运行 Electron 集成的后端服务"
  (loop for message = (read-json-message)
        while message
        do (handle-electron-message message)))
```

### 3.4 构建配置

#### electron-builder.yml
```yaml
appId: com.lispim.desktop
productName: LispIM
directories:
  output: release/build
files:
  - electron/dist/**/*
  - lisp-backend/binary/**/*
  - node_modules/**/*
extraResources:
  - from: lisp-backend/binary/
    to: lisp-backend/
win:
  target:
    - zip
    - nsis
  artifactName: LispIM-${version}-win-${arch}.${ext}
mac:
  target:
    - dmg
  artifactName: LispIM-${version}-mac-${arch}.${ext}
linux:
  target:
    - AppImage
    - deb
  artifactName: LispIM-${version}-linux-${arch}.${ext}
```

### 3.5 SBCL 二进制编译

#### 编译脚本 (build-lisp-backend.lisp)
```lisp
;;;; build-lisp-backend.lisp - 编译 Lisp 后端为独立二进制文件

(require 'asdf)
(require 'sb-ext)

;; 加载 Quicklisp
(load "~/quicklisp/setup.lisp")

;; 加载系统
(ql:quickload :lispim-core)
(ql:quickload :hunchentoot)

;; 创建可执行文件
(sb-ext:save-lisp-and-die 
  "lispim-backend"
  :toplevel #'lispim-core:run-electron-backend
  :executable t
  :save-runtime-options t)
```

#### 构建脚本 (build.sh)
```bash
#!/bin/bash
set -e

echo "Building Lisp Backend..."

# 编译 SBCL 二进制
sbcl --script build-lisp-backend.lisp

# 移动二进制文件
mkdir -p lisp-backend/binary
mv lispim-backend lisp-backend/binary/

echo "Building Electron App..."

# 构建 Electron
cd electron
npm install
npm run build

# 打包
npm run package

echo "Build complete!"
```

---

## 4. 实现路线图

### 阶段 1: 基础架构 (2 周)
- [ ] Electron 项目初始化
- [ ] Lisp 后端编译脚本
- [ ] IPC 通信协议定义
- [ ] 基本窗口管理

### 阶段 2: 核心功能 (3 周)
- [ ] 消息收发集成
- [ ] 用户认证流程
- [ ] 本地存储实现
- [ ] 桌面通知

### 阶段 3: 高级功能 (2 周)
- [ ] 系统托盘
- [ ] 全局快捷键
- [ ] 截图功能
- [ ] 文件拖放

### 阶段 4: 打包发布 (1 周)
- [ ] Windows 打包 (NSIS)
- [ ] macOS 打包 (DMG)
- [ ] Linux 打包 (AppImage)
- [ ] 自动更新

---

## 5. 性能考虑

### 5.1 启动时间
- **目标**: < 3 秒冷启动
- **优化**:
  - SBCL 核心镜像预编译
  - Electron 懒加载
  - 关键路径预加载

### 5.2 内存占用
- **目标**: < 200MB 空闲
- **优化**:
  - Lisp GC 调优
  - Electron 内存限制
  - 缓存大小限制

### 5.3 消息延迟
- **目标**: < 50ms 本地 IPC
- **优化**:
  - 二进制 JSON (MessagePack)
  - 零拷贝 IPC
  - 批处理更新

---

## 6. 安全考虑

### 6.1 Electron 安全
```typescript
// 强制安全设置
const webPreferences = {
  nodeIntegration: false,      // 禁用 Node
  contextIsolation: true,      // 上下文隔离
  webSecurity: true,           // 启用同源策略
  allowRunningInsecureContent: false,
  sandbox: true                // 沙箱模式
};
```

### 6.2 Lisp 后端安全
```lisp
;; 输入验证
(defun validate-message (message)
  "验证消息格式和内容"
  (and (getf message :content)
       (<= (length (getf message :content)) 10000)
       (valid-user-id-p (getf message :sender-id))))

;; 速率限制
(defun rate-limit-check (user-id)
  "检查用户速率限制"
  (let ((count (get-user-request-count user-id)))
    (when (> count 100)
      (error "Rate limit exceeded"))))
```

---

## 7. 总结

### 推荐架构决策

| 决策点 | 选择 | 理由 |
|--------|------|------|
| 桌面框架 | Electron | 成熟生态，跨平台支持好 |
| 后端运行 | 嵌入式 SBCL | 单应用体验，离线优先 |
| 通信协议 | JSON-RPC over STDIO | 简单，易调试 |
| 打包方式 | electron-builder | 自动化程度高 |
| 更新机制 | electron-updater | 标准解决方案 |

### 下一步行动

1. **创建 Electron 项目骨架**
2. **实现 SBCL 二进制编译**
3. **定义 IPC 协议规范**
4. **实现基本消息收发**
5. **测试和打包**

---

*最后更新：2026-04-02*
*LispIM Desktop Architecture v0.1.0*
