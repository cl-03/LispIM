import React, { useState, useRef, KeyboardEvent } from 'react'
import { useAppStore } from '@/store/appStore'

interface MessageInputProps {
  conversationId: number
}

const MessageInput: React.FC<MessageInputProps> = ({ conversationId }) => {
  const { sendMessage } = useAppStore()
  const [content, setContent] = useState('')
  const [isTyping, setIsTyping] = useState(false)
  const [showEmojiPicker, setShowEmojiPicker] = useState(false)
  const textareaRef = useRef<HTMLTextAreaElement>(null)
  const fileInputRef = useRef<HTMLInputElement>(null)
  const imageInputRef = useRef<HTMLInputElement>(null)

  const handleSend = () => {
    if (content.trim()) {
      sendMessage(conversationId, content.trim())
      setContent('')
      setIsTyping(false)
      setShowEmojiPicker(false)
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

  // 处理表情选择
  const handleEmojiSelect = (emoji: string) => {
    const textarea = textareaRef.current
    if (!textarea) return

    const start = textarea.selectionStart
    const end = textarea.selectionEnd
    const newContent = content.substring(0, start) + emoji + content.substring(end)
    setContent(newContent)
    setIsTyping(true)

    // 恢复光标位置
    setTimeout(() => {
      textarea.focus()
      textarea.setSelectionRange(start + emoji.length, start + emoji.length)
    }, 0)
  }

  // 处理文件选择
  const handleFileSelect = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0]
    if (file) {
      // TODO: 实现文件上传
      alert(`文件上传功能开发中：${file.name}`)
    }
    // 重置 input 以允许重复选择同一文件
    if (fileInputRef.current) {
      fileInputRef.current.value = ''
    }
  }

  // 处理图片选择
  const handleImageSelect = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0]
    if (file && file.type.startsWith('image/')) {
      const reader = new FileReader()
      reader.onload = (event) => {
        const imgUrl = event.target?.result as string
        // 发送图片消息（使用 [image:url] 格式）
        const imageMarkup = `[image:${imgUrl}]`
        sendMessage(conversationId, imageMarkup)
      }
      reader.readAsDataURL(file)
    }
    if (imageInputRef.current) {
      imageInputRef.current.value = ''
    }
  }

  // 常用表情列表 (go-fly-master)
  const emojis = Array.from({ length: 72 }, (_, i) => i)

  return (
    <div className="p-4 bg-gray-800 border-t border-gray-700 relative">
      <div className="flex items-end space-x-2">
        {/* 附件按钮 */}
        <button
          onClick={() => fileInputRef.current?.click()}
          className="p-3 text-gray-400 hover:text-white hover:bg-gray-700 rounded-lg transition-colors"
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

        {/* 图片按钮 */}
        <button
          onClick={() => imageInputRef.current?.click()}
          className="p-3 text-gray-400 hover:text-white hover:bg-gray-700 rounded-lg transition-colors"
          title="发送图片"
        >
          <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path
              strokeLinecap="round"
              strokeLinejoin="round"
              strokeWidth={2}
              d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v8a2 2 0 002 2z"
            />
          </svg>
        </button>

        {/* 表情按钮 */}
        <button
          onClick={() => setShowEmojiPicker(!showEmojiPicker)}
          className="p-3 text-gray-400 hover:text-white hover:bg-gray-700 rounded-lg transition-colors"
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
            className="w-full px-4 py-3 bg-gray-700 border border-gray-600 rounded-xl
                     text-white placeholder-gray-500 focus:outline-none focus:ring-2
                     focus:ring-blue-500 focus:border-transparent resize-none
                     max-h-[120px]"
          />
        </div>

        {/* 发送按钮 */}
        <button
          onClick={handleSend}
          disabled={!content.trim()}
          className="p-3 bg-blue-500 hover:bg-blue-600 disabled:bg-gray-600
                   disabled:cursor-not-allowed text-white rounded-lg transition-colors"
          title="发送"
        >
          <svg className="w-5 h-5" fill="currentColor" viewBox="0 0 20 20">
            <path d="M10.894 2.553a1 1 0 00-1.788 0l-7 14a1 1 0 001.169 1.409l5-1.429A1 1 0 009 15.571V11a1 1 0 112 0v4.571a1 1 0 00.725.962l5 1.428a1 1 0 001.17-1.408l-7-14z" />
          </svg>
        </button>
      </div>

      {/* 隐藏的文件输入 */}
      <input
        ref={fileInputRef}
        type="file"
        className="hidden"
        onChange={handleFileSelect}
      />
      <input
        ref={imageInputRef}
        type="file"
        className="hidden"
        accept="image/*"
        onChange={handleImageSelect}
      />

      {/* 表情选择器 */}
      {showEmojiPicker && (
        <div className="absolute bottom-full left-0 mb-2 p-2 bg-white border border-gray-200 rounded-lg shadow-xl z-50">
          <div className="grid grid-cols-8 gap-1 max-w-sm">
            {emojis.map((index) => (
              <button
                key={index}
                onClick={() => {
                  handleEmojiSelect(`[emoji:${index}]`)
                  setShowEmojiPicker(false)
                }}
                className="w-9 h-9 hover:bg-gray-100 rounded transition-colors flex items-center justify-center"
              >
                <img src={`/emojis/${index}.gif`} alt="" className="w-7 h-7 object-contain" />
              </button>
            ))}
          </div>
        </div>
      )}

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
