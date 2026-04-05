/**
 * 键盘快捷键 Hook
 *
 * 支持的快捷键：
 * - Ctrl/Cmd + K: 打开搜索
 * - Ctrl/Cmd + Enter: 发送消息
 * - Escape: 关闭弹窗/取消回复
 * - Ctrl/Cmd + Shift + N: 新建聊天
 * - Ctrl/Cmd + ,: 打开设置
 */

import { useEffect, useCallback } from 'react'

interface KeyboardShortcutOptions {
  onSearch?: () => void
  onSendMessage?: () => void
  onClose?: () => void
  onNewChat?: () => void
  onOpenSettings?: () => void
  enabled?: boolean
}

export function useKeyboardShortcuts(options: KeyboardShortcutOptions = {}) {
  const {
    onSearch,
    onSendMessage,
    onClose,
    onNewChat,
    onOpenSettings,
    enabled = true
  } = options

  const handleKeyDown = useCallback((e: KeyboardEvent) => {
    if (!enabled) return

    // 检查是否在输入框中
    const target = e.target as HTMLElement
    const isInput = target.tagName === 'INPUT' || target.tagName === 'TEXTAREA'

    // Ctrl/Cmd + K: 打开搜索（不在输入框中时触发）
    if ((e.ctrlKey || e.metaKey) && e.key === 'k' && !isInput) {
      e.preventDefault()
      onSearch?.()
      return
    }

    // Ctrl/Cmd + Enter: 发送消息（在输入框中时触发）
    if ((e.ctrlKey || e.metaKey) && e.key === 'Enter' && isInput) {
      e.preventDefault()
      onSendMessage?.()
      return
    }

    // Escape: 关闭弹窗/取消回复
    if (e.key === 'Escape') {
      e.preventDefault()
      onClose?.()
      return
    }

    // Ctrl/Cmd + Shift + N: 新建聊天
    if ((e.ctrlKey || e.metaKey) && e.shiftKey && e.key === 'N') {
      e.preventDefault()
      onNewChat?.()
      return
    }

    // Ctrl/Cmd + ,: 打开设置
    if ((e.ctrlKey || e.metaKey) && e.key === ',') {
      e.preventDefault()
      onOpenSettings?.()
      return
    }
  }, [enabled, onSearch, onSendMessage, onClose, onNewChat, onOpenSettings])

  useEffect(() => {
    if (!enabled) return

    window.addEventListener('keydown', handleKeyDown)
    return () => window.removeEventListener('keydown', handleKeyDown)
  }, [handleKeyDown, enabled])
}

// 全局快捷键帮助文本
export const KEYBOARD_SHORTCUTS = [
  { keys: 'Ctrl+K', description: '打开搜索' },
  { keys: 'Ctrl+Enter', description: '发送消息' },
  { keys: 'Esc', description: '关闭弹窗/取消回复' },
  { keys: 'Ctrl+Shift+N', description: '新建聊天' },
  { keys: 'Ctrl+,', description: '打开设置' },
]
