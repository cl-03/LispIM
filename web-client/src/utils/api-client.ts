/**
 * LispIM API Client v1
 * 统一的 API 客户端，处理所有 HTTP 请求
 */

import type {
  UserStatus,
  ChatFolder,
  Channel,
  SearchOptions,
  SearchResult,
  MessageReaction,
} from '@/types';

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

// 群聊相关类型
export interface Group {
  id: number
  name: string
  avatar?: string
  ownerId: string
  announcement?: string
  announcementEditorId?: string
  announcementUpdatedAt?: number
  memberCount: number
  maxMembers: number
  isMuted: boolean
  isDismissed: boolean
  invitePrivacy: 'all' | 'owner' | 'admin'
  createdAt: number
  updatedAt: number
}

export interface GroupMember {
  userId: string
  role: 'owner' | 'admin' | 'member'
  nickname?: string
  joinedAt: number
  isMuted: boolean
  isQuiet: boolean
  user?: User
}

export interface GroupCreateData {
  name: string
  avatar?: string
  memberIds?: string[]
  maxMembers?: number
  invitePrivacy?: 'all' | 'owner' | 'admin'
}

// 通知偏好设置
export interface NotificationPreferences {
  enableDesktop: boolean
  enableSound: boolean
  enableBadge: boolean
  messageNotifications: boolean
  callNotifications: boolean
  friendRequestNotifications: boolean
  groupNotifications: boolean
  quietMode: boolean
  quietStart: string
  quietEnd: string
}

// 用户通知
export interface UserNotification {
  id: number
  type: 'message' | 'call' | 'friend-request' | 'system' | 'group'
  title: string
  content: string
  data: Record<string, unknown>
  priority: 'low' | 'normal' | 'high'
  createdAt: number
  read: boolean
  delivered: boolean
}

// 置顶消息
export interface PinnedMessage {
  messageId: number
  content: string
  senderId: string
  type: string
  pinnedAt: number
  pinnedBy: string
  pinnedByUsername: string
}

// 群投票相关类型
export interface GroupPoll {
  id: number
  groupId: number
  createdBy: string
  title: string
  description?: string
  multipleChoice: boolean
  allowSuggestions: boolean
  anonymousVoting: boolean
  endAt?: number
  status: 'active' | 'ended' | 'archived'
  createdAt: number
  endedAt?: number
  options: PollOption[]
  results: PollResult[]
}

export interface PollOption {
  id: number
  text: string
  voteCount: number
}

export interface PollResult {
  optionId: number
  text: string
  voteCount: number
  percentage: number
  voters: Array<{ userId: string; username: string }>
}

export interface CreatePollData {
  title: string
  description?: string
  options: string[]
  multipleChoice?: boolean
  allowSuggestions?: boolean
  anonymousVoting?: boolean
  endAt?: number
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

export interface User {
  id: string
  username: string
  displayName: string
  avatar?: string
  status: 'online' | 'offline' | 'away' | 'busy'
  lastSeen?: number
  email?: string
  phone?: string
  bio?: string
  gender?: 'male' | 'female' | 'other'
  birthday?: string
  location?: string
  company?: string
  website?: string
  createdAt?: number
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
  createdAt?: number
  updatedAt?: number
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

// 分块文件上传相关类型
export interface FileTransferInitRequest {
  filename: string
  fileSize: number
  fileType: string
  chunkSize?: number
  recipientId?: string
}

export interface FileTransferInitResponse {
  fileId: string
  filename: string
  fileSize: number
  fileType: string
  chunkSize: number
  totalChunks: number
  uploadUrl: string
}

export interface FileTransferChunkRequest {
  fileId: string
  chunkIndex: number
  chunkData: string // Base64 encoded
  chunkHash?: string
}

export interface FileTransferChunkResponse {
  chunkId: string
  chunkIndex: number
  chunkSize: number
  uploadedChunks: number
  totalChunks: number
}

export interface FileTransferCompleteRequest {
  fileId: string
  fileHash?: string
}

export interface FileTransferCompleteResponse {
  fileId: string
  fileHash: string
  storagePath: string
  downloadUrl: string
}

export interface FileTransferProgress {
  fileId: string
  uploadedChunks: number
  totalChunks: number
  progress: number // 0-100
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
 * 并发请求池配置
 */
export interface RequestPoolConfig {
  maxConcurrent?: number  // 最大并发请求数
  maxRetries?: number     // 最大重试次数
  retryDelay?: number     // 重试延迟 (ms)
}

/**
 * 待处理请求
 */
interface PendingRequest {
  endpoint: string
  options: RequestInit
  resolve: (value: any) => void
  reject: (reason: any) => void
  priority: number
  retryCount: number
}

/**
 * LispIM API Client
 */
export class ApiClient {
  private baseURL: string
  private token?: string
  public getToken(): string | undefined { return this.token; }
  private timeout: number
  private maxConcurrent: number
  private maxRetries: number
  private retryDelay: number

  // 并发控制
  private runningRequests: number = 0
  private requestQueue: PendingRequest[] = []
  private pendingMap: Map<string, Promise<any>> = new Map()  // 请求去重

  constructor(config: ApiClientConfig & RequestPoolConfig = {} as ApiClientConfig & RequestPoolConfig) {
    this.baseURL = config.baseURL
    this.token = config.token
    this.timeout = config.timeout || 30000
    this.maxConcurrent = config.maxConcurrent || 10
    this.maxRetries = config.maxRetries ?? 3
    this.retryDelay = config.retryDelay || 1000
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
   * 通用请求方法（支持并发控制、重试、去重）
   */
  private async request<T>(endpoint: string, options: RequestInit = {}, priority: number = 0): Promise<ApiResponse<T>> {
    const url = `${this.baseURL}${endpoint}`
    const cacheKey = `${options.method || 'GET'}:${url}`

    // GET 请求去重
    if ((options.method === 'GET' || !options.method) && this.pendingMap.has(cacheKey)) {
      return this.pendingMap.get(cacheKey)
    }

    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
      ...(options.headers as Record<string, string>)
    }

    // 添加认证 token
    if (this.token) {
      headers['Authorization'] = `Bearer ${this.token}`
    }

    // 如果当前请求数已达上限，加入队列
    if (this.runningRequests >= this.maxConcurrent) {
      return new Promise((resolve, reject) => {
        this.requestQueue.push({
          endpoint,
          options,
          resolve,
          reject,
          priority,
          retryCount: 0
        })
        // 按优先级排序（数字越大优先级越高）
        this.requestQueue.sort((a, b) => b.priority - a.priority)
      })
    }

    this.runningRequests++

    let timeoutId: ReturnType<typeof setTimeout> | undefined;

    try {
      const controller = new AbortController()
      timeoutId = setTimeout(() => controller.abort(), this.timeout)

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
      if (timeoutId) {
        clearTimeout(timeoutId)
      }

      // 重试逻辑（使用 _requestRaw 避免无限递归）
      if (this.shouldRetry(error) && this.maxRetries > 0) {
        return this._retryRequest(endpoint, options, priority, error)
      }

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
    } finally {
      this.runningRequests--
      this.pendingMap.delete(cacheKey)
      // 处理队列中的下一个请求
      this.processQueue()
    }
  }

