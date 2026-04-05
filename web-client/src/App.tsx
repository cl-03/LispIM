import { useEffect, useState } from 'react'
import { HashRouter, Routes, Route, Navigate, useNavigate, useLocation } from 'react-router-dom'
import { useAppStore } from '@/store/appStore'
import Login from '@/components/Login'
import Register from '@/components/Register'
import Chat from '@/components/Chat'
import Contacts from '@/components/Contacts'
import Discover from '@/components/Discover'
import Profile from '@/components/Profile'
import ProfileDetail from '@/components/ProfileDetail'
import Settings from '@/components/Settings'
import { NetworkIndicator } from '@/components/NetworkIndicator'
import './App.css'

// Main layout with bottom navigation
function MainLayout() {
  const navigate = useNavigate()
  const location = useLocation()
  const [activeTab, setActiveTab] = useState('/')
  const { connected } = useAppStore()

  // Sync activeTab with current location
  useEffect(() => {
    setActiveTab(location.pathname)
  }, [location.pathname, location])

  return (
    <div className="h-screen flex flex-col">
      <div className="flex-1 overflow-hidden">
        <Routes>
          <Route path="/" element={<Chat />} />
          <Route path="/contacts" element={<Contacts />} />
          <Route path="/discover" element={<Discover />} />
          <Route path="/profile" element={<Profile />} />
          <Route path="/profile/detail" element={<ProfileDetail />} />
          <Route path="/settings" element={<Settings />} />
        </Routes>
      </div>

      {/* Bottom Navigation */}
      <nav className="bg-white border-t flex justify-around items-center py-2 safe-area-pb shadow-lg">
        <button
          onClick={() => { navigate('/'); setActiveTab('/') }}
          className={`flex flex-col items-center p-3 rounded-xl transition-all duration-200 ${
            activeTab === '/'
              ? 'text-blue-500 bg-blue-50 scale-105'
              : 'text-gray-500 hover:bg-gray-50'
          }`}
        >
          <div className="relative">
            <svg className="w-6 h-6" fill={activeTab === '/' ? 'currentColor' : 'none'} stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z" />
            </svg>
            {!connected && (
              <div className="absolute -top-1 -right-1 w-2 h-2 bg-red-500 rounded-full animate-pulse" />
            )}
          </div>
          <span className="text-xs mt-1 font-medium">消息</span>
        </button>

        <button
          onClick={() => { navigate('/contacts'); setActiveTab('/contacts') }}
          className={`flex flex-col items-center p-3 rounded-xl transition-all duration-200 ${
            activeTab === '/contacts'
              ? 'text-blue-500 bg-blue-50 scale-105'
              : 'text-gray-500 hover:bg-gray-50'
          }`}
        >
          <svg className="w-6 h-6" fill={activeTab === '/contacts' ? 'currentColor' : 'none'} stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M12 4.354a4 4 0 110 5.292M15 21H3v-1a6 6 0 0112 0v1zm0 0h6v-1a6 6 0 00-9-5.197M13 7a4 4 0 11-8 0 4 4 0 018 0z" />
          </svg>
          <span className="text-xs mt-1 font-medium">联系人</span>
        </button>

        <button
          onClick={() => { navigate('/discover'); setActiveTab('/discover') }}
          className={`flex flex-col items-center p-3 rounded-xl transition-all duration-200 ${
            activeTab === '/discover'
              ? 'text-blue-500 bg-blue-50 scale-105'
              : 'text-gray-500 hover:bg-gray-50'
          }`}
        >
          <svg className="w-6 h-6" fill={activeTab === '/discover' ? 'currentColor' : 'none'} stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M21 12a9 9 0 01-9 9m9-9a9 9 0 00-9-9m9 9H3m9 9a9 9 0 01-9-9m9 9c1.657 0 3-4.03 3-9s-1.343-9-3-9m0 18c-1.657 0-3-4.03-3-9s1.343-9 3-9m-9 9a9 9 0 019-9" />
          </svg>
          <span className="text-xs mt-1 font-medium">发现</span>
        </button>

        <button
          onClick={() => { navigate('/profile'); setActiveTab('/profile') }}
          className={`flex flex-col items-center p-3 rounded-xl transition-all duration-200 ${
            activeTab === '/profile'
              ? 'text-blue-500 bg-blue-50 scale-105'
              : 'text-gray-500 hover:bg-gray-50'
          }`}
        >
          <svg className="w-6 h-6" fill={activeTab === '/profile' ? 'currentColor' : 'none'} stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z" />
          </svg>
          <span className="text-xs mt-1 font-medium">我</span>
        </button>
      </nav>
    </div>
  )
}

function App() {
  const { isAuthenticated, initWebSocket, token, ws } = useAppStore()

  useEffect(() => {
    // 只在已认证且 token 有效时初始化 WebSocket
    if (isAuthenticated && token && !ws) {
      const wsUrl = (import.meta as any).env.VITE_WS_URL || 'ws://localhost:3000'
      initWebSocket(wsUrl)
    }
  }, [isAuthenticated, token, ws, initWebSocket])

  // 调试输出
  useEffect(() => {
    console.log('[App] isAuthenticated:', isAuthenticated, 'token:', token ? 'exists' : 'none')
  }, [isAuthenticated, token])

  // 未认证时显示登录/注册页面
  if (!isAuthenticated) {
    return (
      <HashRouter>
        <div className="min-h-screen bg-gradient-to-br from-gray-900 via-gray-800 to-gray-900">
          <Routes>
            <Route path="/login" element={<Login />} />
            <Route path="/register" element={<Register />} />
            <Route path="/" element={<Navigate to="/login" replace />} />
            <Route path="*" element={<Navigate to="/login" replace />} />
          </Routes>
        </div>
      </HashRouter>
    )
  }

  return (
    <HashRouter>
      <MainLayout />
    </HashRouter>
  )
}

export default App
