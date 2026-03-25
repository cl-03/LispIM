import React, { useRef, useEffect } from 'react'
import { useAppStore } from '@/store/appStore'
import { formatMessageTime, replaceEmojis, linkifyText } from '@/utils/message'
import type { Message } from '@/types'

interface MessageListProps {
  conversationId: number
}

const MessageList: React.FC<MessageListProps> = ({ conversationId }) => {
  const { messages, user, readMessage } = useAppStore()
  const messagesEndRef = useRef<HTMLDivElement>(null)
  const containerRef = useRef<HTMLDivElement>(null)

  const conversationMessages = messages.get(conversationId) || []

  // 滚动到底部
  useEffect(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' })
  }, [conversationMessages])

  // 标记消息为已读
  useEffect(() => {
    conversationMessages.forEach((msg) => {
      if (msg.senderId !== user?.id && !msg.readBy?.some((r) => r.userId === user?.id)) {
        readMessage(msg.id)
      }
    })
  }, [conversationMessages, user, readMessage])

  const isOwnMessage = (senderId: string) => senderId === user?.id

  const renderMessageContent = (message: Message) => {
    if (message.recalled) {
      return (
        <div className="text-gray-500 italic text-sm">[消息已撤回]</div>
      )
    }

    switch (message.messageType) {
      case 'text':
        return (
          <div
            className="text-white whitespace-pre-wrap break-words"
            dangerouslySetInnerHTML={{ __html: replaceEmojis(linkifyText(message.content || '')) }}
          />
        )
      case 'image':
        return (
          <img
            src={message.content}
            alt="图片"
            className="max-w-full rounded-lg cursor-pointer hover:opacity-90"
          />
        )
      case 'file':
        return (
          <div className="flex items-center space-x-2 text-white">
            <svg className="w-8 h-8" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path
                strokeLinecap="round"
                strokeLinejoin="round"
                strokeWidth={2}
                d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"
              />
            </svg>
            <span>{message.content}</span>
          </div>
        )
      default:
        return <div className="text-gray-400 text-sm">暂不支持的消息类型</div>
    }
  }

  return (
    <div ref={containerRef} className="flex-1 overflow-y-auto bg-primary-main">
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

            return (
              <div
                key={msg.id}
                className={`flex ${isOwn ? 'justify-end' : 'justify-start'} animate-fade-in`}
              >
                <div className={`flex ${isOwn ? 'flex-row-reverse' : 'flex-row'} items-end space-x-2 max-w-[80%]`}>
                  {/* 头像 */}
                  {showAvatar && !isOwn && (
                    <div className="w-8 h-8 rounded-full bg-primary-accent flex items-center justify-center text-white text-sm flex-shrink-0">
                      {msg.sender?.displayName?.charAt(0).toUpperCase() || '?'}
                    </div>
                  )}
                  {!showAvatar && !isOwn && <div className="w-8" />}

                  {/* 消息气泡 */}
                  <div className="flex flex-col">
                    {!isOwn && showAvatar && (
                      <span className="text-xs text-gray-400 ml-1 mb-1">
                        {msg.sender?.displayName || '未知用户'}
                      </span>
                    )}
                    <div
                      className={`px-4 py-2 rounded-2xl ${
                        isOwn
                          ? 'bg-primary-highlight text-white'
                          : 'bg-primary-light text-white'
                      }`}
                    >
                      {renderMessageContent(msg)}
                    </div>

                    {/* 时间和已读状态 */}
                    <div
                      className={`flex items-center space-x-1 mt-1 ${
                        isOwn ? 'justify-end' : 'justify-start'
                      }`}
                    >
                      <span className="text-xs text-gray-500">
                        {formatMessageTime(msg.createdAt)}
                      </span>
                      {isOwn && msg.readBy && msg.readBy.length > 0 && (
                        <svg className="w-3 h-3 text-gray-500" fill="currentColor" viewBox="0 0 20 20">
                          <path d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" />
                        </svg>
                      )}
                    </div>
                  </div>
                </div>
              </div>
            )
          })
        )}
        <div ref={messagesEndRef} />
      </div>
    </div>
  )
}

export default MessageList