  /**
   * 原始请求方法（不重试，用于重试逻辑内部调用）
   */
  private async _requestRaw<T>(endpoint: string, options: RequestInit = {}): Promise<ApiResponse<T>> {
    const url = `${this.baseURL}${endpoint}`
    const cacheKey = `${options.method || 'GET'}:${url}`

    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
      ...(options.headers as Record<string, string>)
    }

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
      throw error
    } finally {
      this.pendingMap.delete(cacheKey)
    }
  }

  /**
   * 判断是否应该重试
   */
  private shouldRetry(error: any): boolean {
    // 网络错误、超时、5xx 服务器错误可以重试
    if (error instanceof ApiClientError) {
      if (error.code === 'TIMEOUT' || error.code === 'NETWORK_ERROR') {
        return true
      }
      if (error.code?.startsWith('HTTP_')) {
        const status = parseInt(error.code.replace('HTTP_', ''))
        return status >= 500 && status < 600
      }
    }
    return true
  }

  /**
   * 重试请求（内部方法）
   */
  private async _retryRequest<T>(
    endpoint: string,
    options: RequestInit,
    priority: number,
    lastError: any
  ): Promise<ApiResponse<T>> {
    for (let i = 1; i <= this.maxRetries; i++) {
      // 指数退避：1s, 2s, 4s...
      const delay = this.retryDelay * Math.pow(2, i - 1)
      await new Promise(resolve => setTimeout(resolve, delay))

      try {
        return await this._requestRaw<T>(endpoint, options)
      } catch (error) {
        if (i === this.maxRetries) {
          throw error
        }
      }
    }
    throw lastError
  }

  /**
   * 处理请求队列
   */
  private processQueue(): void {
    if (this.requestQueue.length === 0 || this.runningRequests >= this.maxConcurrent) {
      return
    }

    const nextRequest = this.requestQueue.shift()
    if (nextRequest) {
      this.request(nextRequest.endpoint, nextRequest.options, nextRequest.priority)
        .then(nextRequest.resolve)
        .catch(nextRequest.reject)
    }
  }

  /**
   * GET 请求
   */
  async get<T>(endpoint: string, headers?: HeadersInit, priority: number = 0): Promise<ApiResponse<T>> {
    return this.request<T>(endpoint, { method: 'GET', headers }, priority)
  }

  /**
   * POST 请求
   */
  async post<T>(endpoint: string, body?: unknown, headers?: HeadersInit, priority: number = 0): Promise<ApiResponse<T>> {
    return this.request<T>(endpoint, {
      method: 'POST',
      body: JSON.stringify(body),
      headers
    }, priority)
  }

  /**
   * PUT 请求
   */
  async put<T>(endpoint: string, body?: unknown, headers?: HeadersInit, priority: number = 0): Promise<ApiResponse<T>> {
    return this.request<T>(endpoint, {
      method: 'PUT',
      body: JSON.stringify(body),
      headers
    }, priority)
  }

  /**
   * DELETE 请求
   */
  async delete<T>(endpoint: string, headers?: HeadersInit, priority: number = 0): Promise<ApiResponse<T>> {
    return this.request<T>(endpoint, { method: 'DELETE', headers }, priority)
  }

  /**
   * 批量 GET 请求（并发执行）
   */
  async batchGet<T>(
    endpoints: string[],
    options?: { maxConcurrent?: number }
  ): Promise<ApiResponse<T>[]> {
    const maxConcurrent = options?.maxConcurrent || this.maxConcurrent
    const results: ApiResponse<T>[] = []

    // 使用信号量控制并发
    const semaphore = {
      count: 0,
      queue: Array<() => void>(),
      acquire: (): Promise<void> => {
        if (semaphore.count < maxConcurrent) {
          semaphore.count++
          return Promise.resolve()
        }
        return new Promise(resolve => semaphore.queue.push(resolve))
      },
      release: (): void => {
        if (semaphore.queue.length > 0) {
          const next = semaphore.queue.shift()
          next?.()
        } else {
          semaphore.count--
        }
      }
    }

    const promises = endpoints.map(async (endpoint) => {
      await semaphore.acquire()
      try {
        const result = await this.get<T>(endpoint)
        results.push(result)
        return result
      } finally {
        semaphore.release()
      }
    })

    await Promise.all(promises)
    return results
  }

  /**
   * 批量请求（不同端点，并发执行）
   */
  async batchRequest<T>(
    requests: Array<{
      method: 'GET' | 'POST' | 'PUT' | 'DELETE'
      endpoint: string
      body?: unknown
      headers?: HeadersInit
    }>,
    options?: { maxConcurrent?: number }
  ): Promise<ApiResponse<T>[]> {
    const maxConcurrent = options?.maxConcurrent || this.maxConcurrent
    const results: ApiResponse<T>[] = []

    const semaphore = {
      count: 0,
      queue: Array<() => void>(),
      acquire: (): Promise<void> => {
        if (semaphore.count < maxConcurrent) {
          semaphore.count++
          return Promise.resolve()
        }
        return new Promise(resolve => semaphore.queue.push(resolve))
      },
      release: (): void => {
        if (semaphore.queue.length > 0) {
          const next = semaphore.queue.shift()
          next?.()
        } else {
          semaphore.count--
        }
      }
    }

    const promises = requests.map(async (req) => {
      await semaphore.acquire()
      try {
        let result: ApiResponse<T>
        switch (req.method) {
          case 'GET':
            result = await this.get<T>(req.endpoint, req.headers)
            break
          case 'POST':
            result = await this.post<T>(req.endpoint, req.body, req.headers)
            break
          case 'PUT':
            result = await this.put<T>(req.endpoint, req.body, req.headers)
            break
          case 'DELETE':
            result = await this.delete<T>(req.endpoint, req.headers)
            break
        }
        results.push(result)
        return result
      } finally {
        semaphore.release()
      }
    })

    await Promise.all(promises)
    return results
  }

