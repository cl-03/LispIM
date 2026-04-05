import React, { useState } from 'react'
import { getApiClient, ContactTag } from '@/utils/api-client'

interface ContactTagModalProps {
  onClose: () => void
  tags: ContactTag[]
  onUpdate: () => void
}

const ContactTagModal: React.FC<ContactTagModalProps> = ({ onClose, tags, onUpdate }) => {
  const [newTagName, setNewTagName] = useState('')
  const [newTagColor, setNewTagColor] = useState('#007bff')
  const [loading, setLoading] = useState(false)

  const presetColors = [
    '#007bff', '#6610f2', '#6f42c1', '#e83e8c', '#dc3545',
    '#fd7e14', '#ffc107', '#28a745', '#17a2b8', '#20c997'
  ]

  const handleCreateTag = async () => {
    if (!newTagName.trim()) return

    setLoading(true)
    try {
      const api = getApiClient()
      const response = await api.createContactTag({ name: newTagName.trim(), color: newTagColor })
      if (response.success) {
        setNewTagName('')
        setNewTagColor('#007bff')
        onUpdate()
      }
    } catch (error) {
      console.error('Failed to create tag:', error)
    } finally {
      setLoading(false)
    }
  }

  const handleDeleteTag = async (tagId: number) => {
    try {
      const api = getApiClient()
      const response = await api.deleteContactTag(tagId)
      if (response.success) {
        onUpdate()
      }
    } catch (error) {
      console.error('Failed to delete tag:', error)
    }
  }

  return (
    <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center" style={{ zIndex: 10000 }}>
      <div className="bg-white rounded-lg w-full max-w-md p-6 relative" style={{ zIndex: 10001 }}>
        <div className="flex items-center justify-between mb-4">
          <h2 className="text-lg font-semibold text-gray-900">联系人标签</h2>
          <button onClick={onClose} className="text-gray-500 hover:text-gray-700">
            <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>

        {/* Create New Tag */}
        <div className="mb-4">
          <label className="block text-sm font-medium text-gray-700 mb-2">新建标签</label>
          <div className="flex gap-2 mb-2">
            <input
              type="text"
              value={newTagName}
              onChange={(e) => setNewTagName(e.target.value)}
              placeholder="输入标签名称"
              className="flex-1 px-3 py-2 border border-gray-300 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
              onKeyDown={(e) => e.key === 'Enter' && handleCreateTag()}
            />
            <button
              onClick={handleCreateTag}
              disabled={loading || !newTagName.trim()}
              className="px-4 py-2 bg-blue-500 text-white rounded-lg hover:bg-blue-600 disabled:opacity-50 disabled:cursor-not-allowed text-sm"
            >
              创建
            </button>
          </div>
          {/* Color Picker */}
          <div className="flex items-center gap-2">
            <span className="text-sm text-gray-600">颜色：</span>
            <div className="flex gap-1 flex-wrap">
              {presetColors.map(color => (
                <button
                  key={color}
                  onClick={() => setNewTagColor(color)}
                  className={`w-6 h-6 rounded-full border-2 transition-transform ${
                    newTagColor === color ? 'border-gray-900 scale-110' : 'border-transparent hover:scale-110'
                  }`}
                  style={{ backgroundColor: color }}
                />
              ))}
            </div>
            <input
              type="color"
              value={newTagColor}
              onChange={(e) => setNewTagColor(e.target.value)}
              className="w-8 h-8 border border-gray-300 rounded cursor-pointer"
            />
          </div>
        </div>

        {/* Tags List */}
        <div className="space-y-2 max-h-64 overflow-y-auto">
          {tags.length === 0 ? (
            <div className="text-center py-4 text-gray-500 text-sm">暂无标签</div>
          ) : (
            tags.map(tag => (
              <div
                key={tag.id}
                className="flex items-center justify-between p-3 bg-gray-50 rounded-lg"
              >
                <div className="flex items-center gap-3">
                  <div
                    className="w-3 h-3 rounded-full"
                    style={{ backgroundColor: tag.color }}
                  />
                  <span className="text-sm font-medium text-gray-900">{tag.name}</span>
                  <span className="text-xs text-gray-400">{tag.color}</span>
                </div>
                <button
                  onClick={() => handleDeleteTag(tag.id)}
                  className="p-1 text-gray-400 hover:text-red-500 hover:bg-red-50 rounded"
                >
                  <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
                  </svg>
                </button>
              </div>
            ))
          )}
        </div>
      </div>
    </div>
  )
}

export default ContactTagModal
