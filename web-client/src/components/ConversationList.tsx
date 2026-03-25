import React, { useState, useMemo, useEffect } from 'react'
import { useAppStore } from '@/store/appStore'
import { getMessagePreview, formatMessageTime } from '@/utils/message'
import type { Conversation } from '@/types'

// 系统管理员固定会话
const SYSTEM_ADMIN: Conversation = {
  id: 2, // 系统管理员 ID
  name: '系统管理员',
  type: 'direct',
  participants: ['2'],
  participantUsers: [{
    id: '2',
    username: 'system_admin',
    displayName: '系统管理员',
    status: 'online',
    avatar: undefined
  } as any],
  unreadCount: 0,
  createdAt: Date.now(),
  updatedAt: Date.now(),
  creatorId: 'system'
}

// 文件传输助手固定会话
const FILE_TRANSFER_ASSISTANT: Conversation = {
  id: 999999, // 使用特殊 ID
  name: '文件传输助手',
  type: 'direct',
  participants: [],
  participantUsers: [],
  unreadCount: 0,
  createdAt: Date.now(),
  updatedAt: Date.now(),
  creatorId: 'system'
}

const ConversationList: React.FC = () => {
  const { conversations, activeConversationId, setActiveConversationId, addConversation, user } = useAppStore()
  const [searchQuery, setSearchQuery] = useState('')
  const [initialized, setInitialized] = useState(false)

  // 初始化系统管理员和文件传输助手
  useEffect(() => {
    if (!initialized) {
      // 检查是否已存在系统管理员
      const systemAdminExists = conversations.some(c => c.id === SYSTEM_ADMIN.id)
      if (!systemAdminExists) {
        addConversation(SYSTEM_ADMIN as any)
      }
      // 检查是否已存在文件传输助手
      const fileAssistantExists = conversations.some(c => c.id === FILE_TRANSFER_ASSISTANT.id)
      if (!fileAssistantExists) {
        addConversation(FILE_TRANSFER_ASSISTANT as any)
      }
      setInitialized(true)
    }
  }, [initialized])

  const filteredConversations = useMemo(() => {
    // 将所有会话与系统管理员、文件传输助手合并，它们始终在顶部
    const otherConversations = conversations.filter(
      c => c.id !== SYSTEM_ADMIN.id && c.id !== FILE_TRANSFER_ASSISTANT.id
    )
    const allConversations: Conversation[] = [SYSTEM_ADMIN, FILE_TRANSFER_ASSISTANT, ...otherConversations]

    if (!searchQuery) return allConversations
    return allConversations.filter((conv) => {
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

  const renderAvatar = (conv: Conversation) => {
    // 系统管理员特殊图标
    if (conv.id === SYSTEM_ADMIN.id) {
      return (
        <div className="w-10 h-10 rounded-full bg-red-500 flex items-center justify-center text-white">
          <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z" />
          </svg>
        </div>
      )
    }

    // 文件传输助手特殊图标
    if (conv.id === FILE_TRANSFER_ASSISTANT.id) {
      return (
        <div className="w-10 h-10 rounded-full bg-blue-500 flex items-center justify-center text-white">
          <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M7 16a4 4 0 01-.88-7.903A5 5 0 1115.9 6L16 6a5 5 0 011 9.9M15 13l-3-3m0 0l-3 3m3-3v12" />
          </svg>
        </div>
      )
    }

    if (conv.avatar) {
      return <img src={conv.avatar} alt={conv.name} className="w-10 h-10 rounded-full" />
    }

    const participant = conv.participantUsers?.find((p) => p.id !== conv.creatorId)
    const displayName = participant?.displayName || '?'
    return (
      <div className="w-10 h-10 rounded-full bg-blue-500 flex items-center justify-center text-white font-semibold">
        {displayName.charAt(0).toUpperCase()}
      </div>
    )
  }

  return (
    <div className="flex-1 flex flex-col overflow-hidden bg-gray-900">
      {/* 搜索框 */}
      <div className="p-3">
        <div className="relative">
          <input
            type="text"
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            placeholder="搜索会话..."
            className="w-full px-4 py-2 pl-10 bg-gray-800 border border-gray-700 rounded-lg
                     text-white text-sm placeholder-gray-500 focus:outline-none focus:ring-1
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
              const isFileAssistant = conv.id === FILE_TRANSFER_ASSISTANT.id
              const isSystemAdmin = conv.id === SYSTEM_ADMIN.id

              return (
                <button
                  key={conv.id}
                  onClick={() => setActiveConversationId(conv.id)}
                  className={`w-full p-3 rounded-lg transition-colors text-left
                           ${
                             isActive
                               ? 'bg-gray-700'
                               : 'hover:bg-gray-800'
                           }`}
                >
                  <div className="flex items-start space-x-3">
                    {/* 头像 */}
                    <div className="relative flex-shrink-0">
                      {renderAvatar(conv)}
                      {!isFileAssistant && !isSystemAdmin && conv.type === 'direct' && participant && (
                        <div
                          className={`absolute bottom-0 right-0 w-2.5 h-2.5 ${getStatusColor(
                            participant.status
                          )} rounded-full border-2 border-gray-900`}
                        />
                      )}
                    </div>

                    {/* 内容 */}
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center justify-between">
                        <h4 className="text-white font-medium text-sm truncate">
                          {isSystemAdmin ? '系统管理员' : isFileAssistant ? '文件传输助手' : (conv.type === 'group' ? conv.name : participant?.displayName)}
                        </h4>
                        {lastMessage && (
                          <span className="text-xs text-gray-500 flex-shrink-0">
                            {formatMessageTime(lastMessage.createdAt)}
                          </span>
                        )}
                      </div>
                      <div className="flex items-center justify-between mt-1">
                        <p className="text-xs text-gray-400 truncate">
                          {isSystemAdmin ? (
                            <span className="text-gray-500">有任何问题都可以联系我</span>
                          ) : isFileAssistant ? (
                            <span className="text-gray-500">文件、图片、消息免加密存储</span>
                          ) : lastMessage ? (
                            <>
                              {lastMessage.senderId === user?.id && '你：'}
                              {getMessagePreview(lastMessage.content || '', 30)}
                            </>
                          ) : (
                            '暂无消息'
                          )}
                        </p>
                        {conv.unreadCount > 0 && (
                          <span className="ml-2 px-2 py-0.5 text-xs bg-blue-500 text-white rounded-full min-w-[20px]">
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
