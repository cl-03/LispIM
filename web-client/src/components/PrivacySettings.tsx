import React, { useState } from 'react'

const PrivacySettings: React.FC = () => {
  const [settings, setSettings] = useState({
    showOnlineStatus: true,
    showLastSeen: true,
    showReadReceipts: true,
    allowFriendRequests: true,
    showPhoneNumber: false,
    showEmail: false,
    locationVisible: false,
    momentVisible: 'friends' // 'public' | 'friends' | 'private'
  })

  const toggleSetting = (key: keyof typeof settings) => {
    setSettings(prev => ({
      ...prev,
      [key]: key === 'momentVisible' ? prev[key] : !prev[key]
    }))
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div>
        <h2 className="text-lg font-semibold text-white">隐私设置</h2>
        <p className="text-sm text-gray-400 mt-1">控制您的个人信息和活动的可见性</p>
      </div>

      {/* Online Status */}
      <div className="bg-gray-800 rounded-lg divide-y divide-gray-700">
        <div className="p-4 flex items-center justify-between">
          <div>
            <div className="text-sm font-medium text-white">在线状态</div>
            <div className="text-xs text-gray-500 mt-0.5">
              开启后好友可以看到您是否在线
            </div>
          </div>
          <button
            onClick={() => toggleSetting('showOnlineStatus')}
            className={`w-12 h-6 rounded-full transition-colors ${
              settings.showOnlineStatus ? 'bg-blue-500' : 'bg-gray-600'
            }`}
          >
            <div
              className={`w-5 h-5 bg-white rounded-full transform transition-transform ${
                settings.showOnlineStatus ? 'translate-x-6' : 'translate-x-0.5'
              }`}
            />
          </button>
        </div>

        <div className="p-4 flex items-center justify-between">
          <div>
            <div className="text-sm font-medium text-white">最后上线时间</div>
            <div className="text-xs text-gray-500 mt-0.5">
              开启后好友可以看到您最后上线的时间
            </div>
          </div>
          <button
            onClick={() => toggleSetting('showLastSeen')}
            className={`w-12 h-6 rounded-full transition-colors ${
              settings.showLastSeen ? 'bg-blue-500' : 'bg-gray-600'
            }`}
          >
            <div
              className={`w-5 h-5 bg-white rounded-full transform transition-transform ${
                settings.showLastSeen ? 'translate-x-6' : 'translate-x-0.5'
              }`}
            />
          </button>
        </div>

        <div className="p-4 flex items-center justify-between">
          <div>
            <div className="text-sm font-medium text-white">已读回执</div>
            <div className="text-xs text-gray-500 mt-0.5">
              开启后对方可以看到您是否已读消息
            </div>
          </div>
          <button
            onClick={() => toggleSetting('showReadReceipts')}
            className={`w-12 h-6 rounded-full transition-colors ${
              settings.showReadReceipts ? 'bg-blue-500' : 'bg-gray-600'
            }`}
          >
            <div
              className={`w-5 h-5 bg-white rounded-full transform transition-transform ${
                settings.showReadReceipts ? 'translate-x-6' : 'translate-x-0.5'
              }`}
            />
          </button>
        </div>
      </div>

      {/* Friend Requests */}
      <div className="bg-gray-800 rounded-lg p-4">
        <div className="flex items-center justify-between">
          <div>
            <div className="text-sm font-medium text-white">好友请求</div>
            <div className="text-xs text-gray-500 mt-0.5">
              关闭后将不允许任何人添加您为好友
            </div>
          </div>
          <button
            onClick={() => toggleSetting('allowFriendRequests')}
            className={`w-12 h-6 rounded-full transition-colors ${
              settings.allowFriendRequests ? 'bg-blue-500' : 'bg-gray-600'
            }`}
          >
            <div
              className={`w-5 h-5 bg-white rounded-full transform transition-transform ${
                settings.allowFriendRequests ? 'translate-x-6' : 'translate-x-0.5'
              }`}
            />
          </button>
        </div>
      </div>

      {/* Profile Visibility */}
      <div className="bg-gray-800 rounded-lg divide-y divide-gray-700">
        <div className="p-4 flex items-center justify-between">
          <div>
            <div className="text-sm font-medium text-white">手机号可见性</div>
            <div className="text-xs text-gray-500 mt-0.5">
              控制谁可以看到您的手机号
            </div>
          </div>
          <button
            onClick={() => toggleSetting('showPhoneNumber')}
            className={`w-12 h-6 rounded-full transition-colors ${
              settings.showPhoneNumber ? 'bg-blue-500' : 'bg-gray-600'
            }`}
          >
            <div
              className={`w-5 h-5 bg-white rounded-full transform transition-transform ${
                settings.showPhoneNumber ? 'translate-x-6' : 'translate-x-0.5'
              }`}
            />
          </button>
        </div>

        <div className="p-4 flex items-center justify-between">
          <div>
            <div className="text-sm font-medium text-white">邮箱可见性</div>
            <div className="text-xs text-gray-500 mt-0.5">
              控制谁可以看到您的邮箱
            </div>
          </div>
          <button
            onClick={() => toggleSetting('showEmail')}
            className={`w-12 h-6 rounded-full transition-colors ${
              settings.showEmail ? 'bg-blue-500' : 'bg-gray-600'
            }`}
          >
            <div
              className={`w-5 h-5 bg-white rounded-full transform transition-transform ${
                settings.showEmail ? 'translate-x-6' : 'translate-x-0.5'
              }`}
            />
          </button>
        </div>
      </div>

      {/* Location Privacy */}
      <div className="bg-gray-800 rounded-lg p-4">
        <div className="flex items-center justify-between">
          <div>
            <div className="text-sm font-medium text-white">位置信息</div>
            <div className="text-xs text-gray-500 mt-0.5">
              开启后附近的人可以看到您
            </div>
          </div>
          <button
            onClick={() => toggleSetting('locationVisible')}
            className={`w-12 h-6 rounded-full transition-colors ${
              settings.locationVisible ? 'bg-blue-500' : 'bg-gray-600'
            }`}
          >
            <div
              className={`w-5 h-5 bg-white rounded-full transform transition-transform ${
                settings.locationVisible ? 'translate-x-6' : 'translate-x-0.5'
              }`}
            />
          </button>
        </div>
      </div>

      {/* Moment Privacy */}
      <div className="bg-gray-800 rounded-lg divide-y divide-gray-700">
        <div className="p-4">
          <div className="text-sm font-medium text-white mb-3">朋友圈可见性</div>
          <div className="space-y-2">
            {[
              { value: 'public', label: '公开', desc: '所有人都可以看到' },
              { value: 'friends', label: '好友可见', desc: '仅好友可以看到' },
              { value: 'private', label: '私密', desc: '仅自己可以看到' }
            ].map((option) => (
              <label
                key={option.value}
                className={`flex items-center gap-3 p-3 rounded-lg cursor-pointer transition-colors ${
                  settings.momentVisible === option.value
                    ? 'bg-blue-500/20 border border-blue-500'
                    : 'bg-gray-700/50 border border-transparent hover:bg-gray-700'
                }`}
              >
                <input
                  type="radio"
                  name="momentVisible"
                  value={option.value}
                  checked={settings.momentVisible === option.value}
                  onChange={(e) => setSettings({ ...settings, momentVisible: e.target.value as any })}
                  className="w-4 h-4 text-blue-500"
                />
                <div>
                  <div className="text-sm font-medium text-white">{option.label}</div>
                  <div className="text-xs text-gray-500">{option.desc}</div>
                </div>
              </label>
            ))}
          </div>
        </div>
      </div>
    </div>
  )
}

export default PrivacySettings
