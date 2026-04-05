import React, { useState } from 'react'
import { getApiClient, ContactGroup } from '@/utils/api-client'

interface ContactGroupModalProps {
  onClose: () => void
  groups: ContactGroup[]
  onUpdate: () => void
}

const ContactGroupModal: React.FC<ContactGroupModalProps> = ({ onClose, groups, onUpdate }) => {
  const [newGroupName, setNewGroupName] = useState('')
  const [loading, setLoading] = useState(false)

  const handleCreateGroup = async () => {
    if (!newGroupName.trim()) return

    setLoading(true)
    try {
      const api = getApiClient()
      const response = await api.createContactGroup({ name: newGroupName.trim(), order: groups.length })
      if (response.success) {
        setNewGroupName('')
        onUpdate()
      }
    } catch (error) {
      console.error('Failed to create group:', error)
    } finally {
      setLoading(false)
    }
  }

  const handleDeleteGroup = async (groupId: number) => {
    try {
      const api = getApiClient()
      const response = await api.deleteContactGroup(groupId)
      if (response.success) {
        onUpdate()
      }
    } catch (error) {
      console.error('Failed to delete group:', error)
    }
  }

  return (
    <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center" style={{ zIndex: 10000 }}>
      <div className="bg-white rounded-lg w-full max-w-md p-6 relative" style={{ zIndex: 10001 }}>
        <div className="flex items-center justify-between mb-4">
          <h2 className="text-lg font-semibold text-gray-900">联系人分组</h2>
          <button onClick={onClose} className="text-gray-500 hover:text-gray-700">
            <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>

        {/* Create New Group */}
        <div className="mb-4">
          <label className="block text-sm font-medium text-gray-700 mb-2">新建分组</label>
          <div className="flex gap-2">
            <input
              type="text"
              value={newGroupName}
              onChange={(e) => setNewGroupName(e.target.value)}
              placeholder="输入分组名称"
              className="flex-1 px-3 py-2 border border-gray-300 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
              onKeyDown={(e) => e.key === 'Enter' && handleCreateGroup()}
            />
            <button
              onClick={handleCreateGroup}
              disabled={loading || !newGroupName.trim()}
              className="px-4 py-2 bg-blue-500 text-white rounded-lg hover:bg-blue-600 disabled:opacity-50 disabled:cursor-not-allowed text-sm"
            >
              创建
            </button>
          </div>
        </div>

        {/* Groups List */}
        <div className="space-y-2 max-h-64 overflow-y-auto">
          {groups.length === 0 ? (
            <div className="text-center py-4 text-gray-500 text-sm">暂无分组</div>
          ) : (
            groups.map((group, index) => (
              <div
                key={group.id}
                className="flex items-center justify-between p-3 bg-gray-50 rounded-lg"
              >
                <div className="flex items-center gap-3">
                  <span className="text-xs text-gray-400 w-4">{index + 1}</span>
                  <span className="text-sm font-medium text-gray-900">{group.name}</span>
                </div>
                <button
                  onClick={() => handleDeleteGroup(group.id)}
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

        <div className="mt-4 text-xs text-gray-500">
          <p>提示：拖拽可调整分组顺序（即将支持）</p>
        </div>
      </div>
    </div>
  )
}

export default ContactGroupModal
