import React, { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import AddFriendModal from './AddFriendModal'
import ScanModal from './ScanModal'
import NearbyPeopleModal from './NearbyPeopleModal'
import MomentsFeed from './MomentsFeed'
import { UserStatusStories } from './UserStatusStories'
import GroupModal from './GroupModal'

const Discover: React.FC = () => {
  const navigate = useNavigate()
  const [showScanModal, setShowScanModal] = useState(false)
  const [showAddFriendModal, setShowAddFriendModal] = useState(false)
  const [showNearbyModal, setShowNearbyModal] = useState(false)
  const [showMoments, setShowMoments] = useState(false)
  const [showStatusStories, setShowStatusStories] = useState(false)
  const [showGroupModal, setShowGroupModal] = useState(false)
  const [toast, setToast] = useState<{ message: string; visible: boolean }>({ message: '', visible: false })

  const showToast = (message: string) => {
    setToast({ message, visible: true })
    setTimeout(() => setToast({ message: '', visible: false }), 2000)
  }

  const features = [
    {
      name: '状态动态',
      icon: (
        <svg className="w-8 h-8" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M13 10V3L4 14h7v7l9-11h-7z" />
        </svg>
      ),
      description: '24 小时过期状态',
      color: 'from-yellow-500 to-orange-500',
      gradient: true,
      onClick: () => setShowStatusStories(true)
    },
    {
      name: '朋友圈',
      icon: (
        <svg className="w-8 h-8" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z" />
        </svg>
      ),
      description: '分享生活点滴',
      color: 'from-green-500 to-emerald-500',
      gradient: true,
      onClick: () => setShowMoments(true)
    },
    {
      name: '视频号',
      icon: (
        <svg className="w-8 h-8" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M15 10l4.553-2.276A1 1 0 0121 8.618v6.764a1 1 0 01-1.447.894L15 14M5 18h8a2 2 0 002-2V8a2 2 0 00-2-2H5a2 2 0 00-2 2v8a2 2 0 002 2z" />
        </svg>
      ),
      description: '探索精彩视频',
      color: 'from-purple-500 to-pink-500',
      gradient: true,
      onClick: () => showToast('视频号功能即将上线，敬请期待！')
    },
    {
      name: '扫一扫',
      icon: (
        <svg className="w-8 h-8" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M3 10h18M3 14h18m-9-4v8m-7 0h14a2 2 0 002-2V8a2 2 0 00-2-2H5a2 2 0 00-2 2v8a2 2 0 002 2z" />
        </svg>
      ),
      description: '扫描二维码',
      color: 'from-blue-500 to-cyan-500',
      gradient: true,
      onClick: () => setShowScanModal(true)
    },
    {
      name: '附近的人',
      icon: (
        <svg className="w-8 h-8" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M17.657 16.657L13.414 20.9a1.998 1.998 0 01-2.827 0l-4.244-4.243a8 8 0 1111.314 0z" />
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M15 11a3 3 0 11-6 0 3 3 0 016 0z" />
        </svg>
      ),
      description: '发现附近的朋友',
      color: 'from-indigo-500 to-blue-500',
      gradient: true,
      onClick: () => setShowNearbyModal(true)
    },
    {
      name: '创建群聊',
      icon: (
        <svg className="w-8 h-8" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0zm6 3a2 2 0 11-4 0 2 2 0 014 0zM7 10a2 2 0 11-4 0 2 2 0 014 0z" />
        </svg>
      ),
      description: '创建新的群聊',
      color: 'from-red-500 to-rose-500',
      gradient: true,
      onClick: () => setShowGroupModal(true)
    },
    {
      name: '添加好友',
      icon: (
        <svg className="w-8 h-8" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M18 9v3m0 0v3m0-3h3m-3 0h-3m-2-5a4 4 0 11-8 0 4 4 0 018 0zM3 20a6 6 0 0112 0v1H3v-1z" />
        </svg>
      ),
      description: '搜索添加好友',
      color: 'from-orange-500 to-amber-500',
      gradient: true,
      onClick: () => setShowAddFriendModal(true)
    },
    {
      name: '标签管理',
      icon: (
        <svg className="w-8 h-8" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M7 7h.01M7 3h5c.512 0 1.024.195 1.414.586l7 7a2 2 0 010 2.828l-7 7a2 2 0 01-2.828 0l-7-7A1.994 1.994 0 013 12V7a4 4 0 014-4z" />
        </svg>
      ),
      description: '管理好友标签',
      color: 'from-teal-500 to-cyan-500',
      gradient: true,
      onClick: () => navigate('/contacts')
    }
  ]

  return (
    <div className="h-screen flex flex-col bg-gradient-to-br from-gray-900 via-gray-800 to-gray-900">
      {/* Header */}
      <div className="bg-gradient-to-r from-blue-600 to-blue-700 px-4 py-6 shadow-lg">
        <h1 className="text-2xl font-bold text-white">发现</h1>
        <p className="text-blue-100 text-sm mt-1">探索更多可能</p>
      </div>

      {/* Features Grid */}
      <div className="flex-1 overflow-y-auto p-4">
        <div className="grid grid-cols-2 gap-3">
          {features.map((feature) => (
            <div
              key={feature.name}
              onClick={feature.onClick}
              className="bg-gray-800/80 backdrop-blur rounded-2xl p-4 flex flex-col items-center justify-center gap-3
                         hover:shadow-xl hover:scale-105 transition-all duration-200 cursor-pointer
                         border border-gray-700/50 group"
            >
              <div className={`bg-gradient-to-br ${feature.color} text-white p-3.5 rounded-2xl shadow-lg group-hover:shadow-xl transition-shadow`}>
                {feature.icon}
              </div>
              <div className="text-center">
                <div className="font-medium text-white text-sm">{feature.name}</div>
                <div className="text-xs text-gray-400 mt-0.5">{feature.description}</div>
              </div>
            </div>
          ))}
        </div>

        {/* Official Accounts Section */}
        <div className="mt-6">
          <h2 className="text-lg font-semibold text-white mb-3">官方账号</h2>
          <div className="bg-gray-800/80 backdrop-blur rounded-2xl border border-gray-700/50 overflow-hidden">
            <div
              onClick={() => showToast('LispIM 官方账号即将上线！')}
              className="flex items-center gap-4 p-4 hover:bg-gray-700/50 transition-colors cursor-pointer border-b border-gray-700/50 last:border-0"
            >
              <div className="w-12 h-12 rounded-full bg-gradient-to-br from-blue-500 to-blue-600 flex items-center justify-center text-white shadow-lg">
                <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M13 10V3L4 14h7v7l9-11h-7z" />
                </svg>
              </div>
              <div className="flex-1">
                <div className="font-medium text-white">LispIM 官方</div>
                <div className="text-xs text-gray-400">企业级即时通讯系统</div>
              </div>
              <svg className="w-5 h-5 text-gray-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 5l7 7-7 7" />
              </svg>
            </div>
            <div
              onClick={() => showToast('系统通知账号即将上线！')}
              className="flex items-center gap-4 p-4 hover:bg-gray-700/50 transition-colors cursor-pointer border-b border-gray-700/50 last:border-0"
            >
              <div className="w-12 h-12 rounded-full bg-gradient-to-br from-red-500 to-red-600 flex items-center justify-center text-white shadow-lg">
                <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M15 17h5l-1.405-1.405A2.032 2.032 0 0118 14.158V11a6.002 6.002 0 00-4-5.659V5a2 2 0 10-4 0v.341C7.67 6.165 6 8.388 6 11v3.159c0 .538-.214 1.055-.595 1.436L4 17h5m6 0v1a3 3 0 11-6 0v-1m6 0H9" />
                </svg>
              </div>
              <div className="flex-1">
                <div className="font-medium text-white">系统通知</div>
                <div className="text-xs text-gray-400">重要系统消息通知</div>
              </div>
              <svg className="w-5 h-5 text-gray-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 5l7 7-7 7" />
              </svg>
            </div>
          </div>
        </div>

        {/* More Features */}
        <div className="mt-6 text-center">
          <p className="text-gray-500 text-sm">更多功能敬请期待...</p>
        </div>
      </div>

      {/* Modals */}
      {showMoments && <MomentsFeed onBack={() => setShowMoments(false)} />}
      {showStatusStories && <UserStatusStories onClose={() => setShowStatusStories(false)} />}
      {showScanModal && <ScanModal onClose={() => setShowScanModal(false)} />}
      {showNearbyModal && <NearbyPeopleModal onClose={() => setShowNearbyModal(false)} />}
      {showAddFriendModal && <AddFriendModal onClose={() => setShowAddFriendModal(false)} />}
      {showGroupModal && <GroupModal isOpen={showGroupModal} onClose={() => setShowGroupModal(false)} />}

      {/* Toast Notification */}
      {toast.visible && (
        <div className="fixed top-20 left-1/2 transform -translate-x-1/2 bg-gray-800 text-white px-6 py-3 rounded-lg shadow-lg z-50 animate-fade-in">
          {toast.message}
        </div>
      )}
    </div>
  )
}

export default Discover
