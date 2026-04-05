import React, { useState, useEffect } from 'react'
import { getApiClient, Friend } from '@/utils/api-client'

interface ContactBlacklistModalProps {
  onClose: () => void
  onSelect: (friendId: string) => void
}

const ContactBlacklistModal: React.FC<ContactBlacklistModalProps> = ({ onClose, onSelect }) => {
  const [blacklist, setBlacklist] = useState<Friend[]>([])
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    loadBlacklist()
  }, [])

  const loadBlacklist = async () => {
    setLoading(true)
    try {
      const api = getApiClient()
      const response = await api.getBlacklist()
      if (response.success && response.data) {
        setBlacklist(response.data)
      }
    } catch (error) {
      console.error('Failed to load blacklist:', error)
    } finally {
      setLoading(false)
    }
  }

  const handleUnblock = async (friendId: string) => {
    try {
      const api = getApiClient()
      const response = await api.removeFromBlacklist(friendId)
      if (response.success) {
        setBlacklist(blacklist.filter(f => f.id !== friendId))
        onSelect(friendId)
      }
    } catch (error) {
      console.error('Failed to unblock:', error)
    }
  }

  return (
    <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center" style={{ zIndex: 10000 }}>
      <div className="bg-white rounded-lg w-full max-w-md p-6 relative max-h-[80vh] overflow-y-auto" style={{ zIndex: 10001 }}>
        <div className="flex items-center justify-between mb-4">
          <h2 className="text-lg font-semibold text-gray-900">黑名单</h2>
          <button onClick={onClose} className="text-gray-500 hover:text-gray-700">
            <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>

        {/* Info */}
        <div className="mb-4 p-3 bg-red-50 rounded-lg">
          <div className="text-sm text-red-700">
            黑名单中的用户无法给你发送消息、查看你的朋友圈或添加你为好友
          </div>
        </div>

        {/* Blacklist */}
        {loading ? (
          <div className="text-center py-8 text-gray-400">加载中...</div>
        ) : blacklist.length === 0 ? (
          <div className="text-center py-8 text-gray-500">
            <svg className="w-16 h-16 mx-auto text-gray-300 mb-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M18.364 18.364A9 9 0 005.636 5.636m12.728 12.728A9 9 0 015.636 5.636m12.728 12.728L5.636 5.636" />
            </svg>
            <p>暂无黑名单用户</p>
          </div>
        ) : (
          <div className="space-y-2">
            {blacklist.map(friend => (
              <div
                key={friend.id}
                className="flex items-center gap-3 p-3 bg-gray-50 rounded-lg"
              >
                <div className="w-10 h-10 rounded-full bg-gray-400 flex items-center justify-center text-white font-medium flex-shrink-0">
                  {friend.avatarUrl ? (
                    <img src={friend.avatarUrl} alt={friend.displayName} className="w-10 h-10 rounded-full object-cover" />
                  ) : (
                    (friend.displayName || friend.username).charAt(0).toUpperCase()
                  )}
                </div>
                <div className="flex-1 min-w-0">
                  <div className="font-medium text-gray-900">{friend.displayName || friend.username}</div>
                  <div className="text-sm text-gray-500">@{friend.username}</div>
                </div>
                <button
                  onClick={() => handleUnblock(friend.id)}
                  className="px-3 py-1.5 bg-white border border-gray-300 text-gray-700 text-sm rounded-lg hover:bg-gray-50 transition-colors"
                >
                  移出
                </button>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  )
}

export default ContactBlacklistModal
