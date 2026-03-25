import React, { useState, useMemo } from 'react'
import { useAppStore } from '@/store/appStore'
import { getMessagePreview, formatMessageTime } from '@/utils/message'

const ConversationList: React.FC = () => {
  const { conversations, activeConversationId, setActiveConversationId } = useAppStore()
  const [searchQuery, setSearchQuery] = useState('')

  const filteredConversations = useMemo(() => {
    if (!searchQuery) return conversations
    return conversations.filter((conv) => {
      if (conv.name?.toLowerCase().includes(searchQuery.toLowerCase())) return true
      const participant = conv.participantUsers?.find(
        (p) => p.displayName.toLowerCase().includes(searchQuery.toLowerCase())
      )
      return !!participant
    })
  }, [conversations, searchQuery])

  const getStatusColor = (status: string) => {
    const colors: Record<string, string> = {
      online: 'bg-green-500',
      offline: 'bg-gray-500',
      away: 'bg-yellow-500',
      busy: 'bg-red-500'
    }
    return colors[status] || 'bg-gray-500'
  }

  return (
    <div className="flex-1 flex flex-col overflow-hidden">
      {/* 搜索框 */}
      <div className="p-3">
        <div className="relative">
          <input
            type="text"
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            placeholder="搜索会话..."
            className="w-full px-4 py-2 pl-10 bg-primary-dark border border-primary-accent rounded-lg
                     text-white text-sm placeholder-gray-500 focus:outline-none focus:ring-1
                     focus:ring-primary-highlight"
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

      {/* 会话列表 */}
      <div className="flex-1 overflow-y-auto">
        {filteredConversations.length === 0 ? (
          <div className="p-4 text-center text-gray-500 text-sm">
            {searchQuery ? '没有找到匹配的会话' : '暂无会话'}
          </div>
        ) : (
          <div className="space-y-1 p-2">
            {filteredConversations.map((conv) => {
              const participant = conv.participantUsers?.find((p) => p.id !== conv.creatorId)
              const lastMessage = conv.lastMessage
              const isActive = conv.id === activeConversationId

              return (
                <button
                  key={conv.id}
                  onClick={() => setActiveConversationId(conv.id)}
                  className={`w-full p-3 rounded-lg transition-colors text-left
                           ${
                             isActive
                               ? 'bg-primary-accent'
                               : 'hover:bg-primary-light'
                           }`}
                >
                  <div className="flex items-start space-x-3">
                    {/* 头像 */}
                    <div className="relative flex-shrink-0">
                      {conv.avatar ? (
                        <img src={conv.avatar} alt={conv.name} className="w-10 h-10 rounded-full" />
                      ) : (
                        <div className="w-10 h-10 rounded-full bg-primary-accent flex items-center justify-center text-white font-semibold">
                          {conv.type === 'group'
                            ? conv.name?.charAt(0).toUpperCase()
                            : participant?.displayName.charAt(0).toUpperCase() || '?'}
                        </div>
                      )}
                      {conv.type === 'direct' && participant && (
                        <div
                          className={`absolute bottom-0 right-0 w-2.5 h-2.5 ${getStatusColor(
                            participant.status
                          )} rounded-full border-2 border-primary-dark`}
                        />
                      )}
                    </div>

                    {/* 内容 */}
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center justify-between">
                        <h4 className="text-white font-medium text-sm truncate">
                          {conv.type === 'group' ? conv.name : participant?.displayName}
                        </h4>
                        {lastMessage && (
                          <span className="text-xs text-gray-500 flex-shrink-0">
                            {formatMessageTime(lastMessage.createdAt)}
                          </span>
                        )}
                      </div>
                      <div className="flex items-center justify-between mt-1">
                        <p className="text-xs text-gray-400 truncate">
                          {lastMessage ? (
                            <>
                              {lastMessage.senderId === 'user-123' && '你：'}
                              {getMessagePreview(lastMessage.content || '', 30)}
                            </>
                          ) : (
                            '暂无消息'
                          )}
                        </p>
                        {conv.unreadCount > 0 && (
                          <span className="ml-2 px-2 py-0.5 text-xs bg-primary-highlight text-white rounded-full min-w-[20px]">
                            {conv.unreadCount > 99 ? '99+' : conv.unreadCount}
                          </span>
                        )}
                      </div>
                    </div>
                  </div>
                </button>
              )
            })}
          </div>
        )}
      </div>
    </div>
  )
}

export default ConversationList
