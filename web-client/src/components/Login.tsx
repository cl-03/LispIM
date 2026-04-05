import React, { useState, useEffect } from 'react'
import { useNavigate } from 'react-router-dom'
import { useAppStore } from '@/store/appStore'

const Login: React.FC = () => {
  const navigate = useNavigate()
  const { login, initAPI, apiInitialized } = useAppStore()
  const [username, setUsername] = useState('')
  const [password, setPassword] = useState('')
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState('')
  const [showPassword, setShowPassword] = useState(false)

  // 初始化 API 客户端
  useEffect(() => {
    const API_URL = (import.meta as any).env.VITE_API_URL || 'http://localhost:3000'
    initAPI(API_URL)
  }, [initAPI])

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()

    // 确保 API 已初始化
    if (!apiInitialized) {
      setError('系统初始化中，请稍后')
      return
    }

    setLoading(true)
    setError('')

    // 去除用户名和密码前后的空格
    const trimmedUsername = username.trim()
    const trimmedPassword = password.trim()

    const result = await login(trimmedUsername, trimmedPassword)

    if (!result.success) {
      setError(result.error || '登录失败')
    } else {
      navigate('/')
    }

    setLoading(false)
  }

  const handleWechatLogin = async () => {
    setError('')
    setLoading(true)

    try {
      // 模拟微信授权流程 - 实际应用中这里会打开微信授权二维码
      // 这里直接调用 API
      const mockCode = 'wechat-auth-code-' + Date.now()
      const result = await (useAppStore.getState().wechatLogin)(mockCode)

      if (!result.success) {
        setError(result.error || '微信登录失败')
      } else {
        navigate('/')
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : '微信登录失败')
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="min-h-screen flex items-center justify-center bg-gradient-to-br from-gray-900 via-gray-800 to-gray-900 relative overflow-hidden">
      {/* 动态背景装饰 */}
      <div className="absolute inset-0 overflow-hidden pointer-events-none">
        {/* 大型光晕 */}
        <div className="absolute -top-40 -right-40 w-96 h-96 bg-gradient-to-br from-blue-500/20 to-purple-600/20 rounded-full blur-3xl animate-pulse"></div>
        <div className="absolute -bottom-40 -left-40 w-96 h-96 bg-gradient-to-tr from-indigo-500/20 to-pink-600/20 rounded-full blur-3xl animate-pulse delay-1000"></div>
        {/* 浮动装饰元素 */}
        <div className="absolute top-20 left-20 w-4 h-4 bg-blue-400/30 rounded-full animate-pulse shadow-[0_0_20px_rgba(59,130,246,0.5)]"></div>
        <div className="absolute bottom-32 right-32 w-6 h-6 bg-purple-500/30 rounded-full animate-pulse delay-500 shadow-[0_0_20px_rgba(139,92,246,0.5)]"></div>
        <div className="absolute top-1/3 left-1/4 w-3 h-3 bg-pink-400/30 rounded-full animate-pulse delay-700 shadow-[0_0_15px_rgba(236,72,153,0.5)]"></div>
        <div className="absolute top-2/3 right-1/4 w-5 h-5 bg-cyan-400/30 rounded-full animate-pulse delay-300 shadow-[0_0_18px_rgba(34,211,238,0.5)]"></div>
        {/* 网格背景 */}
        <div className="absolute inset-0 bg-[linear-gradient(rgba(255,255,255,0.02)_1px,transparent_1px),linear-gradient(90deg,rgba(255,255,255,0.02)_1px,transparent_1px)] bg-[size:50px_50px]"></div>
      </div>

      {/* 玻璃态卡片 */}
      <div className="w-full max-w-md p-8 glass-dark rounded-3xl shadow-2xl border border-white/10 relative z-10 transform transition-all duration-300 hover:shadow-[0_0_40px_rgba(59,130,246,0.2)]">
        {/* Logo 和标题 */}
        <div className="text-center mb-8">
          <div className="inline-flex items-center justify-center w-20 h-20 bg-gradient-to-br from-blue-500/30 to-purple-600/30 rounded-2xl mb-4 shadow-[0_0_30px_rgba(59,130,246,0.4)] border border-white/10 backdrop-blur-sm transform hover:scale-105 transition-all duration-300">
            <span className="text-4xl filter drop-shadow-lg">💬</span>
          </div>
          <h1 className="text-4xl font-bold text-transparent bg-clip-text bg-gradient-to-r from-blue-400 via-purple-400 to-pink-400 mb-2 tracking-tight drop-shadow-lg">LispIM</h1>
          <p className="text-gray-400 font-light text-sm">企业级即时通讯系统</p>
        </div>

        {/* 微信快捷登录 */}
        <button
          onClick={handleWechatLogin}
          disabled={loading}
          className="w-full py-3.5 px-4 bg-[#07C160] hover:bg-[#07C160]/90 disabled:bg-gray-600
                   disabled:cursor-not-allowed text-white font-semibold rounded-xl
                   transition-all duration-300 flex items-center justify-center gap-2
                   shadow-[0_4px_20px_rgba(7,193,96,0.4)] hover:shadow-[0_6px_30px_rgba(7,193,96,0.6)]
                   hover:scale-[1.02] active:scale-[0.98] mb-6 border border-white/10"
        >
          {loading ? (
            <span className="flex items-center gap-2">
              <svg className="animate-spin h-5 w-5" viewBox="0 0 24 24">
                <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" fill="none" />
                <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z" />
              </svg>
              连接中...
            </span>
          ) : (
            <>
              <span className="text-xl">💚</span>
              <span>微信快捷登录</span>
            </>
          )}
        </button>

        {/* 分割线 */}
        <div className="relative mb-6">
          <div className="absolute inset-0 flex items-center">
            <div className="w-full border-t border-gray-700"></div>
          </div>
          <div className="relative flex justify-center text-sm">
            <span className="px-4 bg-gray-800/80 text-gray-500">或使用账号登录</span>
          </div>
        </div>

        <form onSubmit={handleSubmit} className="space-y-5">
          <div>
            <label htmlFor="username" className="block text-sm font-medium text-gray-300 mb-2">
              用户名
            </label>
            <input
              type="text"
              id="username"
              value={username}
              onChange={(e) => setUsername(e.target.value)}
              className="w-full px-4 py-3.5 bg-gray-900/50 backdrop-blur border border-gray-700/50 rounded-xl
                       text-white placeholder-gray-500 focus:outline-none focus:ring-2
                       focus:ring-blue-500/50 focus:border-transparent transition-all duration-300
                       hover:border-gray-600 hover:bg-gray-900/70"
              placeholder="请输入用户名"
              required
            />
          </div>

          <div>
            <label htmlFor="password" className="block text-sm font-medium text-gray-300 mb-2">
              密码
            </label>
            <div className="relative">
              <input
                type={showPassword ? 'text' : 'password'}
                id="password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                className="w-full px-4 py-3.5 bg-gray-900/50 backdrop-blur border border-gray-700/50 rounded-xl
                         text-white placeholder-gray-500 focus:outline-none focus:ring-2
                         focus:ring-blue-500/50 focus:border-transparent transition-all duration-300
                         hover:border-gray-600 hover:bg-gray-900/70 pr-12"
                placeholder="请输入密码"
                required
              />
              <button
                type="button"
                onClick={() => setShowPassword(!showPassword)}
                className="absolute right-3 top-1/2 -translate-y-1/2 text-gray-500 hover:text-gray-300 transition-colors p-1"
              >
                {showPassword ? (
                  <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M13.875 18.825A10.05 10.05 0 0112 19c-4.478 0-8.268-2.943-9.543-7a9.97 9.97 0 011.563-3.029m5.858-5.908a9.028 9.028 0 013.387-.632c4.478 0 8.268 2.943 9.543 7a9.97 9.97 0 01-1.563 3.029m-5.858 5.908a10.055 10.055 0 01-1.258 1.917M3 3l18 18" />
                  </svg>
                ) : (
                  <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M2.458 12C3.732 7.943 7.523 5 12 5c4.478 0 8.268 2.943 9.542 7-1.274 4.057-5.064 7-9.542 7-4.477 0-8.268-2.943-9.542-7z" />
                  </svg>
                )}
              </button>
            </div>
          </div>

          <div className="flex items-center justify-between text-sm">
            <label className="flex items-center gap-2 cursor-pointer group">
              <input
                type="checkbox"
                className="w-4 h-4 rounded border-gray-600 bg-gray-900 text-blue-500
                         focus:ring-blue-500 focus:ring-offset-0 transition-colors"
              />
              <span className="text-gray-400 group-hover:text-gray-300 transition-colors">记住我</span>
            </label>
            <button type="button" className="text-blue-400 hover:text-blue-300 font-medium transition-colors">
              忘记密码？
            </button>
          </div>

          {error && (
            <div className="p-3.5 bg-red-500/10 border border-red-500/30 rounded-xl text-red-400 text-sm
                          flex items-center gap-2 shadow-[0_0_20px_rgba(239,68,68,0.2)] animate-pulse">
              <svg className="w-5 h-5 flex-shrink-0" fill="currentColor" viewBox="0 0 20 20">
                <path fillRule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z" clipRule="evenodd" />
              </svg>
              {error}
            </div>
          )}

          <button
            type="submit"
            disabled={loading}
            className="w-full py-3.5 px-4 bg-gradient-to-r from-blue-500 to-indigo-600
                     hover:from-blue-600 hover:to-indigo-700
                     disabled:from-gray-600 disabled:to-gray-600 disabled:cursor-not-allowed
                     text-white font-semibold rounded-xl transition-all duration-300
                     shadow-[0_4px_20px_rgba(59,130,246,0.4)] hover:shadow-[0_6px_30px_rgba(59,130,246,0.6)]
                     hover:scale-[1.02] active:scale-[0.98]"
          >
            {loading ? (
              <span className="flex items-center justify-center gap-2">
                <svg className="animate-spin h-5 w-5" viewBox="0 0 24 24">
                  <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" fill="none" />
                  <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z" />
                </svg>
                登录中...
              </span>
            ) : (
              '登录'
            )}
          </button>
        </form>

        {/* 底部链接 */}
        <div className="mt-6 text-center text-sm">
          <span className="text-gray-500">还没有账号？</span>
          <button
            onClick={() => navigate('/register')}
            className="ml-2 text-transparent bg-clip-text bg-gradient-to-r from-blue-400 to-purple-400
                     hover:from-blue-300 hover:to-purple-300 font-semibold transition-all
                     hover:shadow-[0_0_15px_rgba(59,130,246,0.4)]"
          >
            立即注册
          </button>
        </div>

        {/* 服务协议 */}
        <div className="mt-4 text-center text-xs text-gray-600">
          <p>登录即代表您同意</p>
          <div className="mt-1 space-x-2">
            <button className="text-gray-500 hover:text-blue-400 transition-colors hover:underline">
              《用户服务协议》
            </button>
            <span>·</span>
            <button className="text-gray-500 hover:text-blue-400 transition-colors hover:underline">
              《隐私政策》
            </button>
          </div>
        </div>
      </div>
    </div>
  )
}

export default Login
