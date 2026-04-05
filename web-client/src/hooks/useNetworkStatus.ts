/**
 * 网络状态监控 Hook
 *
 * 监控网络连接状态，提供在线/离线检测和自动重连
 */

import { useState, useEffect, useCallback } from 'react'

interface NetworkState {
  isOnline: boolean
  isReconnecting: boolean
  lastSeen: Date | null
  networkQuality: 'good' | 'poor' | 'offline'
}

export function useNetworkStatus() {
  const [networkState, setNetworkState] = useState<NetworkState>({
    isOnline: navigator.onLine,
    isReconnecting: false,
    lastSeen: null,
    networkQuality: navigator.onLine ? 'good' : 'offline'
  })

  // 检测网络质量
  const checkNetworkQuality = useCallback(async () => {
    if (!navigator.onLine) {
      setNetworkState(prev => ({ ...prev, networkQuality: 'offline' }))
      return
    }

    try {
      const start = performance.now()
      const response = await fetch('/api/v1/health', {
        method: 'HEAD',
        cache: 'no-cache',
        signal: AbortSignal.timeout(5000)
      })
      const latency = performance.now() - start

      if (response.ok) {
        if (latency < 200) {
          setNetworkState(prev => ({ ...prev, networkQuality: 'good' }))
        } else if (latency < 1000) {
          setNetworkState(prev => ({ ...prev, networkQuality: 'poor' }))
        } else {
          setNetworkState(prev => ({ ...prev, networkQuality: 'offline' }))
        }
      }
    } catch {
      setNetworkState(prev => ({ ...prev, networkQuality: 'offline' }))
    }
  }, [])

  useEffect(() => {
    const handleOnline = () => {
      setNetworkState(prev => ({
        ...prev,
        isOnline: true,
        isReconnecting: false,
        lastSeen: new Date(),
        networkQuality: 'good'
      }))
      // 网络恢复时检查质量
      checkNetworkQuality()
    }

    const handleOffline = () => {
      setNetworkState(prev => ({
        ...prev,
        isOnline: false,
        isReconnecting: true,
        lastSeen: new Date(),
        networkQuality: 'offline'
      }))
    }

    window.addEventListener('online', handleOnline)
    window.addEventListener('offline', handleOffline)

    // 定期检查网络质量
    const intervalId = setInterval(checkNetworkQuality, 30000)

    return () => {
      window.removeEventListener('online', handleOnline)
      window.removeEventListener('offline', handleOffline)
      clearInterval(intervalId)
    }
  }, [checkNetworkQuality])

  return networkState
}
