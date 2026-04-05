// Tauri API 客户端
import { invoke } from '@tauri-apps/api/tauri'

export interface User {
  id: string
  username: string
  display_name: string
  email?: string
  avatar?: string
  status: string
}

export interface AuthResponse {
  success: boolean
  user_id?: string
  username?: string
  token?: string
  error?: string
}

export interface Conversation {
  id: number
  type: string
  name?: string
  participants: string[]
  last_message?: any
  last_activity: number
}

export interface Message {
  id: number
  sequence: number
  conversation_id: number
  sender_id: string
  message_type: string
  content?: string
  created_at: number
  edited_at?: number
  read_by?: Array<{ user_id: string; timestamp: number }>
}

/**
 * 登录
 */
export async function login(username: string, password: string): Promise<AuthResponse> {
  return invoke<AuthResponse>('login', { username, password })
}

/**
 * 登出
 */
export async function logout(): Promise<void> {
  return invoke<void>('logout')
}

/**
 * 获取 WebSocket URL
 */
export async function getWsUrl(): Promise<string | null> {
  return invoke<string | null>('get_ws_url')
}

/**
 * 获取用户信息
 */
export async function getUserInfo(userId: string): Promise<User> {
  return invoke<User>('get_user_info', { userId })
}

/**
 * 获取会话列表
 */
export async function getConversations(): Promise<Conversation[]> {
  return invoke<Conversation[]>('get_conversations')
}

/**
 * 获取历史消息
 */
export async function getHistory(conversationId: number, limit?: number): Promise<Message[]> {
  return invoke<Message[]>('get_history', { conversationId, limit })
}
