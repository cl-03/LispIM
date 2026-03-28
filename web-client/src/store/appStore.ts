import { create } from 'zustand'
import { persist } from 'zustand/middleware'
import type { User, Message, Conversation, AuthState, ConnectionState, ChatState, RegisterData } from '@/types'
import type { RegisterRequest } from '@/utils/api-client'
import { LispIMWebSocket, getWebSocket } from '@/utils/websocket'
import { createApiClient, getApiClient, ApiClientError } from '@/utils/api-client'

interface AppState extends AuthState, ConnectionState, ChatState {
  // Actions
  login: (username: string, password: string) => Promise<{ success: boolean; error?: string }>
  logout: () => void
  register: (data: RegisterData) => Promise<{ success: boolean; error?: string }>
  sendVerificationCode: (method: 'phone' | 'email', value: string) => Promise<{ success: boolean; error?: string }>
  wechatLogin: (code: string) => Promise<{ success: boolean; error?: string }>
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
  loadConversations: () => Promise<void>
  loadHistory: (conversationId: number) => Promise<void>

  // WebSocket & API
  ws: LispIMWebSocket | null
  apiInitialized: boolean
  initAPI: (baseURL: string, token?: string) => void
  initWebSocket: (url: string) => Promise<void>
  disconnectWebSocket: () => void
  sendMessage: (conversationId: number, content: string) => Promise<void>
  readMessage: (messageId: number) => void
  recallMessage: (messageId: number) => Promise<{ success: boolean; error?: string }>
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
      apiInitialized: false,

      // 初始化 API 客户端
      initAPI: (baseURL: string, token?: string) => {
        createApiClient({ baseURL, token })
        set({ apiInitialized: true })
      },

      // 认证
      login: async (username: string, password: string) => {
        try {
          const api = getApiClient()
          const response = await api.login({ username, password })

          if (response.success && response.data) {
            const { userId, token } = response.data

            // 获取用户信息（这里简化处理，实际应该从 API 获取）
            const user: User = {
              id: userId,
              username: username,
              displayName: username,
              avatar: undefined,
              status: 'online',
              lastSeen: undefined
            }

            // 更新 API 客户端的 token
            api.setToken(token)

            set({
              isAuthenticated: true,
              token,
              user,
              connecting: false,
              error: null,
              apiInitialized: true
            })

            return { success: true }
          } else {
            return { success: false, error: response.error?.message || 'Login failed' }
          }
        } catch (err) {
          console.error('Login error:', err)
          const error = err as ApiClientError
          return { success: false, error: error.message }
        }
      },

      register: async (data: RegisterData) => {
        try {
          const api = getApiClient()
          const registerData: RegisterRequest = {
            method: data.method === 'wechat' ? 'username' : data.method,
            username: data.username,
            password: data.password,
            email: data.email,
            phone: data.phone,
            phoneCode: data.phoneCode,
            emailCode: data.emailCode,
            displayName: data.displayName,
            invitationCode: data.invitationCode
          }
          const response = await api.register(registerData)

          if (response.success) {
            return { success: true }
          } else {
            return { success: false, error: response.error?.message || 'Register failed' }
          }
        } catch (err) {
          console.error('Register error:', err)
          const error = err as ApiClientError
          return { success: false, error: error.message }
        }
      },

      sendVerificationCode: async (method: 'phone' | 'email', value: string) => {
        try {
          const api = getApiClient()
          const response = await api.sendVerificationCode({ method, value })

          if (response.success) {
            return { success: true, error: undefined }
          } else {
            return { success: false, error: response.error?.message || 'Send code failed' }
          }
        } catch (err) {
          console.error('Send code error:', err)
          const error = err as ApiClientError
          return { success: false, error: error.message }
        }
      },

