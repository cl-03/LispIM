import React, { useRef, useEffect, useState, useMemo } from 'react'
import { useAppStore } from '@/store/appStore'
import { formatMessageTime, replaceEmojis, linkifyText, renderEmojiGifs } from '@/utils/message'
import { getApiClient } from '@/utils/api-client'
import { useScreenshotProtection } from '@/hooks/useScreenshotProtection'
import { PinnedMessages } from './PinnedMessages'
import type { Message, Conversation, MessageReaction } from '@/types'

interface MessageListProps {
  conversationId: number
  onReply?: (message: { id: number; senderName: string; content: string }) => void
}

const MessageList: React.FC<MessageListProps> = ({ conversationId, onReply }) => {
  const { messages, user, loadConversations, editMessage } = useAppStore()
  const messagesEndRef = useRef<HTMLDivElement>(null)
  const containerRef = useRef<HTMLDivElement>(null)
  const [showLoadMore, setShowLoadMore] = useState(false)
  const [showSearch, setShowSearch] = useState(false)
  const [searchQuery, setSearchQuery] = useState('')
  const [searchResults, setSearchResults] = useState<number[]>([])
  const [currentSearchIndex, setCurrentSearchIndex] = useState(-1)
  const [toast, setToast] = useState<{ message: string; visible: boolean }>({ message: '', visible: false })
  const [contextMenu, setContextMenu] = useState<{
    visible: boolean
    x: number
    y: number
    messageId: number | null
  }>({ visible: false, x: 0, y: 0, messageId: null })
  const [showReactionPicker, setShowReactionPicker] = useState<{
    visible: boolean
    x: number
    y: number
    messageId: number | null
  }>({ visible: false, x: 0, y: 0, messageId: null })
  const [pinnedMessageId, setPinnedMessageId] = useState<number | null>(null)
  const [showForwardModal, setShowForwardModal] = useState(false)
  const [forwardMessageId, setForwardMessageId] = useState<number | null>(null)
  const [showChatSettings, setShowChatSettings] = useState(false)
  const [showPinnedMessages, setShowPinnedMessages] = useState(false)
  const [editingMessage, setEditingMessage] = useState<{ id: number; content: string } | null>(null)
  const [showScrollButton, setShowScrollButton] = useState(false)
  const [unreadCount, setUnreadCount] = useState(0)
  const [longPressTimer, setLongPressTimer] = useState<number | null>(null)
  const [isLoadingHistory, setIsLoadingHistory] = useState(false) // 加载历史消息状态
  const [virtualScrollEnabled, setVirtualScrollEnabled] = useState(false) // 虚拟滚动开关

  // 虚拟滚动配置
  const MESSAGE_HEIGHT = 80 // 预估消息高度
  const OVERSCAN = 5 // 预加载条数
  const [visibleStartIndex, setVisibleStartIndex] = useState(0)
  const [visibleEndIndex, setVisibleEndIndex] = useState(100)
  const [totalScrollHeight, setTotalScrollHeight] = useState(0)

  // 启用截图防护
  useScreenshotProtection({
    enabled: true,
    onBlurEnabled: true
  })

  const showToast = (message: string) => {
    setToast({ message, visible: true })
    setTimeout(() => setToast({ message: '', visible: false }), 2000)
  }

  const conversationMessages = useMemo(() => messages.get(conversationId) || [], [messages, conversationId])

  // 计算未读消息数量
  useEffect(() => {
    if (!user?.id) return

    const unreadMessages = conversationMessages.filter((msg) =>
      msg.senderId !== user.id && !msg.readBy?.some((r) => r.userId === user.id)
    )
    setUnreadCount(unreadMessages.length)

    // 自动标记消息为已读
    const unreadIds = unreadMessages.map(m => m.id)
    if (unreadIds.length > 0) {
      const { ws } = useAppStore.getState()
      unreadIds.forEach(id => ws?.readMessage(id))
    }
  }, [conversationMessages, user?.id])

  // 监听滚动状态，显示/隐藏滚动到底部按钮
  useEffect(() => {
    const container = containerRef.current
    if (!container) return

    const handleScroll = () => {
      const { scrollTop, scrollHeight, clientHeight } = container
      // 当滚动到距离底部 100px 以内时，隐藏按钮
      const isNearBottom = scrollHeight - scrollTop - clientHeight < 100
      setShowScrollButton(!isNearBottom && conversationMessages.length > 0)

      // 更新虚拟滚动可见范围
      if (virtualScrollEnabled && conversationMessages.length > 100) {
        const newStartIndex = Math.max(0, Math.floor(scrollTop / MESSAGE_HEIGHT) - OVERSCAN)
        const newEndIndex = Math.min(
          conversationMessages.length,
          Math.ceil((scrollTop + clientHeight) / MESSAGE_HEIGHT) + OVERSCAN
        )
        setVisibleStartIndex(newStartIndex)
        setVisibleEndIndex(newEndIndex)
        setTotalScrollHeight(conversationMessages.length * MESSAGE_HEIGHT)
      }
    }

    container.addEventListener('scroll', handleScroll)
    handleScroll() // 初始化检查

    // 启用虚拟滚动（当消息数量超过 100 条时）
    if (conversationMessages.length > 100) {
      setVirtualScrollEnabled(true)
    }

    return () => container.removeEventListener('scroll', handleScroll)
  }, [conversationMessages.length, virtualScrollEnabled])

  // 滚动到底部
  useEffect(() => {
    if (!showSearch) {
      messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' })
    }
  }, [conversationMessages, showSearch])

  // 标记消息为已读
  useEffect(() => {
    if (!user?.id) return

    conversationMessages.forEach((msg) => {
      if (msg.senderId !== user.id && !msg.readBy?.some((r) => r.userId === user.id)) {
        // 标记为已读
        const { ws } = useAppStore.getState()
        ws?.readMessage(msg.id)
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
    if (isLoadingHistory) return
    setIsLoadingHistory(true)
    try {
      const { loadHistory } = useAppStore.getState()
      await loadHistory(conversationId)
      showToast('已加载更多历史消息')
    } catch (err) {
      showToast('暂无更多历史消息')
    } finally {
      setIsLoadingHistory(false)
    }
  }

  // 右键菜单处理
  const handleContextMenu = (e: React.MouseEvent, messageId: number) => {
    e.preventDefault()
    setContextMenu({
      visible: true,
      x: e.clientX,
      y: e.clientY,
      messageId
    })
  }

  // 长按开始（移动端）
  const handleTouchStart = (e: React.TouchEvent, messageId: number) => {
    const touch = e.touches[0]
    const timer = setTimeout(() => {
      setContextMenu({
        visible: true,
        x: touch.clientX,
        y: touch.clientY,
        messageId
      })
      // 震动反馈
      if (navigator.vibrate) {
        navigator.vibrate(50)
      }
    }, 500)
    setLongPressTimer(timer)
  }

  // 长按结束（移动端）
  const handleTouchEnd = () => {
    if (longPressTimer) {
      clearTimeout(longPressTimer)
      setLongPressTimer(null)
    }
  }

  // 长按移动（取消长按）
  const handleTouchMove = () => {
    if (longPressTimer) {
      clearTimeout(longPressTimer)
      setLongPressTimer(null)
    }
  }

  // 删除消息（双向）
  const handleDeleteForAll = async () => {
    if (!contextMenu.messageId) return

    const api = getApiClient()
    try {
      const result = await api.deleteMessageForAll(contextMenu.messageId, '用户删除')
      if (result.success) {
        showToast('消息已删除')
        // 重新加载会话列表
        loadConversations()
      }
    } catch (error) {
      showToast('删除失败')
    } finally {
      setContextMenu({ visible: false, x: 0, y: 0, messageId: null })
    }
  }

  // 删除消息（仅自己）
  const handleDeleteForSelf = async () => {
    if (!contextMenu.messageId) return

    const api = getApiClient()
    try {
      const result = await api.deleteMessageForSelf(contextMenu.messageId)
      if (result.success) {
        showToast('消息已从本地删除')
        loadConversations()
      }
    } catch (error) {
      showToast('删除失败')
    } finally {
      setContextMenu({ visible: false, x: 0, y: 0, messageId: null })
    }
  }

  // 关闭右键菜单
  useEffect(() => {
    const handleClick = () => {
      setContextMenu({ visible: false, x: 0, y: 0, messageId: null })
      setShowReactionPicker({ visible: false, x: 0, y: 0, messageId: null })
    }
    document.addEventListener('click', handleClick)
    return () => document.removeEventListener('click', handleClick)
  }, [])

  // 显示反应选择器
  const handleShowReactionPicker = (e: React.MouseEvent, messageId: number) => {
    e.preventDefault()
    e.stopPropagation()
    setShowReactionPicker({
      visible: true,
      x: e.clientX,
      y: e.clientY,
      messageId
    })
  }

  // 添加反应
  const handleAddReaction = async (emoji: string) => {
    if (!showReactionPicker.messageId) return

    const api = getApiClient()
    try {
      await api.addReaction(showReactionPicker.messageId, emoji)
      showToast(`已添加 ${emoji} 反应`)
      // 刷新消息列表
      loadConversations()
    } catch {
      showToast('添加反应失败')
    } finally {
      setShowReactionPicker({ visible: false, x: 0, y: 0, messageId: null })
    }
  }

  // 点击反应（切换添加/移除）
  const handleReactionClick = async (messageId: number, emoji: string) => {
    const api = getApiClient()
    try {
      // 获取当前消息的反应详情
      const response = await api.getMessageReactionsDetail(messageId)
      if (response.data) {
        const reactions = response.data as MessageReaction[]
        const existingReaction = reactions.find(r => r.emoji === emoji && r.userId === user?.id)

        if (existingReaction) {
          // 已添加，移除反应
          await api.removeReaction(messageId, emoji)
          showToast(`已移除 ${emoji} 反应`)
        } else {
          // 未添加，添加反应
          await api.addReaction(messageId, emoji)
          showToast(`已添加 ${emoji} 反应`)
        }
        // 刷新消息列表
        loadConversations()
      }
    } catch {
      showToast('操作失败')
    }
  }

  // 置顶消息
  const handlePinMessage = async () => {
    if (!contextMenu.messageId) return

    const api = getApiClient()
    try {
      await api.pinMessage(contextMenu.messageId, conversationId)
      showToast('消息已置顶')
      setPinnedMessageId(contextMenu.messageId)
      loadConversations()
    } catch {
      showToast('置顶消息失败')
    } finally {
      setContextMenu({ visible: false, x: 0, y: 0, messageId: null })
    }
  }

  // 取消置顶
  const handleUnpinMessage = async () => {
    if (!contextMenu.messageId) return

    const api = getApiClient()
    try {
      await api.unpinMessage(contextMenu.messageId, conversationId)
      showToast('消息已取消置顶')
      setPinnedMessageId(null)
      loadConversations()
    } catch {
      showToast('取消置顶失败')
    } finally {
      setContextMenu({ visible: false, x: 0, y: 0, messageId: null })
    }
  }

  // 转发消息
  const handleForwardMessage = () => {
    if (!contextMenu.messageId) return
    setForwardMessageId(contextMenu.messageId)
    setShowForwardModal(true)
    setContextMenu({ visible: false, x: 0, y: 0, messageId: null })
  }

  const handleForwardToConversation = async (targetConvId: number) => {
    if (!forwardMessageId) return

    const api = getApiClient()
    try {
      await api.forwardMessage(forwardMessageId, targetConvId)
      showToast('消息已转发')
      setShowForwardModal(false)
      setForwardMessageId(null)
      loadConversations()
    } catch {
      showToast('转发消息失败')
      setShowForwardModal(false)
      setForwardMessageId(null)
    }
  }

  // 编辑消息
  const handleEditMessage = async (content: string) => {
    if (!editingMessage) return

    try {
      const result = await editMessage(editingMessage.id, content)
      if (result.success) {
        showToast('消息已编辑')
        setEditingMessage(null)
      } else {
        showToast(result.error || '编辑消息失败')
      }
    } catch (err) {
      showToast('编辑消息失败')
    }
  }

  // 清空聊天记录
  const handleClearMessages = () => {
    // 这里需要调用 API 清空聊天记录
    // 暂时只清除本地状态
    const { messages } = useAppStore.getState()
    const updatedMessages = new Map(messages)
    updatedMessages.set(conversationId, [])
    // 更新 store
    useAppStore.setState({ messages: updatedMessages })
    showToast('聊天记录已清空')
  }

  // 监听打开搜索的事件
  useEffect(() => {
    const handleOpenSearch = () => {
      setShowSearch(true)
    }
    window.addEventListener('open-chat-search', handleOpenSearch)
    return () => window.removeEventListener('open-chat-search', handleOpenSearch)
  }, [])

  // 搜索框键盘快捷键
  const handleSearchKeyDown = (e: React.KeyboardEvent<HTMLInputElement>) => {
    if (e.key === 'Enter') {
      e.preventDefault()
      if (e.shiftKey) {
        handleSearchNavigate('prev')
      } else {
        handleSearchNavigate('next')
      }
    } else if (e.key === 'Escape') {
      setShowSearch(false)
      setSearchQuery('')
      setSearchResults([])
    }
  }

  // 高亮搜索关键词（支持中文和英文）
  const highlightSearchText = (content: string) => {
    if (!searchQuery.trim()) return content

    // 转义特殊字符
    const escapedQuery = searchQuery.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')

    // 创建正则表达式，支持中英文
    const regex = new RegExp(`(${escapedQuery})`, 'gi')

    // 高亮标记样式 - 使用更醒目的黄色背景
    const highlightStyle = 'bg-yellow-400 text-gray-900 px-1 rounded font-medium'

    return content.replace(regex, `<mark class="${highlightStyle}">$1</mark>`)
  }

  // 搜索导航时添加平滑滚动和视觉反馈
  const handleSearchNavigate = (direction: 'next' | 'prev') => {
    if (searchResults.length === 0) return

    let newIndex: number
    if (direction === 'next') {
      newIndex = (currentSearchIndex + 1) % searchResults.length
    } else {
      newIndex = (currentSearchIndex - 1 + searchResults.length) % searchResults.length
    }

    setCurrentSearchIndex(newIndex)

    // 滚动到目标消息
    setTimeout(() => {
      const msgIndex = searchResults[newIndex]
      const element = document.getElementById(`msg-${conversationMessages[msgIndex]?.id}`)
      if (element) {
        element.scrollIntoView({ behavior: 'smooth', block: 'center' })
        // 添加闪烁效果
        element.classList.add('ring-2', 'ring-yellow-400')
        setTimeout(() => {
          element.classList.remove('ring-2', 'ring-yellow-400')
        }, 1500)
      }
    }, 100)
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
      case 'text': {
        const content = renderEmojiGifs(replaceEmojis(linkifyText(message.content || '')))
        // 搜索模式下高亮关键词
        const finalContent = (highlight && searchQuery.trim()) ? highlightSearchText(content) : content
        return (
          <div
            className="whitespace-pre-wrap break-words text-sm leading-relaxed message-content"
            dangerouslySetInnerHTML={{ __html: finalContent }}
          />
        )
      }
      case 'image':
        return (
          <img
            src={message.content}
            alt="图片"
            className="max-w-full rounded-lg cursor-pointer hover:opacity-90"
            onClick={() => window.open(message.content, '_blank')}
          />
        )
      case 'file': {
        // 尝试解析 JSON 内容
        let fileInfo: { fileId?: string; filename?: string; size?: number; type?: string; url?: string } | null = null
        try {
          fileInfo = JSON.parse(message.content)
        } catch {
          // 不是 JSON 格式，直接显示内容
        }

        if (fileInfo && fileInfo.filename) {
          const formatFileSize = (bytes: number) => {
            if (bytes === 0) return '0 B'
            const k = 1024
            const sizes = ['B', 'KB', 'MB', 'GB']
            const i = Math.floor(Math.log(bytes) / Math.log(k))
            return Math.round((bytes / Math.pow(k, i)) * 100) / 100 + ' ' + sizes[i]
          }

          const handleDownload = async () => {
            if (fileInfo?.fileId) {
              try {
                showToast('正在下载文件...')
                // 直接打开下载链接
                window.open(`/api/v1/files/${fileInfo.fileId}/download`, '_blank')
              } catch (err) {
                showToast('下载失败')
              }
            }
          }

          return (
            <div
              className="flex items-center space-x-3 p-3 bg-white/10 rounded-xl cursor-pointer hover:bg-white/20 transition-colors"
              onClick={handleDownload}
            >
              <div className="flex-shrink-0">
                <svg className="w-10 h-10 text-blue-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path
                    strokeLinecap="round"
                    strokeLinejoin="round"
                    strokeWidth={1.5}
                    d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"
                  />
                </svg>
              </div>
              <div className="flex-1 min-w-0">
                <div className="text-sm font-medium truncate text-white">
                  {fileInfo.filename}
                </div>
                <div className="text-xs text-white/60 mt-0.5">
                  {fileInfo.size ? formatFileSize(fileInfo.size) : '未知大小'}
                  {fileInfo.type && ` · ${fileInfo.type}`}
                </div>
              </div>
              <div className="flex-shrink-0">
                <svg className="w-5 h-5 text-white/60" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path
                    strokeLinecap="round"
                    strokeLinejoin="round"
                    strokeWidth={2}
                    d="M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-4l-4 4m0 0l-4-4m4 4V4"
                  />
                </svg>
              </div>
            </div>
          )
        }

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
      }
      default:
        return <div className="text-white/60 text-sm">暂不支持的消息类型</div>
    }
  }

  const renderMessageBubble = (msg: Message, isOwn: boolean, showAvatar: boolean) => {
    if (isOwn) {
      // 自己的消息 - 蓝色气泡，右侧显示
      return (
        <div className={`flex ${showAvatar ? 'flex-row-reverse' : 'flex-row-reverse'} items-end gap-2 group/message`}>
          {/* 头像 */}
          {showAvatar && (
            <div className="w-8 h-8 rounded-full bg-gradient-to-br from-blue-500 to-blue-600 flex items-center justify-center text-white text-sm font-medium shadow-[0_2px_10px_rgba(59,130,246,0.4)] flex-shrink-0 border-2 border-blue-400/30 hover:scale-110 transition-transform duration-200 cursor-pointer">
              {user?.displayName?.charAt(0).toUpperCase() || '我'}
            </div>
          )}
          {/* 气泡 */}
          <div className="group relative">
            <div
              className="px-4 py-2.5 bg-gradient-to-br from-blue-500 to-blue-600 text-white rounded-2xl rounded-tr-sm max-w-[280px] sm:max-w-[350px] shadow-[0_4px_15px_rgba(59,130,246,0.3)] border border-blue-400/20 hover:shadow-[0_6px_20px_rgba(59,130,246,0.5)] hover:scale-[1.01] transition-all duration-200 cursor-pointer"
              onContextMenu={(e) => handleContextMenu(e, msg.id)}
            >
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
              {/* 消息时间悬停显示 */}
              <div className="absolute -bottom-5 right-2 opacity-0 group-hover/message:opacity-100 transition-opacity duration-200">
                <span className="text-xs text-gray-400 bg-gray-800/90 px-2 py-0.5 rounded-full backdrop-blur-sm">
                  {formatMessageTime(msg.createdAt)}
                </span>
              </div>
              {/* 快速反应按钮（悬停显示） */}
              <div className="absolute -top-3 -right-2 opacity-0 group-hover:opacity-100 transition-opacity z-10">
                <button
                  onClick={(e) => handleShowReactionPicker(e, msg.id)}
                  className="p-1.5 bg-white rounded-full shadow-lg text-gray-600 hover:text-gray-800 hover:scale-110 transition-all duration-200"
                  title="添加反应"
                >
                  <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M14.828 14.828a4 4 0 01-5.656 0M9 10h.01M15 10h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
                  </svg>
                </button>
              </div>
            </div>
            {/* 反应显示 */}
            {msg.reactions && msg.reactions.length > 0 && (
              <div className="flex flex-wrap gap-1 mt-1.5">
                {msg.reactions.map((reaction, idx) => (
                  <button
                    key={idx}
                    onClick={() => handleReactionClick(msg.id, reaction.emoji)}
                    className="inline-flex items-center gap-1 px-1.5 py-0.5 bg-gray-800/90 hover:bg-gray-700 border border-gray-600/50 rounded-full text-xs transition-all hover:scale-110"
                    title={reaction.userNames?.slice(0, 10).join(', ')}
                  >
                    <span>{reaction.emoji}</span>
                    <span className="text-gray-300 font-medium">{reaction.count}</span>
                  </button>
                ))}
              </div>
            )}
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
        <div className={`flex ${showAvatar ? 'flex-row' : 'flex-row'} items-end gap-2 group/message`}>
          {/* 头像 */}
          {showAvatar && (
            <div className="w-8 h-8 rounded-full bg-gradient-to-br from-emerald-400 to-emerald-500 flex items-center justify-center text-white text-sm font-medium shadow-[0_2px_10px_rgba(16,185,129,0.4)] flex-shrink-0 border-2 border-emerald-300/30 hover:scale-110 transition-transform duration-200 cursor-pointer">
              {msg.sender?.displayName?.charAt(0).toUpperCase() || '?'}
            </div>
          )}
          {/* 气泡 */}
          <div className="group relative">
            <div
              className="px-4 py-2.5 bg-gray-100 text-gray-900 rounded-2xl rounded-tl-sm max-w-[280px] sm:max-w-[350px] shadow-[0_2px_10px_rgba(0,0,0,0.1)] border border-gray-200/50 hover:shadow-[0_4px_15px_rgba(0,0,0,0.15)] hover:scale-[1.01] hover:bg-white transition-all duration-200 cursor-pointer"
              onContextMenu={(e) => handleContextMenu(e, msg.id)}
            >
              {showAvatar && (
                <div className="text-xs text-gray-500 font-medium mb-0.5">
                  {msg.sender?.displayName || '未知用户'}
                </div>
              )}
              {renderMessageContent(msg, showSearch && searchResults.includes(conversationMessages.indexOf(msg)))}
              {/* 消息时间悬停显示 */}
              <div className="absolute -bottom-5 left-2 opacity-0 group-hover/message:opacity-100 transition-opacity duration-200">
                <span className="text-xs text-gray-400 bg-gray-800/90 px-2 py-0.5 rounded-full backdrop-blur-sm">
                  {formatMessageTime(msg.createdAt)}
                </span>
              </div>
              {/* 快速反应按钮（悬停显示） */}
              <div className="absolute -top-3 -left-2 opacity-0 group-hover:opacity-100 transition-opacity z-10">
                <button
                  onClick={(e) => handleShowReactionPicker(e, msg.id)}
                  className="p-1.5 bg-white rounded-full shadow-lg text-gray-600 hover:text-gray-800 hover:scale-110 transition-all duration-200"
                  title="添加反应"
                >
                  <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M14.828 14.828a4 4 0 01-5.656 0M9 10h.01M15 10h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
                  </svg>
                </button>
              </div>
            </div>
            {/* 反应显示 */}
            {msg.reactions && msg.reactions.length > 0 && (
              <div className="flex flex-wrap gap-1 mt-1.5">
                {msg.reactions.map((reaction, idx) => (
                  <button
                    key={idx}
                    onClick={() => handleReactionClick(msg.id, reaction.emoji)}
                    className="inline-flex items-center gap-1 px-1.5 py-0.5 bg-white/90 hover:bg-gray-100 border border-gray-300/50 rounded-full text-xs transition-all hover:scale-110 shadow-sm"
                    title={reaction.userNames?.slice(0, 10).join(', ')}
                  >
                    <span>{reaction.emoji}</span>
                    <span className="text-gray-600 font-medium">{reaction.count}</span>
                  </button>
                ))}
              </div>
            )}
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
        <div className="flex items-center space-x-2 px-4 py-3 bg-gradient-to-r from-gray-800 to-gray-850 border-b border-gray-700/50 shadow-lg backdrop-blur-sm animate-slide-down">
          <div className="flex-1 relative">
            <svg className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
            </svg>
            <input
              type="text"
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              onKeyDown={handleSearchKeyDown}
              placeholder="搜索消息内容..."
              className="w-full pl-10 pr-4 py-2.5 border border-gray-600 rounded-full text-sm focus:outline-none focus:ring-2 focus:ring-blue-500 text-white bg-gray-700/50 placeholder-gray-400 backdrop-blur transition-all duration-200 focus:shadow-[0_0_15px_rgba(59,130,246,0.3)]"
              autoFocus
            />
            {searchQuery && (
              <div className="absolute right-24 top-1/2 -translate-y-1/2 text-xs text-gray-500 pointer-events-none flex items-center gap-1">
                <kbd className="px-1.5 py-0.5 bg-gray-700 rounded text-[10px]">Enter</kbd> 跳转
              </div>
            )}
          </div>
          <div className="flex items-center space-x-1">
            {searchResults.length > 0 && (
              <>
                <span className="text-sm text-gray-400 px-2 py-1 bg-gray-700/50 rounded-lg">
                  {currentSearchIndex + 1} / {searchResults.length}
                </span>
                <button
                  onClick={() => handleSearchNavigate('prev')}
                  className="p-2 hover:bg-gray-700 rounded-lg text-gray-400 hover:text-white transition-all"
                  title="上一条 (Shift+Enter)"
                >
                  <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 19l-7-7 7-7" />
                  </svg>
                </button>
                <button
                  onClick={() => handleSearchNavigate('next')}
                  className="p-2 hover:bg-gray-700 rounded-lg text-gray-400 hover:text-white transition-all"
                  title="下一条 (Enter)"
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
              className="p-2 hover:bg-gray-700 rounded-lg text-gray-400 hover:text-white transition-all"
              title="关闭搜索 (Esc)"
            >
              <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
              </svg>
            </button>
          </div>
        </div>
      )}

      {/* 聊天头部 - 显示设置按钮 */}
      <div className="flex items-center justify-between px-4 py-2.5 bg-gradient-to-r from-gray-800/90 to-gray-800/70 backdrop-blur-xl border-b border-gray-700/50 shadow-lg">
        <div className="text-sm text-gray-400 font-medium">
          消息记录
        </div>
        <div className="flex items-center gap-2">
          <button
            onClick={() => setShowPinnedMessages(true)}
            className="p-2 text-gray-400 hover:text-yellow-400 hover:bg-gray-700/50 rounded-xl transition-all duration-200 hover:shadow-lg"
            title="置顶消息"
          >
            <svg className="w-4 h-4" fill="currentColor" viewBox="0 0 20 20">
              <path d="M10.894 2.553a1 1 0 00-1.788 0l-7 14a1 1 0 001.169 1.409l5-1.429A1 1 0 009 15.571V11a1 1 0 112 0v4.571a1 1 0 00.725.962l5 1.428a1 1 0 001.17-1.408l-7-14z" />
            </svg>
          </button>
          <button
            onClick={() => setShowChatSettings(true)}
            className="p-2 text-gray-400 hover:text-white hover:bg-gray-700/50 rounded-xl transition-all duration-200 hover:shadow-lg"
            title="聊天设置"
          >
            <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z" />
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />
            </svg>
          </button>
        </div>
      </div>

      {/* 消息列表 */}
      <div ref={containerRef} className="flex-1 overflow-y-auto">
        {/* 加载更多历史消息 */}
        {showLoadMore && (
          <div className="text-center py-3">
            {isLoadingHistory ? (
              <div className="flex items-center justify-center gap-2 text-gray-400">
                <svg className="animate-spin h-4 w-4" fill="none" viewBox="0 0 24 24">
                  <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" />
                  <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z" />
                </svg>
                <span className="text-sm">加载中...</span>
              </div>
            ) : (
              <button
                onClick={handleLoadHistory}
                className="px-4 py-1 text-sm text-blue-400 bg-gray-800 border border-blue-500 rounded-full hover:bg-gray-700 transition-colors"
              >
                加载更多历史记录
              </button>
            )}
          </div>
        )}

        {/* 骨架屏加载 */}
        {conversationMessages.length === 0 && isLoadingHistory ? (
          <div className="p-4 space-y-4">
            {[1, 2, 3, 4, 5].map((i) => (
              <div key={i} className={`flex ${i % 2 === 0 ? 'justify-end' : 'justify-start'} animate-pulse`}>
                <div className="w-8 h-8 rounded-full bg-gray-700 mr-2" />
                <div className="bg-gray-700 rounded-2xl px-4 py-3 max-w-[280px]">
                  <div className="h-4 bg-gray-600 rounded w-32 mb-2" />
                  <div className="h-3 bg-gray-600 rounded w-24" />
                </div>
              </div>
            ))}
          </div>
        ) : conversationMessages.length === 0 ? (
          <div className="text-center text-gray-500 py-8">
            <p>暂无消息</p>
            <p className="text-sm mt-2">发送一条消息开始聊天吧</p>
          </div>
        ) : virtualScrollEnabled ? (
          // 虚拟滚动模式
          <div style={{ height: totalScrollHeight, position: 'relative' }}>
            <div style={{ position: 'absolute', top: visibleStartIndex * MESSAGE_HEIGHT, width: '100%' }}>
              {conversationMessages.slice(visibleStartIndex, visibleEndIndex).map((msg, index) => {
                const actualIndex = visibleStartIndex + index
                const isOwn = isOwnMessage(msg.senderId)
                const showAvatar =
                  actualIndex === 0 ||
                  conversationMessages[actualIndex - 1].senderId !== msg.senderId
                const showMessageTime =
                  actualIndex === 0 ||
                  msg.createdAt - conversationMessages[actualIndex - 1].createdAt > 60000

                return (
                  <div
                    key={msg.id}
                    id={`msg-${msg.id}`}
                    className="transition-all duration-300"
                    style={{ height: MESSAGE_HEIGHT }}
                  >
                    {showMessageTime && (
                      <div className="text-center my-2">
                        <span className="px-3 py-1 bg-gray-800 text-gray-400 text-xs rounded-full">
                          {formatMessageTime(msg.createdAt)}
                          {msg.edited_at && <span className="ml-1 text-xs italic">(已编辑)</span>}
                        </span>
                      </div>
                    )}
                    <div
                      className={`px-4 py-1 ${isOwn ? 'justify-end' : 'justify-start'} flex animate-fade-in`}
                      style={{ display: 'flex' }}
                      onContextMenu={(e) => handleContextMenu(e, msg.id)}
                      onTouchStart={(e) => handleTouchStart(e, msg.id)}
                      onTouchEnd={handleTouchEnd}
                      onTouchMove={handleTouchMove}
                    >
                      {renderMessageBubble(msg, isOwn, showAvatar)}
                    </div>
                  </div>
                )
              })}
            </div>
          </div>
        ) : (
          // 普通滚动模式
          <div className="p-4 space-y-4">
            {conversationMessages.map((msg, index) => {
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
                        {msg.edited_at && <span className="ml-1 text-xs italic">(已编辑)</span>}
                      </span>
                    </div>
                  )}

                  {/* 消息气泡 */}
                  <div
                    className={`px-4 py-1 ${isOwn ? 'justify-end' : 'justify-start'} flex animate-fade-in`}
                    onContextMenu={(e) => handleContextMenu(e, msg.id)}
                    onTouchStart={(e) => handleTouchStart(e, msg.id)}
                    onTouchEnd={handleTouchEnd}
                    onTouchMove={handleTouchMove}
                  >
                    {renderMessageBubble(msg, isOwn, showAvatar)}
                  </div>
                </div>
              )
            })}
          </div>
        )}
        <div ref={messagesEndRef} />
      </div>

      {/* 未读消息指示器和滚动到底部按钮 */}
      {showScrollButton && (
        <button
          onClick={() => {
            messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' })
            // 滚动到底部后标记所有消息为已读
            const { ws } = useAppStore.getState()
            conversationMessages
              .filter(msg => msg.senderId !== user?.id && !msg.readBy?.some(r => r.userId === user?.id))
              .forEach(msg => ws?.readMessage(msg.id))
          }}
          className="absolute bottom-20 left-1/2 transform -translate-x-1/2 bg-gradient-to-r from-blue-500 to-indigo-600 hover:from-blue-600 hover:to-indigo-700 text-white px-5 py-3 rounded-full shadow-[0_4px_20px_rgba(59,130,246,0.4)] flex items-center gap-2 transition-all hover:scale-105 hover:shadow-[0_6px_30px_rgba(59,130,246,0.6)] z-40 border border-blue-400/30 backdrop-blur-sm group"
        >
          <span className="text-sm font-medium">滚动到底部</span>
          {unreadCount > 0 && (
            <span className="bg-white text-blue-600 text-xs font-bold px-2.5 py-1 rounded-full shadow-lg group-hover:scale-110 transition-transform">
              {unreadCount}
            </span>
          )}
          <svg className="w-4 h-4 group-hover:translate-y-0.5 transition-transform" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 14l-7 7m0 0l-7-7m7 7V3" />
          </svg>
        </button>
      )}

      {/* 置顶消息提示条 */}
      {pinnedMessageId && (
        <div className="absolute top-2 left-1/2 transform -translate-x-1/2 bg-gradient-to-r from-gray-800 to-gray-900 border border-gray-700/50 text-white px-4 py-2.5 rounded-full shadow-[0_4px_20px_rgba(0,0,0,0.3)] flex items-center gap-2 z-40 backdrop-blur-xl">
          <svg className="w-4 h-4 text-yellow-400 drop-shadow-[0_0_8px_rgba(250,204,21,0.5)]" fill="currentColor" viewBox="0 0 20 20">
            <path d="M10.894 2.553a1 1 0 00-1.788 0l-7 14a1 1 0 001.169 1.409l5-1.429A1 1 0 009 15.571V11a1 1 0 112 0v4.571a1 1 0 00.725.962l5 1.428a1 1 0 001.17-1.408l-7-14z" />
          </svg>
          <span className="text-sm font-medium">消息已置顶</span>
          <button onClick={() => setPinnedMessageId(null)} className="text-gray-400 hover:text-white p-1 hover:bg-gray-700 rounded-lg transition-all">
            <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>
      )}

      {/* 底部工具栏 - 搜索按钮 */}
      {!showSearch && (
        <div className="border-t border-gray-700/50 bg-gradient-to-r from-gray-800/90 to-gray-800/70 backdrop-blur-xl px-4 py-2.5 flex justify-end">
          <button
            onClick={() => setShowSearch(true)}
            className="flex items-center space-x-2 px-4 py-2 text-sm text-gray-300 hover:bg-gray-700/50 rounded-xl transition-all duration-200 hover:shadow-lg"
            title="搜索消息"
          >
            <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
            </svg>
            <span className="font-medium">查找聊天记录</span>
          </button>
        </div>
      )}

      {/* Toast Notification */}
      {toast.visible && (
        <div className="fixed top-20 left-1/2 transform -translate-x-1/2 bg-gradient-to-r from-gray-800 to-gray-900 text-white px-6 py-3.5 rounded-xl shadow-[0_10px_40px_rgba(0,0,0,0.4)] z-50 animate-fade-in border border-gray-700/50 backdrop-blur-xl">
          {toast.message}
        </div>
      )}

      {/* Context Menu */}
      {contextMenu.visible && (
        <ContextMenu
          x={contextMenu.x}
          y={contextMenu.y}
          messageId={contextMenu.messageId}
          messages={conversationMessages}
          user={user}
          pinnedMessageId={pinnedMessageId}
          onPinMessage={handlePinMessage}
          onUnpinMessage={handleUnpinMessage}
          onForwardMessage={handleForwardMessage}
          onReply={onReply}
          onDeleteForAll={handleDeleteForAll}
          onDeleteForSelf={handleDeleteForSelf}
          onEditMessage={(id) => {
            const msg = conversationMessages.find(m => m.id === id)
            if (msg) {
              setEditingMessage({ id: msg.id, content: msg.content || '' })
            }
          }}
          onClose={() => setContextMenu({ visible: false, x: 0, y: 0, messageId: null })}
          showToast={showToast}
        />
      )}

      {/* Reaction Picker */}
      {showReactionPicker.visible && (
        <ReactionPicker
          x={showReactionPicker.x}
          y={showReactionPicker.y}
          onSelect={handleAddReaction}
          onClose={() => setShowReactionPicker({ visible: false, x: 0, y: 0, messageId: null })}
        />
      )}

      {/* Forward Modal */}
      <ForwardModal
        visible={showForwardModal}
        conversations={useAppStore.getState().conversations}
        onSelectConversation={handleForwardToConversation}
        onClose={() => {
          setShowForwardModal(false)
          setForwardMessageId(null)
        }}
      />

      {/* Chat Settings Panel */}
      <ChatSettingsPanel
        visible={showChatSettings}
        conversationId={conversationId}
        onClose={() => setShowChatSettings(false)}
        onClearMessages={handleClearMessages}
      />

      {/* Pinned Messages Panel */}
      {showPinnedMessages && (
        <div className="fixed inset-0 z-50 flex justify-end">
          <div
            className="absolute inset-0 bg-black/50"
            onClick={() => setShowPinnedMessages(false)}
          />
          <PinnedMessages
            conversationId={conversationId}
            currentUserId={user?.id}
            onClose={() => setShowPinnedMessages(false)}
            onJumpToMessage={(messageId) => {
              setShowPinnedMessages(false)
              // Scroll to message
              const element = document.getElementById(`msg-${messageId}`)
              element?.scrollIntoView({ behavior: 'smooth', block: 'center' })
            }}
          />
        </div>
      )}

      {/* 编辑消息对话框 */}
      {editingMessage && (
        <EditMessageModal
          visible={true}
          content={editingMessage.content}
          onSave={handleEditMessage}
          onClose={() => setEditingMessage(null)}
        />
      )}
    </div>
  )
}

// 表情反应选择器组件
interface ReactionPickerProps {
  x: number
  y: number
  onSelect: (emoji: string) => void
  onClose: () => void
}

function ReactionPicker({ x, y, onSelect, onClose }: ReactionPickerProps) {
  const pickerRef = React.useRef<HTMLDivElement>(null)
  const [position, setPosition] = React.useState({ x: 0, y: 0 })

  const emojis = ['👍', '👎', '❤️', '😂', '😮', '😢', '🔥', '🎉', '✨', '💪']

  useEffect(() => {
    if (!pickerRef.current) return

    const pickerWidth = 280
    const pickerHeight = 60
    const padding = 10

    let newX = x - pickerWidth / 2
    let newY = y + 10

    // Check if menu would go off right edge
    if (x + pickerWidth / 2 > window.innerWidth - padding) {
      newX = window.innerWidth - pickerWidth - padding
    }

    // Check if menu would go off bottom edge
    if (y + pickerHeight > window.innerHeight - padding) {
      newY = y - pickerHeight - 10
    }

    // Ensure positive coordinates
    newX = Math.max(padding, newX)
    newY = Math.max(padding, newY)

    setPosition({ x: newX, y: newY })
  }, [x, y])

  useEffect(() => {
    const handleClick = () => onClose()
    document.addEventListener('click', handleClick)
    return () => document.removeEventListener('click', handleClick)
  }, [onClose])

  return (
    <div
      ref={pickerRef}
      className="fixed bg-gradient-to-br from-gray-800 to-gray-900 border border-gray-700/50 rounded-full shadow-[0_10px_40px_rgba(0,0,0,0.5)] z-50 px-3 py-2 flex gap-1.5 backdrop-blur-xl animate-scale-up"
      style={{ left: position.x, top: position.y }}
      onClick={(e) => e.stopPropagation()}
    >
      {emojis.map((emoji) => (
        <button
          key={emoji}
          onClick={() => {
            onSelect(emoji)
            onClose()
          }}
          className="w-9 h-9 flex items-center justify-center text-xl hover:bg-white/20 rounded-full transition-all duration-200 hover:scale-125 active:scale-95"
          title={emoji}
        >
          {emoji}
        </button>
      ))}
    </div>
  )
}

// 转发消息对话框
interface ForwardModalProps {
  visible: boolean
  conversations: Conversation[]
  onSelectConversation: (convId: number) => void
  onClose: () => void
}

function ForwardModal({ visible, conversations, onSelectConversation, onClose }: ForwardModalProps) {
  if (!visible) return null

  return (
    <div className="fixed inset-0 bg-black/50 z-50 flex items-center justify-center">
      <div className="bg-gray-800 rounded-xl w-full max-w-md mx-4 max-h-[60vh] flex flex-col">
        <div className="flex items-center justify-between p-4 border-b border-gray-700">
          <h3 className="text-lg font-semibold text-white">转发消息</h3>
          <button onClick={onClose} className="text-gray-400 hover:text-white">
            <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>
        <div className="flex-1 overflow-y-auto p-2">
          {conversations.length === 0 ? (
            <div className="text-center text-gray-400 py-8">暂无可转发的会话</div>
          ) : (
            conversations.map((conv) => (
              <button
                key={conv.id}
                onClick={() => onSelectConversation(conv.id)}
                className="w-full flex items-center gap-3 p-3 hover:bg-gray-700 rounded-lg transition-colors"
              >
                <div className="w-10 h-10 rounded-full bg-gradient-to-br from-blue-500 to-purple-600 flex items-center justify-center text-white font-medium flex-shrink-0">
                  {conv.name?.charAt(0).toUpperCase() || conv.participants?.[0]?.charAt(0).toUpperCase() || '#'}
                </div>
                <div className="flex-1 text-left min-w-0">
                  <div className="text-white font-medium truncate">
                    {conv.name || '未知会话'}
                  </div>
                  <div className="text-gray-400 text-sm truncate">
                    {conv.type === 'direct' ? '私信' : conv.type === 'group' ? '群组' : '频道'}
                  </div>
                </div>
              </button>
            ))
          )}
        </div>
      </div>
    </div>
  )
}

// 聊天设置面板
interface ChatSettingsPanelProps {
  visible: boolean
  conversationId: number
  onClose: () => void
  onClearMessages: () => void
}

function ChatSettingsPanel({ visible, conversationId, onClose, onClearMessages }: ChatSettingsPanelProps) {
  const [isMuted, setIsMuted] = useState(false)
  const [loading, setLoading] = useState(false)

  if (!visible) return null

  const handleToggleMute = async () => {
    setLoading(true)
    const api = getApiClient()
    try {
      if (isMuted) {
        await api.unmuteConversation(conversationId)
      } else {
        await api.muteConversation(conversationId)
      }
      setIsMuted(!isMuted)
    } catch {
      // 忽略错误
    } finally {
      setLoading(false)
    }
  }

  const handleClearMessages = async () => {
    if (!confirm('确定要清空此会话的聊天记录吗？此操作不可恢复。')) return
    onClearMessages()
    onClose()
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-50 flex items-center justify-center">
      <div className="bg-gray-800 rounded-xl w-full max-w-md mx-4">
        <div className="flex items-center justify-between p-4 border-b border-gray-700">
          <h3 className="text-lg font-semibold text-white">聊天设置</h3>
          <button onClick={onClose} className="text-gray-400 hover:text-white">
            <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>
        <div className="p-4 space-y-4">
          {/* 免打扰 */}
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-3">
              <svg className="w-5 h-5 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5.586 15H4a1 1 0 01-1-1v-4a1 1 0 011-1h1.586l4.707-4.707C10.923 3.663 12 4.109 12 5v14c0 .891-1.077 1.337-1.707.707L5.586 15z" />
              </svg>
              <span className="text-white">免打扰</span>
            </div>
            <button
              onClick={handleToggleMute}
              disabled={loading}
              className={`w-12 h-6 rounded-full transition-colors ${
                isMuted ? 'bg-blue-500' : 'bg-gray-600'
              }`}
            >
              <div
                className={`w-5 h-5 bg-white rounded-full transform transition-transform ${
                  isMuted ? 'translate-x-6' : 'translate-x-1'
                }`}
              />
            </button>
          </div>

          {/* 查找聊天记录 */}
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-3">
              <svg className="w-5 h-5 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
              </svg>
              <span className="text-white">查找聊天记录</span>
            </div>
            <button
              onClick={() => {
                onClose()
                // 触发搜索
                setTimeout(() => {
                  const event = new CustomEvent('open-chat-search')
                  window.dispatchEvent(event)
                }, 100)
              }}
              className="text-gray-400 hover:text-white"
            >
              <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 5l7 7-7 7" />
              </svg>
            </button>
          </div>

          <div className="border-t border-gray-700 my-2"></div>

          {/* 清空聊天记录 */}
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-3">
              <svg className="w-5 h-5 text-red-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
              </svg>
              <span className="text-white">清空聊天记录</span>
            </div>
            <button
              onClick={handleClearMessages}
              className="px-4 py-2 bg-red-500 text-white text-sm rounded-lg hover:bg-red-600 transition-colors"
            >
              清空
            </button>
          </div>
        </div>
      </div>
    </div>
  )
}

// 编辑消息对话框
interface EditMessageModalProps {
  visible: boolean
  content: string
  onSave: (content: string) => void
  onClose: () => void
}

function EditMessageModal({ visible, content, onSave, onClose }: EditMessageModalProps) {
  const [editedContent, setEditedContent] = useState(content)

  useEffect(() => {
    setEditedContent(content)
  }, [content])

  if (!visible) return null

  const handleSave = () => {
    if (editedContent.trim()) {
      onSave(editedContent.trim())
    }
  }

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter' && (e.ctrlKey || e.metaKey)) {
      e.preventDefault()
      handleSave()
    } else if (e.key === 'Escape') {
      onClose()
    }
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-50 flex items-center justify-center">
      <div className="bg-gray-800 rounded-xl w-full max-w-lg mx-4">
        <div className="flex items-center justify-between p-4 border-b border-gray-700">
          <h3 className="text-lg font-semibold text-white">编辑消息</h3>
          <button onClick={onClose} className="text-gray-400 hover:text-white">
            <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>
        <div className="p-4">
          <textarea
            value={editedContent}
            onChange={(e) => setEditedContent(e.target.value)}
            onKeyDown={handleKeyDown}
            placeholder="编辑消息内容..."
            rows={6}
            autoFocus
            className="w-full px-4 py-3 bg-gray-700 border border-gray-600 rounded-xl
                     text-white placeholder-gray-500 focus:outline-none focus:ring-2
                     focus:ring-blue-500 focus:border-transparent resize-none"
          />
          <p className="mt-2 text-xs text-gray-400">提示：Ctrl+Enter 保存，Esc 取消</p>
        </div>
        <div className="p-4 border-t border-gray-700 flex justify-end gap-2">
          <button
            onClick={onClose}
            className="px-4 py-2 text-gray-400 hover:text-white transition-colors"
          >
            取消
          </button>
          <button
            onClick={handleSave}
            disabled={!editedContent.trim()}
            className="px-4 py-2 bg-blue-500 text-white rounded-lg hover:bg-blue-600 disabled:bg-gray-600 disabled:cursor-not-allowed transition-colors"
          >
            保存
          </button>
        </div>
      </div>
    </div>
  )
}

