/**
 * 通知工具 - 桌面通知、声音提示、徽章计数
 */

import type { NotificationPreferences } from '@/hooks/useNotificationPreferences'

export interface NotificationOptions {
  title: string
  body: string
  icon?: string
  onClick?: () => void
  silent?: boolean
  tag?: string
}

let notificationPermission: NotificationPermission = 'default'
let notificationPreferences: NotificationPreferences | null = null

/**
 * 设置通知偏好设置
 */
export function setNotificationPreferences(prefs: NotificationPreferences): void {
  notificationPreferences = prefs
}

/**
 * 获取当前偏好设置
 */
function getPreferences(): NotificationPreferences {
  if (notificationPreferences) {
    return notificationPreferences
  }
  try {
    const stored = localStorage.getItem('lispim_notification_preferences')
    if (stored) {
      notificationPreferences = JSON.parse(stored)
      return notificationPreferences
    }
  } catch {
    // Ignore error
  }
  // Return defaults
  return {
    enableDesktop: true,
    enableSound: true,
    enableBadge: true,
    messageNotifications: true,
    callNotifications: true,
    friendRequestNotifications: true,
    groupNotifications: true,
    quietMode: false,
    quietStart: '22:00',
    quietEnd: '08:00',
    showPreview: true,
    groupMentionsOnly: false
  }
}

/**
 * 检查是否在免打扰时段
 */
function isQuietModeActive(prefs: NotificationPreferences): boolean {
  if (!prefs.quietMode) return false

  const now = new Date()
  const currentTime = now.getHours() * 60 + now.getMinutes()

  const [startHour, startMinute] = prefs.quietStart.split(':').map(Number)
  const [endHour, endMinute] = prefs.quietEnd.split(':').map(Number)

  const startTime = startHour * 60 + startMinute
  const endTime = endHour * 60 + endMinute

  if (startTime > endTime) {
    return currentTime >= startTime || currentTime < endTime
  }

  return currentTime >= startTime && currentTime < endTime
}

/**
 * 请求通知权限
 */
export async function requestNotificationPermission(): Promise<NotificationPermission> {
  if (!('Notification' in window)) {
    console.warn('此浏览器不支持通知')
    return 'denied'
  }

  if (Notification.permission === 'default') {
    notificationPermission = await Notification.requestPermission()
  } else {
    notificationPermission = Notification.permission
  }

  return notificationPermission
}

/**
 * 获取当前通知权限
 */
export function getNotificationPermission(): NotificationPermission {
  if ('Notification' in window) {
    notificationPermission = Notification.permission
  }
  return notificationPermission
}

/**
 * 显示桌面通知
 */
export function showNotification(options: NotificationOptions): void {
  const prefs = getPreferences()

  // 检查是否在免打扰模式
  if (isQuietModeActive(prefs)) {
    return
  }

  // 检查是否启用桌面通知
  if (!prefs.enableDesktop) return

  if (!('Notification' in window)) return
  if (Notification.permission !== 'granted') return

  const notification = new Notification(options.title, {
    body: options.body,
    icon: options.icon || '/logo.png',
    silent: !prefs.enableSound,
    tag: options.tag || 'lispim-message',
    requireInteraction: false,
    badge: '/logo.png'
  })

  if (options.onClick) {
    notification.onclick = (e) => {
      e.preventDefault()
      window.focus()
      options.onClick?.()
      notification.close()
    }
  }

  // 5 秒后自动关闭
  setTimeout(() => notification.close(), 5000)
}

/**
 * 播放通知声音
 */
export function playNotificationSound(): void {
  const prefs = getPreferences()

  // 检查是否启用声音
  if (!prefs.enableSound) return

  // 检查是否在免打扰模式
  if (isQuietModeActive(prefs)) return

  try {
    // 使用 Web Audio API 生成简单的提示音
    const audioContext = new (window.AudioContext || (window as any).webkitAudioContext)()
    const oscillator = audioContext.createOscillator()
    const gainNode = audioContext.createGain()

    oscillator.connect(gainNode)
    gainNode.connect(audioContext.destination)

    oscillator.frequency.value = 800
    oscillator.type = 'sine'
    gainNode.gain.setValueAtTime(0.3, audioContext.currentTime)
    gainNode.gain.exponentialRampToValueAtTime(0.01, audioContext.currentTime + 0.3)

    oscillator.start(audioContext.currentTime)
    oscillator.stop(audioContext.currentTime + 0.3)
  } catch (error) {
    console.warn('无法播放通知声音:', error)
  }
}

/**
 * 更新浏览器徽章计数
 */
export function updateBadgeCount(count: number): void {
  const prefs = getPreferences()

  // 检查是否启用徽章
  if (!prefs.enableBadge) return

  if ('setAppBadge' in navigator) {
    if (count > 0) {
      navigator.setAppBadge(count)
    } else {
      navigator.clearAppBadge()
    }
  }
}