      wechatLogin: async (code: string) => {
        try {
          const api = getApiClient()
          const response = await api.wechatLogin(code)

          if (response.success && response.data) {
            const { userId, token } = response.data
            const user: User = {
              id: userId,
              username: `wechat_${userId}`,
              displayName: `WeChat User`,
              avatar: undefined,
              status: 'online'
            }

            api.setToken(token)

            set({
              isAuthenticated: true,
              token,
              user,
              connecting: false,
              error: null,
              apiInitialized: true
            })

            return { success: true }
          } else {
            return { success: false, error: response.error?.message || 'WeChat login failed' }
          }
        } catch (err) {
          console.error('WeChat login error:', err)
          const error = err as ApiClientError
          return { success: false, error: error.message }
        }
      },

      logout: async () => {
        try {
          const api = getApiClient()
          // 只在 API 已初始化时调用 logout API
          if (api) {
            await api.logout()
          }
        } catch (err) {
          // 忽略登出错误（可能 API 未初始化或 token 已过期）
          console.log('[AppStore] Logout API call failed (expected if not authenticated)')
        }

        const { ws } = get()
        ws?.disconnect()

        // 清除 API 客户端 token
        try {
          const api = getApiClient()
          api.clearToken()
        } catch {
          // API 客户端可能未初始化
        }

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

      // 加载会话列表
      loadConversations: async () => {
        try {
          const state = get()
          // 检查是否已认证且有 token
          if (!state.isAuthenticated || !state.token) {
            return
          }

          // 检查 API 客户端是否已初始化
          if (!state.apiInitialized) {
            console.warn('API not initialized yet, skipping loadConversations')
            return
          }

          const api = getApiClient()
          const response = await api.getConversations()

          if (response.success && response.data) {
            // 类型转换为 types/index.ts 中的 Conversation 类型，添加默认值
            const now = Date.now()
            const convertedConversations = response.data.map(c => ({
              ...c,
              createdAt: (c as any).createdAt || now,
              updatedAt: (c as any).updatedAt || now
            })) as Conversation[]
            set({ conversations: convertedConversations })
          }
        } catch (err) {
          console.error('Load conversations error:', err)
        }
      },

      // 加载历史消息
      loadHistory: async (conversationId: number) => {
        try {
          const api = getApiClient()
          const response = await api.getHistory(conversationId, { limit: 50 })

          if (response.success && response.data) {
            const { messages } = get()
            const updatedMessages = new Map(messages)
            // 类型转换并添加 messageType 字段
            const convertedMessages = response.data.map(msg => ({
              ...msg,
              messageType: (msg as any).type || 'text'
            })) as Message[]
            updatedMessages.set(conversationId, convertedMessages)
            set({ messages: updatedMessages })
          }
        } catch (err) {
          console.error('Load history error:', err)
        }
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
          // 如果消息为空，加载历史消息
          const { messages } = get()
          if (!messages.has(conversationId)) {
            get().loadHistory(conversationId)
          }
        }
      },

