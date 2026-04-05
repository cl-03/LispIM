/**
 * 群组在线状态订阅 Hook
 * 实时更新群组成员在线状态
 */

import { useState, useEffect } from 'react'
import { useAppStore } from '@/store/appStore'
import { getApiClient } from '@/utils/api-client'

export interface GroupPresenceState {
  onlineMembers: Set<string>
  loading: boolean
  lastUpdateTime: number
}

export interface GroupMemberPresence {
  userId: string
  nickname?: string
  role: 'owner' | 'admin' | 'member'
  isOnline: boolean
  lastSeen?: number
}

/**
 * 订阅群组在线状态
 * @param groupId 群组 ID
 * @param memberIds 群组成员 ID 列表
 */
export function useGroupPresence(groupId: number | null, memberIds: string[] = []) {
  const [state, setState] = useState<GroupPresenceState>({
    onlineMembers: new Set(),
    loading: true,
    lastUpdateTime: 0
  })

  const [members, setMembers] = useState<GroupMemberPresence[]>([])
  const { ws } = useAppStore()

  // 加载群成员详情
  useEffect(() => {
    if (!groupId || memberIds.length === 0) return

    let mounted = true

    const loadMembers = async () => {
      try {
        const api = getApiClient()
        const result = await api.getGroupMembers(groupId)

        if (result.success && result.data && mounted) {
          const memberDetails: GroupMemberPresence[] = result.data.map(member => ({
            userId: member.userId,
            nickname: member.nickname,
            role: member.role,
            isOnline: false, // 初始设为离线，等待 presence 更新
            lastSeen: undefined
          }))
          setMembers(memberDetails)
          setState(prev => ({ ...prev, loading: false }))
        }
      } catch (err) {
        console.error('Failed to load group members:', err)
        setState(prev => ({ ...prev, loading: false }))
      }
    }

    loadMembers()

    return () => {
      mounted = false
    }
  }, [groupId, memberIds.length])

  // 订阅群组 presence 事件
  useEffect(() => {
    if (!groupId || !ws) return

    // 订阅群组
    ws.on('group:presence', handlePresenceUpdate)
    ws.on('group:member:update', handleMemberUpdate)

    // 发送订阅请求
    ws.sendTyping(groupId, true) // 复用 typing 通道作为订阅信号

    return () => {
      // 取消订阅
      ws?.off('group:presence', handlePresenceUpdate)
      ws?.off('group:member:update', handleMemberUpdate)
      ws?.sendTyping(groupId, false)
    }
  }, [groupId, ws])

  const handlePresenceUpdate = (data: any) => {
    if (data.groupId !== groupId) return

    const { onlineMembers } = data as { groupId: number; onlineMembers: string[] }

    setState(prev => ({
      ...prev,
      onlineMembers: new Set(onlineMembers),
      lastUpdateTime: Date.now()
    }))

    // 更新成员在线状态
    setMembers(prev => prev.map(member => ({
      ...member,
      isOnline: onlineMembers.includes(member.userId)
    })))
  }

  const handleMemberUpdate = (data: any) => {
    if (data.groupId !== groupId) return

    const { members: updatedMembers } = data as { groupId: number; members: GroupMemberPresence[] }

    setMembers(prev => {
      const newMembers = [...prev]
      for (const updated of updatedMembers) {
        const index = newMembers.findIndex(m => m.userId === updated.userId)
        if (index !== -1) {
          newMembers[index] = { ...newMembers[index], ...updated }
        }
      }
      return newMembers
    })

    setState(prev => ({
      ...prev,
      lastUpdateTime: Date.now()
    }))
  }

  return {
    ...state,
    members,
    onlineCount: state.onlineMembers.size,
    totalMembers: members.length
  }
}

/**
 * 批量订阅多个群组的在线状态
 * @param groupIds 群组 ID 列表
 */
export function useBatchGroupPresence(groupIds: number[]) {
  const [presenceMap, setPresenceMap] = useState<Map<number, Set<string>>>(new Map())
  const { ws } = useAppStore()

  useEffect(() => {
    if (!ws || groupIds.length === 0) return

    const handleGroupPresence = (data: any) => {
      const { groupId, onlineMembers } = data as { groupId: number; onlineMembers: string[] }
      setPresenceMap(prev => {
        const newMap = new Map(prev)
        newMap.set(groupId, new Set(onlineMembers))
        return newMap
      })
    }

    ws.on('group:presence', handleGroupPresence)

    // 订阅所有群组
    groupIds.forEach(groupId => {
      ws?.sendTyping(groupId, true)
    })

    return () => {
      ws?.off('group:presence', handleGroupPresence)
      groupIds.forEach(groupId => {
        ws?.sendTyping(groupId, false)
      })
    }
  }, [groupIds, ws])

  return presenceMap
}

export default useGroupPresence
