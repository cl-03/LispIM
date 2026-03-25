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
