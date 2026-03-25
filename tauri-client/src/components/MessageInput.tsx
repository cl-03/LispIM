import React, { useState, useRef, KeyboardEvent } from 'react'
import { useAppStore } from '@/store/appStore'

interface MessageInputProps {
  conversationId: number
}

const MessageInput: React.FC<MessageInputProps> = ({ conversationId }) => {
  const { sendMessage } = useAppStore()
  const [content, setContent] = useState('')
  const [isTyping, setIsTyping] = useState(false)
  const textareaRef = useRef<HTMLTextAreaElement>(null)

  const handleSend = () => {
    if (content.trim()) {
      sendMessage(conversationId, content.trim())
      setContent('')
      setIsTyping(false)
      textareaRef.current?.focus()
    }
  }

  const handleKeyDown = (e: KeyboardEvent<HTMLTextAreaElement>) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault()
      handleSend()
    }
  }

  const handleChange = (e: React.ChangeEvent<HTMLTextAreaElement>) => {
    setContent(e.target.value)
    setIsTyping(true)

    // 自动调整高度
    if (textareaRef.current) {
      textareaRef.current.style.height = 'auto'
      textareaRef.current.style.height = `${Math.min(textareaRef.current.scrollHeight, 120)}px`
    }
  }

  return (
    <div className="p-4 bg-primary-dark border-t border-primary-accent">
      <div className="flex items-end space-x-2">
        {/* 附件按钮 */}
        <button
          className="p-3 text-gray-400 hover:text-white hover:bg-primary-accent rounded-lg transition-colors"
          title="发送附件"
        >
          <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path
              strokeLinecap="round"
              strokeLinejoin="round"
              strokeWidth={2}
              d="M15.172 7l-6.586 6.586a2 2 0 102.828 2.828l6.414-6.586a4 4 0 00-5.656-5.656l-6.415 6.585a6 6 0 108.486 8.486L20.5 13"
            />
          </svg>
        </button>

        {/* 表情按钮 */}
        <button
          className="p-3 text-gray-400 hover:text-white hover:bg-primary-accent rounded-lg transition-colors"
          title="表情"
        >
          <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path
              strokeLinecap="round"
              strokeLinejoin="round"
              strokeWidth={2}
              d="M14.828 14.828a4 4 0 01-5.656 0M9 10h.01M15 10h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
            />
          </svg>
        </button>

        {/* 输入框 */}
        <div className="flex-1 relative">
          <textarea
            ref={textareaRef}
            value={content}
            onChange={handleChange}
            onKeyDown={handleKeyDown}
            placeholder="输入消息... (Enter 发送，Shift+Enter 换行)"
            rows={1}
            className="w-full px-4 py-3 bg-primary-light border border-primary-accent rounded-xl
                     text-white placeholder-gray-500 focus:outline-none focus:ring-2
                     focus:ring-primary-highlight focus:border-transparent resize-none
                     max-h-[120px]"
          />
        </div>

        {/* 发送按钮 */}
        <button
          onClick={handleSend}
          disabled={!content.trim()}
          className="p-3 bg-primary-highlight hover:bg-primary-highlight/90 disabled:bg-gray-600
                   disabled:cursor-not-allowed text-white rounded-lg transition-colors"
          title="发送"
        >
          <svg className="w-5 h-5" fill="currentColor" viewBox="0 0 20 20">
            <path d="M10.894 2.553a1 1 0 00-1.788 0l-7 14a1 1 0 001.169 1.409l5-1.429A1 1 0 009 15.571V11a1 1 0 112 0v4.571a1 1 0 00.725.962l5 1.428a1 1 0 001.17-1.408l-7-14z" />
          </svg>
        </button>
      </div>

      {/* 正在输入提示 */}
      {isTyping && (
        <div className="mt-2 text-xs text-gray-500">
          正在输入...
        </div>
      )}
    </div>
  )
}

export default MessageInput
