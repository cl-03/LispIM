/**
 * 网络状态指示器组件
 */

import { useNetworkStatus } from '@/hooks/useNetworkStatus'
import { useState } from 'react'

interface NetworkIndicatorProps {
  className?: string
}

export function NetworkIndicator({ className = '' }: NetworkIndicatorProps) {
  const networkState = useNetworkStatus()
  const [showTooltip, setShowTooltip] = useState(false)

  const getStatusColor = () => {
    switch (networkState.networkQuality) {
      case 'good': return 'bg-green-500'
      case 'poor': return 'bg-yellow-500'
      case 'offline': return 'bg-red-500'
      default: return 'bg-gray-500'
    }
  }

  const getStatusText = () => {
    switch (networkState.networkQuality) {
      case 'good': return '网络良好'
      case 'poor': return '网络较差'
      case 'offline': return networkState.isReconnecting ? '重连中...' : '已离线'
      default: return '未知'
    }
  }

  return (
    <div
      className={`relative flex items-center gap-2 ${className}`}
      onMouseEnter={() => setShowTooltip(true)}
      onMouseLeave={() => setShowTooltip(false)}
    >
      <div className={`w-2 h-2 rounded-full ${getStatusColor()} ${networkState.isReconnecting ? 'animate-pulse' : ''}`} />
      <span className="text-xs text-gray-400">{getStatusText()}</span>

      {/* Tooltip */}
      {showTooltip && (
        <div className="absolute top-full right-0 mt-2 px-3 py-2 bg-gray-800 border border-gray-700 rounded-lg shadow-xl z-50 min-w-[150px]">
          <div className="text-xs text-gray-300 space-y-1">
            <div className="flex justify-between">
              <span>在线状态:</span>
              <span className={networkState.isOnline ? 'text-green-400' : 'text-red-400'}>
                {networkState.isOnline ? '在线' : '离线'}
              </span>
            </div>
            <div className="flex justify-between">
              <span>网络质量:</span>
              <span className={
                networkState.networkQuality === 'good' ? 'text-green-400' :
                networkState.networkQuality === 'poor' ? 'text-yellow-400' : 'text-red-400'
              }>
                {networkState.networkQuality === 'good' ? '良好' :
                 networkState.networkQuality === 'poor' ? '较差' : '离线'}
              </span>
            </div>
            {networkState.lastSeen && (
              <div className="flex justify-between">
                <span>最后在线:</span>
                <span className="text-gray-400">
                  {new Date(networkState.lastSeen).toLocaleTimeString('zh-CN', { hour: '2-digit', minute: '2-digit' })}
                </span>
              </div>
            )}
          </div>
        </div>
      )}
    </div>
  )
}
