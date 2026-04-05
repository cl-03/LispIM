import React from 'react'

const AboutSettings: React.FC = () => {
  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="text-center pb-6">
        <div className="w-20 h-20 mx-auto rounded-2xl bg-gradient-to-br from-blue-500 to-purple-600 flex items-center justify-center">
          <svg className="w-12 h-12 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z" />
          </svg>
        </div>
        <h2 className="text-xl font-semibold text-white mt-4">LispIM</h2>
        <p className="text-sm text-gray-400 mt-1">版本 0.1.0</p>
      </div>

      {/* App Info */}
      <div className="bg-gray-800 rounded-lg divide-y divide-gray-700">
        <div className="p-4 flex items-center justify-between">
          <div className="text-sm text-gray-300">构建日期</div>
          <div className="text-sm text-white">2026-04-03</div>
        </div>

        <div className="p-4 flex items-center justify-between">
          <div className="text-sm text-gray-300">技术栈</div>
          <div className="text-sm text-white">Common Lisp + React</div>
        </div>

        <a
          href="https://github.com/lispim/lispim"
          target="_blank"
          rel="noopener noreferrer"
          className="p-4 flex items-center justify-between hover:bg-gray-700 cursor-pointer transition-colors"
        >
          <div className="text-sm text-gray-300">源代码</div>
          <div className="flex items-center gap-2 text-sm text-blue-400">
            GitHub
            <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14" />
            </svg>
          </div>
        </a>
      </div>

      {/* Description */}
      <div className="bg-gray-800 rounded-lg p-4">
        <h3 className="text-sm font-medium text-white mb-2">关于 LispIM</h3>
        <p className="text-sm text-gray-400 leading-relaxed">
          LispIM 是一个现代化的即时通讯平台，采用 Common Lisp 后端和 React 前端构建。
          支持端到端加密、消息同步、朋友圈、附近的人等功能，注重隐私保护和用户体验。
        </p>
      </div>

      {/* Features */}
      <div className="bg-gray-800 rounded-lg p-4">
        <h3 className="text-sm font-medium text-white mb-3">主要功能</h3>
        <div className="grid grid-cols-2 gap-3">
          {[
            { icon: '💬', name: '即时消息' },
            { icon: '🔒', name: '端到端加密' },
            { icon: '👥', name: '好友管理' },
            { icon: '📱', name: '多端同步' },
            { icon: '📸', name: '朋友圈' },
            { icon: '📍', name: '附近的人' },
            { icon: '🔍', name: '全文搜索' },
            { icon: '🎨', name: '主题定制' }
          ].map((feature) => (
            <div
              key={feature.name}
              className="flex items-center gap-2 p-2 bg-gray-700/50 rounded-lg"
            >
              <span className="text-lg">{feature.icon}</span>
              <span className="text-sm text-gray-300">{feature.name}</span>
            </div>
          ))}
        </div>
      </div>

      {/* Team */}
      <div className="bg-gray-800 rounded-lg p-4">
        <h3 className="text-sm font-medium text-white mb-2">开发团队</h3>
        <p className="text-sm text-gray-400">
          LispIM Team © 2026
        </p>
        <p className="text-xs text-gray-500 mt-2">
          采用 MIT 许可证开源
        </p>
      </div>

      {/* Check Update */}
      <div className="bg-gray-800 rounded-lg p-4">
        <div className="flex items-center justify-between">
          <div>
            <div className="text-sm font-medium text-white">检查更新</div>
            <div className="text-xs text-gray-500 mt-0.5">
              当前版本已是最新
            </div>
          </div>
          <button className="px-4 py-2 bg-gray-700 text-white text-sm rounded-lg hover:bg-gray-600 transition-colors">
            检查更新
          </button>
        </div>
      </div>
    </div>
  )
}

export default AboutSettings
