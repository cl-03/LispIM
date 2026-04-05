// WebSocket Protocol v1 消息类型
export const WS_MSG_TYPE = {
  AUTH: 'auth',
  AUTH_RESPONSE: 'auth-response',
  MESSAGE: 'message',
  MESSAGE_RECEIVED: 'message-received',
  MESSAGE_DELIVERED: 'message-delivered',
  MESSAGE_READ: 'message-read',
  PING: 'ping',
  PONG: 'pong',
  ERROR: 'error',
  NOTIFICATION: 'notification',
  PRESENCE: 'presence',
  TYPING: 'typing',
  SYNC_REQUEST: 'sync-request',
  SYNC_RESPONSE: 'sync-response'
} as const

// ACK 类型
export type AckType = 'received' | 'delivered' | 'read'

// WebSocket 消息接口
export interface WSMessage<T = unknown> {
  type: string
  payload: T
  version: string
  timestamp: number
  messageId?: string
  ackRequired?: boolean
  sequence?: number  // 新增序列号用于验证消息顺序
}

// ACK 消息接口
export interface WSAck {
  messageId: string
  ackType: AckType
  timestamp: number
  error?: string
}

// 发送消息的 payload
export interface SendMessagePayload {
  conversationId: number
  content: string
  type?: 'text' | 'image' | 'file'
  replyTo?: number
  mentions?: string[]
  attachments?: Array<{
    type: string
    url: string
    size: number
    name: string
  }>
}

// 认证 payload
export interface AuthPayload {
  token: string
  userId: string
}

export interface WebSocketConfig {
  url: string
  token?: string
  userId?: string
}

// 待确认消息跟踪
interface PendingMessage {
  messageId: string
  timestamp: number
  resolve: () => void
  reject: (error: Error) => void
  timeoutId: ReturnType<typeof setTimeout>
}

export class LispIMWebSocket {
  private socket: WebSocket | null = null
  public config: WebSocketConfig
  private messageHandlers: Map<string, Set<(data: unknown) => void>> = new Map()
  private pendingMessages: Map<string, PendingMessage> = new Map()
  private maxReconnectAttempts = 10
  private reconnectDelay = 1000
  private ackTimeout = 3000 // ACK 超时时间 3 秒（优化降低延迟）
  private reconnectTimer: ReturnType<typeof setTimeout> | null = null
  private heartbeatTimer: ReturnType<typeof setTimeout> | null = null
  private heartbeatInterval = 15000 // 15 秒心跳（优化提高响应性）
  private reconnectBackoffMultiplier = 1.5 // 指数退避 multiplier

  // 新增：序列号跟踪
  private lastSequenceReceived: number = 0
  private seenMessageIds: Map<string, number> = new Map()  // 消息去重
  private readonly SEEN_TTL = 5 * 60 * 1000  // 5 分钟

  // 同步状态（预留）
  // private lastSyncAnchorSeq: number = 0

  constructor(config: WebSocketConfig) {
    this.config = config
  }

  connect(): Promise<void> {
    return new Promise((resolve, reject) => {
      try {
        // 使用原生 WebSocket 连接到 /ws 端点
        const wsUrl = this.config.url.startsWith('http')
          ? this.config.url.replace('http', 'ws')
          : this.config.url

        // 优化 1: 使用 WebSocket 子协议在握手时认证
        const protocols: string[] = ['lispim-v1']
        if (this.config.token) {
          protocols.push(`Bearer:${this.config.token}`)
        }

        this.socket = new WebSocket(wsUrl, protocols)

        this.socket.onopen = () => {
          console.log('[WebSocket] Connected with protocols:', this.socket?.protocol)
          // 连接后仍然发送认证消息作为后备
          this.sendAuth()
          // 启动心跳
          this.startHeartbeat()
          resolve()
        }

        this.socket.onclose = (event) => {
          console.log('[WebSocket] Disconnected:', event.reason)
          this.emit('disconnect', { reason: event.reason })
          // 清理定时器
          this.stopHeartbeat()
          // 启动重连
          this.startReconnect()
        }

        this.socket.onerror = (error) => {
          console.error('[WebSocket] Connection error:', error)
          reject(error)
        }

        // 监听消息
        this.socket.onmessage = (event) => {
          try {
            const message: WSMessage = JSON.parse(event.data)
            // 优化 2: 验证序列号
            if (!this.verifySequence(message)) {
              console.warn('[WebSocket] Out of order message:', message.sequence)
              return
            }
            // 优化 3: 消息去重
            if (this.isDuplicateMessage(message)) {
              console.log('[WebSocket] Duplicate message ignored:', message.messageId)
              return
            }
            this.handleProtocolMessage(message)
          } catch (e) {
            console.error('[WebSocket] Failed to parse message:', e)
          }
        }
      } catch (error) {
        reject(error)
      }
    })
  }

