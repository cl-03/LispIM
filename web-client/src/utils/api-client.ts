/**
 * LispIM API Client v1
 * 统一的 API 客户端，处理所有 HTTP 请求
 */

// API 响应类型
export interface ApiResponse<T = unknown> {
  success: boolean
  data?: T
  message?: string
  error?: ApiError
}

export interface ApiError {
  code: string
  message: string
  details?: unknown
}

// 认证相关类型
export interface LoginRequest {
  username: string
  password: string
}

export interface LoginResponse {
  userId: string
  token: string
}

export interface RegisterRequest {
  method: 'username' | 'phone' | 'email'
  username?: string
  password?: string
  email?: string
  phone?: string
  phoneCode?: string
  emailCode?: string
  displayName?: string
  invitationCode?: string
}

export interface RegisterResponse {
  userId: string
  token?: string
}

export interface SendCodeRequest {
  method: 'phone' | 'email'
  value: string
}

// 会话相关类型
export interface Conversation {
  id: number
  type: 'direct' | 'group' | 'channel'
  name?: string
  avatar?: string
  participants: string[]
  lastMessage?: {
    id: number
    content: string
    timestamp: number
  }
  unreadCount: number
  isPinned: boolean
  isMuted: boolean
}

// 消息相关类型
export interface Message {
  id: number
  sequence: number
  conversationId: number
  senderId: string
  type: 'text' | 'image' | 'voice' | 'video' | 'file' | 'system' | 'notification' | 'link'
  content: string
  attachments?: Array<{
    type: string
    url: string
    size: number
    name: string
  }>
  createdAt: number
  replyTo?: number
  mentions?: string[]
  readBy?: Array<{
    userId: string
    timestamp: number
  }>
}

export interface SendMessageRequest {
  content: string
  type?: 'text' | 'image' | 'voice' | 'video' | 'file'
  attachments?: unknown[]
  replyTo?: number
  mentions?: string[]
}

export interface MarkAsReadRequest {
  messageIds: number[]
}

// 好友相关类型
export interface Friend {
  id: string
  username: string
  displayName: string
  avatarUrl?: string
  email?: string
  phone?: string
  friendStatus: 'pending' | 'accepted' | 'blocked'
  friendSince?: number
}

export interface FriendRequest {
  id: number
  senderId: string
  receiverId: string
  message?: string
  status: 'pending' | 'accepted' | 'rejected' | 'cancelled'
  createdAt: number
  senderUsername: string
  senderDisplayName?: string
  senderAvatar?: string
}

export interface UserSearchResult {
  id: string
  username: string
  displayName?: string
  avatarUrl?: string
}

// 文件上传类型
export interface UploadResponse {
  fileId: string
  filename: string
  url: string
  size: number
}

// API 客户端配置
export interface ApiClientConfig {
  baseURL: string
  token?: string
  timeout?: number
}

// 错误处理
export class ApiClientError extends Error {
  code: string
  details?: unknown

  constructor(code: string, message: string, details?: unknown) {
    super(message)
    this.name = 'ApiClientError'
    this.code = code
    this.details = details
  }
}

/**
 * LispIM API Client
 */
export class ApiClient {
  private baseURL: string
  private token?: string
  private timeout: number

  constructor(config: ApiClientConfig) {
    this.baseURL = config.baseURL
    this.token = config.token
    this.timeout = config.timeout || 30000
  }

  /**
   * 更新 Token
   */
  setToken(token: string) {
    this.token = token
  }

  /**
   * 清除 Token
   */
  clearToken() {
    this.token = undefined
  }

  /**
   * 通用请求方法
   */
  private async request<T>(endpoint: string, options: RequestInit = {}): Promise<ApiResponse<T>> {
    const url = `${this.baseURL}${endpoint}`

    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
      ...(options.headers as Record<string, string>)
    }

    // 添加认证 token
    if (this.token) {
      headers['Authorization'] = `Bearer ${this.token}`
    }

    const controller = new AbortController()
    const timeoutId = setTimeout(() => controller.abort(), this.timeout)

