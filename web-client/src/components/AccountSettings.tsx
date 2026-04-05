import React, { useState } from 'react'
import { useAppStore } from '@/store/appStore'
import { getApiClient } from '@/utils/api-client'

const AccountSettings: React.FC = () => {
  const { user } = useAppStore()
  const [showChangePassword, setShowChangePassword] = useState(false)
  const [showBindPhone, setShowBindPhone] = useState(false)
  const [showBindEmail, setShowBindEmail] = useState(false)
  const [showDeleteAccount, setShowDeleteAccount] = useState(false)

  return (
    <div className="space-y-6">
      {/* Header */}
      <div>
        <h2 className="text-lg font-semibold text-white">账号管理</h2>
        <p className="text-sm text-gray-400 mt-1">管理您的账号绑定和安全设置</p>
      </div>

      {/* Account Info */}
      <div className="bg-gray-800 rounded-lg divide-y divide-gray-700">
        <div className="p-4 flex items-center justify-between">
          <div>
            <div className="text-sm font-medium text-gray-400">用户名</div>
            <div className="text-white mt-0.5">@{user?.username}</div>
          </div>
          <span className="text-xs text-gray-500">不可修改</span>
        </div>

        <div className="p-4 flex items-center justify-between">
          <div>
            <div className="text-sm font-medium text-gray-400">手机号</div>
            <div className="text-white mt-0.5">
              {user?.phone ? (
                <span>{user.phone.replace(/(\d{3})\d{4}(\d{4})/, '$1****$2')}</span>
              ) : (
                <span className="text-gray-500">未绑定</span>
              )}
            </div>
          </div>
          {user?.phone ? (
            <button
              onClick={() => setShowBindPhone(true)}
              className="text-sm text-blue-400 hover:text-blue-300 transition-colors"
            >
              修改
            </button>
          ) : (
            <button
              onClick={() => setShowBindPhone(true)}
              className="px-3 py-1.5 bg-blue-500 text-white text-sm rounded-lg hover:bg-blue-600 transition-colors"
            >
              绑定
            </button>
          )}
        </div>

        <div className="p-4 flex items-center justify-between">
          <div>
            <div className="text-sm font-medium text-gray-400">邮箱</div>
            <div className="text-white mt-0.5">
              {user?.email ? (
                <span>{user.email.replace(/(.{2}).*(@.*)/, '$1***$2')}</span>
              ) : (
                <span className="text-gray-500">未绑定</span>
              )}
            </div>
          </div>
          {user?.email ? (
            <button
              onClick={() => setShowBindEmail(true)}
              className="text-sm text-blue-400 hover:text-blue-300 transition-colors"
            >
              修改
            </button>
          ) : (
            <button
              onClick={() => setShowBindEmail(true)}
              className="px-3 py-1.5 bg-blue-500 text-white text-sm rounded-lg hover:bg-blue-600 transition-colors"
            >
              绑定
            </button>
          )}
        </div>
      </div>

      {/* Change Password */}
      <div className="bg-gray-800 rounded-lg p-4">
        <div className="flex items-center justify-between">
          <div>
            <div className="text-sm font-medium text-white">修改密码</div>
            <div className="text-xs text-gray-500 mt-1">定期修改密码可以提高账号安全性</div>
          </div>
          <button
            onClick={() => setShowChangePassword(true)}
            className="px-4 py-2 bg-gray-700 text-white text-sm rounded-lg hover:bg-gray-600 transition-colors"
          >
            修改
          </button>
        </div>
      </div>

      {/* Delete Account */}
      <div className="bg-red-900/20 border border-red-900/30 rounded-lg p-4">
        <div className="flex items-center justify-between">
          <div>
            <div className="text-sm font-medium text-red-400">注销账号</div>
            <div className="text-xs text-red-400/70 mt-1">
              注销后所有数据将被永久删除，此操作不可恢复
            </div>
          </div>
          <button
            onClick={() => setShowDeleteAccount(true)}
            className="px-4 py-2 bg-red-500 text-white text-sm rounded-lg hover:bg-red-600 transition-colors"
          >
            注销账号
          </button>
        </div>
      </div>

      {/* Modals */}
      {showChangePassword && (
        <ChangePasswordModal onClose={() => setShowChangePassword(false)} />
      )}
      {showBindPhone && (
        <BindPhoneModal
          phone={user?.phone}
          onClose={() => setShowBindPhone(false)}
        />
      )}
      {showBindEmail && (
        <BindEmailModal
          email={user?.email}
          onClose={() => setShowBindEmail(false)}
        />
      )}
      {showDeleteAccount && (
        <DeleteAccountModal onClose={() => setShowDeleteAccount(false)} />
      )}
    </div>
  )
}

