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
  TYPING: 'typing'
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
  private maxReconnectAttempts = 5
  private reconnectDelay = 1000
  private ackTimeout = 5000 // ACK 超时时间 5 秒
  private reconnectTimer: ReturnType<typeof setTimeout> | null = null
  private heartbeatTimer: ReturnType<typeof setTimeout> | null = null
  private heartbeatInterval = 30000 // 30 秒心跳

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

        this.socket = new WebSocket(wsUrl)

        this.socket.onopen = () => {
          console.log('[WebSocket] Connected')
          // 连接后发送认证消息
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
   * 启动重连
   */
  private startReconnect(): void {
    this.stopReconnect()
    let attempts = 0
    this.reconnectTimer = setInterval(() => {
      if (attempts >= this.maxReconnectAttempts) {
        this.stopReconnect()
        return
      }
      console.log('[WebSocket] Reconnecting... attempt', attempts + 1)
      this.connect().catch(() => {
        attempts++
      })
    }, this.reconnectDelay)
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
