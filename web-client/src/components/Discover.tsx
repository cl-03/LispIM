import React, { useState } from 'react'
import AddFriendModal from './AddFriendModal'

const Discover: React.FC = () => {
  const [showScanModal, setShowScanModal] = useState(false)
  const [showAddFriendModal, setShowAddFriendModal] = useState(false)

  const features = [
    {
      name: '朋友圈',
      icon: (
        <svg className="w-8 h-8" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z" />
        </svg>
      ),
      description: '分享生活点滴',
      color: 'bg-green-500',
      onClick: () => alert('朋友圈功能开发中...')
    },
    {
      name: '视频号',
      icon: (
        <svg className="w-8 h-8" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M15 10l4.553-2.276A1 1 0 0121 8.618v6.764a1 1 0 01-1.447.894L15 14M5 18h8a2 2 0 002-2V8a2 2 0 00-2-2H5a2 2 0 00-2 2v8a2 2 0 002 2z" />
        </svg>
      ),
      description: '探索精彩视频',
      color: 'bg-purple-500',
      onClick: () => alert('视频号功能开发中...')
    },
    {
      name: '扫一扫',
      icon: (
        <svg className="w-8 h-8" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M3 10h18M3 14h18m-9-4v8m-7 0h14a2 2 0 002-2V8a2 2 0 00-2-2H5a2 2 0 00-2 2v8a2 2 0 002 2z" />
        </svg>
      ),
      description: '扫描二维码',
      color: 'bg-blue-500',
      onClick: () => setShowScanModal(true)
    },
    {
      name: '添加好友',
      icon: (
        <svg className="w-8 h-8" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M18 9v3m0 0v3m0-3h3m-3 0h-3m-2-5a4 4 0 11-8 0 4 4 0 018 0zM3 20a6 6 0 0112 0v1H3v-1z" />
        </svg>
      ),
      description: '搜索添加好友',
      color: 'bg-red-500',
      onClick: () => setShowAddFriendModal(true)
    }
  ]

  return (
    <div className="h-screen flex flex-col bg-gray-900">
      {/* Header */}
      <div className="bg-gray-800 border-b border-gray-700 px-4 py-3">
        <h1 className="text-xl font-semibold text-white">发现</h1>
      </div>

      {/* Features Grid */}
      <div className="flex-1 overflow-y-auto p-4">
        <div className="grid grid-cols-2 gap-4">
          {features.map((feature) => (
            <div
              key={feature.name}
              onClick={feature.onClick}
              className="bg-gray-800 rounded-xl p-6 flex flex-col items-center justify-center gap-3 hover:shadow-md transition-shadow cursor-pointer border border-gray-700"
            >
              <div className={`${feature.color} text-white p-4 rounded-full`}>
                {feature.icon}
              </div>
              <div className="text-center">
                <div className="font-medium text-white">{feature.name}</div>
                <div className="text-sm text-gray-400">{feature.description}</div>
              </div>
            </div>
          ))}
        </div>

        {/* Scan QR Modal */}
        {showScanModal && (
          <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50">
            <div className="bg-gray-800 rounded-lg p-6 max-w-sm w-full mx-4 border border-gray-700">
              <div className="flex items-center justify-between mb-4">
                <h2 className="text-lg font-semibold text-white">扫一扫</h2>
                <button onClick={() => setShowScanModal(false)} className="text-gray-400 hover:text-white">
                  <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
                  </svg>
                </button>
              </div>
              <div className="aspect-square bg-gray-700 rounded-lg flex items-center justify-center mb-4">
                <div className="text-center text-gray-400">
                  <svg className="w-16 h-16 mx-auto mb-2 opacity-50" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M3 9a2 2 0 012-2h.93a2 2 0 001.664-.89l.812-1.22A2 2 0 0110.07 4h3.86a2 2 0 011.664.89l.812 1.22A2 2 0 0018.07 7H19a2 2 0 012 2v9a2 2 0 01-2 2H5a2 2 0 01-2-2V9z" />
                  </svg>
                  <p>摄像头</p>
                  <p className="text-sm mt-2">摄像头功能开发中</p>
                </div>
              </div>
              <button
                onClick={() => setShowScanModal(false)}
                className="w-full py-2 bg-blue-500 text-white rounded-lg hover:bg-blue-600"
              >
                关闭
              </button>
            </div>
          </div>
        )}

        {/* Add Friend Modal */}
        {showAddFriendModal && (
          <AddFriendModal onClose={() => setShowAddFriendModal(false)} />
        )}

        {/* Coming Soon */}
        <div className="mt-8 text-center text-gray-500 text-sm">
          更多功能敬请期待...
        </div>
      </div>
    </div>
  )
}

export default Discover