    try {
      const response = await fetch(url, {
        ...options,
        headers,
        signal: controller.signal
      })

      clearTimeout(timeoutId)

      const data: ApiResponse<T> = await response.json()

      if (!response.ok) {
        const error = data.error || { code: 'HTTP_ERROR', message: `HTTP ${response.status}` }
        throw new ApiClientError(error.code, error.message, error.details)
      }

      return data
    } catch (error) {
      clearTimeout(timeoutId)

      if (error instanceof ApiClientError) {
        throw error
      }

      if (error instanceof Error) {
        if (error.name === 'AbortError') {
          throw new ApiClientError('TIMEOUT', 'Request timeout')
        }
        throw new ApiClientError('NETWORK_ERROR', error.message)
      }

      throw new ApiClientError('UNKNOWN_ERROR', 'An unknown error occurred')
    }
  }

  /**
   * GET 请求
   */
  async get<T>(endpoint: string, headers?: HeadersInit): Promise<ApiResponse<T>> {
    return this.request<T>(endpoint, { method: 'GET', headers })
  }

  /**
   * POST 请求
   */
  async post<T>(endpoint: string, body?: unknown, headers?: HeadersInit): Promise<ApiResponse<T>> {
    return this.request<T>(endpoint, {
      method: 'POST',
      body: JSON.stringify(body),
      headers
    })
  }

  // ==================== 认证 API ====================

  /**
   * 登录
   */
  async login(credentials: LoginRequest): Promise<ApiResponse<LoginResponse>> {
    return this.post<LoginResponse>('/api/v1/auth/login', credentials)
  }

  /**
   * 注册
   */
  async register(data: RegisterRequest): Promise<ApiResponse<RegisterResponse>> {
    return this.post<RegisterResponse>('/api/v1/auth/register', data)
  }

  /**
   * 发送验证码
   */
  async sendVerificationCode(data: SendCodeRequest): Promise<ApiResponse<void>> {
    return this.post<void>('/api/v1/auth/send-code', data)
  }

  /**
   * 微信登录
   */
  async wechatLogin(code: string): Promise<ApiResponse<LoginResponse>> {
    return this.post<LoginResponse>('/api/v1/auth/wechat', { code })
  }

  /**
   * 登出
   */
  async logout(): Promise<ApiResponse<void>> {
    return this.post<void>('/api/v1/auth/logout')
  }

  // ==================== 会话 API ====================

  /**
   * 获取会话列表
   */
  async getConversations(): Promise<ApiResponse<Conversation[]>> {
    return this.get<Conversation[]>('/api/v1/chat/conversations')
  }

  // ==================== 消息 API ====================

  /**
   * 获取历史消息
   */
  async getHistory(
    conversationId: number,
    options?: { limit?: number; before?: number; after?: number }
  ): Promise<ApiResponse<Message[]>> {
    const headers: HeadersInit = {}
    if (options?.limit) headers['X-Limit'] = String(options.limit)
    if (options?.before) headers['X-Before'] = String(options.before)
    if (options?.after) headers['X-After'] = String(options.after)

    return this.get<Message[]>(`/api/v1/chat/conversations/${conversationId}/messages`, headers)
  }

  /**
   * 发送消息
   */
  async sendMessage(
    conversationId: number,
    data: SendMessageRequest
  ): Promise<ApiResponse<{ id: number; sequence: number; content: string; createdAt: number }>> {
    return this.post(`/api/v1/chat/conversations/${conversationId}/messages`, data)
  }

  /**
   * 标记消息为已读
   */
  async markAsRead(
    conversationId: number,
    messageIds: number[]
  ): Promise<ApiResponse<void>> {
    return this.post(`/api/v1/chat/conversations/${conversationId}/read`, { messageIds })
  }

  /**
   * 撤回消息
   */
  async recallMessage(messageId: number): Promise<ApiResponse<void>> {
    return this.post(`/api/v1/chat/messages/${messageId}/recall`)
  }

  // ==================== 好友 API ====================

  /**
   * 获取好友列表
   */
  async getFriends(): Promise<ApiResponse<Friend[]>> {
    return this.get<Friend[]>('/api/v1/friends')
  }

  /**
   * 发送好友请求
   */
  async sendFriendRequest(friendId: string, message?: string): Promise<ApiResponse<{ requestId: number }>> {
    return this.post('/api/v1/friends/add', { friendId, message })
  }

  /**
   * 获取好友请求列表
   */
  async getFriendRequests(): Promise<ApiResponse<FriendRequest[]>> {
    return this.get<FriendRequest[]>('/api/v1/friends/requests')
  }

  /**
   * 接受好友请求
   */
  async acceptFriendRequest(requestId: number): Promise<ApiResponse<void>> {
    return this.post('/api/v1/friends/accept', { requestId })
  }

  /**
   * 搜索用户
   */
  async searchUsers(query: string, limit?: number): Promise<ApiResponse<UserSearchResult[]>> {
    const params = new URLSearchParams({ q: query })
    if (limit) params.append('limit', String(limit))
    return this.get<UserSearchResult[]>(`/api/v1/users/search?${params.toString()}`)
  }

  // ==================== 文件上传 API ====================

  /**
   * 上传文件
   */
  async uploadFile(file: File, filename: string): Promise<ApiResponse<UploadResponse>> {
    const formData = new FormData()
    formData.append('file', file)
    formData.append('filename', filename)

    const url = `${this.baseURL}/api/v1/upload`
    const headers: HeadersInit = {}
    if (this.token) {
      headers['Authorization'] = this.token
    }

    const controller = new AbortController()
    const timeoutId = setTimeout(() => controller.abort(), this.timeout)

    try {
      const response = await fetch(url, {
        method: 'POST',
        headers,
        body: formData,
        signal: controller.signal
      })

      clearTimeout(timeoutId)

      const data: ApiResponse<UploadResponse> = await response.json()

      if (!response.ok) {
        const error = data.error || { code: 'HTTP_ERROR', message: `HTTP ${response.status}` }
        throw new ApiClientError(error.code, error.message, error.details)
      }

      return data
    } catch (error) {
      clearTimeout(timeoutId)

      if (error instanceof ApiClientError) {
        throw error
      }

      if (error instanceof Error) {
        if (error.name === 'AbortError') {
          throw new ApiClientError('TIMEOUT', 'Request timeout')
        }
        throw new ApiClientError('NETWORK_ERROR', error.message)
      }

      throw new ApiClientError('UNKNOWN_ERROR', 'An unknown error occurred')
    }
  }
}