export default MessageList

// Context Menu Component with viewport-aware positioning
interface ContextMenuProps {
  x: number
  y: number
  messageId: number | null
  messages: Message[]
  user: { id: string; displayName?: string } | undefined
  pinnedMessageId: number | null
  onPinMessage: () => void
  onUnpinMessage: () => void
  onForwardMessage: () => void
  onReply?: (data: { id: number; senderName: string; content: string }) => void
  onDeleteForAll: () => void
  onDeleteForSelf: () => void
  onEditMessage: (id: number) => void
  onClose: () => void
  showToast: (message: string) => void
}

function ContextMenu({
  x,
  y,
  messageId,
  messages,
  user,
  pinnedMessageId,
  onPinMessage,
  onUnpinMessage,
  onForwardMessage,
  onReply,
  onDeleteForAll,
  onDeleteForSelf,
  onEditMessage,
  onClose,
  showToast
}: ContextMenuProps) {
  const menuRef = React.useRef<HTMLDivElement>(null)
  const [position, setPosition] = React.useState({ x: 0, y: 0 })

  useEffect(() => {
    if (!menuRef.current) return

    const menuWidth = 200
    const menuHeight = 400
    const padding = 10

    let newX = x
    let newY = y

    // Check if menu would go off right edge
    if (x + menuWidth > window.innerWidth - padding) {
      newX = window.innerWidth - menuWidth - padding
    }

    // Check if menu would go off bottom edge
    if (y + menuHeight > window.innerHeight - padding) {
      newY = window.innerHeight - menuHeight - padding
    }

    // Ensure positive coordinates
    newX = Math.max(padding, newX)
    newY = Math.max(padding, newY)

    setPosition({ x: newX, y: newY })
  }, [x, y])

  const message = messages.find(m => m.id === messageId)

  return (
    <div
      ref={menuRef}
      className="fixed bg-gradient-to-br from-gray-800 to-gray-900 border border-gray-700/50 rounded-2xl shadow-[0_10px_40px_rgba(0,0,0,0.5)] z-50 py-1.5 min-w-[200px] max-h-[80vh] overflow-y-auto backdrop-blur-xl animate-scale-up"
      style={{ left: position.x, top: position.y }}
      onClick={(e) => e.stopPropagation()}
    >
      <div className="px-3 py-2 border-b border-gray-700/50 mb-1">
        <p className="text-xs text-gray-400 font-medium truncate max-w-[180px]">消息操作</p>
      </div>
      <button
        onClick={onDeleteForAll}
        className="w-full px-4 py-2.5 text-left text-sm text-red-400 hover:bg-gradient-to-r hover:from-red-500/15 hover:to-red-500/5 transition-all duration-200 flex items-center gap-2.5 group"
      >
        <svg className="w-4.5 h-4.5 group-hover:scale-110 transition-transform" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
        </svg>
        <span>删除（双向）</span>
      </button>
      <button
        onClick={onDeleteForSelf}
        className="w-full px-4 py-2.5 text-left text-sm text-gray-300 hover:bg-gradient-to-r hover:from-gray-700/50 hover:to-gray-700/30 transition-all duration-200 flex items-center gap-2.5 group"
      >
        <svg className="w-4.5 h-4.5 group-hover:scale-110 transition-transform" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
        </svg>
        <span>删除（仅自己）</span>
      </button>
      <div className="border-t border-gray-700/50 my-1"></div>
      {pinnedMessageId === messageId ? (
        <button
          onClick={onUnpinMessage}
          className="w-full px-4 py-2.5 text-left text-sm text-yellow-400 hover:bg-gradient-to-r hover:from-yellow-500/15 hover:to-yellow-500/5 transition-all duration-200 flex items-center gap-2.5 group"
        >
          <svg className="w-4.5 h-4.5 group-hover:scale-110 transition-transform" fill="currentColor" viewBox="0 0 20 20">
            <path d="M10.894 2.553a1 1 0 00-1.788 0l-7 14a1 1 0 001.169 1.409l5-1.429A1 1 0 009 15.571V11a1 1 0 112 0v4.571a1 1 0 00.725.962l5 1.428a1 1 0 001.17-1.408l-7-14z" />
          </svg>
          <span>取消置顶</span>
        </button>
      ) : (
        <button
          onClick={onPinMessage}
          className="w-full px-4 py-2.5 text-left text-sm text-gray-300 hover:bg-gradient-to-r hover:from-gray-700/50 hover:to-gray-700/30 transition-all duration-200 flex items-center gap-2.5 group"
        >
          <svg className="w-4.5 h-4.5 group-hover:scale-110 transition-transform text-yellow-400" fill="currentColor" viewBox="0 0 20 20">
            <path d="M10.894 2.553a1 1 0 00-1.788 0l-7 14a1 1 0 001.169 1.409l5-1.429A1 1 0 009 15.571V11a1 1 0 112 0v4.571a1 1 0 00.725.962l5 1.428a1 1 0 001.17-1.408l-7-14z" />
          </svg>
          <span>置顶消息</span>
        </button>
      )}
      <div className="border-t border-gray-700/50 my-1"></div>
      <button
        onClick={() => {
          if (message && onReply) {
            onReply({
              id: message.id,
              senderName: message.sender?.displayName || message.senderUsername || '未知用户',
              content: message.content || ''
            })
          }
          onClose()
        }}
        className="w-full px-4 py-2.5 text-left text-sm text-gray-300 hover:bg-gradient-to-r hover:from-gray-700/50 hover:to-gray-700/30 transition-all duration-200 flex items-center gap-2.5 group"
      >
        <svg className="w-4.5 h-4.5 group-hover:scale-110 transition-transform" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M3 10h10a8 8 0 018 8v2M3 10l6 6m-6-6l6-6" />
        </svg>
        <span>回复</span>
      </button>
      <div className="border-t border-gray-700/50 my-1"></div>
      <button
        onClick={onForwardMessage}
        className="w-full px-4 py-2.5 text-left text-sm text-gray-300 hover:bg-gradient-to-r hover:from-gray-700/50 hover:to-gray-700/30 transition-all duration-200 flex items-center gap-2.5 group"
      >
        <svg className="w-4.5 h-4.5 group-hover:scale-110 transition-transform" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 19l9 2-9-18-9 18 9-2zm0 0v-8" />
        </svg>
        <span>转发</span>
      </button>
      <div className="border-t border-gray-700/50 my-1"></div>
      {message?.senderId === user?.id && (
        <button
          onClick={() => {
            onEditMessage(message.id)
            onClose()
          }}
          className="w-full px-4 py-2.5 text-left text-sm text-gray-300 hover:bg-gradient-to-r hover:from-gray-700/50 hover:to-gray-700/30 transition-all duration-200 flex items-center gap-2.5 group"
        >
          <svg className="w-4.5 h-4.5 group-hover:scale-110 transition-transform" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z" />
          </svg>
          <span>编辑</span>
        </button>
      )}
      <div className="border-t border-gray-700/50 my-1"></div>
      <button
        onClick={() => {
          navigator.clipboard.writeText(message?.content || '')
          showToast('已复制文本')
          onClose()
        }}
        className="w-full px-4 py-2.5 text-left text-sm text-gray-300 hover:bg-gradient-to-r hover:from-gray-700/50 hover:to-gray-700/30 transition-all duration-200 flex items-center gap-2.5 group"
      >
        <svg className="w-4.5 h-4.5 group-hover:scale-110 transition-transform" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z" />
        </svg>
        <span>复制文本</span>
      </button>
    </div>
  )
}
