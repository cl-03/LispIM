/**
 * 会话隐私设置面板
 * 支持阅后即焚、消息删除等设置
 */

import React, { useState, useEffect } from 'react'
import { getApiClient } from '@/utils/api-client'

interface ConversationPrivacySettingsProps {
  conversationId: number
  onClose: () => void
}

interface DisappearingConfig {
  enabled: boolean
  timerSeconds: number
  timerStart: 'IMMEDIATE' | 'FIRST_READ'
}

const TIMER_OPTIONS = [
  { label: '5 秒', value: 5, icon: '⚡' },
  { label: '30 秒', value: 30, icon: '⏱️' },
  { label: '1 分钟', value: 60, icon: '1m' },
  { label: '5 分钟', value: 300, icon: '5m' },
  { label: '15 分钟', value: 900, icon: '15m' },
  { label: '1 小时', value: 3600, icon: '1h' },
  { label: '24 小时', value: 86400, icon: '1d' },
  { label: '7 天', value: 604800, icon: '7d' },
]

export const ConversationPrivacySettings: React.FC<ConversationPrivacySettingsProps> = ({
  conversationId,
  onClose
}) => {
  const api = getApiClient()
  const [config, setConfig] = useState<DisappearingConfig | null>(null)
  const [loading, setLoading] = useState(false)
  const [message, setMessage] = useState<{ type: 'success' | 'error'; text: string } | null>(null)

  // 加载配置
  useEffect(() => {
    loadConfig()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [conversationId])

  const loadConfig = async () => {
    setLoading(true)
    try {
      const result = await api.getDisappearingMessages(conversationId)
      if (result.success && result.data) {
        setConfig(result.data as DisappearingConfig)
      }
    } catch (error) {
      console.error('Failed to load config:', error)
    } finally {
      setLoading(false)
    }
  }

  const handleToggle = async () => {
    if (!config) return

    setLoading(true)
    try {
      const newEnabled = !config.enabled
      const result = await api.setDisappearingMessages(conversationId, newEnabled, config.timerSeconds)
      if (result.success) {
        setConfig({ ...config, enabled: newEnabled })
        setMessage({
          type: 'success',
          text: newEnabled ? '已开启阅后即焚' : '已关闭阅后即焚'
        })
        setTimeout(() => setMessage(null), 2000)
      }
    } catch (error) {
      setMessage({ type: 'error', text: '操作失败' })
      setTimeout(() => setMessage(null), 2000)
    } finally {
      setLoading(false)
    }
  }

  const handleTimerChange = async (seconds: number) => {
    if (!config) return

    setLoading(true)
    try {
      const result = await api.setDisappearingMessages(conversationId, config.enabled, seconds)
      if (result.success) {
        setConfig({ ...config, timerSeconds: seconds })
        setMessage({ type: 'success', text: '已更新定时器' })
        setTimeout(() => setMessage(null), 2000)
      }
    } catch (error) {
      setMessage({ type: 'error', text: '操作失败' })
      setTimeout(() => setMessage(null), 2000)
    } finally {
      setLoading(false)
    }
  }

  if (!config) {
    return (
      <div className="flex items-center justify-center p-8">
        <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-blue-500"></div>
      </div>
    )
  }

  return (
    <div className="bg-white dark:bg-gray-800 rounded-xl shadow-xl max-w-md mx-auto">
      {/* Header */}
      <div className="flex items-center justify-between p-4 border-b border-gray-200 dark:border-gray-700">
        <h3 className="text-lg font-semibold text-gray-900 dark:text-white">隐私设置</h3>
        <button
          onClick={onClose}
          className="p-2 hover:bg-gray-100 dark:hover:bg-gray-700 rounded-lg transition-colors"
        >
          <svg className="w-5 h-5 text-gray-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
          </svg>
        </button>
      </div>

      {/* Content */}
      <div className="p-4 space-y-4">
        {/* Message */}
        {message && (
          <div className={`p-3 rounded-lg text-sm ${
            message.type === 'success'
              ? 'bg-green-100 dark:bg-green-900 text-green-800 dark:text-green-200'
              : 'bg-red-100 dark:bg-red-900 text-red-800 dark:text-red-200'
          }`}>
            {message.text}
          </div>
        )}

        {/* Disappearing Messages Toggle */}
        <div className="flex items-center justify-between p-3 bg-gray-50 dark:bg-gray-900 rounded-lg">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 rounded-full bg-blue-500/20 flex items-center justify-center">
              <svg className="w-5 h-5 text-blue-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z" />
              </svg>
            </div>
            <div>
              <div className="font-medium text-gray-900 dark:text-white">阅后即焚</div>
              <div className="text-xs text-gray-500 dark:text-gray-400">
                {config.enabled ? '消息将自动删除' : '已关闭自动删除'}
              </div>
            </div>
          </div>
          <button
            onClick={handleToggle}
            disabled={loading}
            className={`relative inline-flex h-6 w-11 items-center rounded-full transition-colors ${
              config.enabled ? 'bg-blue-600' : 'bg-gray-300 dark:bg-gray-600'
            }`}
          >
            <span
              className={`inline-block h-4 w-4 transform rounded-full bg-white transition-transform ${
                config.enabled ? 'translate-x-6' : 'translate-x-1'
              }`}
            />
          </button>
        </div>

        {/* Timer Selection */}
        {config.enabled && (
          <div className="space-y-2">
            <label className="text-sm font-medium text-gray-700 dark:text-gray-300">
              自毁时间
            </label>
            <div className="grid grid-cols-4 gap-2">
              {TIMER_OPTIONS.map((option) => (
                <button
                  key={option.value}
                  onClick={() => handleTimerChange(option.value)}
                  className={`p-2 rounded-lg text-sm transition-all ${
                    config.timerSeconds === option.value
                      ? 'bg-blue-500 text-white shadow-md scale-105'
                      : 'bg-gray-100 dark:bg-gray-700 text-gray-700 dark:text-gray-300 hover:bg-gray-200 dark:hover:bg-gray-600'
                  }`}
                >
                  <div className="text-lg mb-0.5">{option.icon}</div>
                  <div>{option.label}</div>
                </button>
              ))}
            </div>
          </div>
        )}

        {/* Info */}
        <div className="p-3 bg-blue-50 dark:bg-blue-900/20 rounded-lg">
          <div className="flex items-start gap-2">
            <svg className="w-5 h-5 text-blue-500 flex-shrink-0 mt-0.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
            </svg>
            <div className="text-sm text-blue-700 dark:text-blue-300">
              <p>阅后即焚消息将在设定时间后自动删除，对双方都生效。</p>
              <p className="mt-1">即使开启此功能，对方仍可能截图或拍照，请谨慎发送敏感信息。</p>
            </div>
          </div>
        </div>
      </div>

      {/* Footer */}
      <div className="p-4 border-t border-gray-200 dark:border-gray-700 flex justify-end">
        <button
          onClick={onClose}
          className="px-4 py-2 text-sm font-medium text-gray-700 dark:text-gray-300 hover:bg-gray-100 dark:hover:bg-gray-700 rounded-lg transition-colors"
        >
          完成
        </button>
      </div>
    </div>
  )
}

export default ConversationPrivacySettings
