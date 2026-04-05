import React from 'react'
import { useNavigate } from 'react-router-dom'
import { useAppStore } from '@/store/appStore'

const ProfileDetail: React.FC = () => {
  const navigate = useNavigate()
  const { user } = useAppStore()

  return (
    <div className="h-screen flex flex-col bg-gradient-to-br from-gray-900 via-gray-800 to-gray-900">
      {/* Header */}
      <div className="bg-gradient-to-r from-indigo-600 to-purple-600 px-4 py-4 shadow-lg flex items-center">
        <button
          onClick={() => navigate('/profile')}
          className="mr-3 text-white/80 hover:text-white transition-colors"
        >
          <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 19l-7-7 7-7" />
          </svg>
        </button>
        <h1 className="text-xl font-bold text-white">个人信息</h1>
      </div>

      {/* Profile Content */}
      <div className="flex-1 overflow-y-auto p-4 space-y-3">
        {/* Avatar & Name Card */}
        <div className="bg-gradient-to-br from-gray-800/80 to-gray-800/60 backdrop-blur rounded-2xl p-6 border border-gray-700/50 shadow-lg">
          <div className="flex items-center gap-4">
            <div className="w-24 h-24 rounded-full bg-gradient-to-br from-blue-500 to-indigo-600 flex items-center justify-center text-white text-3xl font-medium shadow-lg ring-4 ring-blue-500/20">
              {user?.avatar ? (
                <img src={user.avatar} alt={user.displayName} className="w-24 h-24 rounded-full object-cover" />
              ) : (
                (user?.displayName || user?.username || '?').charAt(0).toUpperCase()
              )}
            </div>
            <div className="flex-1">
              <div className="text-2xl font-bold text-white flex items-center gap-2">
                {user?.displayName || user?.username}
                <span className="px-2 py-1 bg-blue-500/30 rounded-full text-xs font-medium">Lv.1</span>
              </div>
              <div className="text-gray-400 text-sm">@{user?.username}</div>
            </div>
          </div>
        </div>

        {/* Info Items */}
        <div className="bg-gray-800/80 backdrop-blur rounded-2xl border border-gray-700/50 overflow-hidden shadow-lg">
          <div className="flex items-center justify-between px-4 py-4 border-b border-gray-700/50">
            <span className="text-gray-400">账号</span>
            <span className="text-white font-medium">{user?.username}</span>
          </div>

          <div className="flex items-center justify-between px-4 py-4 border-b border-gray-700/50">
            <span className="text-gray-400">昵称</span>
            <span className="text-white font-medium">{user?.displayName || '-'}</span>
          </div>

          <div className="flex items-center justify-between px-4 py-4 border-b border-gray-700/50">
            <span className="text-gray-400">在线状态</span>
            <span className="text-green-400 font-medium flex items-center gap-2">
              <span className="w-2 h-2 bg-green-500 rounded-full animate-pulse"></span>
              在线
            </span>
          </div>

          <div className="flex items-center justify-between px-4 py-4">
            <span className="text-gray-400">用户 ID</span>
            <span className="text-gray-500 text-sm font-mono bg-gray-700/50 px-3 py-1 rounded-lg">{user?.id}</span>
          </div>
        </div>

        {/* Bio Card */}
        {user?.bio && (
          <div className="bg-gray-800/80 backdrop-blur rounded-2xl p-5 border border-gray-700/50 shadow-lg">
            <div className="text-gray-400 text-sm mb-2">个人简介</div>
            <div className="text-gray-300 italic leading-relaxed">"{user.bio}"</div>
          </div>
        )}

        {/* QR Code Card */}
        <div className="bg-gray-800/80 backdrop-blur rounded-2xl p-6 border border-gray-700/50 shadow-lg">
          <div className="text-center mb-4">
            <h3 className="text-lg font-semibold text-white">我的二维码</h3>
            <p className="text-gray-400 text-sm mt-1">分享给好友，一起加入 LispIM</p>
          </div>
          <div className="flex justify-center">
            <div className="bg-white rounded-2xl p-4 shadow-xl">
              <div className="w-48 h-48 bg-gradient-to-br from-blue-500 to-indigo-600 rounded-xl flex items-center justify-center relative overflow-hidden">
                {/* QR Code Pattern */}
                <div className="grid grid-cols-7 gap-1 opacity-80">
                  {Array.from({ length: 49 }).map((_, i) => (
                    <div
                      key={i}
                      className={`w-5 h-5 rounded-sm ${i % 8 === 0 || i % 6 === 0 || i % 11 === 0 ? 'bg-gray-800' : 'bg-gray-700'}`}
                    />
                  ))}
                </div>
                {/* Center Logo */}
                <div className="absolute inset-0 flex items-center justify-center">
                  <div className="w-14 h-14 bg-white rounded-full flex items-center justify-center shadow-lg">
                    <svg className="w-8 h-8 text-blue-600" fill="currentColor" viewBox="0 0 24 24">
                      <path d="M13 10V3L4 14h7v7l9-11h-7z" />
                    </svg>
                  </div>
                </div>
              </div>
            </div>
          </div>
          <div className="text-center mt-4">
            <button className="px-6 py-2.5 bg-gradient-to-r from-blue-500 to-indigo-600 text-white rounded-xl font-medium hover:from-blue-600 hover:to-indigo-700 transition-all shadow-lg hover:shadow-xl">
              保存到相册
            </button>
          </div>
        </div>

        {/* User ID Copy Hint */}
        <div className="bg-blue-500/10 backdrop-blur rounded-xl p-4 border border-blue-500/20">
          <div className="flex items-start gap-3">
            <svg className="w-5 h-5 text-blue-400 mt-0.5 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
            </svg>
            <div className="text-sm text-blue-300">
              <div className="font-medium mb-1">温馨提示</div>
              <div className="text-blue-400/80">点击用户 ID 可快速复制，方便分享给好友或用于技术支持。</div>
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}

export default ProfileDetail
