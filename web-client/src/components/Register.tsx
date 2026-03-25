import React, { useState, useEffect } from 'react'
import { useNavigate } from 'react-router-dom'
import { useAppStore } from '@/store/appStore'
import type { RegisterMethod } from '@/types'

const Register: React.FC = () => {
  const navigate = useNavigate()
  const { register, sendVerificationCode } = useAppStore()
  const [method, setMethod] = useState<RegisterMethod>('username')
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState('')
  const [success, setSuccess] = useState('')

  // 用户名密码注册
  const [username, setUsername] = useState('')
  const [password, setPassword] = useState('')
  const [confirmPassword, setConfirmPassword] = useState('')

  // 手机号注册
  const [phone, setPhone] = useState('')
  const [phoneCode, setPhoneCode] = useState('')
  const [phoneCodeSent, setPhoneCodeSent] = useState(false)
  const [phoneCountdown, setPhoneCountdown] = useState(0)

  // 邮箱注册
  const [email, setEmail] = useState('')
  const [emailCode, setEmailCode] = useState('')
  const [emailCodeSent, setEmailCodeSent] = useState(false)
  const [emailCountdown, setEmailCountdown] = useState(0)

  // 邀请码（可选）
  const [invitationCode, setInvitationCode] = useState('')

  // 倒计时效果
  useEffect(() => {
    let interval: ReturnType<typeof setInterval>
    if (phoneCountdown > 0) {
      interval = setInterval(() => {
        setPhoneCountdown(prev => prev - 1)
      }, 1000)
    }
    if (emailCountdown > 0) {
      interval = setInterval(() => {
        setEmailCountdown(prev => prev - 1)
      }, 1000)
    }
    return () => clearInterval(interval)
  }, [phoneCountdown, emailCountdown])

  const handleSendPhoneCode = async () => {
    if (!phone || !/^1[3-9]\d{9}$/.test(phone)) {
      setError('请输入正确的手机号')
      return
    }
    setLoading(true)
    setError('')

    const result = await sendVerificationCode('phone', phone)

    if (result.success) {
      setPhoneCodeSent(true)
      setPhoneCountdown(60)
      setSuccess('验证码已发送')
    } else {
      setError(result.error || '发送失败')
    }

    setLoading(false)
  }

  const handleSendEmailCode = async () => {
    if (!email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
      setError('请输入正确的邮箱地址')
      return
    }
    setLoading(true)
    setError('')

    const result = await sendVerificationCode('email', email)

    if (result.success) {
      setEmailCodeSent(true)
      setEmailCountdown(60)
      setSuccess('验证码已发送')
    } else {
      setError(result.error || '发送失败')
    }

    setLoading(false)
  }

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setError('')
    setSuccess('')

    // 验证
    if (method === 'username') {
      if (!username || username.length < 3) {
        setError('用户名至少 3 个字符')
        return
      }
      if (!password || password.length < 6) {
        setError('密码至少 6 个字符')
        return
      }
      if (password !== confirmPassword) {
        setError('两次输入的密码不一致')
        return
      }
    } else if (method === 'phone') {
      if (!phone || !/^1[3-9]\d{9}$/.test(phone)) {
        setError('请输入正确的手机号')
        return
      }
      if (!phoneCode || phoneCode.length !== 6) {
        setError('请输入 6 位验证码')
        return
      }
    } else if (method === 'email') {
      if (!email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
        setError('请输入正确的邮箱')
        return
      }
      if (!emailCode || emailCode.length !== 6) {
        setError('请输入 6 位验证码')
        return
      }
    }

    setLoading(true)

    const registerData = {
      method,
      username: method === 'username' ? username : undefined,
      password: method === 'username' ? password : undefined,
      phone: method === 'phone' ? phone : undefined,
      phoneCode: method === 'phone' ? phoneCode : undefined,
      email: method === 'email' ? email : undefined,
      emailCode: method === 'email' ? emailCode : undefined,
      invitationCode: invitationCode || undefined
    }

    const result = await register(registerData)

    if (result.success) {
      setSuccess('注册成功！')
      // 注册成功后直接跳转登录页（需要手动登录）
      setTimeout(() => {
        navigate('/login')
      }, 1500)
    } else {
      setError(result.error || '注册失败')
    }

    setLoading(false)
  }

  const handleWechatLogin = async () => {
    // TODO: 实际应用中这里会打开微信授权二维码或跳转微信授权页面
    setError('')
    setSuccess('')
    setLoading(true)

    try {
      const mockCode = 'wechat-auth-code-' + Date.now()
      const result = await (useAppStore.getState().wechatLogin)(mockCode)

      if (result.success) {
        setSuccess('微信授权成功！')
        navigate('/')
      } else {
        setError(result.error || '微信授权失败')
      }
    } catch (err) {
      setLoading(false)
      setError(err instanceof Error ? err.message : '微信授权失败')
    }
  }

  const methods: Array<{ value: RegisterMethod; label: string; icon: string }> = [
    { value: 'username', label: '用户名', icon: '👤' },
    { value: 'phone', label: '手机号', icon: '📱' },
    { value: 'email', label: '邮箱', icon: '📧' },
    { value: 'wechat', label: '微信', icon: '💚' }
  ]

  return (
    <div className="min-h-screen flex items-center justify-center bg-gradient-to-br from-gray-900 via-gray-800 to-gray-900">
      {/* 背景装饰 */}
      <div className="absolute inset-0 overflow-hidden pointer-events-none">
        <div className="absolute -top-40 -right-40 w-80 h-80 bg-blue-500/10 rounded-full blur-3xl"></div>
        <div className="absolute -bottom-40 -left-40 w-80 h-80 bg-blue-600/10 rounded-full blur-3xl"></div>
      </div>

      <div className="w-full max-w-md p-8 bg-gray-800/80 backdrop-blur-xl rounded-2xl shadow-2xl border border-gray-700/50 relative z-10">
        {/* Logo 和标题 */}
        <div className="text-center mb-8">
          <div className="inline-flex items-center justify-center w-16 h-16 bg-blue-500/20 rounded-2xl mb-4">
            <span className="text-3xl">💬</span>
          </div>
          <h1 className="text-3xl font-bold text-white mb-2">注册 LispIM</h1>
          <p className="text-gray-400">创建您的企业通讯账号</p>
        </div>

        {/* 注册方式选择 */}
        <div className="grid grid-cols-4 gap-2 mb-6">
          {methods.map((m) => (
            <button
              key={m.value}
              onClick={() => { setMethod(m.value); setError(''); setSuccess(''); }}
              className={`flex flex-col items-center justify-center p-3 rounded-xl transition-all duration-200 ${
                method === m.value
                  ? 'bg-blue-500 text-white shadow-lg scale-105'
                  : 'bg-gray-900/50 text-gray-400 hover:bg-gray-900 hover:text-white'
              }`}
            >
              <span className="text-xl mb-1">{m.icon}</span>
              <span className="text-xs">{m.label}</span>
            </button>
          ))}
        </div>

        {/* 微信授权快捷入口 */}
        {method === 'wechat' ? (
          <div className="text-center py-8">
            <button
              onClick={handleWechatLogin}
              disabled={loading}
              className="w-full py-4 px-6 bg-[#07C160] hover:bg-[#07C160]/90 disabled:bg-gray-600
                       disabled:cursor-not-allowed text-white font-semibold rounded-xl
                       transition-all duration-200 flex items-center justify-center gap-3 shadow-lg"
            >
              {loading ? (
                <span>授权中...</span>
              ) : (
                <>
                  <span className="text-xl">💚</span>
                  <span>微信快捷登录/注册</span>
                </>
              )}
            </button>
            <p className="mt-4 text-sm text-gray-500">
              微信登录将自动创建账号并登录
            </p>
          </div>
        ) : (
          <form onSubmit={handleSubmit} className="space-y-5">
            {/* 用户名密码注册 */}
            {method === 'username' && (
              <>
                <div>
                  <label htmlFor="username" className="block text-sm font-medium text-gray-300 mb-2">
                    用户名
                  </label>
                  <input
                    type="text"
                    id="username"
                    value={username}
                    onChange={(e) => setUsername(e.target.value)}
                    className="w-full px-4 py-3 bg-gray-900 border border-gray-700 rounded-xl
                             text-white placeholder-gray-500 focus:outline-none focus:ring-2
                             focus:ring-blue-500 focus:border-transparent transition-all"
                    placeholder="至少 3 个字符"
                    required
                    minLength={3}
                  />
                </div>

                <div>
                  <label htmlFor="password" className="block text-sm font-medium text-gray-300 mb-2">
                    密码
                  </label>
                  <input
                    type="password"
                    id="password"
                    value={password}
                    onChange={(e) => setPassword(e.target.value)}
                    className="w-full px-4 py-3 bg-gray-900 border border-gray-700 rounded-xl
                             text-white placeholder-gray-500 focus:outline-none focus:ring-2
                             focus:ring-blue-500 focus:border-transparent transition-all"
                    placeholder="至少 6 个字符"
                    required
                    minLength={6}
                  />
                </div>

                <div>
                  <label htmlFor="confirmPassword" className="block text-sm font-medium text-gray-300 mb-2">
                    确认密码
                  </label>
                  <input
                    type="password"
                    id="confirmPassword"
                    value={confirmPassword}
                    onChange={(e) => setConfirmPassword(e.target.value)}
                    className="w-full px-4 py-3 bg-gray-900 border border-gray-700 rounded-xl
                             text-white placeholder-gray-500 focus:outline-none focus:ring-2
                             focus:ring-blue-500 focus:border-transparent transition-all"
                    placeholder="再次输入密码"
                    required
                  />
                </div>
              </>
            )}

            {/* 手机号注册 */}
            {method === 'phone' && (
              <>
                <div>
                  <label htmlFor="phone" className="block text-sm font-medium text-gray-300 mb-2">
                    手机号
                  </label>
                  <input
                    type="tel"
                    id="phone"
                    value={phone}
                    onChange={(e) => setPhone(e.target.value)}
                    className="w-full px-4 py-3 bg-gray-900 border border-gray-700 rounded-xl
                             text-white placeholder-gray-500 focus:outline-none focus:ring-2
                             focus:ring-blue-500 focus:border-transparent transition-all"
                    placeholder="请输入手机号"
                    pattern="^1[3-9]\d{9}$"
                    required
                  />
                </div>

                <div>
                  <label htmlFor="phoneCode" className="block text-sm font-medium text-gray-300 mb-2">
                    验证码
                  </label>
                  <div className="flex gap-3">
                    <input
                      type="text"
                      id="phoneCode"
                      value={phoneCode}
                      onChange={(e) => setPhoneCode(e.target.value.replace(/\D/g, ''))}
                      className="flex-1 px-4 py-3 bg-gray-900 border border-gray-700 rounded-xl
                               text-white placeholder-gray-500 focus:outline-none focus:ring-2
                               focus:ring-blue-500 focus:border-transparent transition-all"
                      placeholder="6 位验证码"
                      maxLength={6}
                      required
                    />
                    <button
                      type="button"
                      onClick={handleSendPhoneCode}
                      disabled={loading || phoneCodeSent || phoneCountdown > 0}
                      className="px-4 py-3 bg-gray-700 hover:bg-gray-600
                               disabled:bg-gray-600 disabled:cursor-not-allowed
                               text-white font-medium rounded-xl transition-colors whitespace-nowrap"
                    >
                      {phoneCountdown > 0 ? `${phoneCountdown}s` : '发送验证码'}
                    </button>
                  </div>
                </div>
              </>
            )}

            {/* 邮箱注册 */}
            {method === 'email' && (
              <>
                <div>
                  <label htmlFor="email" className="block text-sm font-medium text-gray-300 mb-2">
                    邮箱
                  </label>
                  <input
                    type="email"
                    id="email"
                    value={email}
                    onChange={(e) => setEmail(e.target.value)}
                    className="w-full px-4 py-3 bg-gray-900 border border-gray-700 rounded-xl
                             text-white placeholder-gray-500 focus:outline-none focus:ring-2
                             focus:ring-blue-500 focus:border-transparent transition-all"
                    placeholder="example@email.com"
                    required
                  />
                </div>

                <div>
                  <label htmlFor="emailCode" className="block text-sm font-medium text-gray-300 mb-2">
                    验证码
                  </label>
                  <div className="flex gap-3">
                    <input
                      type="text"
                      id="emailCode"
                      value={emailCode}
                      onChange={(e) => setEmailCode(e.target.value.replace(/\D/g, ''))}
                      className="flex-1 px-4 py-3 bg-gray-900 border border-gray-700 rounded-xl
                               text-white placeholder-gray-500 focus:outline-none focus:ring-2
                               focus:ring-blue-500 focus:border-transparent transition-all"
                      placeholder="6 位验证码"
                      maxLength={6}
                      required
                    />
                    <button
                      type="button"
                      onClick={handleSendEmailCode}
                      disabled={loading || emailCodeSent || emailCountdown > 0}
                      className="px-4 py-3 bg-gray-700 hover:bg-gray-600
                               disabled:bg-gray-600 disabled:cursor-not-allowed
                               text-white font-medium rounded-xl transition-colors whitespace-nowrap"
                    >
                      {emailCountdown > 0 ? `${emailCountdown}s` : '发送验证码'}
                    </button>
                  </div>
                </div>
              </>
            )}

            {/* 邀请码（可选） */}
            <div>
              <label htmlFor="invitationCode" className="block text-sm font-medium text-gray-300 mb-2">
                邀请码 <span className="text-gray-500">(可选)</span>
              </label>
              <input
                type="text"
                id="invitationCode"
                value={invitationCode}
                onChange={(e) => setInvitationCode(e.target.value)}
                className="w-full px-4 py-3 bg-gray-900 border border-gray-700 rounded-xl
                         text-white placeholder-gray-500 focus:outline-none focus:ring-2
                         focus:ring-blue-500 focus:border-transparent transition-all"
                placeholder="有邀请码？填写在这里"
              />
            </div>

            {/* 错误提示 */}
            {error && (
              <div className="p-3 bg-red-500/10 border border-red-500/50 rounded-xl text-red-400 text-sm animate-pulse">
                {error}
              </div>
            )}

            {/* 成功提示 */}
            {success && (
              <div className="p-3 bg-green-500/10 border border-green-500/50 rounded-xl text-green-400 text-sm">
                {success}
              </div>
            )}

            {/* 提交按钮 */}
            <button
              type="submit"
              disabled={loading}
              className="w-full py-3 px-4 bg-blue-500 hover:bg-blue-600
                       disabled:bg-gray-600 disabled:cursor-not-allowed
                       text-white font-semibold rounded-xl transition-all duration-200
                       shadow-lg hover:shadow-blue-500/30"
            >
              {loading ? '注册中...' : '注册'}
            </button>
          </form>
        )}

        {/* 底部链接 */}
        <div className="mt-6 text-center text-sm">
          <span className="text-gray-500">已有账号？</span>
          <button
            onClick={() => navigate('/login')}
            className="ml-2 text-blue-500 hover:text-blue-400 font-medium"
          >
            立即登录
          </button>
        </div>

        {/* 服务协议 */}
        <div className="mt-4 text-center text-xs text-gray-600">
          <p>注册即代表您同意</p>
          <div className="mt-1 space-x-2">
            <button className="text-gray-500 hover:text-blue-400 transition-colors">
              《用户服务协议》
            </button>
            <span>·</span>
            <button className="text-gray-500 hover:text-blue-400 transition-colors">
              《隐私政策》
            </button>
          </div>
        </div>
      </div>
    </div>
  )
}

export default Register