// Change Password Modal
const ChangePasswordModal: React.FC<{ onClose: () => void }> = ({ onClose }) => {
  const [formData, setFormData] = useState({
    currentPassword: '',
    newPassword: '',
    confirmPassword: ''
  })
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState('')

  const handleSubmit = async () => {
    if (!formData.currentPassword || !formData.newPassword) {
      setError('请填写完整密码信息')
      return
    }

    if (formData.newPassword !== formData.confirmPassword) {
      setError('两次输入的新密码不一致')
      return
    }

    if (formData.newPassword.length < 6) {
      setError('新密码长度不能少于 6 个字符')
      return
    }

    try {
      setLoading(true)
      setError('')
      const api = getApiClient()
      const response = await api.changePassword({
        currentPassword: formData.currentPassword,
        newPassword: formData.newPassword
      })

      if (response.success) {
        onClose()
      } else {
        setError(response.error?.message || '修改密码失败')
      }
    } catch (err) {
      setError('修改密码失败，请重试')
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50">
      <div className="bg-white rounded-lg w-full max-w-md p-6 relative">
        <h3 className="text-lg font-semibold text-gray-900 mb-4">修改密码</h3>

        <div className="space-y-4">
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">
              当前密码
            </label>
            <input
              type="password"
              value={formData.currentPassword}
              onChange={(e) => setFormData({ ...formData, currentPassword: e.target.value })}
              className="w-full px-3 py-2 border border-gray-300 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
              placeholder="输入当前密码"
            />
          </div>

          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">
              新密码
            </label>
            <input
              type="password"
              value={formData.newPassword}
              onChange={(e) => setFormData({ ...formData, newPassword: e.target.value })}
              className="w-full px-3 py-2 border border-gray-300 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
              placeholder="输入新密码"
            />
          </div>

          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">
              确认新密码
            </label>
            <input
              type="password"
              value={formData.confirmPassword}
              onChange={(e) => setFormData({ ...formData, confirmPassword: e.target.value })}
              className="w-full px-3 py-2 border border-gray-300 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
              placeholder="再次输入新密码"
            />
          </div>

          {error && (
            <div className="text-red-500 text-sm">{error}</div>
          )}
        </div>

        <div className="flex gap-3 mt-6">
          <button
            onClick={onClose}
            className="flex-1 px-4 py-2 border border-gray-300 text-gray-700 rounded-lg hover:bg-gray-50 text-sm"
          >
            取消
          </button>
          <button
            onClick={handleSubmit}
            disabled={loading}
            className="flex-1 px-4 py-2 bg-blue-500 text-white rounded-lg hover:bg-blue-600 disabled:opacity-50 disabled:cursor-not-allowed text-sm"
          >
            确认修改
          </button>
        </div>
      </div>
    </div>
  )
}

// Bind Phone Modal
const BindPhoneModal: React.FC<{ phone?: string; onClose: () => void }> = ({ phone, onClose }) => {
  const [formData, setFormData] = useState({
    phone: phone || '',
    code: ''
  })
  const [sendingCode, setSendingCode] = useState(false)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState('')
  const [countdown, setCountdown] = useState(0)

  const handleSendCode = async () => {
    if (!formData.phone) {
      setError('请输入手机号')
      return
    }

    try {
      setSendingCode(true)
      setError('')
      const api = getApiClient()
      const response = await api.sendVerificationCode({
        method: 'phone',
        value: formData.phone
      })

      if (response.success) {
        setCountdown(60)
        const timer = setInterval(() => {
          setCountdown((prev) => {
            if (prev <= 1) {
              clearInterval(timer)
              return 0
            }
            return prev - 1
          })
        }, 1000)
      } else {
        setError(response.error?.message || '发送验证码失败')
      }
    } catch (err) {
      setError('发送验证码失败，请重试')
    } finally {
      setSendingCode(false)
    }
  }

  const handleSubmit = async () => {
    if (!formData.phone || !formData.code) {
      setError('请填写完整信息')
      return
    }

    try {
      setLoading(true)
      setError('')
      const api = getApiClient()
      const response = await api.bindPhone({
        phone: formData.phone,
        code: formData.code
      })

      if (response.success) {
        onClose()
      } else {
        setError(response.error?.message || '绑定失败')
      }
    } catch (err) {
      setError('绑定失败，请重试')
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50">
      <div className="bg-white rounded-lg w-full max-w-md p-6 relative">
        <h3 className="text-lg font-semibold text-gray-900 mb-4">
          {phone ? '修改手机号' : '绑定手机号'}
        </h3>

        <div className="space-y-4">
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">
              手机号
            </label>
            <input
              type="tel"
              value={formData.phone}
              onChange={(e) => setFormData({ ...formData, phone: e.target.value })}
              className="w-full px-3 py-2 border border-gray-300 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
              placeholder="输入手机号"
            />
          </div>

          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">
              验证码
            </label>
            <div className="flex gap-2">
              <input
                type="text"
                value={formData.code}
                onChange={(e) => setFormData({ ...formData, code: e.target.value })}
                className="flex-1 px-3 py-2 border border-gray-300 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
                placeholder="输入验证码"
                maxLength={6}
              />
              <button
                onClick={handleSendCode}
                disabled={sendingCode || countdown > 0}
                className="px-4 py-2 bg-blue-500 text-white text-sm rounded-lg hover:bg-blue-600 disabled:opacity-50 disabled:cursor-not-allowed"
              >
                {countdown > 0 ? `${countdown}秒` : '获取验证码'}
              </button>
            </div>
          </div>

          {error && (
            <div className="text-red-500 text-sm">{error}</div>
          )}
        </div>

        <div className="flex gap-3 mt-6">
          <button
            onClick={onClose}
            className="flex-1 px-4 py-2 border border-gray-300 text-gray-700 rounded-lg hover:bg-gray-50 text-sm"
          >
            取消
          </button>
          <button
            onClick={handleSubmit}
            disabled={loading}
            className="flex-1 px-4 py-2 bg-blue-500 text-white rounded-lg hover:bg-blue-600 disabled:opacity-50 disabled:cursor-not-allowed text-sm"
          >
            确认绑定
          </button>
        </div>
      </div>
    </div>
  )
}

// Bind Email Modal
const BindEmailModal: React.FC<{ email?: string; onClose: () => void }> = ({ email, onClose }) => {
  const [formData, setFormData] = useState({
    email: email || '',
    code: ''
  })
  const [sendingCode, setSendingCode] = useState(false)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState('')
  const [countdown, setCountdown] = useState(0)

  const handleSendCode = async () => {
    if (!formData.email) {
      setError('请输入邮箱地址')
      return
    }

    try {
      setSendingCode(true)
      setError('')
      const api = getApiClient()
      const response = await api.sendVerificationCode({
        method: 'email',
        value: formData.email
      })

      if (response.success) {
        setCountdown(60)
        const timer = setInterval(() => {
          setCountdown((prev) => {
            if (prev <= 1) {
              clearInterval(timer)
              return 0
            }
            return prev - 1
          })
        }, 1000)
      } else {
        setError(response.error?.message || '发送验证码失败')
      }
    } catch (err) {
      setError('发送验证码失败，请重试')
    } finally {
      setSendingCode(false)
    }
  }

  const handleSubmit = async () => {
    if (!formData.email || !formData.code) {
      setError('请填写完整信息')
      return
    }

    try {
      setLoading(true)
      setError('')
      const api = getApiClient()
      const response = await api.bindEmail({
        email: formData.email,
        code: formData.code
      })

      if (response.success) {
        onClose()
      } else {
        setError(response.error?.message || '绑定失败')
      }
    } catch (err) {
      setError('绑定失败，请重试')
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50">
      <div className="bg-white rounded-lg w-full max-w-md p-6 relative">
        <h3 className="text-lg font-semibold text-gray-900 mb-4">
          {email ? '修改邮箱' : '绑定邮箱'}
        </h3>

        <div className="space-y-4">
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">
              邮箱地址
            </label>
            <input
              type="email"
              value={formData.email}
              onChange={(e) => setFormData({ ...formData, email: e.target.value })}
              className="w-full px-3 py-2 border border-gray-300 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
              placeholder="输入邮箱地址"
            />
          </div>

          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">
              验证码
            </label>
            <div className="flex gap-2">
              <input
                type="text"
                value={formData.code}
                onChange={(e) => setFormData({ ...formData, code: e.target.value })}
                className="flex-1 px-3 py-2 border border-gray-300 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
                placeholder="输入验证码"
                maxLength={6}
              />
              <button
                onClick={handleSendCode}
                disabled={sendingCode || countdown > 0}
                className="px-4 py-2 bg-blue-500 text-white text-sm rounded-lg hover:bg-blue-600 disabled:opacity-50 disabled:cursor-not-allowed"
              >
                {countdown > 0 ? `${countdown}秒` : '获取验证码'}
              </button>
            </div>
          </div>

          {error && (
            <div className="text-red-500 text-sm">{error}</div>
          )}
        </div>

        <div className="flex gap-3 mt-6">
          <button
            onClick={onClose}
            className="flex-1 px-4 py-2 border border-gray-300 text-gray-700 rounded-lg hover:bg-gray-50 text-sm"
          >
            取消
          </button>
          <button
            onClick={handleSubmit}
            disabled={loading}
            className="flex-1 px-4 py-2 bg-blue-500 text-white rounded-lg hover:bg-blue-600 disabled:opacity-50 disabled:cursor-not-allowed text-sm"
          >
            确认绑定
          </button>
        </div>
      </div>
    </div>
  )
}

// Delete Account Modal
const DeleteAccountModal: React.FC<{ onClose: () => void }> = ({ onClose }) => {
  const [password, setPassword] = useState('')
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState('')
  const { logout } = useAppStore()

  const handleSubmit = async () => {
    if (!password) {
      setError('请输入密码确认注销')
      return
    }

    try {
      setLoading(true)
      setError('')
      const api = getApiClient()
      const response = await api.deleteAccount(password)

      if (response.success) {
        logout()
        window.location.href = '/login'
      } else {
        setError(response.error?.message || '注销失败')
      }
    } catch (err) {
      setError('注销失败，请重试')
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50">
      <div className="bg-white rounded-lg w-full max-w-md p-6 relative">
        <h3 className="text-lg font-semibold text-red-600 mb-4">注销账号</h3>

        <div className="mb-4 p-4 bg-red-50 rounded-lg">
          <p className="text-sm text-red-700">
            <strong>警告：</strong>注销账号后，您的所有数据（包括消息、联系人、朋友圈等）将被永久删除，此操作不可恢复。
          </p>
        </div>

        <div className="space-y-4">
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">
              输入密码确认
            </label>
            <input
              type="password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              className="w-full px-3 py-2 border border-gray-300 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-red-500"
              placeholder="输入登录密码"
            />
          </div>

          {error && (
            <div className="text-red-500 text-sm">{error}</div>
          )}
        </div>

        <div className="flex gap-3 mt-6">
          <button
            onClick={onClose}
            className="flex-1 px-4 py-2 border border-gray-300 text-gray-700 rounded-lg hover:bg-gray-50 text-sm"
          >
            取消
          </button>
          <button
            onClick={handleSubmit}
            disabled={loading}
            className="flex-1 px-4 py-2 bg-red-500 text-white rounded-lg hover:bg-red-600 disabled:opacity-50 disabled:cursor-not-allowed text-sm"
          >
            确认注销
          </button>
        </div>
      </div>
    </div>
  )
}

export default AccountSettings
