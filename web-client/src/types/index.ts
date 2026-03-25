export interface User {
  id: string
  username: string
  displayName: string
  avatar?: string
  status: 'online' | 'offline' | 'away' | 'busy'
  lastSeen?: number
}

export interface Message {
  id: number
  sequence: number
  conversationId: number
  senderId: string
  sender?: User
  messageType: 'text' | 'image' | 'file' | 'voice' | 'video'
  content: string
  attachments?: Attachment[]
  mentions?: string[]
  replyTo?: number
  createdAt: number
  readBy?: Array<{ userId: string; timestamp: number }>
  recalled?: boolean
  encrypted?: boolean
}

export interface Attachment {
  id: string
  type: 'image' | 'file' | 'voice' | 'video'
  name: string
  size: number
  url: string
  thumbnailUrl?: string
}

export interface Conversation {
  id: number
  type: 'direct' | 'group'
  name?: string
  avatar?: string
  participants: string[]
  participantUsers?: User[]
  lastMessage?: Message
  unreadCount: number
  createdAt: number
  updatedAt: number
  creatorId?: string
  draft?: string
}

export interface Connection {
  id: string
  userId: string
  state: 'connecting' | 'authenticated' | 'active' | 'closing' | 'closed'
  lastHeartbeat: number
  outputBufferSize: number
}

export interface WebSocketMessage {
  type: string
  payload: Record<string, unknown>
  timestamp: number
}

export interface AuthState {
  isAuthenticated: boolean
  user: User | null
  token: string | null
  refreshToken: string | null
}

export interface RegisterData {
  method: 'username' | 'phone' | 'email' | 'wechat'
  username?: string
  password?: string
  phone?: string
  phoneCode?: string
  email?: string
  emailCode?: string
  wechatCode?: string
  displayName?: string
  invitationCode?: string
}

export type RegisterMethod = 'username' | 'phone' | 'email' | 'wechat'

export interface ConnectionState {
  connected: boolean
  connecting: boolean
  error: string | null
  reconnectAttempts: number
}

export interface ChatState {
  conversations: Conversation[]
  activeConversationId: number | null
  messages: Map<number, Message[]>
  users: Map<string, User>
}
