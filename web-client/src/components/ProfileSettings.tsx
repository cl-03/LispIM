import React, { useState, useRef } from 'react'
import { useAppStore } from '@/store/appStore'
import { getApiClient } from '@/utils/api-client'

const ProfileSettings: React.FC = () => {
  const { user, updateUser } = useAppStore()
  const [editing, setEditing] = useState(false)
  const [loading, setLoading] = useState(false)
  const [avatarUrl, setAvatarUrl] = useState(user?.avatar || '')
  const fileInputRef = useRef<HTMLInputElement>(null)

  const [formData, setFormData] = useState({
    displayName: user?.displayName || '',
    bio: user?.bio || '',
    gender: (user?.gender as 'male' | 'female' | 'other' | '') || '',
    birthday: user?.birthday || '',
    location: user?.location || '',
    company: user?.company || '',
    website: user?.website || ''
  })

  const handleAvatarUpload = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0]
    if (!file) return

    try {
      setLoading(true)
      const api = getApiClient()
      const response = await api.uploadFile(file, file.name)

      if (response.success && response.data) {
        setAvatarUrl(response.data.url)
        // Update profile with new avatar
        await api.updateProfile({ avatar: response.data.url })
        updateUser({ ...user!, avatar: response.data.url })
      }
    } catch (error) {
      console.error('Failed to upload avatar:', error)
    } finally {
      setLoading(false)
    }
  }

  const handleSubmit = async () => {
    try {
      setLoading(true)
      const api = getApiClient()
      const response = await api.updateProfile({
        displayName: formData.displayName,
        avatar: avatarUrl
      })

      if (response.success && response.data) {
        updateUser({ ...user!, displayName: formData.displayName, avatar: avatarUrl })
        setEditing(false)
      }
    } catch (error) {
      console.error('Failed to update profile:', error)
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="space-y-5">
      {/* Header */}
      <div className="flex items-center justify-between mb-2">
        <div>
          <h2 className="text-xl font-bold text-white">个人资料</h2>
          <p className="text-sm text-gray-400 mt-1">管理您的个人信息和展示资料</p>
        </div>
        {!editing ? (
          <button
            onClick={() => setEditing(true)}
            className="px-5 py-2.5 bg-gradient-to-r from-blue-500 to-indigo-600 text-white rounded-xl hover:from-blue-600 hover:to-indigo-700 transition-all text-sm font-medium shadow-lg hover:shadow-xl hover:scale-105"
          >
            编辑资料
          </button>
        ) : (
          <div className="flex gap-2">
            <button
              onClick={() => {
                setEditing(false)
                setFormData({
                  displayName: user?.displayName || '',
                  bio: user?.bio || '',
                  gender: (user?.gender as 'male' | 'female' | 'other' | '') || '',
                  birthday: user?.birthday || '',
                  location: user?.location || '',
                  company: user?.company || '',
                  website: user?.website || ''
                })
              }}
              className="px-4 py-2 border border-gray-600 text-gray-300 rounded-xl hover:bg-gray-800 transition-colors text-sm"
            >
              取消
            </button>
            <button
              onClick={handleSubmit}
              disabled={loading}
              className="px-5 py-2.5 bg-gradient-to-r from-blue-500 to-indigo-600 text-white rounded-xl disabled:opacity-50 disabled:cursor-not-allowed text-sm font-medium shadow-lg hover:shadow-xl hover:scale-105 transition-all"
            >
              保存
            </button>
          </div>
        )}
      </div>

      {/* Avatar Card */}
      <div className="bg-gradient-to-br from-gray-800/80 to-gray-800/60 backdrop-blur rounded-2xl p-6 border border-gray-700/50 shadow-lg">
        <div className="flex items-center gap-6">
          <div className="relative group">
            <div className="w-28 h-28 rounded-full bg-gradient-to-br from-blue-500 to-indigo-600 flex items-center justify-center text-white text-3xl font-bold overflow-hidden shadow-xl ring-4 ring-blue-500/20">
              {avatarUrl ? (
                <img src={avatarUrl} alt={user?.displayName} className="w-28 h-28 object-cover" />
              ) : (
                (user?.displayName || user?.username || '?').charAt(0).toUpperCase()
              )}
            </div>
            {editing && (
              <button
                onClick={() => fileInputRef.current?.click()}
                disabled={loading}
                className="absolute bottom-1 right-1 p-2.5 bg-gradient-to-r from-blue-500 to-indigo-600 rounded-full text-white hover:from-blue-600 hover:to-indigo-700 transition-all shadow-lg opacity-0 group-hover:opacity-100"
              >
                <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M3 9a2 2 0 012-2h.93a2 2 0 001.664-.89l.812-1.22A2 2 0 0110.07 4h3.86a2 2 0 011.664.89l.812 1.22A2 2 0 0018.07 7H19a2 2 0 012 2v9a2 2 0 01-2 2H5a2 2 0 01-2-2V9z" />
                </svg>
                <input
                  ref={fileInputRef}
                  type="file"
                  accept="image/*"
                  onChange={handleAvatarUpload}
                  className="hidden"
                />
              </button>
            )}
          </div>
          <div>
            <h3 className="text-xl font-bold text-white">{user?.displayName || user?.username}</h3>
            <p className="text-gray-400 text-sm">@{user?.username}</p>
            {editing && (
              <p className="text-xs text-gray-500 mt-3 bg-gray-700/50 px-3 py-2 rounded-lg inline-block">
                <svg className="w-4 h-4 inline mr-1 -mt-0.5" fill="currentColor" viewBox="0 0 24 24">
                  <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-2 15l-5-5 1.41-1.41L10 14.17l7.59-7.59L19 8l-9 9z"/>
                </svg>
                点击相机图标上传新头像，支持 JPG、PNG 格式
              </p>
            )}
          </div>
        </div>
      </div>

      {/* Basic Info */}
      <div className="bg-gradient-to-br from-gray-800/80 to-gray-800/60 backdrop-blur rounded-2xl border border-gray-700/50 shadow-lg overflow-hidden">
        <div className="divide-y divide-gray-700/50">
          <div className="p-5">
            <label className="block text-sm font-medium text-gray-300 mb-2">
              显示名称
            </label>
            <input
              type="text"
              value={formData.displayName}
              onChange={(e) => setFormData({ ...formData, displayName: e.target.value })}
              disabled={!editing}
              className={`w-full px-4 py-2.5 bg-gray-700/50 border border-gray-600 rounded-xl text-white text-sm focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent transition-all ${
                !editing ? 'cursor-not-allowed opacity-50' : ''
              }`}
              placeholder="输入您的显示名称"
            />
          </div>

          <div className="p-5">
            <label className="block text-sm font-medium text-gray-300 mb-2">
              个人简介
            </label>
            <textarea
              value={formData.bio}
              onChange={(e) => setFormData({ ...formData, bio: e.target.value })}
              disabled={!editing}
              rows={3}
              className={`w-full px-4 py-2.5 bg-gray-700/50 border border-gray-600 rounded-xl text-white text-sm focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent resize-none transition-all ${
                !editing ? 'cursor-not-allowed opacity-50' : ''
              }`}
              placeholder="介绍一下自己..."
            />
          </div>

          <div className="p-5">
            <label className="block text-sm font-medium text-gray-300 mb-2">
              性别
            </label>
            <select
              value={formData.gender}
              onChange={(e) => setFormData({ ...formData, gender: e.target.value })}
              disabled={!editing}
              className={`w-full px-4 py-2.5 bg-gray-700/50 border border-gray-600 rounded-xl text-white text-sm focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent transition-all ${
                !editing ? 'cursor-not-allowed opacity-50' : ''
              }`}
            >
              <option value="">未指定</option>
              <option value="male">男</option>
              <option value="female">女</option>
              <option value="other">其他</option>
            </select>
          </div>

          <div className="p-5">
            <label className="block text-sm font-medium text-gray-300 mb-2">
              生日
            </label>
            <input
              type="date"
              value={formData.birthday}
              onChange={(e) => setFormData({ ...formData, birthday: e.target.value })}
              disabled={!editing}
              className={`w-full px-4 py-2.5 bg-gray-700/50 border border-gray-600 rounded-xl text-white text-sm focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent transition-all ${
                !editing ? 'cursor-not-allowed opacity-50' : ''
              }`}
            />
          </div>

          <div className="p-5">
            <label className="block text-sm font-medium text-gray-300 mb-2">
              所在地区
            </label>
            <input
              type="text"
              value={formData.location}
              onChange={(e) => setFormData({ ...formData, location: e.target.value })}
              disabled={!editing}
              className={`w-full px-4 py-2.5 bg-gray-700/50 border border-gray-600 rounded-xl text-white text-sm focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent transition-all ${
                !editing ? 'cursor-not-allowed opacity-50' : ''
              }`}
              placeholder="例如：北京，中国"
            />
          </div>

          <div className="p-5">
            <label className="block text-sm font-medium text-gray-300 mb-2">
              公司
            </label>
            <input
              type="text"
              value={formData.company}
              onChange={(e) => setFormData({ ...formData, company: e.target.value })}
              disabled={!editing}
              className={`w-full px-4 py-2.5 bg-gray-700/50 border border-gray-600 rounded-xl text-white text-sm focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent transition-all ${
                !editing ? 'cursor-not-allowed opacity-50' : ''
              }`}
              placeholder="输入公司名称"
            />
          </div>

          <div className="p-5">
            <label className="block text-sm font-medium text-gray-300 mb-2">
              个人网站
            </label>
            <input
              type="url"
              value={formData.website}
              onChange={(e) => setFormData({ ...formData, website: e.target.value })}
              disabled={!editing}
              className={`w-full px-4 py-2.5 bg-gray-700/50 border border-gray-600 rounded-xl text-white text-sm focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent transition-all ${
                !editing ? 'cursor-not-allowed opacity-50' : ''
              }`}
              placeholder="https://example.com"
            />
          </div>
        </div>
      </div>
    </div>
  )
}

export default ProfileSettings
