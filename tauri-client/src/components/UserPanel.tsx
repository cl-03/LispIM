import React from 'react'
import { useAppStore } from '@/store/appStore'
import type { User } from '@/types'

interface UserPanelProps {
  user: User
  onToggleSidebar: () => void
}

const UserPanel: React.FC<UserPanelProps> = ({ user, onToggleSidebar }) => {
  const { logout } = useAppStore()

  const statusColors = {
    online: 'bg-green-500',
    offline: 'bg-gray-500',
    away: 'bg-yellow-500',
    busy: 'bg-red-500'
  }

  return (
    <div className="p-4 border-b border-primary-accent">
      <div className="flex items-center justify-between">
        <div className="flex items-center space-x-3">
          {/* 头像 */}
          <div className="relative">
            <div className="w-10 h-10 rounded-full bg-primary-accent flex items-center justify-center text-white font-semibold">
              {user.displayName.charAt(0).toUpperCase()}
            </div>
            <div
              className={`absolute bottom-0 right-0 w-3 h-3 ${
                statusColors[user.status]
              } rounded-full border-2 border-primary-dark`}
            />
          </div>

          {/* 用户信息 */}
          <div className="flex-1">
            <h3 className="text-white font-medium">{user.displayName}</h3>
            <p className="text-xs text-gray-400 capitalize">{user.status}</p>
          </div>
        </div>

        {/* 折叠按钮 */}
        <button
          onClick={onToggleSidebar}
          className="p-2 hover:bg-primary-accent rounded-lg transition-colors"
          title="折叠侧边栏"
        >
          <svg className="w-5 h-5 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M11 19l-7-7 7-7m8 14l-7-7 7-7" />
          </svg>
        </button>
      </div>

      {/* 操作菜单 */}
      <div className="mt-3 flex space-x-2">
        <button
          onClick={logout}
          className="flex-1 px-3 py-2 text-sm bg-primary-accent hover:bg-red-500/50 rounded-lg transition-colors text-gray-300 hover:text-white"
        >
          退出登录
        </button>
      </div>
    </div>
  )
}

export default UserPanel
