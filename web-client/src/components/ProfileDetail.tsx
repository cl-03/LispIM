import React from 'react'
import { useNavigate } from 'react-router-dom'
import { useAppStore } from '@/store/appStore'

const ProfileDetail: React.FC = () => {
  const navigate = useNavigate()
  const { user } = useAppStore()

  return (
    <div className="h-screen flex flex-col bg-gray-900">
      {/* Header */}
      <div className="bg-gray-800 border-b border-gray-700 px-4 py-3 flex items-center">
        <button
          onClick={() => navigate('/profile')}
          className="mr-3 text-gray-400 hover:text-white"
        >
          <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 19l-7-7 7-7" />
          </svg>
        </button>
        <h1 className="text-xl font-semibold text-white">个人信息</h1>
      </div>

      {/* Profile Content */}
      <div className="flex-1 overflow-y-auto">
        {/* Avatar */}
        <div className="bg-gray-800 p-6 mb-2">
          <div className="flex items-center gap-4">
            <div className="w-24 h-24 rounded-full bg-blue-500 flex items-center justify-center text-white text-3xl font-medium">
              {user?.avatar ? (
                <img src={user.avatar} alt={user.displayName} className="w-24 h-24 rounded-full object-cover" />
              ) : (
                (user?.displayName || user?.username || '?').charAt(0).toUpperCase()
              )}
            </div>
            <div className="flex-1">
              <div className="text-xl font-semibold text-white">
                {user?.displayName || user?.username}
              </div>
              <div className="text-gray-400">@{user?.username}</div>
            </div>
          </div>
        </div>

        {/* Info Items */}
        <div className="bg-gray-800 divide-y divide-gray-700">
          <div className="flex items-center justify-between px-4 py-4">
            <span className="text-gray-400 w-20">账号</span>
            <span className="text-white flex-1 text-right">{user?.username}</span>
          </div>

          <div className="flex items-center justify-between px-4 py-4">
            <span className="text-gray-400 w-20">昵称</span>
            <span className="text-white flex-1 text-right">{user?.displayName || '-'}</span>
          </div>

          <div className="flex items-center justify-between px-4 py-4">
            <span className="text-gray-400 w-20">状态</span>
            <span className="text-green-400 flex-1 text-right flex items-center justify-end gap-2">
              <span className="w-2 h-2 bg-green-500 rounded-full"></span>
              在线
            </span>
          </div>

          <div className="flex items-center justify-between px-4 py-4">
            <span className="text-gray-400 w-20">用户 ID</span>
            <span className="text-gray-500 flex-1 text-right text-sm font-mono">{user?.id}</span>
          </div>
        </div>

        {/* QR Code Placeholder */}
        <div className="bg-gray-800 mt-2 p-6">
          <div className="text-center mb-4">
            <span className="text-gray-400">我的二维码</span>
          </div>
          <div className="flex justify-center">
            <div className="w-48 h-48 bg-white rounded-lg flex items-center justify-center">
              <div className="text-center text-gray-400">
                <svg className="w-16 h-16 mx-auto mb-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M12 4v1m6 11h2m-6 0h-2v4h2v-4zM6 8V4m0 0l3 3m-3-3L3 7m17 1v4m0 0l-3-3m3 3l3 3M6 16v4m0 0l3-3m-3 3l-3 3" />
                </svg>
                <span className="text-sm">二维码功能开发中</span>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}

export default ProfileDetail
