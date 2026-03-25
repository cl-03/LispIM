import React, { useState, useEffect, useMemo } from 'react'
import { useNavigate } from 'react-router-dom'
import { getApiClient, Friend } from '@/utils/api-client'
import AddFriendModal from './AddFriendModal'

const Contacts: React.FC = () => {
  const navigate = useNavigate()
  const [friends, setFriends] = useState<Friend[]>([])
  const [loading, setLoading] = useState(true)
  const [showAddFriendModal, setShowAddFriendModal] = useState(false)
  const [searchQuery, setSearchQuery] = useState('')

  useEffect(() => {
    loadFriends()
  }, [])

  const loadFriends = async () => {
    try {
      const api = getApiClient()
      const response = await api.getFriends()
      if (response.success && response.data) {
        setFriends(response.data)
      }
    } catch (error) {
      console.error('Failed to load friends:', error)
    } finally {
      setLoading(false)
    }
  }

  const openChat = (conversationId: number) => {
    navigate(`/?conv=${conversationId}`)
  }

  // 过滤好友列表
  const filteredFriends = useMemo(() => {
    if (!searchQuery.trim()) return friends
    const query = searchQuery.toLowerCase()
    return friends.filter(friend =>
      friend.displayName?.toLowerCase().includes(query) ||
      friend.username.toLowerCase().includes(query)
    )
  }, [friends, searchQuery])

  return (
    <div className="h-screen flex flex-col bg-gray-900">
      {/* Header */}
      <div className="bg-gray-800 border-b border-gray-700 px-4 py-3">
        <div className="flex items-center justify-between mb-3">
          <h1 className="text-xl font-semibold text-white">联系人</h1>
          <button
            onClick={() => setShowAddFriendModal(true)}
            className="px-4 py-2 bg-blue-500 text-white rounded-lg hover:bg-blue-600 transition-colors text-sm"
          >
            添加好友
          </button>
        </div>
        {/* 搜索框 */}
        <div className="relative">
          <input
            type="text"
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            placeholder="搜索联系人..."
            className="w-full px-4 py-2 pl-10 bg-gray-700 border border-gray-600 rounded-lg
                     text-white text-sm placeholder-gray-500 focus:outline-none focus:ring-2
                     focus:ring-blue-500"
          />
          <svg
            className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-gray-500"
            fill="none"
            stroke="currentColor"
            viewBox="0 0 24 24"
          >
            <path
              strokeLinecap="round"
              strokeLinejoin="round"
              strokeWidth={2}
              d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z"
            />
          </svg>
        </div>
      </div>

      {/* Friends List */}
      <div className="flex-1 overflow-y-auto">
        {loading ? (
          <div className="flex items-center justify-center h-full">
            <div className="text-gray-400">加载中...</div>
          </div>
        ) : (
          <div className="divide-y divide-gray-700">
            {/* 系统管理员固定联系人 */}
            {!searchQuery && (
              <div
                onClick={() => openChat(2)}
                className="flex items-center px-4 py-3 hover:bg-gray-800 cursor-pointer transition-colors"
              >
                <div className="w-12 h-12 rounded-full bg-red-500 flex items-center justify-center text-white">
                  <svg className="w-7 h-7" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z" />
                  </svg>
                </div>
                <div className="ml-3 flex-1">
                  <div className="font-medium text-white">系统管理员</div>
                  <div className="text-sm text-gray-500">有任何问题都可以联系我</div>
                </div>
                <div className="w-2.5 h-2.5 bg-green-500 rounded-full border-2 border-gray-900"></div>
              </div>
            )}

            {/* 分组标题 */}
            {!searchQuery && filteredFriends.length > 0 && (
              <div className="px-4 py-2 bg-gray-800/50">
                <div className="text-xs text-gray-500 font-medium">好友 ({filteredFriends.length})</div>
              </div>
            )}

            {/* 好友列表 */}
            {filteredFriends.length === 0 && !searchQuery ? (
              <div className="py-8 text-center text-gray-400">
                <p>暂无好友</p>
                <p className="text-sm mt-2">点击"添加好友"开始添加</p>
              </div>
            ) : filteredFriends.length === 0 && searchQuery ? (
              <div className="py-8 text-center text-gray-400">
                <p>没有找到匹配的联系人</p>
              </div>
            ) : (
              filteredFriends.map((friend) => (
                <div
                  key={friend.id}
                  className="flex items-center px-4 py-3 hover:bg-gray-800 cursor-pointer transition-colors"
                >
                  <div className="w-12 h-12 rounded-full bg-blue-500 flex items-center justify-center text-white font-medium relative flex-shrink-0">
                    {friend.avatarUrl ? (
                      <img src={friend.avatarUrl} alt={friend.displayName} className="w-12 h-12 rounded-full object-cover" />
                    ) : (
                      (friend.displayName || friend.username).charAt(0).toUpperCase()
                    )}
                    <div className="absolute bottom-0 right-0 w-3 h-3 bg-green-500 rounded-full border-2 border-gray-900"></div>
                  </div>
                  <div className="ml-3 flex-1 min-w-0">
                    <div className="font-medium text-white truncate">{friend.displayName || friend.username}</div>
                    <div className="text-sm text-gray-400 truncate">{friend.username}</div>
                  </div>
                </div>
              ))
            )}
          </div>
        )}
      </div>

      {/* Add Friend Modal */}
      {showAddFriendModal && (
        <AddFriendModal onClose={() => setShowAddFriendModal(false)} />
      )}
    </div>
  )
}

export default Contacts
