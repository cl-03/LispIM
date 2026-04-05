import React, { useState, useEffect, useMemo } from 'react'
import { useNavigate } from 'react-router-dom'
import {
  getApiClient,
  Friend,
  FriendRequest,
  ContactGroup,
  ContactTag
} from '@/utils/api-client'
import AddFriendModal from './AddFriendModal'
import ContactGroupModal from './ContactGroupModal'
import ContactTagModal from './ContactTagModal'
import ContactRemarkModal from './ContactRemarkModal'
import ContactBlacklistModal from './ContactBlacklistModal'
import ContactStarModal from './ContactStarModal'

const Contacts: React.FC = () => {
  const navigate = useNavigate()
  const [friends, setFriends] = useState<Friend[]>([])
  const [friendRequests, setFriendRequests] = useState<FriendRequest[]>([])
  const [loading, setLoading] = useState(true)
  const [showAddFriendModal, setShowAddFriendModal] = useState(false)
  const [showFriendRequests, setShowFriendRequests] = useState(false)
  const [searchQuery, setSearchQuery] = useState('')
  const [requestCount, setRequestCount] = useState(0)

  // Contact management state
  const [groups, setGroups] = useState<ContactGroup[]>([])
  const [tags, setTags] = useState<ContactTag[]>([])
  const [starContacts, setStarContacts] = useState<string[]>([])
  const [blacklist, setBlacklist] = useState<string[]>([])

  // UI state
  const [selectedGroup, setSelectedGroup] = useState<number | 'all' | 'star' | 'blacklist'>('all')
  const [showGroupModal, setShowGroupModal] = useState(false)
  const [showTagModal, setShowTagModal] = useState(false)
  const [showRemarkModal, setShowRemarkModal] = useState(false)
  const [showBlacklistModal, setShowBlacklistModal] = useState(false)
  const [showStarModal, setShowStarModal] = useState(false)
  const [selectedFriend, setSelectedFriend] = useState<Friend | null>(null)
  const [contextMenu, setContextMenu] = useState<{ x: number; y: number; friend: Friend } | null>(null)

  useEffect(() => {
    loadContacts()
    loadFriendRequests()
    loadGroups()
    loadTags()
    loadStarContacts()
    loadBlacklist()
  }, [])

  const loadContacts = async () => {
    try {
      const api = getApiClient()
      const response = await api.getFriends()
      if (response.success && response.data) {
        setFriends(response.data)
      }
    } catch (error) {
      console.error('Failed to load friends:', error)
    } finally {
      setLoading(false)
    }
  }

  const loadFriendRequests = async () => {
    try {
      const api = getApiClient()
      const response = await api.getFriendRequests()
      if (response.success && response.data) {
        const formattedRequests = response.data.map((req: any) => ({
          ...req,
          receiverId: req.receiverId || req.receiver_id || '',
          status: req.status || 'pending',
          senderUsername: req.senderUsername || req.sender?.username || ''
        }))
        setFriendRequests(formattedRequests)
        setRequestCount(formattedRequests.length)
      }
    } catch (error) {
      console.error('Failed to load friend requests:', error)
    }
  }

  const loadGroups = async () => {
    try {
      const api = getApiClient()
      const response = await api.getContactGroups()
      if (response.success && response.data) {
        setGroups(response.data.sort((a, b) => a.order - b.order))
      }
    } catch (error) {
      console.error('Failed to load groups:', error)
    }
  }

  const loadTags = async () => {
    try {
      const api = getApiClient()
      const response = await api.getContactTags()
      if (response.success && response.data) {
        setTags(response.data)
      }
    } catch (error) {
      console.error('Failed to load tags:', error)
    }
  }

  const loadStarContacts = async () => {
    try {
      const api = getApiClient()
      const response = await api.getStarContacts()
      if (response.success && response.data) {
        setStarContacts(response.data.map(c => (c as any).starred_id || (c as any).userId))
      }
    } catch (error) {
      console.error('Failed to load star contacts:', error)
    }
  }

  const loadBlacklist = async () => {
    try {
      const api = getApiClient()
      const response = await api.getBlacklist()
      if (response.success && response.data) {
        setBlacklist(response.data.map(b => (b as any).blocked_id || (b as any).userId))
      }
    } catch (error) {
      console.error('Failed to load blacklist:', error)
    }
  }

  const handleAcceptRequest = async (requestId: number) => {
    try {
      const api = getApiClient()
      const response = await api.acceptFriendRequest(requestId)
      if (response.success) {
        await loadContacts()
        await loadFriendRequests()
      }
    } catch (error) {
      console.error('Accept request error:', error)
    }
  }

  const handleRejectRequest = async (requestId: number) => {
    try {
      const api = getApiClient()
      const response = await api.rejectFriendRequest(requestId)
      if (response.success) {
        await loadFriendRequests()
      }
    } catch (error) {
      console.error('Reject request error:', error)
    }
  }

  const handleToggleStar = async (friendId: string, e?: React.MouseEvent) => {
    e?.stopPropagation()
    try {
      const api = getApiClient()
      const isStarred = starContacts.includes(friendId)
      if (isStarred) {
        await api.removeStarContact(friendId)
        setStarContacts(starContacts.filter(id => id !== friendId))
      } else {
        await api.addStarContact(friendId)
        setStarContacts([...starContacts, friendId])
      }
    } catch (error) {
      console.error('Toggle star error:', error)
    }
  }

  const handleBlacklist = async (friendId: string, e?: React.MouseEvent) => {
    e?.stopPropagation()
    try {
      const api = getApiClient()
      if (blacklist.includes(friendId)) {
        await api.removeFromBlacklist(friendId)
        setBlacklist(blacklist.filter(id => id !== friendId))
      } else {
        await api.addToBlacklist(friendId)
        setBlacklist([...blacklist, friendId])
      }
    } catch (error) {
      console.error('Blacklist error:', error)
    }
  }

  const handleSetRemark = (friend: Friend, e?: React.MouseEvent) => {
    e?.stopPropagation()
    setSelectedFriend(friend)
    setShowRemarkModal(true)
    setContextMenu(null)
  }

  const handleAddToGroup = (friend: Friend, e?: React.MouseEvent) => {
    e?.stopPropagation()
    setSelectedFriend(friend)
    setContextMenu(null)
    // Open group selection modal
  }

  const handleAddTag = (friend: Friend, e?: React.MouseEvent) => {
    e?.stopPropagation()
    setSelectedFriend(friend)
    setContextMenu(null)
    // Open tag selection modal
  }

  const openChat = (conversationId: number) => {
    navigate(`/?conv=${conversationId}`)
  }

  const handleContextMenu = (e: React.MouseEvent, friend: Friend) => {
    e.preventDefault()
    e.stopPropagation()
    setContextMenu({ x: e.clientX, y: e.clientY, friend })
  }

  const closeContextMenu = () => {
    setContextMenu(null)
  }

  // 分组好友
  const groupedFriends = useMemo(() => {
    let filtered = friends

    // Filter by blacklist
    const showBlacklist = selectedGroup === 'blacklist'
    if (showBlacklist) {
      return friends.filter(f => blacklist.includes(f.id))
    }

    // Filter by star
    if (selectedGroup === 'star') {
      return friends.filter(f => starContacts.includes(f.id))
    }

    // Filter by specific group (if implemented)
    // For now, show all non-blacklisted friends

    // Filter by search query
    if (searchQuery.trim()) {
      const query = searchQuery.toLowerCase()
      filtered = filtered.filter(friend =>
        friend.displayName?.toLowerCase().includes(query) ||
        friend.username.toLowerCase().includes(query)
      )
    }

    // Exclude blacklisted from normal view
    if (!showBlacklist) {
      filtered = filtered.filter(f => !blacklist.includes(f.id))
    }

    return filtered
  }, [friends, selectedGroup, searchQuery, blacklist, starContacts])

  // 按首字母分组显示好友
  const friendsByLetter = useMemo(() => {
    const letters: Record<string, Friend[]> = {}
    groupedFriends.forEach(friend => {
      const name = friend.displayName || friend.username
      const letter = name.charAt(0).toUpperCase()
      const key = /[A-Z]/.test(letter) ? letter : '#'
      if (!letters[key]) {
        letters[key] = []
      }
      letters[key].push(friend)
    })
    return Object.entries(letters).sort((a, b) => {
      if (a[0] === '#') return 1
      if (b[0] === '#') return -1
      return a[0].localeCompare(b[0])
    })
  }, [groupedFriends])

  return (
    <div className="h-screen flex flex-col bg-gray-900">
      {/* Header */}
      <div className="bg-gray-800 border-b border-gray-700 px-4 py-3">
        <div className="flex items-center justify-between mb-3">
          <h1 className="text-xl font-semibold text-white">联系人</h1>
          <div className="flex gap-2">
            {/* Star Contacts */}
            <button
              onClick={() => setShowStarModal(true)}
              className={`px-3 py-2 rounded-lg transition-colors text-sm flex items-center gap-1 ${
                selectedGroup === 'star'
                  ? 'bg-yellow-600 text-white'
                  : 'bg-gray-700 text-gray-300 hover:bg-gray-600'
              }`}
            >
              <svg className="w-4 h-4" fill="currentColor" viewBox="0 0 20 20">
                <path d="M9.049 2.927c.3-.921 1.603-.921 1.902 0l1.07 3.292a1 1 0 00.95.69h3.462c.969 0 1.371 1.24.588 1.81l-2.8 2.034a1 1 0 00-.364 1.118l1.07 3.292c.3.921-.755 1.688-1.54 1.118l-2.8-2.034a1 1 0 00-1.175 0l-2.8 2.034c-.784.57-1.838-.197-1.539-1.118l1.07-3.292a1 1 0 00-.364-1.118L2.98 8.72c-.783-.57-.38-1.81.588-1.81h3.461a1 1 0 00.951-.69l1.07-3.292z" />
              </svg>
              星标
            </button>
            {/* Blacklist */}
            <button
              onClick={() => setShowBlacklistModal(true)}
              className={`px-3 py-2 rounded-lg transition-colors text-sm flex items-center gap-1 ${
                selectedGroup === 'blacklist'
                  ? 'bg-red-600 text-white'
                  : 'bg-gray-700 text-gray-300 hover:bg-gray-600'
              }`}
            >
              <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M18.364 18.364A9 9 0 005.636 5.636m12.728 12.728A9 9 0 015.636 5.636m12.728 12.728L5.636 5.636" />
              </svg>
              黑名单
            </button>
            {/* Friend Requests Button */}
            <button
              onClick={() => setShowFriendRequests(!showFriendRequests)}
              className="relative px-4 py-2 bg-gray-700 text-white rounded-lg hover:bg-gray-600 transition-colors text-sm flex items-center gap-1"
            >
              <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z" />
              </svg>
              好友请求
              {requestCount > 0 && (
                <span className="absolute -top-1 -right-1 w-5 h-5 bg-red-500 rounded-full text-xs flex items-center justify-center">
                  {requestCount}
                </span>
              )}
            </button>
            <button
              onClick={() => setShowAddFriendModal(true)}
              className="px-4 py-2 bg-blue-500 text-white rounded-lg hover:bg-blue-600 transition-colors text-sm"
            >
              添加好友
            </button>
          </div>
        </div>
        {/* 搜索框 */}
        <div className="relative">
          <input
            type="text"
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            placeholder="搜索联系人..."
            className="w-full px-4 py-2 pl-10 bg-gray-700 border border-gray-600 rounded-lg
                     text-white text-sm placeholder-gray-500 focus:outline-none focus:ring-2
                     focus:ring-blue-500"
          />
          <svg
            className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-gray-500"
            fill="none"
            stroke="currentColor"
            viewBox="0 0 24 24"
          >
            <path
              strokeLinecap="round"
              strokeLinejoin="round"
              strokeWidth={2}
              d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z"
            />
          </svg>
        </div>
      </div>

      {/* Sidebar + Content */}
      <div className="flex-1 flex overflow-hidden">
        {/* Sidebar - Groups */}
        <div className="w-48 bg-gray-800 border-r border-gray-700 overflow-y-auto">
          <div className="p-2">
            <div className="flex items-center justify-between mb-2">
              <span className="text-xs text-gray-500 font-medium">分组</span>
              <button
                onClick={() => setShowGroupModal(true)}
                className="p-1 hover:bg-gray-700 rounded"
              >
                <svg className="w-3.5 h-3.5 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 4v16m8-8H4" />
                </svg>
              </button>
            </div>
            <div
              onClick={() => setSelectedGroup('all')}
              className={`px-3 py-2 rounded-lg cursor-pointer text-sm mb-1 ${
                selectedGroup === 'all'
                  ? 'bg-blue-600 text-white'
                  : 'text-gray-300 hover:bg-gray-700'
              }`}
            >
              全部好友
            </div>
            {groups.map(group => (
              <div
                key={group.id}
                onClick={() => setSelectedGroup(group.id)}
                className={`px-3 py-2 rounded-lg cursor-pointer text-sm mb-1 flex items-center justify-between ${
                  selectedGroup === group.id
                    ? 'bg-blue-600 text-white'
                    : 'text-gray-300 hover:bg-gray-700'
                }`}
              >
                <span>{group.name}</span>
                <button
                  onClick={(e) => {
                    e.stopPropagation()
                    // Delete group
                  }}
                  className="opacity-0 group-hover:opacity-100 p-1 hover:bg-gray-600 rounded"
                >
                  <svg className="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
                  </svg>
                </button>
              </div>
            ))}

            {/* Tags Section */}
            <div className="mt-4">
              <div className="flex items-center justify-between mb-2">
                <span className="text-xs text-gray-500 font-medium">标签</span>
                <button
                  onClick={() => setShowTagModal(true)}
                  className="p-1 hover:bg-gray-700 rounded"
                >
                  <svg className="w-3.5 h-3.5 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 4v16m8-8H4" />
                  </svg>
                </button>
              </div>
              <div className="space-y-1">
                {tags.map(tag => (
                  <div
                    key={tag.id}
                    className="px-3 py-1.5 rounded-lg text-sm text-gray-300 hover:bg-gray-700 cursor-pointer flex items-center gap-2"
                  >
                    <div
                      className="w-2.5 h-2.5 rounded-full"
                      style={{ backgroundColor: tag.color }}
                    />
                    {tag.name}
                  </div>
                ))}
              </div>
            </div>
          </div>
        </div>

        {/* Main Content - Friends List */}
        <div className="flex-1 overflow-y-auto" onClick={closeContextMenu}>
          {loading ? (
            <div className="flex items-center justify-center h-full">
              <div className="text-gray-400">加载中...</div>
            </div>
          ) : (
            <div className="divide-y divide-gray-700">
              {/* Blacklist View */}
              {selectedGroup === 'blacklist' && (
                <div className="px-4 py-2 bg-red-900/20 border-b border-red-900/30">
                  <div className="text-sm text-red-400">黑名单中的用户无法给你发送消息或查看你的动态</div>
                </div>
              )}

              {/* Star View */}
              {selectedGroup === 'star' && (
                <div className="px-4 py-2 bg-yellow-900/20 border-b border-yellow-900/30">
                  <div className="text-sm text-yellow-400">星标联系人 ({starContacts.length})</div>
                </div>
              )}

              {/* System Admin */}
              {!searchQuery && selectedGroup !== 'blacklist' && (
                <div
                  onClick={() => openChat(2)}
                  className="flex items-center px-4 py-3 hover:bg-gray-800 cursor-pointer transition-colors"
                >
                  <div className="w-12 h-12 rounded-full bg-red-500 flex items-center justify-center text-white">
                    <svg className="w-7 h-7" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z" />
                    </svg>
                  </div>
                  <div className="ml-3 flex-1">
                    <div className="font-medium text-white">系统管理员</div>
                    <div className="text-sm text-gray-500">有任何问题都可以联系我</div>
                  </div>
                  <div className="w-2.5 h-2.5 bg-green-500 rounded-full border-2 border-gray-900"></div>
                </div>
              )}

              {/* Friends by Letter */}
              {friendsByLetter.length === 0 ? (
                <div className="py-8 text-center text-gray-400">
                  <p>
                    {selectedGroup === 'blacklist'
                      ? '黑名单为空'
                      : selectedGroup === 'star'
                      ? '暂无星标联系人'
                      : '暂无好友'}
                  </p>
                </div>
              ) : (
                friendsByLetter.map(([letter, letterFriends]) => (
                  <div key={letter}>
                    <div className="px-4 py-1.5 bg-gray-800/50 sticky top-0">
                      <div className="text-xs text-gray-500 font-medium">{letter}</div>
                    </div>
                    {letterFriends.map((friend) => (
                      <div
                        key={friend.id}
                        className="flex items-center px-4 py-3 hover:bg-gray-800 cursor-pointer transition-colors relative group"
                        onClick={() => openChat(1)}
                        onContextMenu={(e) => handleContextMenu(e, friend)}
                      >
                        <div className="w-12 h-12 rounded-full bg-blue-500 flex items-center justify-center text-white font-medium flex-shrink-0 relative">
                          {friend.avatarUrl ? (
                            <img
                              src={friend.avatarUrl}
                              alt={friend.displayName}
                              className="w-12 h-12 rounded-full object-cover"
                            />
                          ) : (
                            (friend.displayName || friend.username).charAt(0).toUpperCase()
                          )}
                          {/* Star indicator */}
                          {starContacts.includes(friend.id) && (
                            <div className="absolute -top-0.5 -right-0.5">
                              <svg className="w-4 h-4 text-yellow-400" fill="currentColor" viewBox="0 0 20 20">
                                <path d="M9.049 2.927c.3-.921 1.603-.921 1.902 0l1.07 3.292a1 1 0 00.95.69h3.462c.969 0 1.371 1.24.588 1.81l-2.8 2.034a1 1 0 00-.364 1.118l1.07 3.292c.3.921-.755 1.688-1.54 1.118l-2.8-2.034a1 1 0 00-1.175 0l-2.8 2.034c-.784.57-1.838-.197-1.539-1.118l1.07-3.292a1 1 0 00-.364-1.118L2.98 8.72c-.783-.57-.38-1.81.588-1.81h3.461a1 1 0 00.951-.69l1.07-3.292z" />
                              </svg>
                            </div>
                          )}
                        </div>
                        <div className="ml-3 flex-1 min-w-0">
                          <div className="font-medium text-white truncate">
                            {friend.displayName || friend.username}
                            {blacklist.includes(friend.id) && (
                              <span className="ml-2 text-xs text-red-400">(已拉黑)</span>
                            )}
                          </div>
                          <div className="text-sm text-gray-400 truncate">{friend.username}</div>
                        </div>
                        {/* Quick Actions */}
                        <div className="flex items-center gap-1 opacity-0 group-hover:opacity-100 transition-opacity">
                          <button
                            onClick={(e) => handleToggleStar(friend.id, e)}
                            className={`p-1.5 rounded hover:bg-gray-700 ${
                              starContacts.includes(friend.id)
                                ? 'text-yellow-400'
                                : 'text-gray-400'
                            }`}
                            title={starContacts.includes(friend.id) ? '取消星标' : '添加星标'}
                          >
                            <svg className="w-4 h-4" fill={starContacts.includes(friend.id) ? 'currentColor' : 'none'} stroke="currentColor" viewBox="0 0 24 24">
                              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M11.049 2.927c.3-.921 1.603-.921 1.902 0l1.519 4.674a1 1 0 00.95.69h4.915c.969 0 1.371 1.24.588 1.81l-3.976 2.888a1 1 0 00-.363 1.118l1.518 4.674c.3.922-.755 1.688-1.538 1.118l-3.976-2.888a1 1 0 00-1.176 0l-3.976 2.888c-.783.57-1.838-.197-1.538-1.118l1.518-4.674a1 1 0 00-.363-1.118l-3.976-2.888c-.784-.57-.38-1.81.588-1.81h4.914a1 1 0 00.951-.69l1.519-4.674z" />
                            </svg>
                          </button>
                          <button
                            onClick={(e) => handleSetRemark(friend, e)}
                            className="p-1.5 rounded hover:bg-gray-700 text-gray-400"
                            title="设置备注"
                          >
                            <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z" />
                            </svg>
                          </button>
                          <button
                            onClick={(e) => handleBlacklist(friend.id, e)}
                            className={`p-1.5 rounded hover:bg-gray-700 ${
                              blacklist.includes(friend.id)
                                ? 'text-red-400'
                                : 'text-gray-400'
                            }`}
                            title={blacklist.includes(friend.id) ? '移出黑名单' : '加入黑名单'}
                          >
                            <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M18.364 18.364A9 9 0 005.636 5.636m12.728 12.728A9 9 0 015.636 5.636m12.728 12.728L5.636 5.636" />
                            </svg>
                          </button>
                        </div>
                      </div>
                    ))}
                  </div>
                ))
              )}
            </div>
          )}
        </div>
      </div>

      {/* Context Menu */}
      {contextMenu && (
        <div
          className="fixed bg-gray-800 border border-gray-700 rounded-lg shadow-lg py-1 z-50 min-w-[160px]"
          style={{ left: contextMenu.x, top: contextMenu.y }}
        >
          <button
            onClick={() => handleSetRemark(contextMenu.friend)}
            className="w-full px-4 py-2 text-left text-sm text-gray-300 hover:bg-gray-700 flex items-center gap-2"
          >
            <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z" />
            </svg>
            设置备注
          </button>
          <button
            onClick={() => handleAddToGroup(contextMenu.friend)}
            className="w-full px-4 py-2 text-left text-sm text-gray-300 hover:bg-gray-700 flex items-center gap-2"
          >
            <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 11H5m14 0a2 2 0 012 2v6a2 2 0 01-2 2H5a2 2 0 01-2-2v-6a2 2 0 012-2m14 0V9a2 2 0 00-2-2M5 11V9a2 2 0 012-2m0 0V5a2 2 0 012-2h6a2 2 0 012 2v2M7 7h10" />
            </svg>
            添加到分组
          </button>
          <button
            onClick={() => handleAddTag(contextMenu.friend)}
            className="w-full px-4 py-2 text-left text-sm text-gray-300 hover:bg-gray-700 flex items-center gap-2"
          >
            <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M7 7h.01M7 3h5c.512 0 1.024.195 1.414.586l7 7a2 2 0 010 2.828l-7 7a2 2 0 01-2.828 0l-7-7A1.994 1.994 0 013 12V7a4 4 0 014-4z" />
            </svg>
            添加标签
          </button>
          <div className="border-t border-gray-700 my-1"></div>
          <button
            onClick={() => handleToggleStar(contextMenu.friend.id)}
            className="w-full px-4 py-2 text-left text-sm text-gray-300 hover:bg-gray-700 flex items-center gap-2"
          >
            <svg className="w-4 h-4" fill={starContacts.includes(contextMenu.friend.id) ? 'currentColor' : 'none'} stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M11.049 2.927c.3-.921 1.603-.921 1.902 0l1.519 4.674a1 1 0 00.95.69h4.915c.969 0 1.371 1.24.588 1.81l-3.976 2.888a1 1 0 00-.363 1.118l1.518 4.674c.3.922-.755 1.688-1.538 1.118l-3.976-2.888a1 1 0 00-1.176 0l-3.976 2.888c-.783.57-1.838-.197-1.538-1.118l1.518-4.674a1 1 0 00-.363-1.118l-3.976-2.888c-.784-.57-.38-1.81.588-1.81h4.914a1 1 0 00.951-.69l1.519-4.674z" />
            </svg>
            {starContacts.includes(contextMenu.friend.id) ? '取消星标' : '添加星标'}
          </button>
          <button
            onClick={() => handleBlacklist(contextMenu.friend.id)}
            className="w-full px-4 py-2 text-left text-sm text-red-400 hover:bg-gray-700 flex items-center gap-2"
          >
            <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M18.364 18.364A9 9 0 005.636 5.636m12.728 12.728A9 9 0 015.636 5.636m12.728 12.728L5.636 5.636" />
            </svg>
            {blacklist.includes(contextMenu.friend.id) ? '移出黑名单' : '加入黑名单'}
          </button>
        </div>
      )}

      {/* Friend Requests Modal */}
      {showFriendRequests && (
        <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center" style={{ zIndex: 9999 }}>
          <div className="bg-white rounded-lg w-full max-w-md p-6 relative max-h-[80vh] overflow-y-auto" style={{ zIndex: 10000 }}>
            <div className="flex items-center justify-between mb-4">
              <h2 className="text-lg font-semibold text-gray-900">好友请求</h2>
              <button onClick={() => setShowFriendRequests(false)} className="text-gray-500 hover:text-gray-700">
                <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
                </svg>
              </button>
            </div>
            {friendRequests.length === 0 ? (
              <div className="text-center py-8 text-gray-500">
                <p>暂无好友请求</p>
              </div>
            ) : (
              <div className="space-y-3">
                {friendRequests.map((request) => (
                  <div key={request.id} className="flex items-center gap-3 p-3 border rounded-lg bg-gray-50">
                    <div className="w-10 h-10 rounded-full bg-blue-500 flex items-center justify-center text-white font-medium">
                      {request.senderAvatar ? (
                        <img src={request.senderAvatar} alt={request.senderDisplayName || request.senderUsername} className="w-10 h-10 rounded-full object-cover" />
                      ) : (
                        (request.senderDisplayName || request.senderUsername).charAt(0).toUpperCase()
                      )}
                    </div>
                    <div className="flex-1 min-w-0">
                      <div className="font-medium text-gray-900">{request.senderDisplayName || request.senderUsername}</div>
                      <div className="text-xs text-gray-500">@{request.senderUsername}</div>
                      {request.message && <div className="text-xs text-gray-600 mt-1">{request.message}</div>}
                    </div>
                    <div className="flex gap-2">
                      <button
                        onClick={() => handleAcceptRequest(request.id)}
                        className="px-3 py-1 bg-green-500 text-white text-sm rounded hover:bg-green-600"
                      >
                        接受
                      </button>
                      <button
                        onClick={() => handleRejectRequest(request.id)}
                        className="px-3 py-1 bg-gray-300 text-gray-700 text-sm rounded hover:bg-gray-400"
                      >
                        拒绝
                      </button>
                    </div>
                  </div>
                ))}
              </div>
            )}
          </div>
        </div>
      )}

      {/* Modals */}
      {showAddFriendModal && <AddFriendModal onClose={() => setShowAddFriendModal(false)} />}
      {showGroupModal && <ContactGroupModal onClose={() => setShowGroupModal(false)} groups={groups} onUpdate={loadGroups} />}
      {showTagModal && <ContactTagModal onClose={() => setShowTagModal(false)} tags={tags} onUpdate={loadTags} />}
      {showRemarkModal && selectedFriend && (
        <ContactRemarkModal
          friend={selectedFriend}
          onClose={() => setShowRemarkModal(false)}
        />
      )}
      {showBlacklistModal && (
        <ContactBlacklistModal
          onClose={() => setShowBlacklistModal(false)}
          onSelect={(friendId) => {
            setBlacklist(blacklist.filter(id => id !== friendId))
          }}
        />
      )}
      {showStarModal && (
        <ContactStarModal
          onClose={() => setShowStarModal(false)}
          friends={friends.filter(f => starContacts.includes(f.id))}
        />
      )}
    </div>
  )
}

export default Contacts
