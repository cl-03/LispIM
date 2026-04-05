import React from 'react'
import ReactDOM from 'react-dom/client'
import App from './App'
import './index.css'
import { requestNotificationPermission, setNotificationPreferences } from '@/utils/notifications'

// 应用启动时请求通知权限
requestNotificationPermission().then((permission) => {
  console.log('[Notification] Permission:', permission)
})

// 加载通知偏好设置
try {
  const stored = localStorage.getItem('lispim_notification_preferences')
  if (stored) {
    const prefs = JSON.parse(stored)
    setNotificationPreferences(prefs)
  }
} catch {
  // Ignore error
}

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>
)
