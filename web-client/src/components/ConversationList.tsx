import React, { useState, useMemo, useEffect } from 'react'
import { useAppStore } from '@/store/appStore'
import { getMessagePreview, formatMessageTime } from '@/utils/message'
import { getApiClient } from '@/utils/api-client'
import type { Conversation } from '@/types'

// 系统管理员固定会话
const SYSTEM_ADMIN: Conversation = {
  id: 2,
  type: 'direct',
  participants: ['2'],
  participantUsers: [{
    id: '2',
    username: 'system_admin',
    displayName: '系统管理员',
    status: 'online',
    avatar: undefined
  } as any],
  creator_id: 'system',
  last_activity: Date.now(),
  last_sequence: 0,
  is_pinned: false,
  is_muted: false,
  unread_count: 0,
  unreadCount: 0,
  createdAt: Date.now(),
  updatedAt: Date.now()
}

// 文件传输助手固定会话
const FILE_TRANSFER_ASSISTANT: Conversation = {
  id: 999999,
  type: 'direct',
  participants: [],
  participantUsers: [],
  creator_id: 'system',
  last_activity: Date.now(),
  last_sequence: 0,
  is_pinned: false,
  is_muted: false,
  unread_count: 0,
  unreadCount: 0,
  createdAt: Date.now(),
  updatedAt: Date.now()
}

const ConversationList: React.FC = () => {
  const { conversations, activeConversationId, setActiveConversationId, addConversation, user } = useAppStore()
  const [searchQuery, setSearchQuery] = useState('')
  const [initialized, setInitialized] = useState(false)
  const [contextMenu, setContextMenu] = useState<{
    visible: boolean
    x: number
    y: number
    conversationId: number | null
  }>({ visible: false, x: 0, y: 0, conversationId: null })

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
    // eslint-disable-next-line react-hooks/exhaustive-deps
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

  // 右键菜单处理
  const handleContextMenu = (e: React.MouseEvent, conversationId: number) => {
    e.preventDefault()
    setContextMenu({
      visible: true,
      x: e.clientX,
      y: e.clientY,
      conversationId
    })
  }

  // 关闭右键菜单
  useEffect(() => {
    const handleClick = () => setContextMenu({ visible: false, x: 0, y: 0, conversationId: null })
    document.addEventListener('click', handleClick)
    return () => document.removeEventListener('click', handleClick)
  }, [])

  // 置顶/取消置顶会话
  const handleTogglePin = async () => {
    if (!contextMenu.conversationId) return
    const api = getApiClient()
    try {
      const conv = conversations.find(c => c.id === contextMenu.conversationId)
      if (conv?.is_pinned) {
        await api.unpinConversation(contextMenu.conversationId)
      } else {
        await api.pinConversation(contextMenu.conversationId)
      }
    } catch {
      // 忽略错误
    } finally {
      setContextMenu({ visible: false, x: 0, y: 0, conversationId: null })
    }
  }

  // 切换免打扰
  const handleToggleMute = async () => {
    if (!contextMenu.conversationId) return
    const api = getApiClient()
    try {
      const conv = conversations.find(c => c.id === contextMenu.conversationId)
      if (conv?.is_muted) {
        await api.unmuteConversation(contextMenu.conversationId)
      } else {
        await api.muteConversation(contextMenu.conversationId)
      }
    } catch {
      // 忽略错误
    } finally {
      setContextMenu({ visible: false, x: 0, y: 0, conversationId: null })
    }
  }

  // 删除会话
  const handleDeleteConversation = async () => {
    if (!contextMenu.conversationId) return
    if (!confirm('确定要删除这个会话吗？')) return
    const api = getApiClient()
    try {
      await api.deleteConversation(contextMenu.conversationId)
    } catch {
      // 忽略错误
    } finally {
      setContextMenu({ visible: false, x: 0, y: 0, conversationId: null })
    }
  }

  return (
    <div className="flex-1 flex flex-col overflow-hidden bg-gradient-to-b from-gray-900/50 to-gray-900">
      {/* 搜索框 */}
      <div className="p-3">
        <div className="relative">
          <input
            type="text"
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            placeholder="搜索会话..."
            className="w-full px-4 py-3 pl-11 bg-gray-800/80 backdrop-blur border border-gray-700/50 rounded-xl
                     text-white text-sm placeholder-gray-500 focus:outline-none focus:ring-2 focus:ring-blue-500/50
                     focus:border-transparent transition-all duration-300 hover:border-gray-600
                     shadow-[0_2px_10px_rgba(0,0,0,0.2)] focus:shadow-[0_4px_20px_rgba(59,130,246,0.2)]"
          />
          <svg
            className="absolute left-3.5 top-1/2 -translate-y-1/2 w-5 h-5 text-gray-500"
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
          <div className="p-8 text-center">
            <svg className="w-16 h-16 mx-auto text-gray-600 mb-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z" />
            </svg>
            <p className="text-gray-500 text-sm">
              {searchQuery ? '没有找到匹配的会话' : '暂无会话'}
            </p>
          </div>
        ) : (
          <div className="space-y-1.5 p-2">
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
                  onContextMenu={(e) => handleContextMenu(e, conv.id)}
                  className={`w-full p-3 rounded-xl transition-all duration-300 text-left group ${
                    isActive
                      ? 'bg-gradient-to-r from-blue-600/25 to-indigo-600/25 border border-blue-500/40 shadow-[0_4px_20px_rgba(59,130,246,0.25)] scale-[1.02]'
                      : 'hover:bg-gray-800/60 border border-transparent hover:border-gray-600/50 hover:shadow-lg hover:scale-[1.01]'
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
                          )} rounded-full border-2 border-gray-900 animate-pulse shadow-[0_0_10px_currentColor]`}
                        />
                      )}
                    </div>

                    {/* 内容 */}
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center justify-between">
                        <div className="flex items-center gap-1.5 flex-1 min-w-0">
                          <h4 className="text-white font-semibold text-sm truncate">
                            {isSystemAdmin ? '系统管理员' : isFileAssistant ? '文件传输助手' : (conv.type === 'group' ? conv.name : participant?.displayName)}
                          </h4>
                          {/* 免打扰图标 */}
                          {conv.is_muted && (
                            <svg className="w-3.5 h-3.5 text-gray-500 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5.586 15H4a1 1 0 01-1-1v-4a1 1 0 011-1h1.586l4.707-4.707C10.923 3.663 12 4.109 12 5v14c0 .891-1.077 1.337-1.707.707L5.586 15z" />
                              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M3 3l18 18" />
                            </svg>
                          )}
                        </div>
                        {lastMessage && (
                          <span className="text-xs text-gray-500 flex-shrink-0 ml-2">
                            {formatMessageTime((lastMessage as any).timestamp || (lastMessage as any).createdAt || 0)}
                          </span>
                        )}
                      </div>
                      <div className="flex items-center justify-between mt-1.5">
                        <p className="text-xs text-gray-400 truncate flex-1">
                          {isSystemAdmin ? (
                            <span className="text-gray-500 italic">有任何问题都可以联系我</span>
                          ) : isFileAssistant ? (
                            <span className="text-gray-500 italic">文件、图片、消息免加密存储</span>
                          ) : lastMessage ? (
                            <>
                              {lastMessage.senderId === user?.id && <span className="text-blue-400 mr-1">你：</span>}
                              {getMessagePreview(lastMessage.content || '', 30)}
                            </>
                          ) : (
                            '暂无消息'
                          )}
                        </p>
                        {conv.unreadCount > 0 && (
                          <span className="ml-2 px-2.5 py-1 text-xs font-medium bg-gradient-to-r from-blue-500 to-indigo-600 text-white rounded-full min-w-[24px] shadow-[0_2px_10px_rgba(59,130,246,0.4)] animate-pulse">
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

      {/* 右键菜单 */}
      <ConversationContextMenu
        visible={contextMenu.visible}
        x={contextMenu.x}
        y={contextMenu.y}
        conversation={conversations.find(c => c.id === contextMenu.conversationId) || null}
        onTogglePin={handleTogglePin}
        onToggleMute={handleToggleMute}
        onDelete={handleDeleteConversation}
      />
    </div>
  )
}

