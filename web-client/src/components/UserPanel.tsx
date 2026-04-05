import React, { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useAppStore } from '@/store/appStore'

interface UserPanelProps {
  onToggleSidebar: () => void
}

const UserPanel: React.FC<UserPanelProps> = ({ onToggleSidebar }) => {
  const navigate = useNavigate()
  const { user, logout } = useAppStore()
  const [showDropdown, setShowDropdown] = useState(false)

  const statusColors = {
    online: 'bg-green-500',
    offline: 'bg-gray-500',
    away: 'bg-yellow-500',
    busy: 'bg-red-500'
  }

  const statusLabels = {
    online: '在线',
    offline: '离线',
    away: '离开',
    busy: '忙碌'
  }

  const handleLogout = () => {
    logout()
    window.location.href = '/login'
  }

  return (
    <div className="p-4 border-b border-gray-700 bg-gray-800">
      <div className="flex items-center justify-between">
        <div
          className="flex items-center space-x-3 cursor-pointer flex-1 min-w-0"
          onClick={() => setShowDropdown(!showDropdown)}
        >
          {/* 头像 */}
          <div className="relative flex-shrink-0">
            <div className="w-10 h-10 rounded-full bg-blue-500 flex items-center justify-center text-white font-semibold overflow-hidden">
              {user?.avatar ? (
                <img src={user.avatar} alt={user.displayName} className="w-10 h-10 object-cover" />
              ) : (
                (user?.displayName || user?.username || '?').charAt(0).toUpperCase()
              )}
            </div>
            <div
              className={`absolute bottom-0 right-0 w-3 h-3 ${
                statusColors[user?.status as keyof typeof statusColors] || 'bg-gray-500'
              } rounded-full border-2 border-gray-800`}
            />
          </div>

          {/* 用户信息 */}
          <div className="flex-1 min-w-0">
            <h3 className="text-white font-medium truncate">
              {user?.displayName || user?.username}
            </h3>
            <p className="text-xs text-gray-400">
              {statusLabels[user?.status as keyof typeof statusLabels] || '离线'}
            </p>
          </div>
        </div>

        {/* 折叠按钮 */}
        <button
          onClick={onToggleSidebar}
          className="p-2 hover:bg-gray-700 rounded-lg transition-colors ml-2"
          title="折叠侧边栏"
        >
          <svg className="w-5 h-5 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M11 19l-7-7 7-7m8 14l-7-7 7-7" />
          </svg>
        </button>
      </div>

      {/* 用户信息下拉菜单 */}
      {showDropdown && (
        <>
          <div className="fixed inset-0 z-10" onClick={() => setShowDropdown(false)} />
          <div className="absolute left-4 right-4 mt-2 bg-gray-700 rounded-lg shadow-lg z-20 overflow-hidden">
            {/* 用户详情 */}
            <div className="p-4 border-b border-gray-600">
              <div className="flex items-center gap-3">
                <div className="w-12 h-12 rounded-full bg-blue-500 flex items-center justify-center text-white font-medium overflow-hidden">
                  {user?.avatar ? (
                    <img src={user.avatar} alt={user.displayName} className="w-12 h-12 object-cover" />
                  ) : (
                    (user?.displayName || user?.username || '?').charAt(0).toUpperCase()
                  )}
                </div>
                <div className="flex-1 min-w-0">
                  <div className="text-white font-medium truncate">
                    {user?.displayName || user?.username}
                  </div>
                  <div className="text-xs text-gray-400 truncate">@{user?.username}</div>
                </div>
              </div>
            </div>

            {/* 快捷操作 */}
            <div className="p-2">
              <button
                onClick={() => {
                  navigate('/profile')
                  setShowDropdown(false)
                }}
                className="w-full flex items-center gap-3 px-3 py-2 text-sm text-gray-300 hover:bg-gray-600 rounded-lg transition-colors"
              >
                <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z" />
                </svg>
                个人信息
              </button>

              <button
                onClick={() => {
                  navigate('/settings')
                  setShowDropdown(false)
                }}
                className="w-full flex items-center gap-3 px-3 py-2 text-sm text-gray-300 hover:bg-gray-600 rounded-lg transition-colors"
              >
                <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z" />
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />
                </svg>
                设置
              </button>
            </div>

            {/* 退出登录 */}
            <div className="p-2 border-t border-gray-600">
              <button
                onClick={handleLogout}
                className="w-full flex items-center gap-3 px-3 py-2 text-sm text-red-400 hover:bg-red-900/20 rounded-lg transition-colors"
              >
                <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M17 16l4-4m0 0l-4-4m4 4H7m6 4v1a3 3 0 01-3 3H6a3 3 0 01-3-3V7a3 3 0 013-3h4a3 3 0 013 3v1" />
                </svg>
                退出登录
              </button>
            </div>
          </div>
        </>
      )}

      {/* 操作菜单 */}
      <div className="mt-3 flex space-x-2">
        <button
          onClick={() => navigate('/profile')}
          className="flex-1 px-3 py-2 text-sm bg-gray-700 hover:bg-gray-600 rounded-lg transition-colors text-gray-300"
        >
          个人中心
        </button>
        <button
          onClick={() => navigate('/settings')}
          className="flex-1 px-3 py-2 text-sm bg-gray-700 hover:bg-gray-600 rounded-lg transition-colors text-gray-300"
        >
          设置
        </button>
      </div>
    </div>
  )
}

export default UserPanel