      // 消息管理
      addMessage: (message: Message) => {
        const { messages, conversations, activeConversationId, user } = get()

        // 更新消息列表
        const convMessages = messages.get(message.conversationId) || []

        // 检查是否是后端返回的真实消息（正 ID），如果是，替换掉临时消息（负 ID）
        if (message.id > 0) {
          // 查找是否有相同 senderId 和 content 的临时消息
          const tempMessageIndex = convMessages.findIndex(
            m => m.id < 0 && m.senderId === message.senderId && m.content === message.content
          )
          if (tempMessageIndex !== -1) {
            // 替换临时消息为真实消息
            const updatedMessagesArr = [...convMessages]
            updatedMessagesArr[tempMessageIndex] = message
            const updatedMessages = new Map(messages)
            updatedMessages.set(message.conversationId, updatedMessagesArr)

            // 更新会话的最后消息
            const updatedConversations = conversations.map(c =>
              c.id === message.conversationId
                ? { ...c, lastMessage: message, updatedAt: message.createdAt }
                : c
            )

            set({
              messages: updatedMessages,
              conversations: updatedConversations
            })
            return
          }
        }

        // 如果没有临时消息，直接添加新消息
        const updatedMessages = new Map(messages)
        updatedMessages.set(message.conversationId, [...convMessages, message])

        // 更新会话的最后消息
        const updatedConversations = conversations.map(c =>
          c.id === message.conversationId
            ? { ...c, lastMessage: message, updatedAt: message.createdAt }
            : c
        )

        // 如果是当前活跃会话且不是自己发的消息，标记为已读
        if (activeConversationId === message.conversationId && message.senderId !== user?.id) {
          const { ws } = get()
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
      initWebSocket: async (url: string) => {
        const { user, setConnected, setDisconnected, addMessage, updateConversation, updateUserStatus, loadConversations, token } = get()

        if (!token) {
          setDisconnected('No token available')
          return
        }

        const ws = getWebSocket({ url, token, userId: user?.id })

        // 设置事件处理器
        ws.on('message', (data) => {
          addMessage(data as Message)
        })

        ws.on('conversation:update', (data) => {
          updateConversation(data as Conversation)
        })

        ws.on('user:status', (data) => {
          const { userId, status } = data as { userId: string; status: string }
          updateUserStatus(userId, status)
        })

        ws.on('auth:response', (data) => {
          console.log('[WebSocket] Auth response:', data)
        })

        ws.on('error', (data) => {
          console.error('[WebSocket] Error:', data)
        })

        set({ ws })

        try {
          await ws.connect()
          setConnected()
          // 等待一小段时间确保 API 客户端已初始化，然后加载会话列表
          setTimeout(() => {
            loadConversations()
          }, 100)
        } catch (error) {
          setDisconnected(error instanceof Error ? error.message : 'Connection failed')
        }
      },

      disconnectWebSocket: () => {
        const { ws } = get()
        ws?.disconnect()
        set({ ws: null, connected: false })
      },

      sendMessage: async (conversationId: number, content: string) => {
        const { ws, user } = get()
        if (!ws) {
          throw new Error('WebSocket not connected')
        }
        // 创建临时消息 ID（使用负数避免与真实 ID 冲突）
        const tempId = -Date.now()
        // 立即在本地添加消息（optimistic update）
        const tempMessage: Message = {
          id: tempId,
          sequence: 0,
          conversationId,
          senderId: user?.id || 'unknown',
          content,
          messageType: 'text',
          createdAt: Date.now() / 1000,
          readBy: []
        }
        // 添加到本地消息列表
        get().addMessage(tempMessage)
        try {
          await ws.sendMessage(conversationId, content)
        } catch (error) {
          console.error('Send message error:', error)
          // 发送失败时移除临时消息
          const { messages } = get()
          const convMessages = messages.get(conversationId) || []
          const updatedMessages = convMessages.filter(m => m.id !== tempId)
          const updatedMap = new Map(messages)
          updatedMap.set(conversationId, updatedMessages)
          set({ messages: updatedMap })
          throw error
        }
      },

      readMessage: (messageId: number) => {
        const { ws } = get()
        ws?.readMessage(messageId)
      },

      recallMessage: async (messageId: number) => {
        try {
          const api = getApiClient()
          const response = await api.recallMessage(messageId)

          if (response.success) {
            return { success: true }
          } else {
            return { success: false, error: response.error?.message }
          }
        } catch (err) {
          console.error('Recall message error:', err)
          const error = err as ApiClientError
          return { success: false, error: error.message }
        }
      }
    }),
    {
      name: 'lispim-storage',
      partialize: (state) => ({
        isAuthenticated: state.isAuthenticated,
        token: state.token,
        refreshToken: state.refreshToken,
        user: state.user
      }),
      onRehydrateStorage: () => {
        // Re-initialize API client with persisted token when app reloads
        return (state, error) => {
          if (error || !state?.token) return
          // Initialize API client with the persisted token
          const baseURL = (import.meta as any).env.VITE_API_URL || 'http://localhost:3000/api/v1'
          createApiClient({ baseURL, token: state.token })
          // Use set to update apiInitialized since state here is the hydrated state, not the store
          useAppStore.setState({ apiInitialized: true })
        }
      }
    }
  )
)
