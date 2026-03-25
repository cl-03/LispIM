import dayjs from 'dayjs'
import relativeTime from 'dayjs/plugin/relativeTime'
import 'dayjs/locale/zh-cn'

dayjs.extend(relativeTime)
dayjs.locale('zh-cn')

/**
 * 格式化消息时间
 */
export function formatMessageTime(timestamp: number): string {
  const now = dayjs()
  const messageTime = dayjs(timestamp * 1000)

  if (now.isSame(messageTime, 'day')) {
    return messageTime.format('HH:mm')
  } else if (now.subtract(1, 'day').isSame(messageTime, 'day')) {
    return `昨天 ${messageTime.format('HH:mm')}`
  } else if (now.subtract(6, 'day').isAfter(messageTime)) {
    return messageTime.format('MM/DD HH:mm')
  } else {
    return messageTime.format('YYYY/MM/DD HH:mm')
  }
}

/**
 * 格式化相对时间
 */
export function formatRelativeTime(timestamp: number): string {
  return dayjs(timestamp * 1000).fromNow()
}

/**
 * 格式化文件大小
 */
export function formatFileSize(bytes: number): string {
  if (bytes === 0) return '0 B'
  const k = 1024
  const sizes = ['B', 'KB', 'MB', 'GB', 'TB']
  const i = Math.floor(Math.log(bytes) / Math.log(k))
  return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i]
}

/**
 * 生成消息摘要
 */
export function getMessagePreview(content: string, maxLength: number = 50): string {
  if (content.length <= maxLength) return content
  return content.substring(0, maxLength) + '...'
}

/**
 * 提取提及的用户
 */
export function extractMentions(content: string): string[] {
  const mentionRegex = /@(\w+)/g
  const matches = content.matchAll(mentionRegex)
  return Array.from(matches, m => m[1])
}

/**
 * 移除提及标记
 */
export function removeMentions(content: string): string {
  return content.replace(/@\w+\s?/g, '')
}

/**
 * 检查消息是否包含链接
 */
export function containsLink(content: string): boolean {
  const urlRegex = /(https?:\/\/[^\s]+)/g
  return urlRegex.test(content)
}

/**
 * 提取链接
 */
export function extractLinks(content: string): string[] {
  const urlRegex = /(https?:\/\/[^\s]+)/g
  const matches = content.match(urlRegex)
  return matches || []
}

/**
 * 自动链接化文本中的 URL
 */
export function linkifyText(content: string): string {
  const urlRegex = /(https?:\/\/[^\s]+)/g
  return content.replace(urlRegex, '<a href="$1" target="_blank" rel="noopener noreferrer">$1</a>')
}

/**
 * 表情符号映射
 */
export const emojiMap: Record<string, string> = {
  ':)': '😊',
  ':D': '😀',
  ':(': '😢',
  ';)': '😉',
  ':P': '😛',
  '<3': '❤️',
  ':+1:': '👍',
  ':-1:': '👎',
  ':fire:': '🔥',
  ':celebration:': '🎉'
}

/**
 * 文本表情转换
 */
export function replaceEmojis(content: string): string {
  let result = content
  for (const [key, emoji] of Object.entries(emojiMap)) {
    result = result.replace(new RegExp(key.replace(/[()+]/g, '\\$&'), 'g'), emoji)
  }
  return result
}

/**
 * 将 [emoji:N] 格式转换为 img 标签
 */
export function renderEmojiGifs(content: string): string {
  return content.replace(/\[emoji:(\d+)\]/g, '<img src="/emojis/$1.gif" alt="emoji" class="emoji-gif" loading="lazy" />')
}

/**
 * 防抖函数
 */
export function debounce<T extends (...args: unknown[]) => unknown>(
  func: T,
  wait: number
): (...args: Parameters<T>) => void {
  let timeout: ReturnType<typeof setTimeout> | null = null
  return (...args: Parameters<T>) => {
    if (timeout) clearTimeout(timeout)
    timeout = setTimeout(() => func(...args), wait)
  }
}

/**
 * 节流函数
 */
export function throttle<T extends (...args: unknown[]) => unknown>(
  func: T,
  limit: number
): (...args: Parameters<T>) => void {
  let inThrottle: boolean = false
  return (...args: Parameters<T>) => {
    if (!inThrottle) {
      func(...args)
      inThrottle = true
      setTimeout(() => (inThrottle = false), limit)
    }
  }
}

/**
 * WebSocket 连接配置 - 使用本地端口 3000
 */
export const WS_CONFIG = {
  url: 'ws://localhost:3000/ws',
  reconnectInterval: 3000,
  maxReconnectAttempts: 5,
  heartbeatInterval: 30000
}

/**
 * 消息类型枚举
 */
export enum MessageType {
  TEXT = 'text',
  IMAGE = 'image',
  VOICE = 'voice',
  VIDEO = 'video',
  FILE = 'file',
  SYSTEM = 'system',
  NOTIFICATION = 'notification'
}

/**
 * 消息状态枚举
 */
export enum MessageStatus {
  SENDING = 'sending',
  SENT = 'sent',
  DELIVERED = 'delivered',
  READ = 'read',
  FAILED = 'failed'
}

/**
 * 生成唯一消息 ID
 */
export function generateMessageId(): string {
  return `msg_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`
}

/**
 * 验证消息内容
 */
export function validateMessage(content: string, type: MessageType = MessageType.TEXT): { valid: boolean; error?: string } {
  if (!content || content.trim().length === 0) {
    return { valid: false, error: '消息内容不能为空' }
  }

  if (content.length > 10000) {
    return { valid: false, error: '消息内容过长，最大长度为 10000 字符' }
  }

  if (type === MessageType.TEXT && containsLink(content)) {
    // 检查是否有潜在的危险链接
    const links = extractLinks(content)
    for (const link of links) {
      if (link.includes('javascript:') || link.includes('data:')) {
        return { valid: false, error: '包含不安全链接' }
      }
    }
  }

  return { valid: true }
}

/**
 * 清理消息内容 (XSS 防护)
 */
export function sanitizeMessage(content: string): string {
  const div = document.createElement('div')
  div.textContent = content
  return div.innerHTML
}
