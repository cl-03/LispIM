import { create } from 'zustand'
import { persist } from 'zustand/middleware'
import type { User, Message, Conversation, AuthState, ConnectionState, ChatState } from '@/types'
import { LispIMWebSocket, getWebSocket } from '@/utils/websocket'

interface AppState extends AuthState, ConnectionState, ChatState {
  // Actions
  login: (token: string, user: User) => void
  logout: () => void
  setConnecting: () => void
  setConnected: () => void
  setDisconnected: (error?: string) => void
  addConversation: (conversation: Conversation) => void
  updateConversation: (conversation: Conversation) => void
  setActiveConversationId: (conversationId: number | null) => void
  addMessage: (message: Message) => void
  markMessageAsRead: (messageId: number, userId: string) => void
  updateUser: (user: User) => void
  updateUserStatus: (userId: string, status: string) => void

  // WebSocket
  ws: LispIMWebSocket | null
  initWebSocket: (url: string, token: string) => Promise<void>
  disconnectWebSocket: () => void
  sendMessage: (conversationId: number, content: string) => void
  readMessage: (messageId: number) => void
}

const initialState: ChatState = {
  conversations: [],
  activeConversationId: null,
  messages: new Map(),
  users: new Map()
}

const initialAuthState: AuthState = {
  isAuthenticated: false,
  user: null,
  token: null,
  refreshToken: null
}

const initialConnectionState: ConnectionState = {
  connected: false,
  connecting: false,
  error: null,
  reconnectAttempts: 0
}

export const useAppStore = create<AppState>()(
  persist(
    (set, get) => ({
      ...initialState,
      ...initialAuthState,
      ...initialConnectionState,
      ws: null,

      // 认证
      login: (token: string, user: User) => {
        set({
          isAuthenticated: true,
          token,
          user,
          connecting: false,
          error: null
        })
      },

      logout: () => {
        const { ws } = get()
        ws?.disconnect()
        set({
          ...initialAuthState,
          ...initialState,
          ...initialConnectionState
        })
      },

      setConnecting: () => {
        set({ connecting: true, error: null })
      },

      setConnected: () => {
        set({ connected: true, connecting: false, error: null, reconnectAttempts: 0 })
      },

      setDisconnected: (error?: string) => {
        set({
          connected: false,
          connecting: false,
          error: error || 'Connection lost'
        })
      },

      // 会话管理
      addConversation: (conversation: Conversation) => {
        const { conversations } = get()
        const exists = conversations.find(c => c.id === conversation.id)
        if (!exists) {
          set({ conversations: [conversation, ...conversations] })
        }
      },

      updateConversation: (conversation: Conversation) => {
        const { conversations } = get()
        set({
          conversations: conversations.map(c =>
            c.id === conversation.id ? conversation : c
          )
        })
      },

      setActiveConversationId: (conversationId: number | null) => {
        set({ activeConversationId: conversationId })
        if (conversationId) {
          const { ws } = get()
          ws?.subscribe(conversationId)
        }
      },

      // 消息管理
      addMessage: (message: Message) => {
        const { messages, conversations, activeConversationId } = get()

        // 更新消息列表
        const convMessages = messages.get(message.conversationId) || []
        const updatedMessages = new Map(messages)
        updatedMessages.set(message.conversationId, [...convMessages, message])

        // 更新会话的最后消息
        const updatedConversations = conversations.map(c =>
          c.id === message.conversationId
            ? { ...c, lastMessage: message, updatedAt: message.createdAt }
            : c
        )

        // 如果是当前活跃会话且不是自己发的消息，标记为已读
        if (activeConversationId === message.conversationId && message.senderId !== get().user?.id) {
          const { ws, user } = get()
          ws?.readMessage(message.id)
          message.readBy = [...(message.readBy || []), { userId: user!.id, timestamp: Date.now() / 1000 }]
        }

        set({
          messages: updatedMessages,
          conversations: updatedConversations
        })
      },

      markMessageAsRead: (messageId: number, userId: string) => {
        const { messages } = get()
        const timestamp = Date.now() / 1000

        messages.forEach((convMessages, convId) => {
          const updated = convMessages.map(msg =>
            msg.id === messageId
              ? { ...msg, readBy: [...(msg.readBy || []), { userId, timestamp }] }
              : msg
          )
          messages.set(convId, updated)
        })

        set({ messages: new Map(messages) })
      },

      // 用户管理
      updateUser: (user: User) => {
        const { users } = get()
        const updatedUsers = new Map(users)
        updatedUsers.set(user.id, user)
        set({ users: updatedUsers })
      },

      updateUserStatus: (userId: string, status: string) => {
        const { users } = get()
        const user = users.get(userId)
        if (user) {
          const updatedUser = { ...user, status: status as User['status'] }
          const updatedUsers = new Map(users)
          updatedUsers.set(userId, updatedUser)
          set({ users: updatedUsers })
        }
      },

      // WebSocket
      initWebSocket: async (url: string, token: string) => {
        const { user, setConnected, setDisconnected, addMessage, updateConversation, updateUserStatus } = get()

        const ws = getWebSocket({ url, token, userId: user?.id })

        ws.on('message', (data) => {
          addMessage(data as Message)
        })

        ws.on('conversation:update', (data) => {
          updateConversation(data as Conversation)
        })

        ws.on('user:status', (data) => {
          updateUserStatus((data as { userId: string }).userId, (data as { status: string }).status)
        })

        set({ ws })

        try {
          await ws.connect()
          setConnected()
        } catch (error) {
          setDisconnected(error instanceof Error ? error.message : 'Connection failed')
        }
      },

      disconnectWebSocket: () => {
        const { ws } = get()
        ws?.disconnect()
        set({ ws: null, connected: false })
      },

      sendMessage: (conversationId: number, content: string) => {
        const { ws } = get()
        ws?.sendMessage(conversationId, content)
      },

      readMessage: (messageId: number) => {
        const { ws } = get()
        ws?.readMessage(messageId)
      }
    }),
    {
      name: 'lispim-storage',
      partialize: (state) => ({
        isAuthenticated: state.isAuthenticated,
        token: state.token,
        refreshToken: state.refreshToken,
        user: state.user
      })
    }
  )
)
