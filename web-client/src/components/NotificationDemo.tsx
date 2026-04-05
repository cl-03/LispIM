/**
 * 通知演示组件
 * 用于测试各种通知类型
 */

import React from 'react'
import {
  showMessageNotification,
  showCallNotification,
  showFriendRequestNotification,
  showGroupNotification,
  playNotificationSound,
  updateBadgeCount,
  clearNotifications,
  requestNotificationPermission
} from '@/utils/notifications'

const NotificationDemo: React.FC = () => {
  const handleRequestPermission = async () => {
    const result = await requestNotificationPermission()
    console.log('通知权限:', result)
    alert(`通知权限：${result}`)
  }

  const handleMessageNotification = () => {
    showMessageNotification(
      '张三',
      '你好，这是一条测试消息！最近怎么样？',
      undefined,
      () => {
        console.log('点击了消息通知')
      }
    )
  }

  const handleCallNotification = () => {
    showCallNotification('李四', 'video')
  }

  const handleFriendRequestNotification = () => {
    showFriendRequestNotification(
      '王五',
      '我是你的老同学，加个好友吧！'
    )
  }

  const handleGroupNotification = () => {
    showGroupNotification(
      '技术交流群',
      '管理员',
      '大家好，今晚 8 点有技术分享，欢迎大家参加！',
      false,
      undefined,
      () => {
        console.log('点击了群通知')
      }
    )
  }

  const handleGroupMentionNotification = () => {
    showGroupNotification(
      '产品讨论群',
      '产品经理',
      '@你 这个功能什么时候能上线？',
      true,
      undefined,
      () => {
        console.log('点击了 @ 通知')
      }
    )
  }

  const handlePlaySound = () => {
    playNotificationSound()
  }

  const handleUpdateBadge = () => {
    const count = Math.floor(Math.random() * 10)
    updateBadgeCount(count)
    console.log(`徽章计数：${count}`)
  }

  const handleClearBadge = () => {
    clearNotifications()
    console.log('已清除徽章')
  }

  return (
    <div className="p-4 space-y-4">
      <h2 className="text-lg font-semibold text-white mb-4">通知演示</h2>

      <div className="grid gap-3">
        <button
          onClick={handleRequestPermission}
          className="px-4 py-2 bg-blue-500 text-white rounded-lg hover:bg-blue-600"
        >
          请求通知权限
        </button>

        <button
          onClick={handleMessageNotification}
          className="px-4 py-2 bg-green-500 text-white rounded-lg hover:bg-green-600"
        >
          测试消息通知
        </button>

        <button
          onClick={handleCallNotification}
          className="px-4 py-2 bg-purple-500 text-white rounded-lg hover:bg-purple-600"
        >
          测试通话通知
        </button>

        <button
          onClick={handleFriendRequestNotification}
          className="px-4 py-2 bg-yellow-500 text-white rounded-lg hover:bg-yellow-600"
        >
          测试好友请求通知
        </button>

        <button
          onClick={handleGroupNotification}
          className="px-4 py-2 bg-indigo-500 text-white rounded-lg hover:bg-indigo-600"
        >
          测试群通知
        </button>

        <button
          onClick={handleGroupMentionNotification}
          className="px-4 py-2 bg-red-500 text-white rounded-lg hover:bg-red-600"
        >
          测试 @ 提醒通知
        </button>

        <button
          onClick={handlePlaySound}
          className="px-4 py-2 bg-gray-500 text-white rounded-lg hover:bg-gray-600"
        >
          播放提示音
        </button>

        <div className="flex gap-2">
          <button
            onClick={handleUpdateBadge}
            className="px-4 py-2 bg-pink-500 text-white rounded-lg hover:bg-pink-600"
          >
            随机徽章计数
          </button>
          <button
            onClick={handleClearBadge}
            className="px-4 py-2 bg-gray-600 text-white rounded-lg hover:bg-gray-700"
          >
            清除徽章
          </button>
        </div>
      </div>

      <div className="mt-6 p-4 bg-gray-800 rounded-lg">
        <h3 className="text-sm font-semibold text-white mb-2">通知功能说明</h3>
        <ul className="text-xs text-gray-400 space-y-1">
          <li>• 消息通知：显示发送者姓名和消息预览</li>
          <li>• 通话通知：显示语音/视频通话邀请，播放持续铃声</li>
          <li>• 好友请求：显示请求者和验证消息</li>
          <li>• 群通知：区分普通消息和 @ 提醒</li>
          <li>• 免打扰模式：在设置的时间段内静音所有通知</li>
          <li>• 徽章计数：在浏览器标签上显示未读数</li>
        </ul>
      </div>
    </div>
  )
}

export default NotificationDemo