/**
 * 清除所有通知相关状态
 */
export function clearNotifications(): void {
  if ('clearAppBadge' in navigator) {
    navigator.clearAppBadge()
  }
}

/**
 * 显示消息通知
 */
export function showMessageNotification(
  senderName: string,
  messagePreview: string,
  icon?: string,
  onClick?: () => void
): void {
  const prefs = getPreferences()

  // 检查是否启用消息通知
  if (!prefs.messageNotifications) return

  // 检查是否在免打扰模式
  if (isQuietModeActive(prefs)) return

  // 根据设置决定是否显示预览
  const body = prefs.showPreview
    ? (messagePreview.length > 100 ? messagePreview.slice(0, 100) + '...' : messagePreview)
    : '新消息'

  showNotification({
    title: senderName,
    body,
    icon,
    onClick,
    tag: 'lispim-message'
  })

  // 根据设置决定是否播放声音（单独检查，因为 showNotification 内部也会检查）
  if (prefs.enableSound) {
    playNotificationSound()
  }
}

/**
 * 显示通话邀请通知
 */
export function showCallNotification(
  callerName: string,
  callType: 'voice' | 'video',
  icon?: string
): void {
  const prefs = getPreferences()

  // 检查是否启用通话通知
  if (!prefs.callNotifications) return

  // 检查是否在免打扰模式
  if (isQuietModeActive(prefs)) return

  const title = `${callType === 'voice' ? '语音' : '视频'}通话邀请`
  const body = `${callerName} 正在邀请您进行${callType === 'voice' ? '语音' : '视频'}通话`

  showNotification({
    title,
    body,
    icon,
    tag: 'lispim-call'
  })

  // 播放铃声
  if (prefs.enableSound) {
    playCallRingtone()
  }
}

/**
 * 显示好友请求通知
 */
export function showFriendRequestNotification(
  requesterName: string,
  message?: string,
  icon?: string
): void {
  const prefs = getPreferences()

  // 检查是否启用好友请求通知
  if (!prefs.friendRequestNotifications) return

  // 检查是否在免打扰模式
  if (isQuietModeActive(prefs)) return

  const body = message || `${requesterName} 想添加您为好友`

  showNotification({
    title: '新的好友请求',
    body,
    icon,
    tag: 'lispim-friend-request'
  })

  // 播放提示音
  if (prefs.enableSound) {
    playNotificationSound()
  }
}

/**
 * 显示群聊通知
 */
export function showGroupNotification(
  groupName: string,
  senderName: string,
  messagePreview: string,
  isMention: boolean = false,
  icon?: string,
  onClick?: () => void
): void {
  const prefs = getPreferences()

  // 检查是否启用群通知
  if (!prefs.groupNotifications) return

  // 检查是否在免打扰模式
  if (isQuietModeActive(prefs)) return

  // 如果设置为仅 @ 提醒且不是 @ 消息，则不显示
  if (prefs.groupMentionsOnly && !isMention) return

  const body = prefs.showPreview
    ? `${senderName}: ${messagePreview.length > 50 ? messagePreview.slice(0, 50) + '...' : messagePreview}`
    : `${senderName} 在 ${groupName} 发送了消息`

  showNotification({
    title: isMention ? `${senderName} 在 ${groupName} @了您` : groupName,
    body,
    icon,
    onClick,
    tag: 'lispim-group'
  })

  // 播放提示音
  if (prefs.enableSound) {
    playNotificationSound()
  }
}

/**
 * 播放通话铃声（持续响铃）
 */
let callRingtoneInterval: ReturnType<typeof setInterval> | null = null

export function playCallRingtone(): void {
  const prefs = getPreferences()
  if (!prefs.enableSound) return

  stopCallRingtone()

  try {
    const audioContext = new (window.AudioContext || (window as any).webkitAudioContext)()

    const playRing = () => {
      const oscillator = audioContext.createOscillator()
      const gainNode = audioContext.createGain()

      oscillator.connect(gainNode)
      gainNode.connect(audioContext.destination)

      oscillator.frequency.value = 600
      oscillator.type = 'sine'
      gainNode.gain.setValueAtTime(0.3, audioContext.currentTime)
      gainNode.gain.exponentialRampToValueAtTime(0.01, audioContext.currentTime + 0.5)

      oscillator.start(audioContext.currentTime)
      oscillator.stop(audioContext.currentTime + 0.5)
    }

    // 立即播放一次
    playRing()

    // 然后每隔 2 秒播放一次
    callRingtoneInterval = setInterval(playRing, 2000)
  } catch (error) {
    console.warn('无法播放通话铃声:', error)
  }
}

export function stopCallRingtone(): void {
  if (callRingtoneInterval) {
    clearInterval(callRingtoneInterval)
    callRingtoneInterval = null
  }
}