  /**
   * 获取当前运行中的请求数
   */
  getRunningRequestCount(): number {
    return this.runningRequests
  }

  /**
   * 获取队列中的请求数
   */
  getQueuedRequestCount(): number {
    return this.requestQueue.length
  }

  /**
   * 设置最大并发数
   */
  setMaxConcurrent(count: number): void {
    this.maxConcurrent = count
    // 如果增加了并发数，处理队列
    if (count > this.runningRequests) {
      this.processQueue()
    }
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

  /**
   * 编辑消息
   */
  async editMessage(messageId: number, content: string): Promise<ApiResponse<void>> {
    return this.put(`/api/v1/chat/messages/${messageId}/edit`, { content })
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

  // ==================== 增量同步 API (新增) ====================

  /**
   * 获取增量消息（离线消息同步）
   * @param anchorSeq 上次同步的序列号
   * @param batchSize 批次大小
   */
  async getIncrementalMessages(
    anchorSeq: number,
    batchSize: number = 50
  ): Promise<ApiResponse<{ messages: Message[]; hasMore: boolean; nextAnchorSeq: number }>> {
    return this.get(`/api/v1/sync/messages?anchor_seq=${anchorSeq}&batch_size=${batchSize}`)
  }

  /**
   * 获取增量会话（离线会话同步）
   * @param anchorSeq 上次同步的序列号
   */
  async getIncrementalConversations(
    anchorSeq: number
  ): Promise<ApiResponse<{ conversations: Conversation[]; hasMore: boolean; nextAnchorSeq: number }>> {
    return this.get(`/api/v1/sync/conversations?anchor_seq=${anchorSeq}`)
  }

  /**
   * 完整同步（初次加载或刷新后）
   */
  async fullSync(): Promise<ApiResponse<{
    conversations: Conversation[]
    messages: Message[]
    anchorSeq: number
  }>> {
    return this.get('/api/v1/sync/full')
  }

  // ==================== 扫一扫 API (QR Code) ====================

  /**
   * 生成个人二维码
   */
  async generateQRCode(): Promise<ApiResponse<{
    qrData: any
    qrJson: string
    username: string
    displayName: string
  }>> {
    return this.post('/api/v1/qr/generate')
  }

  /**
   * 扫描二维码
   */
  async scanQRCode(qrJson: string): Promise<ApiResponse<{
    success: boolean
    type: string
    user: {
      id: string
      username: string
      displayName: string
      avatar: string
    }
  }>> {
    return this.post('/api/v1/qr/scan', { qrJson })
  }

  // ==================== 附近的人 API (Location) ====================

  /**
   * 上报位置
   */
  async reportLocation(data: {
    latitude: number
    longitude: number
    accuracy?: number
    city?: string
    district?: string
  }): Promise<ApiResponse<void>> {
    return this.post('/api/v1/location/report', data)
  }

  /**
   * 获取附近的人
   */
  async getNearbyUsers(params: {
    lat?: number
    lng?: number
    radius?: number
    city?: string
    district?: string
  }): Promise<ApiResponse<{
    users: Array<{
      user_id: string
      latitude: number
      longitude: number
      distance: number
      timestamp: number
      city: string
      district: string
      displayName?: string
      username?: string
      avatar?: string
    }>
    count: number
  }>> {
    const queryParams = new URLSearchParams()
    if (params.lat) queryParams.append('lat', String(params.lat))
    if (params.lng) queryParams.append('lng', String(params.lng))
    if (params.radius) queryParams.append('radius', String(params.radius))
    if (params.city) queryParams.append('city', params.city)
    if (params.district) queryParams.append('district', params.district)
    return this.get(`/api/v1/location/nearby?${queryParams.toString()}`)
  }

  /**
   * 设置位置隐私
   */
  async setLocationPrivacy(visible: boolean): Promise<ApiResponse<{
    visible: boolean
  }>> {
    return this.post('/api/v1/location/privacy', { visible })
  }

  // ==================== 朋友圈 API (Moments) ====================

  /**
   * 获取朋友圈动态
   */
  async getMoments(params?: {
    page?: number
    page_size?: number
  }): Promise<ApiResponse<{
    moments: Moment[]
    page: number
    page_size: number
    has_more: boolean
  }>> {
    const queryParams = new URLSearchParams()
    if (params?.page) queryParams.append('page', String(params.page))
    if (params?.page_size) queryParams.append('page_size', String(params.page_size))
    return this.get(`/api/v1/moments?${queryParams.toString()}`)
  }

  /**
   * 发布朋友圈
   */
  async createMoment(data: {
    content: string
    photos?: string[]
    type?: 'text' | 'image' | 'video' | 'link'
    location?: string
    visibility?: 'public' | 'friends' | 'private'
  }): Promise<ApiResponse<{
    id: number
    message: string
  }>> {
    return this.post('/api/v1/moments/post', data)
  }

  /**
   * 获取朋友圈详情
   */
  async getMoment(postId: number): Promise<ApiResponse<Moment>> {
    return this.get(`/api/v1/moments/${postId}`)
  }

  /**
   * 点赞/取消点赞朋友圈
   */
  async likeMoment(postId: number, action: 'like' | 'unlike'): Promise<ApiResponse<void>> {
    return this.post(`/api/v1/moments/${postId}/like`, { action })
  }

  /**
   * 评论朋友圈
   */
  async commentMoment(postId: number, data: {
    content: string
    reply_to_user_id?: string
    reply_to_username?: string
  }): Promise<ApiResponse<{
    id: number
    message: string
  }>> {
    return this.post(`/api/v1/moments/${postId}/comment`, data)
  }

  /**
   * 删除评论
   */
  async deleteComment(postId: number, commentId: number): Promise<ApiResponse<void>> {
    return this.request(`/api/v1/moments/${postId}/comments/${commentId}`, { method: 'DELETE' })
  }
  /**
   * 删除动态
   */
  async deleteMoment(postId: number): Promise<ApiResponse<void>> {
    return this.request(`/api/v1/moments/${postId}`, { method: 'DELETE' })
  }

  // ==================== 通讯录 API (Contacts) ====================

  /**
   * 获取联系人分组列表
   */
  async getContactGroups(): Promise<ApiResponse<ContactGroup[]>> {
    return this.get('/api/v1/contacts/groups')
  }

  /**
   * 创建联系人分组
   */
  async createContactGroup(data: { name: string; order?: number }): Promise<ApiResponse<{ id: number }>> {
    return this.post('/api/v1/contacts/groups', data)
  }

  /**
   * 删除联系人分组
   */
  async deleteContactGroup(groupId: number): Promise<ApiResponse<void>> {
    return this.request(`/api/v1/contacts/groups/${groupId}`, { method: 'DELETE' })
  }

  /**
   * 获取分组成员
   */
  async getContactGroupMembers(groupId: number): Promise<ApiResponse<Friend[]>> {
    return this.get(`/api/v1/contacts/groups/${groupId}/members`)
  }

  /**
   * 获取联系人标签列表
   */
  async getContactTags(): Promise<ApiResponse<ContactTag[]>> {
    return this.get('/api/v1/contacts/tags')
  }

  /**
   * 创建联系人标签
   */
  async createContactTag(data: { name: string; color?: string }): Promise<ApiResponse<{ id: number }>> {
    return this.post('/api/v1/contacts/tags', data)
  }

  /**
   * 删除联系人标签
   */
  async deleteContactTag(tagId: number): Promise<ApiResponse<void>> {
    return this.request(`/api/v1/contacts/tags/${tagId}`, { method: 'DELETE' })
  }

  /**
   * 设置好友备注
   */
  async setContactRemark(
    friendId: string,
    data: {
      remark: string
      description?: string
      phone?: string
      email?: string
      company?: string
      birthday?: string
    }
  ): Promise<ApiResponse<void>> {
    return this.put(`/api/v1/contacts/friends/${friendId}/remark`, data)
  }

  /**
   * 获取好友分组
   */
  async getFriendGroups(friendId: string): Promise<ApiResponse<ContactGroup[]>> {
    return this.get(`/api/v1/contacts/friends/${friendId}/groups`)
  }

  /**
   * 添加好友到分组
   */
  async addFriendToGroup(groupId: number, friendId: string): Promise<ApiResponse<void>> {
    return this.post(`/api/v1/contacts/friends/${friendId}/groups`, { groupId })
  }

  /**
   * 获取好友标签
   */
  async getFriendTags(friendId: string): Promise<ApiResponse<ContactTag[]>> {
    return this.get(`/api/v1/contacts/friends/${friendId}/tags`)
  }

  /**
   * 添加标签到好友
   */
  async addTagToFriend(tagId: number, friendId: string): Promise<ApiResponse<void>> {
    return this.post(`/api/v1/contacts/friends/${friendId}/tags`, { tagId, action: 'add' })
  }

  /**
   * 从好友移除标签
   */
  async removeTagFromFriend(tagId: number, friendId: string): Promise<ApiResponse<void>> {
    return this.post(`/api/v1/contacts/friends/${friendId}/tags`, { tagId, action: 'remove' })
  }

  /**
   * 获取黑名单
   */
  async getBlacklist(): Promise<ApiResponse<Friend[]>> {
    return this.get('/api/v1/contacts/blacklist')
  }

  /**
   * 添加用户到黑名单
   */
  async addToBlacklist(blockedId: string): Promise<ApiResponse<void>> {
    return this.post('/api/v1/contacts/blacklist', { blockedId })
  }

  /**
   * 从黑名单移除
   */
  async removeFromBlacklist(blockedId: string): Promise<ApiResponse<void>> {
    return this.request(`/api/v1/contacts/blacklist/${blockedId}`, { method: 'DELETE' })
  }

  /**
   * 获取星标联系人
   */
  async getStarContacts(): Promise<ApiResponse<Friend[]>> {
    return this.get('/api/v1/contacts/stars')
  }

  /**
   * 添加星标联系人
   */
  async addStarContact(starredId: string): Promise<ApiResponse<void>> {
    return this.post('/api/v1/contacts/stars', { starredId })
  }

  /**
   * 移除星标联系人
   */
  async removeStarContact(starredId: string): Promise<ApiResponse<void>> {
    return this.request(`/api/v1/contacts/stars/${starredId}`, { method: 'DELETE' })
  }

  /**
   * 搜索联系人
   */
  async searchContacts(query: string, limit?: number): Promise<ApiResponse<Friend[]>> {
    const params = new URLSearchParams({ q: query })
    if (limit) params.append('limit', String(limit))
    return this.get(`/api/v1/contacts/search?${params.toString()}`)
  }

  // ==================== 好友 API ====================

  /**
   * 获取好友列表
   */
  async getFriends(): Promise<ApiResponse<Friend[]>> {
    return this.get<Friend[]>('/api/v1/contacts/friends')
  }

  /**
   * 获取好友申请列表
   */
  async getFriendRequests(): Promise<ApiResponse<{
    id: number
    senderId: string
    sender: {
      id: string
      username: string
      displayName: string
      avatar: string
    }
    message: string
    createdAt: number
  }[]>> {
    return this.get('/api/v1/contacts/friend-requests')
  }

  /**
   * 发送好友申请
   */
  async sendFriendRequest(receiverId: string, message?: string): Promise<ApiResponse<{ requestId: number }>> {
    return this.post('/api/v1/contacts/friend-request/send', { receiverId, message })
  }

  /**
   * 接受好友申请
   */
  async acceptFriendRequest(requestId: number): Promise<ApiResponse<void>> {
    return this.post(`/api/v1/contacts/friend-request/${requestId}/accept`)
  }

  /**
   * 拒绝好友申请
   */
  async rejectFriendRequest(requestId: number): Promise<ApiResponse<void>> {
    return this.post(`/api/v1/contacts/friend-request/${requestId}/reject`)
  }

  /**
   * 删除好友
   */
  async deleteFriend(friendId: string): Promise<ApiResponse<void>> {
    return this.request(`/api/v1/contacts/friends/${friendId}`, { method: 'DELETE' })
  }

  // ==================== 账号管理 API (Account) ====================

  /**
   * 修改密码
   */
  async changePassword(data: {
    currentPassword: string
    newPassword: string
  }): Promise<ApiResponse<void>> {
    return this.post('/api/v1/account/change-password', data)
  }

  /**
   * 绑定手机号
   */
  async bindPhone(data: {
    phone: string
    code: string
  }): Promise<ApiResponse<void>> {
    return this.post('/api/v1/account/bind-phone', data)
  }

  /**
   * 绑定邮箱
   */
  async bindEmail(data: {
    email: string
    code: string
  }): Promise<ApiResponse<void>> {
    return this.post('/api/v1/account/bind-email', data)
  }

  /**
   * 解绑手机号
   */
  async unbindPhone(): Promise<ApiResponse<void>> {
    return this.post('/api/v1/account/unbind-phone')
  }

  /**
   * 解绑邮箱
   */
  async unbindEmail(): Promise<ApiResponse<void>> {
    return this.post('/api/v1/account/unbind-email')
  }

  /**
   * 获取活跃会话列表
   */
  async getSessions(): Promise<ApiResponse<UserSession[]>> {
    return this.get('/api/v1/account/sessions')
  }

  /**
   * 撤销会话
   */
  async revokeSession(sessionId: string): Promise<ApiResponse<void>> {
    return this.request(`/api/v1/account/sessions/${sessionId}`, { method: 'DELETE' })
  }

  /**
   * 删除账号
   */
  async deleteAccount(password: string): Promise<ApiResponse<void>> {
    return this.post('/api/v1/account/delete', { password })
  }

  /**
   * 更新用户资料
   */
  async updateProfile(data: {
    displayName?: string
    avatar?: string
  }): Promise<ApiResponse<User>> {
    return this.put('/api/v1/users/profile', data)
  }

  /**
   * 获取当前用户信息
   */
  async getCurrentUser(): Promise<ApiResponse<User>> {
    return this.get('/api/v1/users/me')
  }

  // ==================== 分块文件上传 API (Chunked File Upload) ====================

  /**
   * 初始化分块文件上传
   */
  async initFileUpload(data: FileTransferInitRequest): Promise<ApiResponse<FileTransferInitResponse>> {
    return this.post('/api/v1/files/upload/init', data)
  }

  /**
   * 上传文件分块
   */
  async uploadChunk(data: FileTransferChunkRequest): Promise<ApiResponse<FileTransferChunkResponse>> {
    return this.post('/api/v1/files/upload/chunk', data)
  }

  /**
   * 完成文件上传
   */
  async completeFileUpload(data: FileTransferCompleteRequest): Promise<ApiResponse<FileTransferCompleteResponse>> {
    return this.post('/api/v1/files/upload/complete', data)
  }

  /**
   * 获取上传进度
   */
  async getUploadProgress(fileId: string): Promise<ApiResponse<FileTransferProgress>> {
    return this.get(`/api/v1/files/${fileId}/progress`)
  }

  /**
   * 下载文件
   */
  async downloadFile(fileId: string): Promise<Blob> {
    const url = `${this.baseURL}/api/v1/files/${fileId}/download`
    const headers: HeadersInit = {}
    if (this.token) {
      headers['Authorization'] = `Bearer ${this.token}`
    }

    const response = await fetch(url, { headers })
    if (!response.ok) {
      throw new ApiClientError('DOWNLOAD_FAILED', 'Failed to download file')
    }
    return response.blob()
  }

  /**
   * 获取文件下载 URL
   */
  getFileDownloadUrl(fileId: string): string {
    return `${this.baseURL}/api/v1/files/${fileId}/download`
  }

  // ==================== 群聊 API (Group Chat) ====================

  /**
   * 创建群组
   */
  async createGroup(data: GroupCreateData): Promise<ApiResponse<{
    id: number
    name: string
    avatar?: string
    ownerId: string
    memberCount: number
    createdAt: number
  }>> {
    return this.post('/api/v1/groups', data)
  }

  /**
   * 获取我的群组列表
   */
  async getGroups(): Promise<ApiResponse<Group[]>> {
    return this.get('/api/v1/groups')
  }

  /**
   * 获取群组详情
   */
  async getGroup(groupId: number): Promise<ApiResponse<Group & {
    members: GroupMember[]
  }>> {
    return this.get(`/api/v1/groups/${groupId}`)
  }

  /**
   * 更新群组信息
   */
  async updateGroup(groupId: number, data: {
    name?: string
    avatar?: string
    announcement?: string
    invitePrivacy?: 'all' | 'owner' | 'admin'
  }): Promise<ApiResponse<void>> {
    return this.put(`/api/v1/groups/${groupId}`, data)
  }

  /**
   * 删除群组
   */
  async deleteGroup(groupId: number): Promise<ApiResponse<void>> {
    return this.request(`/api/v1/groups/${groupId}`, { method: 'DELETE' })
  }

  /**
   * 获取群成员列表
   */
  async getGroupMembers(groupId: number): Promise<ApiResponse<GroupMember[]>> {
    return this.get(`/api/v1/groups/${groupId}/members`)
  }

  /**
   * 添加群成员
   */
  async addGroupMember(groupId: number, memberId: string, data?: {
    role?: 'admin' | 'member'
    nickname?: string
  }): Promise<ApiResponse<void>> {
    return this.post(`/api/v1/groups/${groupId}/members`, { memberId, ...data })
  }

  /**
   * 移除群成员
   */
  async removeGroupMember(groupId: number, userId: string): Promise<ApiResponse<void>> {
    return this.request(`/api/v1/groups/${groupId}/members/${userId}`, { method: 'DELETE' })
  }

  /**
   * 更新成员角色
   */
  async updateMemberRole(groupId: number, userId: string, role: 'admin' | 'member'): Promise<ApiResponse<void>> {
    return this.put(`/api/v1/groups/${groupId}/members/${userId}`, { role })
  }

  /**
   * 设置成员昵称
   */
  async setMemberNickname(groupId: number, userId: string, nickname: string): Promise<ApiResponse<void>> {
    return this.put(`/api/v1/groups/${groupId}/members/${userId}`, { nickname })
  }

  // ==================== 语音/视频通话 API (Call) ====================

  /**
   * 创建通话
   */
  async createCall(data: {
    calleeId: string
    type?: 'voice' | 'video'
    conversationId?: number
    offer?: boolean
  }): Promise<ApiResponse<{
    id: string
    callerId: string
    calleeId: string
    type: 'voice' | 'video'
    status: string
  }>> {
    return this.post('/api/v1/calls', data)
  }

  /**
   * 获取通话信息
   */
  async getCall(callId: string): Promise<ApiResponse<{
    id: string
    callerId: string
    calleeId: string
    conversationId: number
    type: 'voice' | 'video'
    status: string
    duration: number
    startedAt?: number
    endedAt?: number
    createdAt: number
  }>> {
    return this.get(`/api/v1/calls/${callId}`)
  }

  /**
   * 接听通话
   */
  async answerCall(callId: string): Promise<ApiResponse<void>> {
    return this.post(`/api/v1/calls/${callId}/answer`)
  }

  /**
   * 拒绝通话
   */
  async rejectCall(callId: string): Promise<ApiResponse<void>> {
    return this.post(`/api/v1/calls/${callId}/reject`)
  }

  /**
   * 结束通话
   */
  async endCall(callId: string): Promise<ApiResponse<void>> {
    return this.post(`/api/v1/calls/${callId}/end`)
  }

  /**
   * 发送 SDP Offer
   */
  async sendOffer(callId: string, offer: RTCSessionDescriptionInit): Promise<ApiResponse<void>> {
    return this.post(`/api/v1/calls/${callId}/offer`, { offer })
  }

  /**
   * 发送 SDP Answer
   */
  async sendAnswer(callId: string, answer: RTCSessionDescriptionInit): Promise<ApiResponse<void>> {
    return this.post(`/api/v1/calls/${callId}/answer`, { answer })
  }

  /**
   * 发送 ICE Candidate
   */
  async sendIceCandidate(callId: string, candidate: RTCIceCandidateInit): Promise<ApiResponse<void>> {
    return this.post(`/api/v1/calls/${callId}/ice`, { candidate })
  }

  /**
   * 获取通话历史
   */
  async getCallHistory(params?: { limit?: number; offset?: number }): Promise<ApiResponse<{
    id: string
    callerId: string
    calleeId: string
    conversationId: number
    type: 'voice' | 'video'
    status: string
    duration: number
    startedAt?: number
    endedAt?: number
    createdAt: number
  }[]>> {
    const queryParams = new URLSearchParams()
    if (params?.limit) queryParams.append('limit', String(params.limit))
    if (params?.offset) queryParams.append('offset', String(params.offset))
    return this.get(`/api/v1/calls/history?${queryParams.toString()}`)
  }

  // ==================== 隐私增强 API (Privacy) ====================

  /**
   * 设置阅后即焚
   */
  async setDisappearingMessages(conversationId: number, enabled: boolean, timerSeconds?: number): Promise<ApiResponse<void>> {
    return this.put(`/api/v1/conversations/${conversationId}/disappearing`, { enabled, timerSeconds })
  }

  /**
   * 获取阅后即焚设置
   */
  async getDisappearingMessages(conversationId: number): Promise<ApiResponse<{
    enabled: boolean
    timerSeconds: number
    timerStart: 'IMMEDIATE' | 'FIRST_READ'
  }>> {
    return this.get(`/api/v1/conversations/${conversationId}/disappearing`)
  }

  /**
   * 删除消息（双向）
   */
  async deleteMessageForAll(messageId: number, reason?: string): Promise<ApiResponse<void>> {
    return this.post(`/api/v1/messages/${messageId}/delete-all`, { reason })
  }

  /**
   * 删除消息（仅自己）
   */
  async deleteMessageForSelf(messageId: number): Promise<ApiResponse<void>> {
    return this.post(`/api/v1/messages/${messageId}/delete-self`)
  }

  /**
   * 获取隐私设置
   */
  async getPrivacySettings(): Promise<ApiResponse<{
    metadataMinimization: boolean
    metadataRetentionHours: number
    deleteForEveryoneTimeLimit: number
    disappearingMessageTimers: number[]
  }>> {
    return this.get('/api/v1/privacy/settings')
  }

  /**
   * 获取隐私统计
   */
  async getPrivacyStats(): Promise<ApiResponse<{
    disappearingConversations: number
    scheduledDeletions: number
    metadataMinimizationEnabled: boolean
    metadataRetentionHours: number
  }>> {
    return this.get('/api/v1/privacy/stats')
  }

  // ==================== 消息表情回应 API ====================

  /**
   * 获取消息反应列表
   */
  async getMessageReactions(messageId: number): Promise<ApiResponse<{
    id: number
    emoji: string
    userIds: string[]
    count: number
    createdAt: number
  }[]>> {
    return this.get(`/api/v1/messages/${messageId}/reactions`)
  }

  /**
   * 添加消息反应
   */
  async addReaction(messageId: number, emoji: string): Promise<ApiResponse<{
    id: number
    emoji: string
    count: number
  }>> {
    return this.post(`/api/v1/messages/${messageId}/reactions/${encodeURIComponent(emoji)}`)
  }

  /**
   * 移除消息反应
   */
  async removeReaction(messageId: number, emoji: string): Promise<ApiResponse<void>> {
    return this.delete(`/api/v1/messages/${messageId}/reactions/${encodeURIComponent(emoji)}`)
  }

  // ==================== 群公告 API ====================

  /**
   * 获取群公告详情
   */
  async getGroupAnnouncement(groupId: number): Promise<ApiResponse<{
    announcement: string
    announcementEditorId: string
    announcementUpdatedAt: number
  }>> {
    return this.get(`/api/v1/groups/${groupId}/announcement`)
  }

  /**
   * 更新群公告
   */
  async updateGroupAnnouncement(groupId: number, announcement: string): Promise<ApiResponse<void>> {
    return this.put(`/api/v1/groups/${groupId}/announcement`, { announcement })
  }

  /**
   * 获取群公告历史
   */
  async getGroupAnnouncementHistory(groupId: number): Promise<ApiResponse<{
    id: number
    groupId: number
    userId: string
    action: string
    createdAt: number
  }[]>> {
    return this.get(`/api/v1/groups/${groupId}/announcement/history`)
  }

  // ==================== 消息置顶 API ====================

  async getPinnedMessages(conversationId: number): Promise<ApiResponse<PinnedMessage[]>> {
    return this.get(`/api/v1/conversations/${conversationId}/pinned-messages`)
  }

  async pinMessage(messageId: number, conversationId: number): Promise<ApiResponse<void>> {
    return this.post(`/api/v1/messages/${messageId}/pin`, { conversationId })
  }

  async unpinMessage(messageId: number, conversationId: number): Promise<ApiResponse<void>> {
    return this.post(`/api/v1/messages/${messageId}/unpin`, { conversationId })
  }

  // ==================== 消息转发 API ====================

  async forwardMessage(messageId: number, conversationId: number): Promise<ApiResponse<void>> {
    return this.post(`/api/v1/messages/${messageId}/forward`, { conversationId })
  }

  // ==================== 会话管理 API ====================

  async pinConversation(conversationId: number): Promise<ApiResponse<void>> {
    return this.post(`/api/v1/conversations/${conversationId}/pin`)
  }

  async unpinConversation(conversationId: number): Promise<ApiResponse<void>> {
    return this.post(`/api/v1/conversations/${conversationId}/unpin`)
  }

  async muteConversation(conversationId: number): Promise<ApiResponse<void>> {
    return this.post(`/api/v1/conversations/${conversationId}/mute`)
  }

  async unmuteConversation(conversationId: number): Promise<ApiResponse<void>> {
    return this.post(`/api/v1/conversations/${conversationId}/unmute`)
  }

  async deleteConversation(conversationId: number): Promise<ApiResponse<void>> {
    return this.delete(`/api/v1/conversations/${conversationId}`)
  }

  // ==================== 通知偏好设置 API ====================

  async getNotificationPreferences(): Promise<ApiResponse<NotificationPreferences>> {
    return this.get('/api/v1/notifications/preferences')
  }

  async updateNotificationPreferences(prefs: Partial<NotificationPreferences>): Promise<ApiResponse<void>> {
    return this.put('/api/v1/notifications/preferences', prefs)
  }

  // ==================== 用户通知 API ====================

  async getNotifications(params?: { limit?: number; unread?: boolean }): Promise<ApiResponse<UserNotification[]>> {
    const queryParams = new URLSearchParams()
    if (params?.limit) queryParams.append('limit', params.limit.toString())
    if (params?.unread) queryParams.append('unread', 'true')
    const query = queryParams.toString()
    return this.get(`/api/v1/notifications${query ? `?${query}` : ''}`)
  }

  async markNotificationAsRead(notificationId: number): Promise<ApiResponse<void>> {
    return this.post(`/api/v1/notifications/${notificationId}/read`)
  }

  async markAllNotificationsAsRead(): Promise<ApiResponse<void>> {
    return this.post('/api/v1/notifications/read-all')
  }

  // ==================== 语音消息 API ====================

  /**
   * 上传语音消息
   */
  async uploadVoice(file: File, duration: number): Promise<ApiResponse<{ url: string; waveform: number[] }>> {
    const formData = new FormData()
    formData.append('file', file)
    formData.append('duration', String(duration))

    return this.post('/api/v1/upload/voice', formData as unknown as Record<string, string> | undefined)
  }

  // ==================== 用户状态/动态 API ====================

  /**
   * 获取好友状态列表
   */
  async getStatusUpdates(): Promise<ApiResponse<UserStatus[]>> {
    return this.get('/api/v1/status/friends')
  }

  /**
   * 获取用户状态详情
   */
  async getStatus(statusId: number): Promise<ApiResponse<UserStatus>> {
    return this.get(`/api/v1/status/${statusId}`)
  }

  /**
   * 发布状态
   */
  async createStatus(data: {
    content: string
    mediaType?: 'image' | 'video' | 'text'
    mediaFile?: File
    expiresIn?: number
  }): Promise<ApiResponse<UserStatus>> {
    const formData = new FormData()
    formData.append('content', data.content)
    if (data.mediaType) formData.append('mediaType', data.mediaType)
    if (data.mediaFile) formData.append('mediaFile', data.mediaFile)
    if (data.expiresIn) formData.append('expiresIn', String(data.expiresIn))

    return this.post('/api/v1/status', formData)
  }

  /**
   * 删除状态
   */
  async deleteStatus(statusId: number): Promise<ApiResponse<void>> {
    return this.request(`/api/v1/status/${statusId}`, { method: 'DELETE' })
  }

  /**
   * 查看状态（增加观看次数）
   */
  async viewStatus(statusId: number): Promise<ApiResponse<void>> {
    return this.post(`/api/v1/status/${statusId}/view`)
  }

  // ==================== 聊天文件夹 API ====================

  /**
   * 获取聊天文件夹列表
   */
  async getChatFolders(): Promise<ApiResponse<ChatFolder[]>> {
    return this.get('/api/v1/chat-folders')
  }

  /**
   * 创建聊天文件夹
   */
  async createChatFolder(data: { name: string; icon?: string; conversationIds?: number[] }): Promise<ApiResponse<ChatFolder>> {
    return this.post('/api/v1/chat-folders', data)
  }

  /**
   * 更新聊天文件夹
   */
  async updateChatFolder(folderId: number, data: Partial<ChatFolder>): Promise<ApiResponse<ChatFolder>> {
    return this.put(`/api/v1/chat-folders/${folderId}`, data)
  }

  /**
   * 删除聊天文件夹
   */
  async deleteChatFolder(folderId: number): Promise<ApiResponse<void>> {
    return this.request(`/api/v1/chat-folders/${folderId}`, { method: 'DELETE' })
  }

  /**
   * 获取文件夹内的对话
   */
  async getFolderConversations(folderId: number): Promise<ApiResponse<Conversation[]>> {
    return this.get(`/api/v1/chat-folders/${folderId}/conversations`)
  }

  // ==================== 频道 API ====================

  /**
   * 获取群频道列表
   */
  async getGroupChannels(groupId: number): Promise<ApiResponse<Channel[]>> {
    return this.get(`/api/v1/groups/${groupId}/channels`)
  }

  /**
   * 创建频道
   */
  async createChannel(groupId: number, data: { name: string; type: 'text' | 'voice'; parentId?: number }): Promise<ApiResponse<Channel>> {
    return this.post(`/api/v1/groups/${groupId}/channels`, data)
  }

  /**
   * 更新频道
   */
  async updateChannel(groupId: number, channelId: number, data: Partial<Channel>): Promise<ApiResponse<Channel>> {
    return this.put(`/api/v1/groups/${groupId}/channels/${channelId}`, data)
  }

  /**
   * 删除频道
   */
  async deleteChannel(groupId: number, channelId: number): Promise<ApiResponse<void>> {
    return this.request(`/api/v1/groups/${groupId}/channels/${channelId}`, { method: 'DELETE' })
  }

  /**
   * 切换频道
   */
  async switchChannel(channelId: number): Promise<ApiResponse<Channel>> {
    return this.post(`/api/v1/channels/${channelId}/switch`)
  }

  // ==================== 消息搜索 API ====================

  /**
   * 全局搜索消息
   */
  async searchMessages(options: SearchOptions): Promise<ApiResponse<SearchResult[]>> {
    const params = new URLSearchParams()
    params.append('q', options.query)

    if (options.conversationId) params.append('conversationId', String(options.conversationId))
    if (options.senderId) params.append('senderId', options.senderId)
    if (options.startDate) params.append('startDate', String(options.startDate))
    if (options.endDate) params.append('endDate', String(options.endDate))
    if (options.messageType) params.append('messageType', options.messageType)
    if (options.limit) params.append('limit', String(options.limit))
    if (options.offset) params.append('offset', String(options.offset))

    return this.get(`/api/v1/messages/search?${params.toString()}`)
  }

  /**
   * 搜索对话内消息
   */
  async searchInConversation(conversationId: number, query: string, options?: { limit?: number; offset?: number }): Promise<ApiResponse<SearchResult[]>> {
    const params = new URLSearchParams({ q: query })
    if (options?.limit) params.append('limit', String(options.limit))
    if (options?.offset) params.append('offset', String(options.offset))

    return this.get(`/api/v1/conversations/${conversationId}/messages/search?${params.toString()}`)
  }

  /**
   * 搜索对话内媒体文件
   */
  async getConversationMedia(conversationId: number, type?: 'image' | 'video' | 'file' | 'link', options?: { limit?: number; offset?: number }): Promise<ApiResponse<Message[]>> {
    const params = new URLSearchParams()
    if (type) params.append('type', type)
    if (options?.limit) params.append('limit', String(options.limit))
    if (options?.offset) params.append('offset', String(options.offset))

    return this.get(`/api/v1/conversations/${conversationId}/media?${params.toString()}`)
  }

  /**
   * 搜索对话内链接
   */
  async getConversationLinks(conversationId: number, options?: { limit?: number }): Promise<ApiResponse<Message[]>> {
    const params = new URLSearchParams()
    if (options?.limit) params.append('limit', String(options.limit))

    return this.get(`/api/v1/conversations/${conversationId}/links?${params.toString()}`)
  }

  // ==================== 消息表情回应扩展 API ====================

  /**
   * 获取消息反应详情（带用户列表）
   */
  async getMessageReactionsDetail(messageId: number): Promise<ApiResponse<MessageReaction[]>> {
    return this.get(`/api/v1/messages/${messageId}/reactions/detail`)
  }

  /**
   * 获取常用表情列表
   */
  async getFrequentReactions(limit?: number): Promise<ApiResponse<{ emoji: string; count: number }[]>> {
    const params = limit ? `?limit=${limit}` : ''
    return this.get(`/api/v1/reactions/frequent${params}`)
  }

  /**
   * 获取自定义表情包列表
   */
  async getCustomEmojiPacks(): Promise<ApiResponse<{ id: number; name: string; emojis: Array<{ id: string; url: string }> }[]>> {
    return this.get('/api/v1/emoji-packs')
  }

  /**
   * 添加自定义表情
   */
  async addCustomEmoji(file: File, name: string): Promise<ApiResponse<{ id: string; url: string }>> {
    const formData = new FormData()
    formData.append('file', file)
    formData.append('name', name)

    return this.post('/api/v1/emoji', formData)
  }

  // ==================== 群投票 API ====================

  async getGroupPolls(groupId: number, status?: 'active' | 'ended' | 'archived'): Promise<ApiResponse<GroupPoll[]>> {
    const params = new URLSearchParams()
    if (status) params.append('status', status)
    const query = params.toString()
    return this.get(`/api/v1/groups/${groupId}/polls${query ? `?${query}` : ''}`)
  }

  async createPoll(groupId: number, poll: CreatePollData): Promise<ApiResponse<GroupPoll>> {
    return this.post(`/api/v1/groups/${groupId}/polls`, poll)
  }

  async getPoll(pollId: number): Promise<ApiResponse<GroupPoll>> {
    return this.get(`/api/v1/polls/${pollId}`)
  }

  async castVote(pollId: number, optionId: number): Promise<ApiResponse<void>> {
    return this.post(`/api/v1/polls/${pollId}/vote`, { optionId })
  }

  async endPoll(pollId: number): Promise<ApiResponse<void>> {
    return this.post(`/api/v1/polls/${pollId}/end`)
  }
}

// ==================== 朋友圈类型定义 ====================

export interface Moment {
  id: number
  user_id: string
  username: string
  display_name: string
  avatar: string
  content: string
  photos: string[]
  type: 'text' | 'image' | 'video' | 'link'
  location: string
  created_at: number
  likes_count: number
  comments_count: number
  liked_by: string[]
  comments: MomentComment[]
  visibility: 'public' | 'friends' | 'private'
}

export interface MomentComment {
  id: number
  post_id: number
  user_id: string
  username: string
  display_name: string
  avatar: string
  content: string
  reply_to_user_id: string
  reply_to_username: string
  created_at: number
}

// ==================== 通讯录类型定义 ====================

export interface ContactGroup {
  id: number
  user_id: string
  name: string
  order: number
  created_at: number
}

export interface ContactTag {
  id: number
  user_id: string
  name: string
  color: string
  created_at: number
}

export interface ContactRemark {
  friend_id: string
  user_id: string
  remark: string
  description?: string
  phone?: string
  email?: string
  company?: string
  birthday?: string
  created_at: number
  updated_at: number
}

export interface BlacklistEntry {
  id: number
  user_id: string
  blocked_id: string
  blocked_username: string
  blocked_display_name?: string
  blocked_avatar?: string
  created_at: number
}

export interface StarContact {
  id: number
  user_id: string
  starred_id: string
  starred_username: string
  starred_display_name?: string
  starred_avatar?: string
  created_at: number
}

export interface UserSession {
  id: string
  user_id: string
  device: string
  ip_address: string
  location: string
  last_active: number
  current: boolean
}

export interface UserProfile {
  id: string
  username: string
  displayName: string
  email?: string
  phone?: string
  avatar?: string
  bio?: string
  gender?: 'male' | 'female' | 'other'
  birthday?: string
  location?: string
  company?: string
  website?: string
  created_at: number
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
