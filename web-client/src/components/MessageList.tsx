import React, { useRef, useEffect, useState } from 'react'
import { useAppStore } from '@/store/appStore'
import { formatMessageTime, replaceEmojis, linkifyText, renderEmojiGifs } from '@/utils/message'
import type { Message } from '@/types'

interface MessageListProps {
  conversationId: number
}

const MessageList: React.FC<MessageListProps> = ({ conversationId }) => {
  const { messages, user, readMessage } = useAppStore()
  const messagesEndRef = useRef<HTMLDivElement>(null)
  const containerRef = useRef<HTMLDivElement>(null)
  const [showLoadMore, setShowLoadMore] = useState(false)
  const [showSearch, setShowSearch] = useState(false)
  const [searchQuery, setSearchQuery] = useState('')
  const [searchResults, setSearchResults] = useState<number[]>([])
  const [currentSearchIndex, setCurrentSearchIndex] = useState(-1)

  const conversationMessages = messages.get(conversationId) || []

  // 滚动到底部
  useEffect(() => {
    if (!showSearch) {
      messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' })
    }
  }, [conversationMessages, showSearch])

  // 标记消息为已读
  useEffect(() => {
    conversationMessages.forEach((msg) => {
      if (msg.senderId !== user?.id && !msg.readBy?.some((r) => r.userId === user?.id)) {
        readMessage(msg.id)
      }
    })
  }, [conversationMessages, user?.id])

  // 检查是否需要显示加载更多
  useEffect(() => {
    if (conversationMessages.length > 20) {
      setShowLoadMore(true)
    }
  }, [conversationMessages])

  // 搜索消息
  useEffect(() => {
    if (searchQuery.trim()) {
      const results = conversationMessages
        .map((msg, index) => ({
          index,
          msg,
          match: msg.content?.toLowerCase().includes(searchQuery.toLowerCase())
        }))
        .filter(item => item.match)
        .map(item => item.index)
      setSearchResults(results)
      setCurrentSearchIndex(results.length > 0 ? 0 : -1)
    } else {
      setSearchResults([])
      setCurrentSearchIndex(-1)
    }
  }, [searchQuery, conversationMessages])

  // 滚动到当前搜索位置
  useEffect(() => {
    if (currentSearchIndex >= 0 && searchResults.length > 0) {
      const msgIndex = searchResults[currentSearchIndex]
      const element = document.getElementById(`msg-${conversationMessages[msgIndex]?.id}`)
      element?.scrollIntoView({ behavior: 'smooth', block: 'center' })
    }
  }, [currentSearchIndex, searchResults, conversationMessages])

  const isOwnMessage = (senderId: string) => senderId === user?.id

  // 加载历史消息
  const handleLoadHistory = async () => {
    // TODO: 调用后端 API 加载历史消息
    alert('历史消息加载功能开发中...')
  }

  // 搜索相关函数
  const handleSearchNavigate = (direction: 'next' | 'prev') => {
    if (searchResults.length === 0) return
    if (direction === 'next') {
      setCurrentSearchIndex((prev) => (prev + 1) % searchResults.length)
    } else {
      setCurrentSearchIndex((prev) => (prev - 1 + searchResults.length) % searchResults.length)
    }
  }

  // 高亮搜索关键词
  const highlightSearchText = (content: string) => {
    if (!searchQuery.trim()) return content
    const regex = new RegExp(`(${searchQuery.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')})`, 'gi')
    return content.replace(regex, '<mark class="bg-yellow-300 text-gray-900 px-0.5 rounded">$1</mark>')
  }

  const renderMessageContent = (message: Message, highlight = false) => {
    if (message.recalled) {
      return (
        <div className="text-white/60 italic text-sm">[消息已撤回]</div>
      )
    }

    // 检查是否为图片消息 [image:url]
    if (message.messageType === 'text' && message.content?.match(/^\[image:(.+)\]$/)) {
      const match = message.content.match(/^\[image:(.+)\]$/)
      if (match && match[1]) {
        return (
          <img
            src={match[1]}
            alt="图片"
            className="max-w-full rounded-lg cursor-pointer hover:opacity-90"
            onClick={() => window.open(match[1], '_blank')}
          />
        )
      }
    }

    switch (message.messageType) {
      case 'text':
        let content = renderEmojiGifs(replaceEmojis(linkifyText(message.content || '')))
        // 搜索模式下高亮关键词
        if (highlight && searchQuery.trim()) {
          content = highlightSearchText(content)
        }
        return (
          <div
            className="whitespace-pre-wrap break-words text-sm leading-relaxed message-content"
            dangerouslySetInnerHTML={{ __html: content }}
          />
        )
      case 'image':
        return (
          <img
            src={message.content}
            alt="图片"
            className="max-w-full rounded-lg cursor-pointer hover:opacity-90"
            onClick={() => window.open(message.content, '_blank')}
          />
        )
      case 'file':
        return (
          <div className="flex items-center space-x-2 text-sm">
            <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path
                strokeLinecap="round"
                strokeLinejoin="round"
                strokeWidth={2}
                d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"
              />
            </svg>
            <span className="truncate max-w-[200px]">{message.content}</span>
          </div>
        )
      default:
        return <div className="text-white/60 text-sm">暂不支持的消息类型</div>
    }
  }

  const renderMessageBubble = (msg: Message, isOwn: boolean, showAvatar: boolean) => {
    if (isOwn) {
      // 自己的消息 - 蓝色气泡，右侧显示
      return (
        <div className={`flex ${showAvatar ? 'flex-row-reverse' : 'flex-row-reverse'} items-end gap-2`}>
          {/* 头像 */}
          {showAvatar && (
            <div className="w-8 h-8 rounded-full bg-gradient-to-br from-blue-500 to-blue-600 flex items-center justify-center text-white text-sm font-medium shadow-md flex-shrink-0">
              {user?.displayName?.charAt(0).toUpperCase() || '我'}
            </div>
          )}
          {/* 气泡 */}
          <div className="group relative">
            <div className="px-4 py-2.5 bg-gradient-to-br from-blue-500 to-blue-600 text-white rounded-2xl rounded-tr-sm max-w-[280px] sm:max-w-[350px] shadow-lg border border-blue-400/20">
              {renderMessageContent(msg, showSearch && searchResults.includes(conversationMessages.indexOf(msg)))}
              {/* 已读状态 */}
              {msg.readBy && msg.readBy.length > 0 && (
                <div className="flex items-center justify-end mt-1 text-xs text-blue-100 gap-1">
                  <svg className="w-3.5 h-3.5" fill="currentColor" viewBox="0 0 12 12">
                    <path d="M10.675 2.825a4.25 4.25 0 0 0-7.342 0l-2.65 3.264a.75.75 0 1 0 1.163.948l2.65-3.264a2.75 2.75 0 0 1 4.753 0l2.651 3.264a.75.75 0 0 0 1.163-.948L10.675 2.825ZM5.88 6.052a.75.75 0 0 0-1.093-.152L1.66 8.527a.75.75 0 1 0 1.013 1.105l2.58-2.367 3.52 3.658a.75.75 0 1 0 1.082-1.04L5.88 6.052Z"/>
                  </svg>
                  <span>{msg.readBy.length}人已读</span>
                </div>
              )}
            </div>
            {/* 发送者名称（仅当显示头像时） */}
            {showAvatar && (
              <div className="text-right mt-1">
                <span className="text-xs text-gray-400">{user?.displayName || '我'}</span>
              </div>
            )}
          </div>
        </div>
      )
    } else {
      // 对方的消息 - 白色气泡，左侧显示
      return (
        <div className={`flex ${showAvatar ? 'flex-row' : 'flex-row'} items-end gap-2`}>
          {/* 头像 */}
          {showAvatar && (
            <div className="w-8 h-8 rounded-full bg-gradient-to-br from-emerald-400 to-emerald-500 flex items-center justify-center text-white text-sm font-medium shadow-md flex-shrink-0">
              {msg.sender?.displayName?.charAt(0).toUpperCase() || '?'}
            </div>
          )}
          {/* 气泡 */}
          <div className="group relative">
            <div className="px-4 py-2.5 bg-gray-100 text-gray-900 rounded-2xl rounded-tl-sm max-w-[280px] sm:max-w-[350px] shadow-lg border border-gray-200">
              {showAvatar && (
                <div className="text-xs text-gray-500 font-medium mb-0.5">
                  {msg.sender?.displayName || '未知用户'}
                </div>
              )}
              {renderMessageContent(msg, showSearch && searchResults.includes(conversationMessages.indexOf(msg)))}
            </div>
            {/* 发送者名称（仅当显示头像时） */}
            {showAvatar && (
              <div className="mt-1">
                <span className="text-xs text-gray-400">{msg.sender?.displayName || '未知用户'}</span>
              </div>
            )}
          </div>
        </div>
      )
    }
  }

  return (
    <div ref={containerRef} className="flex-1 flex flex-col overflow-hidden bg-gray-900">
      {/* 搜索栏 */}
      {showSearch && (
        <div className="flex items-center space-x-2 px-4 py-2 bg-gray-800 border-b border-gray-700 shadow-sm">
          <div className="flex-1 relative">
            <input
              type="text"
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              placeholder="搜索消息内容..."
              className="w-full px-4 py-1.5 border border-gray-600 rounded-full text-sm focus:outline-none focus:ring-2 focus:ring-blue-500 text-white bg-gray-700 placeholder-gray-400"
              autoFocus
            />
          </div>
          <div className="flex items-center space-x-1">
            {searchResults.length > 0 && (
              <>
                <span className="text-sm text-gray-400 px-2">
                  {currentSearchIndex + 1} / {searchResults.length}
                </span>
                <button
                  onClick={() => handleSearchNavigate('prev')}
                  className="p-1.5 hover:bg-gray-700 rounded text-gray-400"
                  title="上一条"
                >
                  <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 19l-7-7 7-7" />
                  </svg>
                </button>
                <button
                  onClick={() => handleSearchNavigate('next')}
                  className="p-1.5 hover:bg-gray-700 rounded text-gray-400"
                  title="下一条"
                >
                  <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 5l7 7-7 7" />
                  </svg>
                </button>
              </>
            )}
            <button
              onClick={() => {
                setShowSearch(false)
                setSearchQuery('')
                setSearchResults([])
              }}
              className="p-1.5 hover:bg-gray-700 rounded text-gray-400"
              title="关闭搜索"
            >
              <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
              </svg>
            </button>
          </div>
        </div>
      )}

      {/* 消息列表 */}
      <div className="flex-1 overflow-y-auto">
        {/* 加载更多历史消息 */}
        {showLoadMore && (
          <div className="text-center py-3">
            <button
              onClick={handleLoadHistory}
              className="px-4 py-1 text-sm text-blue-400 bg-gray-800 border border-blue-500 rounded-full hover:bg-gray-700 transition-colors"
            >
              加载更多历史记录
            </button>
          </div>
        )}

        <div className="p-4 space-y-4">
          {conversationMessages.length === 0 ? (
            <div className="text-center text-gray-500 py-8">
              <p>暂无消息</p>
              <p className="text-sm mt-2">发送一条消息开始聊天吧</p>
            </div>
          ) : (
            conversationMessages.map((msg, index) => {
              const isOwn = isOwnMessage(msg.senderId)
              const showAvatar =
                index === 0 ||
                conversationMessages[index - 1].senderId !== msg.senderId
              const showMessageTime =
                index === 0 ||
                msg.createdAt - conversationMessages[index - 1].createdAt > 60000 // 1 分钟

              // 搜索模式下，如果不匹配则隐藏
              if (showSearch && searchQuery.trim()) {
                const matchIndex = searchResults.indexOf(index)
                if (matchIndex === -1) return null
              }

              return (
                <div
                  key={msg.id}
                  id={`msg-${msg.id}`}
                  className={`flex flex-col transition-all duration-300 ${
                    showSearch && searchResults.includes(index) ? 'scroll-mt-32' : ''
                  }`}
                >
                  {/* 时间戳 */}
                  {showMessageTime && (
                    <div className="text-center my-2">
                      <span className="px-3 py-1 bg-gray-800 text-gray-400 text-xs rounded-full">
                        {formatMessageTime(msg.createdAt)}
                      </span>
                    </div>
                  )}

                  {/* 消息气泡 */}
                  <div className={`px-4 py-1 ${isOwn ? 'justify-end' : 'justify-start'} flex animate-fade-in`}>
                    {renderMessageBubble(msg, isOwn, showAvatar)}
                  </div>
                </div>
              )
            })
          )}
          <div ref={messagesEndRef} />
        </div>
      </div>

      {/* 底部工具栏 - 搜索按钮 */}
      {!showSearch && (
        <div className="border-t border-gray-700 bg-gray-800 px-4 py-2 flex justify-end">
          <button
            onClick={() => setShowSearch(true)}
            className="flex items-center space-x-1 px-3 py-1.5 text-sm text-gray-300 hover:bg-gray-700 rounded-lg transition-colors"
            title="搜索消息"
          >
            <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
            </svg>
            <span>查找聊天记录</span>
          </button>
        </div>
      )}
    </div>
  )
}

export default MessageList