  /**
   * 验证序列号连续性
   */
  private verifySequence(message: WSMessage): boolean {
    const seq = message.sequence
    if (seq === undefined) return true  // 没有序列号则跳过验证

    if (seq <= this.lastSequenceReceived) {
      console.warn('[WebSocket] Out of order: expected >', this.lastSequenceReceived, 'got', seq)
      return false
    }
    this.lastSequenceReceived = seq
    return true
  }

  /**
   * 检查消息是否重复
   */
  private isDuplicateMessage(message: WSMessage): boolean {
    const msgId = message.messageId
    if (!msgId) return false

    const now = Date.now()
    const seenTime = this.seenMessageIds.get(msgId)

    if (seenTime !== undefined) {
      // 检查是否过期
      if (now - seenTime > this.SEEN_TTL) {
        this.seenMessageIds.delete(msgId)
        return false
      }
      return true  // 重复消息
    }

    // 记录新消息
    this.seenMessageIds.set(msgId, now)

    // 定期清理过期记录
    if (this.seenMessageIds.size > 1000) {
      const cutoff = now - this.SEEN_TTL
      for (const [id, time] of this.seenMessageIds.entries()) {
        if (time < cutoff) this.seenMessageIds.delete(id)
      }
    }

    return false
  }

  /**
   * 处理 Protocol v1 消息
   */
  private handleProtocolMessage(message: WSMessage): void {
    const { type, payload, messageId, ackRequired } = message

    // 如果是需要 ACK 的消息，发送确认
    if (ackRequired && messageId) {
      this.sendAck(messageId, 'received')
    }

    switch (type) {
      case WS_MSG_TYPE.AUTH_RESPONSE:
        this.emit('auth:response', payload)
        break

      case WS_MSG_TYPE.MESSAGE:
        this.emit('message', payload)
        break

      case WS_MSG_TYPE.MESSAGE_RECEIVED:
      case WS_MSG_TYPE.MESSAGE_DELIVERED:
      case WS_MSG_TYPE.MESSAGE_READ:
        // 处理 ACK
        this.handleAck(payload as WSAck)
        break

      case WS_MSG_TYPE.PING:
        this.sendPong(payload as { timestamp: number })
        break

      case WS_MSG_TYPE.PRESENCE:
        this.emit('presence:update', payload)
        break

      case WS_MSG_TYPE.TYPING:
        this.emit('typing:update', payload)
        break

      case WS_MSG_TYPE.ERROR:
        this.emit('error', payload)
        break

      default:
        // 兼容旧版消息类型
        this.emit(type, payload)
        break
    }
  }

  /**
   * 处理 ACK
   */
  private handleAck(ack: WSAck): void {
    const pending = this.pendingMessages.get(ack.messageId)
    if (pending) {
      clearTimeout(pending.timeoutId)
      this.pendingMessages.delete(ack.messageId)

      if (ack.error) {
        pending.reject(new Error(ack.error))
      } else {
        pending.resolve()
      }
    }
  }

  disconnect(): void {
    // 停止重连
    this.stopReconnect()
    // 停止心跳
    this.stopHeartbeat()

    if (this.socket) {
      this.socket.close()
      this.socket = null
    }
    // 清理所有待确认消息
    this.pendingMessages.forEach((pending) => {
      clearTimeout(pending.timeoutId)
      pending.reject(new Error('Disconnected'))
    })
    this.pendingMessages.clear()
  }

  /**
   * 启动心跳
   */
  private startHeartbeat(): void {
    this.stopHeartbeat()
    this.heartbeatTimer = setInterval(() => {
      if (this.isConnected()) {
        this.sendHeartbeat()
      }
    }, this.heartbeatInterval)
  }

  private stopHeartbeat(): void {
    if (this.heartbeatTimer) {
      clearInterval(this.heartbeatTimer)
      this.heartbeatTimer = null
    }
  }

  /**
   * 启动重连（指数退避）
   */
  private startReconnect(): void {
    this.stopReconnect()
    let attempts = 0
    let currentDelay = this.reconnectDelay

    const attemptReconnect = () => {
      if (attempts >= this.maxReconnectAttempts) {
        this.stopReconnect()
        console.error('[WebSocket] Max reconnect attempts reached')
        return
      }

      attempts++
      console.log('[WebSocket] Reconnecting... attempt', attempts, 'in', currentDelay, 'ms')

      this.reconnectTimer = setTimeout(async () => {
        try {
          await this.connect()
          // 连接成功，重置延迟
          currentDelay = this.reconnectDelay
        } catch {
          // 连接失败，增加延迟（指数退避）
          currentDelay = Math.min(currentDelay * this.reconnectBackoffMultiplier, 30000)
          attemptReconnect()
        }
      }, currentDelay)
    }

    attemptReconnect()
  }

  private stopReconnect(): void {
    if (this.reconnectTimer) {
      clearInterval(this.reconnectTimer)
      this.reconnectTimer = null
    }
  }

