import React, { useState } from 'react'
import { getApiClient } from '@/utils/api-client'
import { useScreenshotProtection } from '@/hooks/useScreenshotProtection'

interface UserSession {
  id: string
  device: string
  ip_address: string
  location: string
  last_active: number
  current: boolean
}

const SecuritySettings: React.FC = () => {
  const [sessions, setSessions] = useState<UserSession[]>([
    {
      id: '1',
      device: 'Chrome on Windows',
      ip_address: '192.168.1.100',
      location: '北京，中国',
      last_active: Date.now() / 1000,
      current: true
    }
  ])
  const [loading, setLoading] = useState(false)

  // 启用截图防护
  useScreenshotProtection({
    enabled: true,
    onBlurEnabled: true,
    onScreenshotDetected: () => {
      console.log('Screenshot attempt detected')
    }
  })

  const formatLastActive = (timestamp: number) => {
    const diff = Date.now() / 1000 - timestamp
    const minutes = Math.floor(diff / 60)
    const hours = Math.floor(minutes / 60)
    const days = Math.floor(hours / 24)

    if (days > 0) return `${days}天前`
    if (hours > 0) return `${hours}小时前`
    if (minutes > 0) return `${minutes}分钟前`
    return '刚刚'
  }

  const handleRevokeSession = async (sessionId: string) => {
    try {
      setLoading(true)
      const api = getApiClient()
      await api.revokeSession(sessionId)
      setSessions(sessions.filter(s => s.id !== sessionId))
    } catch (error) {
      console.error('Failed to revoke session:', error)
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div>
        <h2 className="text-lg font-semibold text-white">账号安全</h2>
        <p className="text-sm text-gray-400 mt-1">管理您的登录设备和账号安全</p>
      </div>

      {/* Security Status */}
      <div className="bg-gray-800 rounded-lg p-4">
        <div className="flex items-center gap-4">
          <div className="w-12 h-12 rounded-full bg-green-500/20 flex items-center justify-center">
            <svg className="w-6 h-6 text-green-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z" />
            </svg>
          </div>
          <div>
            <div className="text-white font-medium">账号状态良好</div>
            <div className="text-sm text-gray-400">您的账号目前没有安全风险</div>
          </div>
        </div>
      </div>

      {/* Login Sessions */}
      <div className="bg-gray-800 rounded-lg divide-y divide-gray-700">
        <div className="p-4 border-b border-gray-700">
          <h3 className="text-sm font-medium text-white">登录设备管理</h3>
          <p className="text-xs text-gray-500 mt-1">管理已登录的设备，发现异常可立即退出</p>
        </div>

        {sessions.map((session) => (
          <div
            key={session.id}
            className="p-4 flex items-center justify-between"
          >
            <div className="flex items-center gap-3">
              <div className="w-10 h-10 rounded-full bg-gray-700 flex items-center justify-center">
                <svg className="w-5 h-5 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M9.75 17L9 20l-1 1h4l-1-1-.75-3M3 13h18M5 17h14a2 2 0 002-2V5a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z" />
                </svg>
              </div>
              <div>
                <div className="text-sm font-medium text-white">
                  {session.device}
                  {session.current && (
                    <span className="ml-2 text-xs text-green-400">当前设备</span>
                  )}
                </div>
                <div className="text-xs text-gray-500">
                  {session.location} • {session.ip_address} • {formatLastActive(session.last_active)}
                </div>
              </div>
            </div>
            {!session.current && (
              <button
                onClick={() => handleRevokeSession(session.id)}
                disabled={loading}
                className="px-3 py-1.5 text-sm text-red-400 hover:text-red-300 hover:bg-red-900/20 rounded-lg transition-colors disabled:opacity-50"
              >
                退出
              </button>
            )}
          </div>
        ))}
      </div>

      {/* Security Tips */}
      <div className="bg-blue-900/20 border border-blue-900/30 rounded-lg p-4">
        <h3 className="text-sm font-medium text-blue-400 mb-2">安全提示</h3>
        <ul className="text-xs text-blue-400/80 space-y-1">
          <li>• 定期修改密码，避免使用简单密码</li>
          <li>• 不要在公共电脑上保持登录状态</li>
          <li>• 如发现异常登录，请立即修改密码并退出可疑设备</li>
          <li>• 绑定手机号和邮箱可提高账号安全性</li>
        </ul>
      </div>
    </div>
  )
}

export default SecuritySettings
