import React, { useState, useEffect } from 'react'
import { useSearchParams } from 'react-router-dom'
import { useAppStore } from '@/store/appStore'
import ConversationList from './ConversationList'
import MessageList from './MessageList'
import MessageInput from './MessageInput'
import { ChatFolders } from './ChatFolders'
import { UserStatusStories } from './UserStatusStories'
import { useKeyboardShortcuts } from '@/hooks/useKeyboardShortcuts'
import { NetworkIndicator } from './NetworkIndicator'

const Chat: React.FC = () => {
  const [searchParams] = useSearchParams()
  const { activeConversationId, loadConversations, setActiveConversationId } = useAppStore()
  const [showList, setShowList] = useState(true)
  const [showFolders, setShowFolders] = useState(false)
  const [showStatusStories, setShowStatusStories] = useState(false)
  const [replyingTo, setReplyingTo] = useState<{ id: number; senderName: string; content: string } | null>(null)
  const [showShortcutHelp, setShowShortcutHelp] = useState(false)

  // 键盘快捷键
  useKeyboardShortcuts({
    onSearch: () => {
      // 触发搜索事件
      const event = new CustomEvent('open-chat-search')
      window.dispatchEvent(event)
    },
    onClose: () => {
      setReplyingTo(null)
      setShowFolders(false)
      setShowStatusStories(false)
    },
    onNewChat: () => {
      // 新建聊天逻辑（可以在未来实现）
      console.log('新建聊天')
    },
    onOpenSettings: () => {
      setShowShortcutHelp(true)
    },
    enabled: !!activeConversationId
  })

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
    <div className="h-full flex flex-col bg-gradient-to-br from-gray-900 via-gray-800 to-gray-900">
      {/* Conversation List - Hidden when chatting on mobile */}
      <div
        className={`${
          showList ? 'w-full md:w-80' : 'hidden md:block md:w-80'
        } transition-all duration-300 bg-gradient-to-b from-gray-800/90 to-gray-800/70 backdrop-blur-xl border-r border-gray-700/50 shadow-2xl`}
      >
        <div className="h-full flex flex-col">
          {/* Header */}
          <div className="px-4 py-3.5 border-b border-gray-700/50 flex items-center justify-between bg-gradient-to-r from-blue-600/10 to-indigo-600/10 backdrop-blur-sm">
            <div>
              <h2 className="text-lg font-bold text-white drop-shadow-lg">消息</h2>
              <p className="text-xs text-gray-400 mt-0.5">保持连接，随时沟通</p>
            </div>
            <div className="flex items-center space-x-1">
              {/* 网络状态指示器 */}
              <NetworkIndicator />
              {/* 文件夹按钮 */}
              <button
                onClick={() => setShowFolders(!showFolders)}
                className={`p-2 text-gray-400 hover:text-white rounded-xl transition-all duration-200 ${
                  showFolders ? 'bg-gradient-to-r from-blue-500 to-indigo-600 text-white shadow-[0_0_15px_rgba(59,130,246,0.4)]' : 'hover:bg-gray-700/50 hover:shadow-lg'
                }`}
                title="聊天文件夹"
              >
                <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M3 7v10a2 2 0 002 2h14a2 2 0 002-2V9a2 2 0 00-2-2h-6l-2-2H5a2 2 0 00-2 2z" />
                </svg>
              </button>
              {/* 状态动态按钮 */}
              <button
                onClick={() => setShowStatusStories(!showStatusStories)}
                className={`p-2 text-gray-400 hover:text-white rounded-xl transition-all duration-200 ${
                  showStatusStories ? 'bg-gradient-to-r from-yellow-500 to-orange-500 text-white shadow-[0_0_15px_rgba(234,179,8,0.4)]' : 'hover:bg-gray-700/50 hover:shadow-lg'
                }`}
                title="状态动态"
              >
                <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M13 10V3L4 14h7v7l9-11h-7z" />
                </svg>
              </button>
            </div>
          </div>

          {/* 聊天文件夹 */}
          {showFolders && (
            <ChatFolders onClose={() => setShowFolders(false)} />
          )}

          {/* 用户状态动态 */}
          {showStatusStories && (
            <UserStatusStories onClose={() => setShowStatusStories(false)} />
          )}

          {/* Conversation List */}
          <ConversationList />
        </div>
      </div>

      {/* Main Chat Area */}
      <div className="flex-1 flex flex-col min-w-0">
        {activeConversationId ? (
          <>
            {/* Message List */}
            <MessageList
              conversationId={activeConversationId}
              onReply={(message) => setReplyingTo(message)}
            />

            {/* Message Input */}
            <MessageInput
              conversationId={activeConversationId}
              replyingTo={replyingTo}
              onCancelReply={() => setReplyingTo(null)}
            />
          </>
        ) : (
          <div className="flex-1 flex items-center justify-center text-gray-400">
            <div className="text-center max-w-md px-4">
              <div className="w-24 h-24 mx-auto mb-6 rounded-full bg-gradient-to-br from-blue-500/20 to-indigo-500/20 flex items-center justify-center shadow-[0_0_40px_rgba(59,130,246,0.3)] border border-blue-500/20">
                <svg
                  className="w-12 h-12 text-blue-400 drop-shadow-[0_0_10px_rgba(59,130,246,0.5)]"
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
              </div>
              <h3 className="text-xl font-semibold text-white mb-2 drop-shadow-lg">欢迎使用 LispIM</h3>
              <p className="text-gray-400 mb-6">选择一个会话开始聊天，或创建新的对话</p>
              <div className="flex items-center justify-center gap-2 text-sm text-gray-500 bg-gray-800/50 backdrop-blur rounded-xl p-3 border border-gray-700/50 shadow-lg">
                <svg className="w-4 h-4 text-blue-400 drop-shadow-[0_0_8px_rgba(59,130,246,0.5)]" fill="currentColor" viewBox="0 0 24 24">
                  <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-2 15l-5-5 1.41-1.41L10 14.17l7.59-7.59L19 8l-9 9z"/>
                </svg>
                按 <kbd className="px-2 py-0.5 bg-gradient-to-r from-gray-700 to-gray-600 rounded-lg text-gray-300 font-mono shadow-inner border border-gray-600">Ctrl+K</kbd> 快速搜索
              </div>
            </div>
          </div>
        )}
      </div>

      {/* 快捷键帮助 */}
      <ShortcutHelpModal visible={showShortcutHelp} onClose={() => setShowShortcutHelp(false)} />
    </div>
  )
}