  /**
   * 发送认证消息
   */
  private sendAuth(): void {
    if (!this.config.token || !this.config.userId) return

    const authMessage: WSMessage<AuthPayload> = {
      type: WS_MSG_TYPE.AUTH,
      payload: {
        token: this.config.token,
        userId: this.config.userId
      },
      version: '1.0',
      timestamp: Date.now()
    }

    this.socket?.send(JSON.stringify(authMessage))
  }

  /**
   * 发送消息（支持 ACK）
   */
  sendMessage(conversationId: number, content: string, type: 'text' | 'image' | 'file' = 'text'): Promise<void> {
    return this.sendWSMessage(WS_MSG_TYPE.MESSAGE, {
      conversationId,
      content,
      type
    } as SendMessagePayload, true)
  }

  /**
   * 发送已读回执
   */
  readMessage(messageId: number): void {
    this.sendWSMessage(WS_MSG_TYPE.MESSAGE_READ, {
      messageId,
      timestamp: Date.now()
    }, false)
  }

  /**
   * 订阅会话
   */
  subscribe(conversationId: number): void {
    this.sendWSMessage(WS_MSG_TYPE.PRESENCE, {
      conversationId,
      status: 'online'
    }, false)
  }

  /**
   * 取消订阅会话
   */
  unsubscribe(conversationId: number): void {
    this.sendWSMessage(WS_MSG_TYPE.PRESENCE, {
      conversationId,
      status: 'offline'
    }, false)
  }

  /**
   * 发送输入状态
   */
  sendTyping(conversationId: number, isTyping: boolean): void {
    this.sendWSMessage(WS_MSG_TYPE.TYPING, {
      conversationId,
      isTyping
    }, false)
  }

  /**
   * 发送心跳
   */
  sendHeartbeat(): void {
    this.sendWSMessage(WS_MSG_TYPE.PING, {
      timestamp: Date.now()
    }, false)
  }

  /**
   * 发送 Pong
   */
  private sendPong(data: { timestamp: number }): void {
    this.sendWSMessage(WS_MSG_TYPE.PONG, data, false)
  }

  /**
   * 发送 ACK
   */
  private sendAck(messageId: string, ackType: AckType): void {
    const ackMessage: WSMessage<WSAck> = {
      type: WS_MSG_TYPE.MESSAGE_RECEIVED,
      payload: {
        messageId,
        ackType,
        timestamp: Date.now()
      },
      version: '1.0',
      timestamp: Date.now()
    }

    this.socket?.send(JSON.stringify(ackMessage))
  }

  /**
   * 通用发送消息方法（支持 ACK 跟踪）
   */
  private sendWSMessage(type: string, payload: unknown, ackRequired: boolean): Promise<void> {
    return new Promise((resolve, reject) => {
      if (!this.socket || this.socket.readyState !== WebSocket.OPEN) {
        reject(new Error('WebSocket not connected'))
        return
      }

      const messageId = ackRequired ? `msg-${Date.now()}-${Math.random().toString(36).substr(2, 9)}` : undefined

      const message: WSMessage = {
        type,
        payload,
        version: '1.0',
        timestamp: Date.now()
      }

      if (ackRequired && messageId) {
        message.messageId = messageId
        message.ackRequired = true

        // 设置超时
        const timeoutId = setTimeout(() => {
          this.pendingMessages.delete(messageId)
          reject(new Error('Message acknowledgment timeout'))
        }, this.ackTimeout)

        // 存储待确认消息
        this.pendingMessages.set(messageId, {
          messageId,
          timestamp: Date.now(),
          resolve,
          reject,
          timeoutId
        })
      }

      try {
        this.socket.send(JSON.stringify(message))
        if (!ackRequired) {
          resolve()
        }
      } catch (error) {
        reject(error)
      }
    })
  }

  on(event: string, handler: (data: unknown) => void): void {
    if (!this.messageHandlers.has(event)) {
      this.messageHandlers.set(event, new Set())
    }
    this.messageHandlers.get(event)!.add(handler)
  }

  off(event: string, handler: (data: unknown) => void): void {
    this.messageHandlers.get(event)?.delete(handler)
  }

  private emit(event: string, data: unknown): void {
    this.messageHandlers.get(event)?.forEach(handler => handler(data))
  }

  isConnected(): boolean {
    return this.socket !== null && this.socket.readyState === WebSocket.OPEN
  }

  /**
   * 获取待确认消息数量
   */
  getPendingMessageCount(): number {
    return this.pendingMessages.size
  }
}

// 创建单例
let wsInstance: LispIMWebSocket | null = null

export function getWebSocket(config: WebSocketConfig): LispIMWebSocket {
  // 如果已有实例但已断开连接，创建新实例
  if (wsInstance && !wsInstance.isConnected()) {
    wsInstance.disconnect()
    wsInstance = null
  }

  if (!wsInstance) {
    wsInstance = new LispIMWebSocket(config)
  } else {
    // 如果配置变化，更新配置
    wsInstance.config = config
  }
  return wsInstance
}
