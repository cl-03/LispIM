import React from 'react'
import { useNotificationPreferences } from '@/hooks/useNotificationPreferences'
import { setNotificationPreferences } from '@/utils/notifications'

const NotificationSettings: React.FC = () => {
  const { preferences, updatePreferences, togglePreference, isQuietModeActive } = useNotificationPreferences()

  // 同步偏好设置到通知工具
  React.useEffect(() => {
    setNotificationPreferences(preferences)
  }, [preferences])

  return (
    <div className="space-y-6">
      {/* Header */}
      <div>
        <h2 className="text-lg font-semibold text-white">消息通知</h2>
        <p className="text-sm text-gray-400 mt-1">管理您的消息通知和提醒设置</p>
      </div>

      {/* Message Notifications */}
      <div className="bg-gray-800 rounded-lg divide-y divide-gray-700">
        <div className="p-4 flex items-center justify-between">
          <div>
            <div className="text-sm font-medium text-white">桌面通知</div>
            <div className="text-xs text-gray-500 mt-0.5">
              收到新消息时显示桌面通知
            </div>
          </div>
          <button
            onClick={() => togglePreference('enableDesktop')}
            className={`w-12 h-6 rounded-full transition-colors ${
              preferences.enableDesktop ? 'bg-blue-500' : 'bg-gray-600'
            }`}
          >
            <div
              className={`w-5 h-5 bg-white rounded-full transform transition-transform ${
                preferences.enableDesktop ? 'translate-x-6' : 'translate-x-0.5'
              }`}
            />
          </button>
        </div>

        <div className="p-4 flex items-center justify-between">
          <div>
            <div className="text-sm font-medium text-white">提示音</div>
            <div className="text-xs text-gray-500 mt-0.5">
              收到消息时播放提示音
            </div>
          </div>
          <button
            onClick={() => togglePreference('enableSound')}
            className={`w-12 h-6 rounded-full transition-colors ${
              preferences.enableSound ? 'bg-blue-500' : 'bg-gray-600'
            }`}
          >
            <div
              className={`w-5 h-5 bg-white rounded-full transform transition-transform ${
                preferences.enableSound ? 'translate-x-6' : 'translate-x-0.5'
              }`}
            />
          </button>
        </div>

        <div className="p-4 flex items-center justify-between">
          <div>
            <div className="text-sm font-medium text-white">徽章计数</div>
            <div className="text-xs text-gray-500 mt-0.5">
              在浏览器标签上显示未读消息数
            </div>
          </div>
          <button
            onClick={() => togglePreference('enableBadge')}
            className={`w-12 h-6 rounded-full transition-colors ${
              preferences.enableBadge ? 'bg-blue-500' : 'bg-gray-600'
            }`}
          >
            <div
              className={`w-5 h-5 bg-white rounded-full transform transition-transform ${
                preferences.enableBadge ? 'translate-x-6' : 'translate-x-0.5'
              }`}
            />
          </button>
        </div>

        <div className="p-4 flex items-center justify-between">
          <div>
            <div className="text-sm font-medium text-white">消息预览</div>
            <div className="text-xs text-gray-500 mt-0.5">
              在通知中显示消息内容预览
            </div>
          </div>
          <button
            onClick={() => togglePreference('showPreview')}
            className={`w-12 h-6 rounded-full transition-colors ${
              preferences.showPreview ? 'bg-blue-500' : 'bg-gray-600'
            }`}
          >
            <div
              className={`w-5 h-5 bg-white rounded-full transform transition-transform ${
                preferences.showPreview ? 'translate-x-6' : 'translate-x-0.5'
              }`}
            />
          </button>
        </div>
      </div>

      {/* Do Not Disturb */}
      <div className="bg-gray-800 rounded-lg p-4">
        <div className="flex items-center justify-between mb-4">
          <div>
            <div className="text-sm font-medium text-white">免打扰模式</div>
            <div className="text-xs text-gray-500 mt-0.5">
              开启后将静音所有通知
              {isQuietModeActive && <span className="ml-2 text-yellow-400">(当前处于免打扰时段)</span>}
            </div>
          </div>
          <button
            onClick={() => togglePreference('quietMode')}
            className={`w-12 h-6 rounded-full transition-colors ${
              preferences.quietMode ? 'bg-blue-500' : 'bg-gray-600'
            }`}
          >
            <div
              className={`w-5 h-5 bg-white rounded-full transform transition-transform ${
                preferences.quietMode ? 'translate-x-6' : 'translate-x-0.5'
              }`}
            />
          </button>
        </div>

        {preferences.quietMode && (
          <div className="flex gap-4">
            <div className="flex-1">
              <label className="block text-xs text-gray-500 mb-1">开始时间</label>
              <input
                type="time"
                value={preferences.quietStart}
                onChange={(e) => updatePreferences({ quietStart: e.target.value })}
                className="w-full px-3 py-2 bg-gray-700 border border-gray-600 rounded-lg text-white text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
              />
            </div>
            <div className="flex-1">
              <label className="block text-xs text-gray-500 mb-1">结束时间</label>
              <input
                type="time"
                value={preferences.quietEnd}
                onChange={(e) => updatePreferences({ quietEnd: e.target.value })}
                className="w-full px-3 py-2 bg-gray-700 border border-gray-600 rounded-lg text-white text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
              />
            </div>
          </div>
        )}
      </div>

      {/* Other Notifications */}
      <div className="bg-gray-800 rounded-lg divide-y divide-gray-700">
        <div className="p-4 flex items-center justify-between">
          <div>
            <div className="text-sm font-medium text-white">新消息通知</div>
            <div className="text-xs text-gray-500 mt-0.5">
              收到新消息时发送通知
            </div>
          </div>
          <button
            onClick={() => togglePreference('messageNotifications')}
            className={`w-12 h-6 rounded-full transition-colors ${
              preferences.messageNotifications ? 'bg-blue-500' : 'bg-gray-600'
            }`}
          >
            <div
              className={`w-5 h-5 bg-white rounded-full transform transition-transform ${
                preferences.messageNotifications ? 'translate-x-6' : 'translate-x-0.5'
              }`}
            />
          </button>
        </div>

        <div className="p-4 flex items-center justify-between">
          <div>
            <div className="text-sm font-medium text-white">通话通知</div>
            <div className="text-xs text-gray-500 mt-0.5">
              收到通话邀请时发送通知
            </div>
          </div>
          <button
            onClick={() => togglePreference('callNotifications')}
            className={`w-12 h-6 rounded-full transition-colors ${
              preferences.callNotifications ? 'bg-blue-500' : 'bg-gray-600'
            }`}
          >
            <div
              className={`w-5 h-5 bg-white rounded-full transform transition-transform ${
                preferences.callNotifications ? 'translate-x-6' : 'translate-x-0.5'
              }`}
            />
          </button>
        </div>

        <div className="p-4 flex items-center justify-between">
          <div>
            <div className="text-sm font-medium text-white">好友请求通知</div>
            <div className="text-xs text-gray-500 mt-0.5">
              收到好友请求时发送通知
            </div>
          </div>
          <button
            onClick={() => togglePreference('friendRequestNotifications')}
            className={`w-12 h-6 rounded-full transition-colors ${
              preferences.friendRequestNotifications ? 'bg-blue-500' : 'bg-gray-600'
            }`}
          >
            <div
              className={`w-5 h-5 bg-white rounded-full transform transition-transform ${
                preferences.friendRequestNotifications ? 'translate-x-6' : 'translate-x-0.5'
              }`}
            />
          </button>
        </div>

        <div className="p-4 flex items-center justify-between">
          <div>
            <div className="text-sm font-medium text-white">群聊通知</div>
            <div className="text-xs text-gray-500 mt-0.5">
              群消息发送通知（关闭后仅 @ 提醒）
            </div>
          </div>
          <button
            onClick={() => togglePreference('groupNotifications')}
            className={`w-12 h-6 rounded-full transition-colors ${
              preferences.groupNotifications ? 'bg-blue-500' : 'bg-gray-600'
            }`}
          >
            <div
              className={`w-5 h-5 bg-white rounded-full transform transition-transform ${
                preferences.groupNotifications ? 'translate-x-6' : 'translate-x-0.5'
              }`}
            />
          </button>
        </div>
      </div>

      {/* Group Settings */}
      <div className="bg-gray-800 rounded-lg p-4">
        <div className="flex items-center justify-between">
          <div>
            <div className="text-sm font-medium text-white">群聊仅提醒 @ 我的消息</div>
            <div className="text-xs text-gray-500 mt-0.5">
              开启后群聊只会在被@时发送通知
            </div>
          </div>
          <button
            onClick={() => togglePreference('groupMentionsOnly')}
            className={`w-12 h-6 rounded-full transition-colors ${
              preferences.groupMentionsOnly ? 'bg-blue-500' : 'bg-gray-600'
            }`}
          >
            <div
              className={`w-5 h-5 bg-white rounded-full transform transition-transform ${
                preferences.groupMentionsOnly ? 'translate-x-6' : 'translate-x-0.5'
              }`}
            />
          </button>
        </div>
      </div>

      {/* Test Notification */}
      <div className="bg-gray-800 rounded-lg p-4">
        <div className="flex items-center justify-between">
          <div>
            <div className="text-sm font-medium text-white">测试通知</div>
            <div className="text-xs text-gray-500 mt-0.5">
              发送一条测试通知以验证设置
            </div>
          </div>
          <button
            onClick={() => {
              import('@/utils/notifications').then(({ showMessageNotification }) => {
                showMessageNotification('LispIM', '这是一条测试通知', undefined, () => {
                  window.focus()
                })
              })
            }}
            className="px-4 py-2 bg-blue-500 text-white text-sm rounded-lg hover:bg-blue-600 transition-colors"
          >
            发送测试
          </button>
        </div>
      </div>
    </div>
  )
}

export default NotificationSettings
