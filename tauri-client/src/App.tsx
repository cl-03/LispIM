import { useEffect } from 'react'
import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom'
import { useAppStore } from '@/store/appStore'
import Login from '@/components/Login'
import Chat from '@/components/Chat'
import './App.css'

// 引入 Tauri API
import { appWindow } from '@tauri-apps/api/window'
import { listen } from '@tauri-apps/api/event'

function App() {
  const { isAuthenticated, initWebSocket, token, user } = useAppStore()

  useEffect(() => {
    // Tauri 窗口事件监听
    const unlisten = listen('tauri://focus', () => {
      console.log('Window focused')
    })

    return () => {
      unlisten()
    }
  }, [])

  useEffect(() => {
    if (isAuthenticated && token) {
      // Tauri 环境下使用不同的 WebSocket 地址
      const wsUrl = (import.meta as any).env.VITE_WS_URL || 'ws://localhost:3000'
      initWebSocket(wsUrl, token)
    }
  }, [isAuthenticated, token, initWebSocket])

  return (
    <BrowserRouter>
      <Routes>
        <Route
          path="/login"
          element={isAuthenticated ? <Navigate to="/" /> : <Login />}
        />
        <Route
          path="/"
          element={isAuthenticated ? <Chat /> : <Navigate to="/login" />}
        />
      </Routes>
    </BrowserRouter>
  )
}

export default App
