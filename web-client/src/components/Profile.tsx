import React, { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useAppStore } from '@/store/appStore'

const Profile: React.FC = () => {
  const navigate = useNavigate()
  const { user, logout } = useAppStore()
  const [showQR, setShowQR] = useState(false)

  const handleLogout = () => {
    logout()
    window.location.href = '/login'
  }

  const menuItems = [
    {
      icon: (
        <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z" />
        </svg>
      ),
      label: '个人信息',
      desc: '头像、昵称、个人简介',
      color: 'from-blue-500 to-cyan-500',
      onClick: () => navigate('/settings')
    },
    {
      icon: (
        <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z" />
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />
        </svg>
      ),
      label: '设置',
      desc: '账号、隐私、通知设置',
      color: 'from-gray-500 to-slate-500',
      onClick: () => navigate('/settings')
    },
    {
      icon: (
        <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z" />
        </svg>
      ),
      label: '账号安全',
      desc: '密码、登录设备管理',
      color: 'from-red-500 to-rose-500',
      onClick: () => navigate('/settings')
    },
    {
      icon: (
        <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
        </svg>
      ),
      label: '关于我们',
      desc: '版本信息、开源协议',
      color: 'from-purple-500 to-pink-500',
      onClick: () => navigate('/settings')
    },
    {
      icon: (
        <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z" />
        </svg>
      ),
      label: '我的二维码',
      desc: '分享给好友',
      color: 'from-green-500 to-emerald-500',
      onClick: () => setShowQR(true)
    },
    {
      icon: (
        <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M5 5a2 2 0 012-2h10a2 2 0 012 2v16l-7-3.5L5 21V5z" />
        </svg>
      ),
      label: '收藏夹',
      desc: '查看收藏内容',
      color: 'from-yellow-500 to-amber-500',
      onClick: () => showToast('收藏夹即将上线！')
    }
  ]

  const [toast, setToast] = useState<{ message: string; visible: boolean }>({ message: '', visible: false })

  const showToast = (message: string) => {
    setToast({ message, visible: true })
    setTimeout(() => setToast({ message: '', visible: false }), 2000)
  }

  return (
    <div className="h-screen flex flex-col bg-gradient-to-br from-gray-900 via-gray-800 to-gray-900">
      {/* Header */}
      <div className="bg-gradient-to-r from-indigo-600 to-purple-600 px-4 py-6 shadow-lg">
        <h1 className="text-2xl font-bold text-white">我</h1>
        <p className="text-indigo-100 text-sm mt-1">管理个人资料和设置</p>
      </div>

      {/* Content */}
      <div className="flex-1 overflow-y-auto p-4 space-y-3">
        {/* Profile Card */}
        <div
          onClick={() => navigate('/settings')}
          className="bg-gradient-to-br from-gray-800/80 to-gray-800/60 backdrop-blur rounded-2xl p-5 border border-gray-700/50 shadow-lg cursor-pointer hover:shadow-xl transition-all duration-200"
        >
          <div className="flex items-center gap-4">
            <div className="w-20 h-20 rounded-full bg-gradient-to-br from-blue-500 to-indigo-600 flex items-center justify-center text-white text-2xl font-medium shadow-lg overflow-hidden ring-2 ring-white/20">
              {user?.avatar ? (
                <img src={user.avatar} alt={user.displayName} className="w-20 h-20 object-cover" />
              ) : (
                (user?.displayName || user?.username || '?').charAt(0).toUpperCase()
              )}
            </div>
            <div className="flex-1">
              <div className="text-xl font-bold text-white flex items-center gap-2">
                {user?.displayName || user?.username}
                <span className="px-2 py-0.5 bg-blue-500/30 rounded-full text-xs">Lv.1</span>
              </div>
              <div className="text-gray-400 text-sm">@{user?.username}</div>
              {user?.bio && (
                <div className="text-sm text-gray-500 mt-2 line-clamp-2 italic">"{user.bio}"</div>
              )}
            </div>
          </div>
        </div>

        {/* Online Status Card */}
        <div className="bg-gray-800/80 backdrop-blur rounded-2xl p-4 border border-gray-700/50">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-3">
              <div className="w-2 h-2 bg-green-500 rounded-full animate-pulse"></div>
              <span className="text-gray-300">在线状态</span>
            </div>
            <span className="text-green-400 text-sm font-medium">在线中</span>
          </div>
        </div>

        {/* Menu Items */}
        <div className="bg-gray-800/80 backdrop-blur rounded-2xl border border-gray-700/50 overflow-hidden shadow-lg">
          {menuItems.map((item, index) => (
            <div
              key={index}
              className="flex items-center gap-3 px-4 py-3.5 hover:bg-gray-700/50 cursor-pointer transition-all duration-200 group border-b border-gray-700/30 last:border-0"
              onClick={item.onClick}
            >
              <div className={`bg-gradient-to-br ${item.color} text-white p-2.5 rounded-xl shadow-md group-hover:shadow-lg transition-shadow`}>
                {item.icon}
              </div>
              <div className="flex-1">
                <div className="text-gray-200 font-medium">{item.label}</div>
                <div className="text-xs text-gray-500">{item.desc}</div>
              </div>
              <svg className="w-5 h-5 text-gray-500 group-hover:text-gray-300 transition-colors" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 5l7 7-7 7" />
              </svg>
            </div>
          ))}
        </div>

        {/* Stats */}
        <div className="bg-gray-800/80 backdrop-blur rounded-2xl p-5 border border-gray-700/50 shadow-lg">
          <div className="flex justify-around text-center">
            <div className="flex-1">
              <div className="text-2xl font-bold text-white">0</div>
              <div className="text-xs text-gray-500 mt-1">好友</div>
            </div>
            <div className="w-px bg-gray-700/50"></div>
            <div className="flex-1">
              <div className="text-2xl font-bold text-white">0</div>
              <div className="text-xs text-gray-500 mt-1">朋友圈</div>
            </div>
            <div className="w-px bg-gray-700/50"></div>
            <div className="flex-1">
              <div className="text-2xl font-bold text-white">0</div>
              <div className="text-xs text-gray-500 mt-1">收藏</div>
            </div>
          </div>
        </div>

        {/* Logout Button */}
        <div className="pt-2">
          <button
            onClick={handleLogout}
            className="w-full py-3.5 bg-gradient-to-r from-red-500 to-rose-600 text-white rounded-2xl hover:from-red-600 hover:to-rose-700 transition-all duration-200 font-medium shadow-lg hover:shadow-xl hover:scale-[1.02] active:scale-[0.98]"
          >
            退出登录
          </button>
        </div>
      </div>

      {/* QR Code Modal */}
      {showQR && (
        <div className="fixed inset-0 bg-black/70 backdrop-blur-sm flex items-center justify-center z-50 p-4" onClick={() => setShowQR(false)}>
          <div className="bg-gray-800 rounded-3xl p-6 max-w-xs w-full shadow-2xl border border-gray-700" onClick={e => e.stopPropagation()}>
            <div className="text-center mb-4">
              <h3 className="text-lg font-semibold text-white">我的二维码</h3>
              <p className="text-gray-400 text-sm mt-1">分享给好友，一起加入 LispIM</p>
            </div>
            <div className="bg-white rounded-2xl p-4 mb-4">
              <div className="aspect-square bg-gradient-to-br from-blue-500 to-indigo-600 rounded-xl flex items-center justify-center relative overflow-hidden">
                {/* QR Code Pattern */}
                <div className="grid grid-cols-7 gap-1 opacity-80">
                  {Array.from({ length: 49 }).map((_, i) => (
                    <div
                      key={i}
                      className={`w-3 h-3 rounded-sm ${i % 8 === 0 || i % 6 === 0 || i % 11 === 0 ? 'bg-gray-800' : 'bg-gray-700'}`}
                    />
                  ))}
                </div>
                {/* Center Logo */}
                <div className="absolute inset-0 flex items-center justify-center">
                  <div className="w-12 h-12 bg-white rounded-full flex items-center justify-center shadow-lg">
                    <svg className="w-7 h-7 text-blue-600" fill="currentColor" viewBox="0 0 24 24">
                      <path d="M13 10V3L4 14h7v7l9-11h-7z" />
                    </svg>
                  </div>
                </div>
              </div>
            </div>
            <button
              onClick={() => {
                showToast('二维码已保存')
                setShowQR(false)
              }}
              className="w-full py-2.5 bg-gradient-to-r from-blue-500 to-indigo-600 text-white rounded-xl font-medium hover:from-blue-600 hover:to-indigo-700 transition-all"
            >
              保存到相册
            </button>
            <button
              onClick={() => setShowQR(false)}
              className="w-full py-2.5 mt-2 text-gray-400 hover:text-white transition-colors"
            >
              关闭
            </button>
          </div>
        </div>
      )}

      {/* Toast */}
      {toast.visible && (
        <div className="fixed top-20 left-1/2 transform -translate-x-1/2 bg-gray-800 text-white px-6 py-3 rounded-lg shadow-lg z-50 animate-fade-in">
          {toast.message}
        </div>
      )}
    </div>
  )
}

export default Profile
