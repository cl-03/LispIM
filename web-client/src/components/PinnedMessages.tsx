/**
 * PinnedMessages 组件 - 置顶消息
 */

import React, { useState, useEffect, useCallback } from 'react'
import { getApiClient } from '../utils/api-client'
import type { PinnedMessage } from '../types'

interface PinnedMessagesProps {
  conversationId: number
  currentUserId?: string
  onClose: () => void
  onJumpToMessage: (messageId: number) => void
}

export const PinnedMessages: React.FC<PinnedMessagesProps> = ({
  conversationId,
  onClose,
  onJumpToMessage
}) => {
  const api = getApiClient()
  const [pinnedMessages, setPinnedMessages] = useState<PinnedMessage[]>([])
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [isCollapsed, setIsCollapsed] = useState(false)

  // 加载置顶消息
  const loadPinnedMessages = useCallback(async () => {
    setLoading(true)
    setError(null)
    try {
      const result = await api.getPinnedMessages(conversationId)
      if (result.success && result.data) {
        setPinnedMessages(result.data as PinnedMessage[])
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : '加载置顶消息失败')
    } finally {
      setLoading(false)
    }
  }, [conversationId, api])

  useEffect(() => {
    loadPinnedMessages()
  }, [loadPinnedMessages])

  // 取消置顶
  const handleUnpin = async (messageId: number, e: React.MouseEvent) => {
    e.stopPropagation()
    try {
      const result = await api.unpinMessage(messageId, conversationId)
      if (result.success) {
        loadPinnedMessages()
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : '取消置顶失败')
    }
  }

  // 跳转到消息
  const handleJumpToMessage = (messageId: number) => {
    onJumpToMessage(messageId)
    onClose()
  }

  // 获取消息类型图标
  const getMessageTypeIcon = (type: string) => {
    const icons: Record<string, string> = {
      text: '💬',
      image: '🖼️',
      file: '📁',
      voice: '🎤',
      video: '🎥',
      link: '🔗',
      system: '⚙️',
      notification: '🔔'
    }
    return icons[type] || '💬'
  }

  // 截断内容
  const truncateContent = (content: string, maxLength = 50) => {
    if (!content) return ''
    if (content.length <= maxLength) return content
    return content.slice(0, maxLength) + '...'
  }

  if (loading) {
    return (
      <div className="bg-gray-800/95 backdrop-blur-sm border-l border-gray-700 w-80 h-full shadow-2xl">
        <div className="flex items-center justify-between p-4 border-b border-gray-700">
          <h3 className="text-white font-semibold">置顶消息</h3>
          <button
            onClick={onClose}
            className="text-gray-400 hover:text-white transition-colors"
          >
            <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>
        <div className="flex items-center justify-center h-32">
          <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-blue-500"></div>
        </div>
      </div>
    )
  }

  return (
    <div className="bg-gray-800/95 backdrop-blur-sm border-l border-gray-700 w-80 h-full shadow-2xl flex flex-col">
      {/* Header */}
      <div className="flex items-center justify-between p-4 border-b border-gray-700">
        <div className="flex items-center gap-2">
          <svg className="w-5 h-5 text-yellow-400" fill="currentColor" viewBox="0 0 20 20">
            <path d="M10.894 2.553a1 1 0 00-1.788 0l-7 14a1 1 0 001.169 1.409l5-1.429A1 1 0 009 15.571V11a1 1 0 112 0v4.571a1 1 0 00.725.962l5 1.428a1 1 0 001.17-1.408l-7-14z" />
          </svg>
          <h3 className="text-white font-semibold">置顶消息</h3>
          {pinnedMessages.length > 0 && (
            <span className="bg-yellow-500 text-gray-900 text-xs font-bold px-2 py-0.5 rounded-full">
              {pinnedMessages.length}
            </span>
          )}
        </div>
        <div className="flex items-center gap-1">
          <button
            onClick={() => setIsCollapsed(!isCollapsed)}
            className="p-1 text-gray-400 hover:text-white hover:bg-gray-700 rounded transition-colors"
            title={isCollapsed ? '展开' : '收起'}
          >
            <svg
              className={`w-4 h-4 transition-transform ${isCollapsed ? 'rotate-180' : ''}`}
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24"
            >
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 9l-7 7-7-7" />
            </svg>
          </button>
          <button
            onClick={onClose}
            className="p-1 text-gray-400 hover:text-white hover:bg-gray-700 rounded transition-colors"
          >
            <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>
      </div>

      {/* Error */}
      {error && (
        <div className="mx-4 mt-3 p-3 bg-red-500/10 border border-red-500/30 rounded-lg">
          <p className="text-red-400 text-sm">{error}</p>
        </div>
      )}

      {/* Body */}
      <div className="flex-1 overflow-y-auto">
        {isCollapsed ? (
          <div className="p-4">
            <button
              onClick={() => setIsCollapsed(false)}
              className="w-full py-2 text-sm text-blue-400 hover:bg-gray-700 rounded-lg transition-colors"
            >
              展开查看置顶消息
            </button>
          </div>
        ) : pinnedMessages.length === 0 ? (
          <div className="flex flex-col items-center justify-center h-48 text-gray-400">
            <svg className="w-16 h-16 mb-4 text-gray-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path
                strokeLinecap="round"
                strokeLinejoin="round"
                strokeWidth={1.5}
                d="M5 5a2 2 0 012-2h10a2 2 0 012 2v16l-7-3.5L5 21V5z"
              />
            </svg>
            <p className="text-sm">暂无置顶消息</p>
            <p className="text-xs mt-2 text-gray-500">右键消息选择"置顶"可以快速查看</p>
          </div>
        ) : (
          <div className="p-2 space-y-2">
            {pinnedMessages.map((msg) => (
              <div
                key={msg.messageId}
                onClick={() => handleJumpToMessage(msg.messageId)}
                className="group p-3 bg-gray-700/50 hover:bg-gray-700 border border-gray-600 hover:border-yellow-500/50 rounded-lg cursor-pointer transition-all duration-200 hover:shadow-lg"
              >
                <div className="flex items-start justify-between gap-2">
                  <div className="flex items-center gap-2 flex-1 min-w-0">
                    <span className="text-lg flex-shrink-0">
                      {getMessageTypeIcon(msg.type)}
                    </span>
                    <div className="flex-1 min-w-0">
                      <p className="text-white text-sm font-medium truncate">
                        {msg.pinnedByUsername || '未知用户'}
                      </p>
                      <p className="text-gray-300 text-xs mt-1 line-clamp-2">
                        {truncateContent(msg.content || '')}
                      </p>
                    </div>
                  </div>
                  <button
                    onClick={(e) => handleUnpin(msg.messageId, e)}
                    className="opacity-0 group-hover:opacity-100 p-1 text-gray-400 hover:text-red-400 hover:bg-red-500/10 rounded transition-all"
                    title="取消置顶"
                  >
                    <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
                    </svg>
                  </button>
                </div>
                <div className="flex items-center justify-between mt-2 pt-2 border-t border-gray-600/50">
                  <span className="text-xs text-gray-500">
                    {new Date(msg.pinnedAt).toLocaleString('zh-CN', {
                      month: 'numeric',
                      day: 'numeric',
                      hour: '2-digit',
                      minute: '2-digit'
                    })}
                  </span>
                  <span className="text-xs text-gray-500">
                    由 {msg.pinnedByUsername || '管理员'} 置顶
                  </span>
                </div>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  )
}

export default PinnedMessages