// 创建单例实例
let apiClientInstance: ApiClient | null = null

/**
 * 获取 API 客户端实例
 */
export function createApiClient(config: ApiClientConfig): ApiClient {
  apiClientInstance = new ApiClient(config)
  return apiClientInstance
}

/**
 * 获取 API 客户端单例
 */
export function getApiClient(): ApiClient {
  if (!apiClientInstance) {
    throw new Error('ApiClient not initialized. Call createApiClient first.')
  }
  return apiClientInstance
}

/**
 * API 错误码常量
 */
export const ApiErrorCode = {
  // 认证错误
  AUTH_REQUIRED: 'AUTH_REQUIRED',
  AUTH_INVALID: 'AUTH_INVALID',
  AUTH_INVALID_CREDENTIALS: 'AUTH_INVALID_CREDENTIALS',
  METHOD_NOT_ALLOWED: 'METHOD_NOT_ALLOWED',

  // 注册错误
  MISSING_FIELDS: 'MISSING_FIELDS',
  REGISTER_FAILED: 'REGISTER_FAILED',
  INVALID_METHOD: 'INVALID_METHOD',

  // 频率限制
  RATE_LIMITED: 'RATE_LIMITED',

  // 微信登录
  WECHAT_LOGIN_FAILED: 'WECHAT_LOGIN_FAILED',

  // 资源不存在
  NOT_FOUND: 'NOT_FOUND',

  // 权限错误
  ACCESS_DENIED: 'ACCESS_DENIED',

  // 请求错误
  INVALID_REQUEST: 'INVALID_REQUEST',
  INVALID_ID: 'INVALID_ID',

  // 撤回错误
  RECALL_TIMEOUT: 'RECALL_TIMEOUT',

  // 内部错误
  INTERNAL_ERROR: 'INTERNAL_ERROR',

  // 网络错误
  TIMEOUT: 'TIMEOUT',
  NETWORK_ERROR: 'NETWORK_ERROR'
} as const
