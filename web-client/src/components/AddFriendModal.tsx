import React, { useState } from 'react'
import { getApiClient, UserSearchResult, createApiClient } from '@/utils/api-client'
import { useAppStore } from '@/store/appStore'

interface AddFriendModalProps {
  onClose: () => void
}

const AddFriendModal: React.FC<AddFriendModalProps> = ({ onClose }) => {
  const { token } = useAppStore()
  const [searchQuery, setSearchQuery] = useState('')
  const [searchResults, setSearchResults] = useState<UserSearchResult[]>([])
  const [loading, setLoading] = useState(false)
  const [message, setMessage] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [successMsg, setSuccessMsg] = useState<string | null>(null)

  const handleSearch = async () => {
    setError(null)
    setSuccessMsg(null)
    if (!searchQuery.trim()) {
      setError('请输入搜索内容')
      return
    }

    setLoading(true)
    try {
      // 确保 API 客户端已初始化
      let api
      try {
        api = getApiClient()
      } catch {
        // 如果 API 客户端未初始化，创建新的实例
        const baseURL = (import.meta as any).env.VITE_API_URL || 'http://localhost:3000'
        createApiClient({ baseURL, token: token || undefined })
        api = getApiClient()
      }

      const response = await api.searchUsers(searchQuery)
      if (response.success && response.data) {
        if (response.data.length === 0) {
          setError('未找到匹配的用户')
        } else {
          setSearchResults(response.data)
        }
      } else {
        setError(response.error?.message || '未找到用户')
      }
    } catch (err) {
      console.error('[AddFriendModal] Search failed:', err)
      const errorMessage = err instanceof Error ? err.message : '搜索失败，请稍后重试'
      setError(errorMessage)
    } finally {
      setLoading(false)
    }
  }

  const handleSendRequest = async (userId: string) => {
    try {
      let api
      try {
        api = getApiClient()
      } catch {
        const baseURL = (import.meta as any).env.VITE_API_URL || 'http://localhost:3000'
        createApiClient({ baseURL, token: token || undefined })
        api = getApiClient()
      }

      const response = await api.sendFriendRequest(userId, message || undefined)
      if (response.success) {
        setSuccessMsg('好友请求已发送')
        setError(null)
        setMessage('')
        setSearchResults([])
        setSearchQuery('')
        setTimeout(() => onClose(), 1500)
      } else {
        setError(`发送失败：${response.error?.message || '未知错误'}`)
      }
    } catch (err) {
      console.error('[AddFriendModal] Send request failed:', err)
      setError('发送失败，请稍后重试')
    }
  }

  return (
    <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center" style={{ zIndex: 9999 }}>
      <div className="bg-white rounded-lg w-full max-w-md p-6 relative" style={{ zIndex: 10000 }}>
        <div className="flex items-center justify-between mb-4">
          <h2 className="text-lg font-semibold text-gray-900">添加好友</h2>
          <button onClick={onClose} className="text-gray-500 hover:text-gray-700">
            <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>

        {/* Search */}
        <div className="flex gap-2 mb-4">
          <input
            type="text"
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            placeholder="搜索用户名或昵称"
            className="flex-1 px-3 py-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500 text-gray-900 bg-white"
            onKeyDown={(e) => e.key === 'Enter' && handleSearch()}
          />
          <button
            onClick={handleSearch}
            disabled={loading}
            className="px-4 py-2 bg-blue-500 text-white rounded-lg hover:bg-blue-600 disabled:opacity-50 whitespace-nowrap"
          >
            {loading ? '搜索中...' : '搜索'}
          </button>
        </div>

        {/* Error Message */}
        {error && (
          <div className="mb-4 p-3 bg-red-50 border border-red-200 rounded-lg text-red-600 text-sm">
            {error}
          </div>
        )}

        {/* Success Message */}
        {successMsg && (
          <div className="mb-4 p-3 bg-green-50 border border-green-200 rounded-lg text-green-600 text-sm">
            {successMsg}
          </div>
        )}

        {/* Search Results */}
        {searchResults.length > 0 && (
          <div className="max-h-64 overflow-y-auto border rounded-lg">
            {searchResults.map((user) => (
              <div
                key={user.id}
                className="flex items-center justify-between px-4 py-3 border-b last:border-b-0 hover:bg-gray-50"
              >
                <div className="flex items-center gap-3">
                  <div className="w-10 h-10 rounded-full bg-gray-200 flex items-center justify-center overflow-hidden">
                    {user.avatarUrl ? (
                      <img src={user.avatarUrl} alt={user.displayName} className="w-10 h-10 object-cover" />
                    ) : (
                      <span className="text-gray-600 font-medium">
                        {(user.displayName || user.username).charAt(0).toUpperCase()}
                      </span>
                    )}
                  </div>
                  <div>
                    <div className="font-medium text-gray-900">{user.displayName || user.username}</div>
                    <div className="text-sm text-gray-500">@{user.username}</div>
                  </div>
                </div>
                <button
                  onClick={() => handleSendRequest(user.id)}
                  className="px-3 py-1.5 bg-blue-500 text-white text-sm rounded hover:bg-blue-600 transition-colors"
                >
                  添加
                </button>
              </div>
            ))}
          </div>
        )}

        {/* Message */}
        <div className="mt-4">
          <label className="block text-sm text-gray-600 mb-1">验证消息（可选）</label>
          <textarea
            value={message}
            onChange={(e) => setMessage(e.target.value)}
            placeholder="我是..."
            className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500 resize-none text-gray-900 bg-white"
            rows={3}
          />
        </div>

        {/* Actions */}
        <div className="flex justify-end gap-2 mt-4">
          <button
            onClick={onClose}
            className="px-4 py-2 text-gray-700 bg-gray-100 rounded-lg hover:bg-gray-200 transition-colors"
          >
            取消
          </button>
        </div>
      </div>
    </div>
  )
}

export default AddFriendModal