// 快捷键帮助对话框
function ShortcutHelpModal({ visible, onClose }: { visible: boolean; onClose: () => void }) {
  if (!visible) return null

  const shortcuts = [
    { keys: 'Ctrl+K', description: '打开搜索' },
    { keys: 'Ctrl+Enter', description: '发送消息' },
    { keys: 'Esc', description: '关闭弹窗/取消回复' },
    { keys: 'Ctrl+Shift+N', description: '新建聊天' },
    { keys: 'Ctrl+,', description: '打开设置' },
  ]

  return (
    <div className="fixed inset-0 bg-black/70 backdrop-blur-sm z-50 flex items-center justify-center p-4" onClick={onClose}>
      <div className="bg-gradient-to-br from-gray-800 to-gray-900 rounded-2xl w-full max-w-md mx-4 shadow-[0_0_40px_rgba(59,130,246,0.3)] border border-gray-700/50 backdrop-blur-xl" onClick={e => e.stopPropagation()}>
        <div className="flex items-center justify-between p-5 border-b border-gray-700/50 bg-gradient-to-r from-blue-600/10 to-indigo-600/10 rounded-t-2xl">
          <div>
            <h3 className="text-lg font-bold text-white drop-shadow-lg">键盘快捷键</h3>
            <p className="text-xs text-gray-400 mt-1">快速上手，提升效率</p>
          </div>
          <button onClick={onClose} className="text-gray-400 hover:text-white p-1 hover:bg-gray-700 rounded-lg transition-all">
            <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>
        <div className="p-5 space-y-3">
          {shortcuts.map((shortcut, index) => (
            <div key={index} className="flex items-center justify-between p-3 rounded-xl hover:bg-gradient-to-r hover:from-gray-700/30 hover:to-gray-700/50 transition-all duration-200">
              <span className="text-gray-300 text-sm font-medium">{shortcut.description}</span>
              <kbd className="px-3 py-1.5 bg-gradient-to-r from-gray-700 to-gray-600 text-gray-200 text-sm rounded-xl font-mono shadow-[0_2px_10px_rgba(0,0,0,0.3)] border border-gray-600 hover:border-gray-500 transition-all">
                {shortcut.keys}
              </kbd>
            </div>
          ))}
        </div>
        <div className="p-5 border-t border-gray-700/50 bg-gradient-to-r from-gray-800/50 to-gray-800/30 rounded-b-2xl">
          <button
            onClick={onClose}
            className="w-full py-2.5 bg-gradient-to-r from-blue-500 to-indigo-600 text-white rounded-xl hover:from-blue-600 hover:to-indigo-700 transition-all duration-300 font-medium shadow-[0_4px_20px_rgba(59,130,246,0.4)] hover:shadow-[0_6px_30px_rgba(59,130,246,0.6)] hover:scale-[1.02]"
          >
            知道了
          </button>
        </div>
      </div>
    </div>
  )
}

export default Chat
