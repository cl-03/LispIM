/**
 * 消息反应组件
 * 支持添加、移除表情反应
 */

import React, { useState } from 'react'
import { getApiClient } from '@/utils/api-client'

interface Reaction {
  id: number
  emoji: string
  userIds: string[]
  count: number
  createdAt: number
}

interface MessageReactionsProps {
  messageId: number
  initialReactions?: Reaction[]
  currentUserId?: string
}

const COMMON_EMOJIS = [
  '👍', '❤️', '😂', '😮', '😢', '😡',
  '👎', '💯', '🔥', '✨', '🎉', '🤔',
  '👀', '🙏', '💪', '💖', '🚀', '👋'
]

export const MessageReactions: React.FC<MessageReactionsProps> = ({
  messageId,
  initialReactions = [],
  currentUserId
}) => {
  const api = getApiClient()
  const [reactions, setReactions] = useState<Reaction[]>(initialReactions)
  const [showPicker, setShowPicker] = useState(false)
  const [loading, setLoading] = useState(false)

  // 添加反应
  const handleAddReaction = async (emoji: string) => {
    if (loading) return

    setLoading(true)
    try {
      const result = await api.addReaction(messageId, emoji)
      if (result.success && result.data) {
        setReactions(prev => {
          const existing = prev.find(r => r.emoji === emoji)
          if (existing) {
            return prev.map(r =>
              r.emoji === emoji
                ? { ...r, count: r.count + 1, userIds: [...r.userIds, currentUserId!] }
                : r
            )
          }
          return [...prev, {
            id: result.data.id,
            emoji,
            userIds: [currentUserId!],
            count: 1,
            createdAt: Date.now() / 1000
          }]
        })
      }
    } catch (error) {
      console.error('Failed to add reaction:', error)
    } finally {
      setLoading(false)
      setShowPicker(false)
    }
  }

  // 移除反应
  const handleRemoveReaction = async (emoji: string) => {
    if (loading) return

    setLoading(true)
    try {
      const result = await api.removeReaction(messageId, emoji)
      if (result.success) {
        setReactions(prev =>
          prev
            .map(r => {
              if (r.emoji === emoji) {
                return {
                  ...r,
                  count: r.count - 1,
                  userIds: r.userIds.filter(id => id !== currentUserId)
                }
              }
              return r
            })
            .filter(r => r.count > 0)
        )
      }
    } catch (error) {
      console.error('Failed to remove reaction:', error)
    } finally {
      setLoading(false)
    }
  }

  // 检查当前用户是否已反应
  const hasReacted = (emoji: string) => {
    const reaction = reactions.find(r => r.emoji === emoji)
    return reaction?.userIds.includes(currentUserId!)
  }

  return (
    <div className="relative">
      {/* 反应列表 */}
      <div className="flex flex-wrap items-center gap-1 mt-2">
        {reactions.map((reaction) => {
          const userReacted = hasReacted(reaction.emoji)
          return (
            <button
              key={reaction.id}
              onClick={() => userReacted ? handleRemoveReaction(reaction.emoji) : handleAddReaction(reaction.emoji)}
              className={`inline-flex items-center gap-1 px-2 py-1 rounded-full text-sm transition-all ${
                userReacted
                  ? 'bg-blue-500 text-white shadow-md'
                  : 'bg-gray-100 dark:bg-gray-700 text-gray-700 dark:text-gray-300 hover:bg-gray-200 dark:hover:bg-gray-600'
              }`}
              title={userReacted ? '移除反应' : '添加反应'}
            >
              <span className="text-base">{reaction.emoji}</span>
              <span className="font-medium">{reaction.count}</span>
            </button>
          )
        })}

        {/* 添加反应按钮 */}
        <button
          onClick={() => setShowPicker(!showPicker)}
          disabled={loading}
          className="w-7 h-7 flex items-center justify-center rounded-full bg-gray-100 dark:bg-gray-700 text-gray-500 hover:bg-gray-200 dark:hover:bg-gray-600 transition-colors"
          title="添加反应"
        >
          <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 4v16m8-8H4" />
          </svg>
        </button>
      </div>

      {/* 表情选择器 */}
      {showPicker && (
        <>
          {/* 遮罩层 */}
          <div
            className="fixed inset-0 z-40"
            onClick={() => setShowPicker(false)}
          />

          {/* 选择器面板 */}
          <div className="absolute bottom-full left-0 mb-2 bg-white dark:bg-gray-800 rounded-xl shadow-xl border border-gray-200 dark:border-gray-700 p-3 z-50 min-w-[200px]">
            <div className="grid grid-cols-6 gap-2">
              {COMMON_EMOJIS.map((emoji) => (
                <button
                  key={emoji}
                  onClick={() => handleAddReaction(emoji)}
                  disabled={loading}
                  className={`w-8 h-8 flex items-center justify-center text-xl rounded-lg transition-all ${
                    hasReacted(emoji)
                      ? 'bg-blue-100 dark:bg-blue-900 ring-2 ring-blue-500'
                      : 'hover:bg-gray-100 dark:hover:bg-gray-700'
                  }`}
                >
                  {emoji}
                </button>
              ))}
            </div>
          </div>
        </>
      )}
    </div>
  )
}

export default MessageReactions
