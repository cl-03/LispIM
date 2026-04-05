import React, { useState, useEffect } from 'react'
import { getApiClient } from '@/utils/api-client'
import type { Group, GroupMember, User } from '@/utils/api-client'

interface GroupModalProps {
  isOpen: boolean
  onClose: () => void
  groupId?: number
  onCreateSuccess?: (group: Group) => void
}

const GroupModal: React.FC<GroupModalProps> = ({ isOpen, onClose, groupId, onCreateSuccess }) => {
  const api = getApiClient()
  const [loading, setLoading] = useState(false)
  const [group, setGroup] = useState<Group | null>(null)
  const [members, setMembers] = useState<GroupMember[]>([])
  const [showAddMember, setShowAddMember] = useState(false)

  // Create group form
  const [newGroupName, setNewGroupName] = useState('')
  const [newGroupAvatar, setNewGroupAvatar] = useState('')

  // Edit form
  const [editName, setEditName] = useState('')
  const [editAnnouncement, setEditAnnouncement] = useState('')
  const [isEditing, setIsEditing] = useState(false)

  const isOwner = group && localStorage.getItem('userId') === group.ownerId

  useEffect(() => {
    if (isOpen && groupId) {
      loadGroup(groupId)
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isOpen, groupId])

  const loadGroup = async (gid: number) => {
    try {
      setLoading(true)
      const result = await api.getGroup(gid)
      if (result.success && result.data) {
        setGroup(result.data as Group)
        setMembers(result.data.members || [])
        setEditName(result.data.name)
        setEditAnnouncement(result.data.announcement || '')
      }
    } catch (err) {
      console.error('Failed to load group:', err)
    } finally {
      setLoading(false)
    }
  }

  const handleCreateGroup = async () => {
    if (!newGroupName.trim()) return

    try {
      setLoading(true)
      const result = await api.createGroup({
        name: newGroupName.trim(),
        avatar: newGroupAvatar.trim() || undefined
      })

      if (result.success && result.data) {
        onCreateSuccess?.(result.data as Group)
        resetForm()
        onClose()
      }
    } catch (err) {
      console.error('Create group failed:', err)
    } finally {
      setLoading(false)
    }
  }

  const handleUpdateGroup = async () => {
    if (!groupId || !group) return

    try {
      setLoading(true)
      await api.updateGroup(groupId, {
        name: editName.trim() || undefined,
        announcement: editAnnouncement
      })

      setGroup({ ...group, name: editName, announcement: editAnnouncement })
      setIsEditing(false)
    } catch (err) {
      console.error('Update group failed:', err)
    } finally {
      setLoading(false)
    }
  }

  const handleAddMember = async (userId: string) => {
    if (!groupId) return

    try {
      await api.addGroupMember(groupId, userId)
      loadGroup(groupId)
      setShowAddMember(false)
    } catch (err) {
      console.error('Add member failed:', err)
    }
  }

  const handleRemoveMember = async (userId: string) => {
    if (!groupId) return

    if (!confirm('确定要移除该成员吗？')) return

    try {
      await api.removeGroupMember(groupId, userId)
      loadGroup(groupId)
    } catch (err) {
      console.error('Remove member failed:', err)
    }
  }

  const handleUpdateMemberRole = async (userId: string, role: 'admin' | 'member') => {
    if (!groupId) return

    try {
      await api.updateMemberRole(groupId, userId, role)
      loadGroup(groupId)
    } catch (err) {
      console.error('Update role failed:', err)
    }
  }

  const resetForm = () => {
    setNewGroupName('')
    setNewGroupAvatar('')
    setGroup(null)
    setMembers([])
  }

  const handleClose = () => {
    resetForm()
    onClose()
  }

  if (!isOpen) return null

  return (
    <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4">
      <div className="bg-gray-800 rounded-2xl w-full max-w-2xl max-h-[80vh] overflow-hidden flex flex-col">
        {/* Header */}
        <div className="flex items-center justify-between p-4 border-b border-gray-700">
          <h2 className="text-xl font-semibold text-white">
            {groupId ? '群组详情' : '创建群组'}
          </h2>
          <button
            onClick={handleClose}
            className="p-2 hover:bg-gray-700 rounded-lg transition-colors"
          >
            <svg className="w-5 h-5 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>

        {/* Content */}
        <div className="flex-1 overflow-y-auto p-4">
          {groupId ? (
            // Group Detail View
            loading ? (
              <div className="flex items-center justify-center py-12">
                <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-blue-500"></div>
              </div>
            ) : group ? (
              <div className="space-y-6">
                {/* Group Info */}
                <div className="flex items-center space-x-4">
                  <div className="w-16 h-16 rounded-full bg-gradient-to-br from-purple-500 to-pink-500 flex items-center justify-center text-white text-2xl font-bold">
                    {group.avatar ? (
                      <img src={group.avatar} alt={group.name} className="w-full h-full rounded-full object-cover" />
                    ) : (
                      group.name.charAt(0).toUpperCase()
                    )}
                  </div>
                  <div className="flex-1">
                    {isEditing ? (
                      <div className="space-y-2">
                        <input
                          type="text"
                          value={editName}
                          onChange={(e) => setEditName(e.target.value)}
                          className="w-full px-3 py-2 bg-gray-700 border border-gray-600 rounded-lg text-white"
                          placeholder="群名称"
                        />
                        <textarea
                          value={editAnnouncement}
                          onChange={(e) => setEditAnnouncement(e.target.value)}
                          className="w-full px-3 py-2 bg-gray-700 border border-gray-600 rounded-lg text-white text-sm"
                          placeholder="群公告"
                          rows={2}
                        />
                        <div className="flex space-x-2">
                          <button
                            onClick={handleUpdateGroup}
                            disabled={loading}
                            className="px-4 py-2 bg-blue-500 hover:bg-blue-600 rounded-lg text-sm text-white"
                          >
                            保存
                          </button>
                          <button
                            onClick={() => setIsEditing(false)}
                            className="px-4 py-2 bg-gray-600 hover:bg-gray-700 rounded-lg text-sm text-white"
                          >
                            取消
                          </button>
                        </div>
                      </div>
                    ) : (
                      <>
                        <h3 className="text-lg font-semibold text-white">{group.name}</h3>
                        <p className="text-sm text-gray-400">
                          {group.memberCount} / {group.maxMembers} 成员
                        </p>
                        {group.announcement && (
                          <p className="text-sm text-gray-500 mt-1">{group.announcement}</p>
                        )}
                      </>
                    )}
                  </div>
                  {isOwner && !isEditing && (
                    <button
                      onClick={() => setIsEditing(true)}
                      className="p-2 hover:bg-gray-700 rounded-lg transition-colors"
                    >
                      <svg className="w-5 h-5 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z" />
                      </svg>
                    </button>
                  )}
                </div>

                {/* Members List */}
                <div>
                  <div className="flex items-center justify-between mb-3">
                    <h4 className="text-sm font-medium text-gray-300">群成员 ({members.length})</h4>
                    {isOwner && (
                      <button
                        onClick={() => setShowAddMember(!showAddMember)}
                        className="text-sm text-blue-400 hover:text-blue-300"
                      >
                        添加成员
                      </button>
                    )}
                  </div>

                  {showAddMember && (
                    <AddMemberPanel
                      groupId={groupId}
                      existingMembers={members.map(m => m.userId)}
                      onAdd={handleAddMember}
                      onClose={() => setShowAddMember(false)}
                    />
                  )}

                  <div className="space-y-2 max-h-64 overflow-y-auto">
                    {members.map((member) => (
                      <div
                        key={member.userId}
                        className="flex items-center justify-between p-3 bg-gray-700/50 rounded-lg"
                      >
                        <div className="flex items-center space-x-3">
                          <div className="w-8 h-8 rounded-full bg-gradient-to-br from-blue-400 to-blue-600 flex items-center justify-center text-white text-sm font-medium">
                            {member.nickname?.charAt(0).toUpperCase() || member.userId.charAt(0).toUpperCase()}
                          </div>
                          <div>
                            <p className="text-sm text-white">
                              {member.nickname || member.userId}
                              {member.role === 'owner' && <span className="ml-2 text-xs text-yellow-400">群主</span>}
                              {member.role === 'admin' && <span className="ml-2 text-xs text-blue-400">管理员</span>}
                            </p>
                            {member.isQuiet && <p className="text-xs text-gray-500">消息免打扰</p>}
                          </div>
                        </div>
                        {isOwner && member.role !== 'owner' && (
                          <div className="flex items-center space-x-2">
                            <select
                              value={member.role}
                              onChange={(e) => handleUpdateMemberRole(member.userId, e.target.value as 'admin' | 'member')}
                              className="bg-gray-600 border border-gray-500 rounded text-xs text-white px-2 py-1"
                            >
                              <option value="member">成员</option>
                              <option value="admin">管理员</option>
                            </select>
                            <button
                              onClick={() => handleRemoveMember(member.userId)}
                              className="p-1 hover:bg-red-500/20 rounded transition-colors"
                            >
                              <svg className="w-4 h-4 text-red-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
                              </svg>
                            </button>
                          </div>
                        )}
                      </div>
                    ))}
                  </div>
                </div>

                {/* Group Actions */}
                {isOwner && (
                  <div className="pt-4 border-t border-gray-700">
                    <button
                      onClick={async () => {
                        if (confirm('确定要解散该群组吗？此操作不可恢复。')) {
                          await api.deleteGroup(groupId)
                          handleClose()
                        }
                      }}
                      className="w-full py-3 bg-red-500/10 hover:bg-red-500/20 text-red-400 rounded-lg transition-colors"
                    >
                      解散群组
                    </button>
                  </div>
                )}
              </div>
            ) : null
          ) : (
            // Create Group View
            <div className="space-y-4">
              <div>
                <label className="block text-sm font-medium text-gray-300 mb-2">
                  群名称
                </label>
                <input
                  type="text"
                  value={newGroupName}
                  onChange={(e) => setNewGroupName(e.target.value)}
                  className="w-full px-4 py-3 bg-gray-700 border border-gray-600 rounded-xl text-white placeholder-gray-500 focus:outline-none focus:ring-2 focus:ring-blue-500"
                  placeholder="请输入群名称"
                  maxLength={50}
                />
              </div>

              <div>
                <label className="block text-sm font-medium text-gray-300 mb-2">
                  群头像（可选）
                </label>
                <input
                  type="text"
                  value={newGroupAvatar}
                  onChange={(e) => setNewGroupAvatar(e.target.value)}
                  className="w-full px-4 py-3 bg-gray-700 border border-gray-600 rounded-xl text-white placeholder-gray-500 focus:outline-none focus:ring-2 focus:ring-blue-500"
                  placeholder="输入头像 URL"
                />
              </div>

              <div className="pt-4">
                <button
                  onClick={handleCreateGroup}
                  disabled={loading || !newGroupName.trim()}
                  className="w-full py-3 bg-blue-500 hover:bg-blue-600 disabled:bg-gray-600 disabled:cursor-not-allowed text-white rounded-xl font-medium transition-colors"
                >
                  {loading ? '创建中...' : '创建群组'}
                </button>
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  )
}

// Add Member Panel Component
interface AddMemberPanelProps {
  groupId: number
  existingMembers: string[]
  onAdd: (userId: string) => void
  onClose: () => void
}

const AddMemberPanel: React.FC<AddMemberPanelProps> = ({ existingMembers, onAdd, onClose }) => {
  const [friends, setFriends] = useState<User[]>([])
  const [searchQuery, setSearchQuery] = useState('')
  const api = getApiClient()

  useEffect(() => {
    api.getFriends().then(result => {
      if (result.success && result.data) {
        setFriends(result.data.filter(f => !existingMembers.includes(f.id)).map(f => ({
          ...f,
          status: (f as any).status || 'offline'
        })))
      }
    })
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  const filteredFriends = friends.filter(f =>
    f.username.toLowerCase().includes(searchQuery.toLowerCase()) ||
    f.displayName?.toLowerCase().includes(searchQuery.toLowerCase())
  )

  return (
    <div className="mb-4 p-4 bg-gray-700/50 rounded-lg">
      <div className="flex items-center justify-between mb-3">
        <h5 className="text-sm font-medium text-white">选择好友</h5>
        <button onClick={onClose} className="text-gray-400 hover:text-white">
          <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
          </svg>
        </button>
      </div>

      <input
        type="text"
        value={searchQuery}
        onChange={(e) => setSearchQuery(e.target.value)}
        className="w-full px-3 py-2 bg-gray-600 border border-gray-500 rounded-lg text-white text-sm mb-3"
        placeholder="搜索好友..."
      />

      <div className="max-h-40 overflow-y-auto space-y-1">
        {filteredFriends.map((friend) => (
          <button
            key={friend.id}
            onClick={() => onAdd(friend.id)}
            className="w-full flex items-center space-x-3 p-2 hover:bg-gray-600 rounded-lg transition-colors text-left"
          >
            <div className="w-6 h-6 rounded-full bg-gradient-to-br from-green-400 to-green-600 flex items-center justify-center text-white text-xs font-medium">
              {friend.displayName?.charAt(0).toUpperCase() || friend.username.charAt(0).toUpperCase()}
            </div>
            <span className="text-sm text-white">{friend.displayName || friend.username}</span>
          </button>
        ))}
      </div>
    </div>
  )
}

export default GroupModal
