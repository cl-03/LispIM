import React, { useState } from 'react'
import { useAppStore } from '@/store/appStore'
import ConversationList from './ConversationList'
import MessageList from './MessageList'
import MessageInput from './MessageInput'
import UserPanel from './UserPanel'

const Chat: React.FC = () => {
  const { user, activeConversationId } = useAppStore()
  const [sidebarOpen, setSidebarOpen] = useState(true)

  return (
    <div className="h-screen flex bg-primary-main">
      {/* 侧边栏 */}
      <div
        className={`${
          sidebarOpen ? 'w-80' : 'w-0'
        } transition-all duration-300 overflow-hidden bg-primary-dark border-r border-primary-accent`}
      >
        <div className="h-full flex flex-col">
          {/* 用户信息面板 */}
          <UserPanel user={user!} onToggleSidebar={() => setSidebarOpen(!sidebarOpen)} />

          {/* 会话列表 */}
          <ConversationList />
        </div>
      </div>

      {/* 主聊天区域 */}
      <div className="flex-1 flex flex-col min-w-0">
        {activeConversationId ? (
          <>
            {/* 消息列表 */}
            <MessageList conversationId={activeConversationId} />

            {/* 消息输入框 */}
            <MessageInput conversationId={activeConversationId} />
          </>
        ) : (
          <div className="flex-1 flex items-center justify-center text-gray-500">
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
