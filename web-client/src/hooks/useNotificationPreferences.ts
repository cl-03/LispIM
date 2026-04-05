/**
 * 通知偏好设置 Hook
 * 管理用户的通知设置，包括桌面通知、声音、徽章等
 */

import { useState, useEffect } from 'react'

export interface NotificationPreferences {
  enableDesktop: boolean
  enableSound: boolean
  enableBadge: boolean
  messageNotifications: boolean
  callNotifications: boolean
  friendRequestNotifications: boolean
  groupNotifications: boolean
  quietMode: boolean
  quietStart: string
  quietEnd: string
  showPreview: boolean
  groupMentionsOnly: boolean
}

const DEFAULT_PREFERENCES: NotificationPreferences = {
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

const STORAGE_KEY = 'lispim_notification_preferences'

/**
 * 获取存储的偏好设置
 */
function getStoredPreferences(): NotificationPreferences {
  try {
    const stored = localStorage.getItem(STORAGE_KEY)
    if (stored) {
      return { ...DEFAULT_PREFERENCES, ...JSON.parse(stored) }
    }
  } catch (error) {
    console.warn('Failed to load notification preferences:', error)
  }
  return DEFAULT_PREFERENCES
}

/**
 * 保存偏好设置到存储
 */
function savePreferences(prefs: NotificationPreferences): void {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(prefs))
  } catch (error) {
    console.warn('Failed to save notification preferences:', error)
  }
}

/**
 * 检查当前是否在免打扰时段内
 */
export function isQuietModeActive(quietMode: boolean, quietStart: string, quietEnd: string): boolean {
  if (!quietMode) return false

  const now = new Date()
  const currentTime = now.getHours() * 60 + now.getMinutes()

  const [startHour, startMinute] = quietStart.split(':').map(Number)
  const [endHour, endMinute] = quietEnd.split(':').map(Number)

  const startTime = startHour * 60 + startMinute
  const endTime = endHour * 60 + endMinute

  // 处理跨天情况（如 22:00 到 08:00）
  if (startTime > endTime) {
    return currentTime >= startTime || currentTime < endTime
  }

  return currentTime >= startTime && currentTime < endTime
}

/**
 * 通知偏好设置 Hook
 */
export function useNotificationPreferences() {
  const [preferences, setPreferences] = useState<NotificationPreferences>(getStoredPreferences)
  const [isQuietModeActiveNow, setIsQuietModeActiveNow] = useState(false)

  // 定期检查免打扰状态
  useEffect(() => {
    const checkQuietMode = () => {
      setIsQuietModeActiveNow(isQuietModeActive(
        preferences.quietMode,
        preferences.quietStart,
        preferences.quietEnd
      ))
    }

    checkQuietMode()
    const interval = setInterval(checkQuietMode, 60000) // 每分钟检查一次

    return () => clearInterval(interval)
  }, [preferences.quietMode, preferences.quietStart, preferences.quietEnd])

  const updatePreferences = (updates: Partial<NotificationPreferences>) => {
    const newPrefs = { ...preferences, ...updates }
    setPreferences(newPrefs)
    savePreferences(newPrefs)
  }

  const togglePreference = (key: keyof NotificationPreferences) => {
    const value = preferences[key]
    if (typeof value === 'boolean') {
      updatePreferences({ [key]: !value } as Partial<NotificationPreferences>)
    }
  }

  return {
    preferences,
    isQuietModeActive: isQuietModeActiveNow,
    updatePreferences,
    togglePreference,
    canSendNotification: (type: 'message' | 'call' | 'friend-request' | 'group') => {
      // 检查免打扰模式
      if (isQuietModeActiveNow) return false

      // 检查全局设置
      if (!preferences.messageNotifications && type === 'message') return false
      if (!preferences.callNotifications && type === 'call') return false
      if (!preferences.friendRequestNotifications && type === 'friend-request') return false
      if (!preferences.groupNotifications && type === 'group') return false

      return true
    }
  }
}

/**
 * 获取通知预览文本（根据设置决定是否显示完整内容）
 */
export function getNotificationPreview(content: string, showPreview: boolean): string {
  if (!showPreview) {
    return '新消息'
  }
  return content.length > 100 ? content.slice(0, 100) + '...' : content
}
