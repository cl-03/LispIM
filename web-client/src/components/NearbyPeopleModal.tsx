import React, { useState, useEffect } from 'react'
import { getApiClient } from '@/utils/api-client'

interface NearbyUser {
  user_id: string
  latitude: number
  longitude: number
  distance: number
  timestamp: number
  city: string
  district: string
  displayName?: string
  username?: string
  avatar?: string
}

interface NearbyPeopleModalProps {
  onClose: () => void
}

const NearbyPeopleModal: React.FC<NearbyPeopleModalProps> = ({ onClose }) => {
  const [nearbyUsers, setNearbyUsers] = useState<NearbyUser[]>([])
  const [loading, setLoading] = useState(true)
  const [locationPermission, setLocationPermission] = useState<'granted' | 'denied' | 'prompt'>('prompt')
  const [locationShared, setLocationShared] = useState(true)
  const [currentLocation, setCurrentLocation] = useState<{ lat: number; lng: number } | null>(null)
  const [refreshing, setRefreshing] = useState(false)
  const [toast, setToast] = useState<{ message: string; visible: boolean }>({ message: '', visible: false })

  const showToast = (message: string) => {
    setToast({ message, visible: true })
    setTimeout(() => setToast({ message: '', visible: false }), 2000)
  }

  const requestLocationPermission = async () => {
    try {
      const permission = await navigator.permissions.query({ name: 'geolocation' as PermissionName })
      setLocationPermission(permission.state)

      if (permission.state === 'prompt') {
        navigator.geolocation.getCurrentPosition(
          (position) => {
            setLocationPermission('granted')
            setCurrentLocation({
              lat: position.coords.latitude,
              lng: position.coords.longitude
            })
            fetchNearbyUsers(position.coords.latitude, position.coords.longitude)
          },
          () => {
            setLocationPermission('denied')
            showToast('无法获取您的位置')
          }
        )
      } else if (permission.state === 'granted') {
        navigator.geolocation.getCurrentPosition(
          (position) => {
            setCurrentLocation({
              lat: position.coords.latitude,
              lng: position.coords.longitude
            })
            fetchNearbyUsers(position.coords.latitude, position.coords.longitude)
          },
          () => {
            showToast('无法获取您的位置')
          }
        )
      } else {
        showToast('位置权限已被拒绝')
      }
    } catch {
      setLocationPermission('prompt')
    }
  }

  const fetchNearbyUsers = async (lat: number, lng: number, radius: number = 10) => {
    setLoading(true)
    try {
      const api = getApiClient()
      const response = await api.get(`/api/v1/location/nearby?lat=${lat}&lng=${lng}&radius=${radius}`)

      if (response.success && response.data) {
        const data = response.data as { users?: NearbyUser[] }
        setNearbyUsers(data.users || [])
      } else {
        setNearbyUsers([])
      }
    } catch {
      showToast('获取附近的人失败')
      setNearbyUsers([])
    } finally {
      setLoading(false)
      setRefreshing(false)
    }
  }

  const reportLocation = async () => {
    if (!currentLocation) return

    try {
      const api = getApiClient()
      const response = await api.post('/api/v1/location/report', {
        latitude: currentLocation.lat,
        longitude: currentLocation.lng,
        accuracy: 10,
        city: '北京市',
        district: '朝阳区'
      })

      if (response.success) {
        setLocationShared(true)
        showToast('位置已上报')
      }
    } catch {
      // Ignore error
    }
  }

  const toggleLocationPrivacy = async () => {
    try {
      const api = getApiClient()
      const response = await api.post('/api/v1/location/privacy', {
        visible: !locationShared
      })

      if (response.success) {
        setLocationShared(!locationShared)
        showToast(locationShared ? '已隐藏位置' : '已显示位置')
      }
    } catch {
      showToast('设置失败')
    }
  }

  const handleRefresh = () => {
    if (currentLocation) {
      setRefreshing(true)
      fetchNearbyUsers(currentLocation.lat, currentLocation.lng)
    } else {
      requestLocationPermission()
    }
  }

  const handleAddFriend = async (userId: string) => {
    try {
      const api = getApiClient()
      const response = await api.post('/api/v1/friends/add', {
        friendId: userId,
        message: `您好，在附近的人看到您`
      })

      if (response.success) {
        showToast('好友请求已发送')
      } else {
        showToast(response.message || '发送失败')
      }
    } catch {
      showToast('发送好友请求失败')
    }
  }

  useEffect(() => {
    requestLocationPermission()

    // Check location privacy status
    const checkPrivacy = async () => {
      try {
        // We'll need to add a GET endpoint for privacy status
        // For now, default to true
        setLocationShared(true)
      } catch {
        // Ignore error
      }
    }
    checkPrivacy()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  useEffect(() => {
    if (currentLocation && locationShared) {
      reportLocation()
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [currentLocation, locationShared])

  useEffect(() => {
    if (currentLocation && locationShared) {
      fetchNearbyUsers(currentLocation.lat, currentLocation.lng)
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [currentLocation, locationShared])

  const formatDistance = (km: number) => {
    if (km < 1) {
      return `${Math.round(km * 1000)}m`
    }
    return `${km.toFixed(1)}km`
  }

  const formatTimeAgo = (timestamp: number) => {
    const seconds = Math.floor((Date.now() / 1000) - timestamp)
    if (seconds < 60) return '刚刚'
    if (seconds < 3600) return `${Math.floor(seconds / 60)}分钟前`
    if (seconds < 86400) return `${Math.floor(seconds / 3600)}小时前`
    return `${Math.floor(seconds / 86400)}天前`
  }

  return (
    <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50">
      <div className="bg-gray-800 rounded-xl w-full max-w-md mx-4 max-h-[80vh] flex flex-col">
        {/* Header */}
        <div className="flex items-center justify-between p-4 border-b border-gray-700">
          <h2 className="text-xl font-semibold text-white">附近的人</h2>
          <button onClick={onClose} className="text-gray-400 hover:text-white">
            <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>

        {/* Location Status */}
        <div className="p-4 border-b border-gray-700">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-3">
              <div className={`w-3 h-3 rounded-full ${locationShared ? 'bg-green-500' : 'bg-gray-500'}`} />
              <span className="text-white text-sm">
                {locationShared ? '位置已公开' : '位置已隐藏'}
              </span>
            </div>
            <button
              onClick={toggleLocationPrivacy}
              className={`px-3 py-1.5 rounded-lg text-sm font-medium transition-colors ${
                locationShared
                  ? 'bg-gray-700 text-white hover:bg-gray-600'
                  : 'bg-blue-500 text-white hover:bg-blue-600'
              }`}
            >
              {locationShared ? '隐藏位置' : '显示位置'}
            </button>
          </div>
        </div>

        {/* Refresh Button */}
        <div className="p-4 border-b border-gray-700 flex items-center justify-between">
          <div className="text-gray-400 text-sm">
            {currentLocation
              ? `发现 ${nearbyUsers.length} 位附近的人`
              : locationPermission === 'denied'
              ? '位置权限被拒绝'
              : '获取位置中...'}
          </div>
          <button
            onClick={handleRefresh}
            disabled={loading || !currentLocation}
            className="p-2 text-gray-400 hover:text-white disabled:opacity-50"
          >
            <svg
              className={`w-5 h-5 ${refreshing ? 'animate-spin' : ''}`}
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24"
            >
              <path
                strokeLinecap="round"
                strokeLinejoin="round"
                strokeWidth={2}
                d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"
              />
            </svg>
          </button>
        </div>

        {/* User List */}
        <div className="flex-1 overflow-y-auto p-4">
          {loading ? (
            <div className="flex items-center justify-center py-12">
              <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-blue-500" />
            </div>
          ) : nearbyUsers.length === 0 ? (
            <div className="text-center py-12 text-gray-500">
              <svg className="w-16 h-16 mx-auto mb-4 opacity-50" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path
                  strokeLinecap="round"
                  strokeLinejoin="round"
                  strokeWidth={1.5}
                  d="M17.657 16.657L13.414 20.9a1.998 1.998 0 01-2.827 0l-4.244-4.243a8 8 0 1111.314 0z"
                />
                <path
                  strokeLinecap="round"
                  strokeLinejoin="round"
                  strokeWidth={1.5}
                  d="M15 11a3 3 0 11-6 0 3 3 0 016 0z"
                />
              </svg>
              <p>{currentLocation ? '附近还没有人' : '请开启位置权限'}</p>
            </div>
          ) : (
            <div className="space-y-3">
              {nearbyUsers.map((nearbyUser) => (
                <div
                  key={nearbyUser.user_id}
                  className="flex items-center gap-3 p-3 bg-gray-700/50 rounded-lg hover:bg-gray-700 transition-colors"
                >
                  <div className="w-12 h-12 rounded-full bg-blue-500 flex items-center justify-center text-white font-medium flex-shrink-0">
                    {nearbyUser.avatar ? (
                      <img
                        src={nearbyUser.avatar}
                        alt={nearbyUser.displayName || nearbyUser.username}
                        className="w-12 h-12 rounded-full object-cover"
                      />
                    ) : (
                      (nearbyUser.displayName || nearbyUser.username || '?').charAt(0).toUpperCase()
                    )}
                  </div>
                  <div className="flex-1 min-w-0">
                    <div className="text-white font-medium truncate">
                      {nearbyUser.displayName || nearbyUser.username || '未知用户'}
                    </div>
                    <div className="text-gray-400 text-sm truncate">
                      @{nearbyUser.username || nearbyUser.user_id}
                    </div>
                  </div>
                  <div className="text-right">
                    <div className="text-blue-400 text-sm font-medium">
                      {formatDistance(nearbyUser.distance)}
                    </div>
                    <div className="text-gray-500 text-xs">
                      {formatTimeAgo(nearbyUser.timestamp)}
                    </div>
                  </div>
                  <button
                    onClick={() => handleAddFriend(nearbyUser.user_id)}
                    className="px-3 py-1.5 bg-blue-500 text-white text-sm rounded-lg hover:bg-blue-600 flex-shrink-0"
                  >
                    打招呼
                  </button>
                </div>
              ))}
            </div>
          )}
        </div>

        {/* Tips */}
        <div className="p-4 border-t border-gray-700 text-center text-gray-500 text-xs">
          {locationShared
            ? '开启位置后可被附近的人发现 · 距离信息仅供估算'
            : '隐藏位置后不会被附近的人发现'}
        </div>
      </div>

      {/* Toast */}
      {toast.visible && (
        <div className="fixed top-20 left-1/2 transform -translate-x-1/2 bg-gray-800 text-white px-6 py-3 rounded-lg shadow-lg z-50">
          {toast.message}
        </div>
      )}
    </div>
  )
}

export default NearbyPeopleModal