// 右键菜单组件
interface ConversationContextMenuProps {
  visible: boolean
  x: number
  y: number
  conversation: Conversation | null
  onTogglePin: () => void
  onToggleMute: () => void
  onDelete: () => void
}

function ConversationContextMenu({
  visible,
  x,
  y,
  conversation,
  onTogglePin,
  onToggleMute,
  onDelete
}: ConversationContextMenuProps) {
  if (!visible || !conversation) return null

  return (
    <div
      className="fixed bg-gradient-to-br from-gray-800 to-gray-900 border border-gray-700/50 rounded-xl shadow-[0_10px_40px_rgba(0,0,0,0.5)] z-50 py-2 min-w-[180px] backdrop-blur-xl"
      style={{ left: x, top: y }}
      onClick={(e) => e.stopPropagation()}
    >
      <div className="px-3 py-2 border-b border-gray-700/50 mb-1 bg-gradient-to-r from-gray-700/30 to-transparent">
        <p className="text-xs text-gray-400 truncate font-medium">
          {conversation.type === 'group' ? conversation.name : conversation.participantUsers?.find(p => p.id !== conversation.creatorId)?.displayName || '未知会话'}
        </p>
      </div>
      <button
        onClick={onTogglePin}
        className="w-full px-4 py-2.5 text-left text-sm text-gray-300 hover:bg-gradient-to-r hover:from-gray-700/50 hover:to-gray-700/30 transition-all duration-200 flex items-center gap-3"
      >
        <svg className="w-4 h-4" fill={conversation.is_pinned ? 'currentColor' : 'none'} stroke="currentColor" viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 5a2 2 0 012-2h10a2 2 0 012 2v16l-7-3.5L5 21V5z" />
        </svg>
        {conversation.is_pinned ? '取消置顶' : '置顶会话'}
      </button>
      <button
        onClick={onToggleMute}
        className="w-full px-4 py-2.5 text-left text-sm text-gray-300 hover:bg-gradient-to-r hover:from-gray-700/50 hover:to-gray-700/30 transition-all duration-200 flex items-center gap-3"
      >
        <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5.586 15H4a1 1 0 01-1-1v-4a1 1 0 011-1h1.586l4.707-4.707C10.923 3.663 12 4.109 12 5v14c0 .891-1.077 1.337-1.707.707L5.586 15z" />
        </svg>
        {conversation.is_muted ? '取消免打扰' : '设为免打扰'}
      </button>
      <div className="border-t border-gray-700/50 my-1"></div>
      <button
        onClick={onDelete}
        className="w-full px-4 py-2.5 text-left text-sm text-red-400 hover:bg-red-500/10 transition-all duration-200 flex items-center gap-3 hover:shadow-[0_0_15px_rgba(239,68,68,0.2)]"
      >
        <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
        </svg>
        删除会话
      </button>
    </div>
  )
}

export default ConversationList
