import React, { useState, useEffect } from 'react'
import { useSearchParams } from 'react-router-dom'
import { useAppStore } from '@/store/appStore'
import ConversationList from './ConversationList'
import MessageList from './MessageList'
import MessageInput from './MessageInput'

const Chat: React.FC = () => {
  const [searchParams] = useSearchParams()
  const { activeConversationId, loadConversations, setActiveConversationId } = useAppStore()
  const [showList, setShowList] = useState(true)

  // 加载会话列表
  useEffect(() => {
    loadConversations()
  }, [loadConversations])

  // 从 URL 参数读取 conversation ID
  useEffect(() => {
    const convId = searchParams.get('conv')
    if (convId) {
      const id = parseInt(convId, 10)
      if (!isNaN(id)) {
        setActiveConversationId(id)
        setShowList(false)
      }
    }
  }, [searchParams, setActiveConversationId])

  // When a conversation is selected, hide the list on mobile
  useEffect(() => {
    if (activeConversationId) {
      setShowList(false)
    }
  }, [activeConversationId])

  return (
    <div className="h-full flex flex-col bg-gray-900">
      {/* Conversation List - Hidden when chatting on mobile */}
      <div
        className={`${
          showList ? 'w-full md:w-80' : 'hidden md:block md:w-80'
        } transition-all duration-300 bg-gray-800 border-r border-gray-700`}
      >
        <div className="h-full flex flex-col">
          {/* Header */}
          <div className="px-4 py-3 border-b border-gray-700">
            <h2 className="text-lg font-semibold text-white">消息</h2>
          </div>

          {/* Conversation List */}
          <ConversationList />
        </div>
      </div>

      {/* Main Chat Area */}
      <div className="flex-1 flex flex-col min-w-0">
        {activeConversationId ? (
          <>
            {/* Message List */}
            <MessageList conversationId={activeConversationId} />

            {/* Message Input */}
            <MessageInput conversationId={activeConversationId} />
          </>
        ) : (
          <div className="flex-1 flex items-center justify-center text-gray-400">
            <div className="text-center">
              <svg
                className="w-16 h-16 mx-auto mb-4 opacity-50"
                fill="none"
                stroke="currentColor"
                viewBox="0 0 24 24"
              >
                <path
                  strokeLinecap="round"
                  strokeLinejoin="round"
                  strokeWidth={1.5}
                  d="M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z"
                />
              </svg>
              <p className="text-lg">选择一个会话开始聊天</p>
            </div>
          </div>
        )}
      </div>
    </div>
  )
}

export default Chat
