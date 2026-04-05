# LispIM 桌面应用构建指南

## 构建输出

### Unpacked 版本 (测试用)
位置：`release/win-unpacked/`
运行方式：双击 `LispIM.exe` 或运行 `start-electron.bat`

## 构建命令

### 开发模式 (热更新)
```bash
npm run electron:dev
```

### 生产构建

#### Windows (Portable)
```bash
npm run electron:build:win
```

#### macOS
```bash
npm run electron:build:mac
```

#### Linux
```bash
npm run electron:build:linux
```

## 文件结构

```
web-client/
├── dist/                 # Vite 构建输出
├── electron/
│   ├── main.js          # Electron 主进程
│   └── preload.js       # Electron 预加载脚本
├── release/
│   └── win-unpacked/    # Unpacked 版本 (可直接运行)
├── electron-builder.json # Electron Builder 配置
└── start-electron.bat   # Windows 启动脚本
```

## 注意事项

1. **图标**: 需要添加 `public/icon.ico` 以自定义应用图标
2. **网络**: 完整打包需要下载 NSIS 工具 (可能需要代理)
3. **签名**: 生产环境需要代码签名证书

## 当前状态

✅ Vite 构建完成
✅ Electron 主进程配置完成
✅ Unpacked 版本可运行
⏳ NSIS 打包需要网络连接 (GitHub releases)

## 开发者模式运行

如果您想查看实时开发效果：

```bash
# 安装依赖
npm install

# 启动开发服务器 + Electron
npm run electron:dev
```

这将同时启动 Vite 开发服务器和 Electron 窗口，支持热更新。
