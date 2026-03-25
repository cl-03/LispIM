import { io, Socket } from 'socket.io-client'
import type { Message, Conversation, WebSocketMessage } from '@/types'
import { encryptMessage } from '@/utils/crypto'

export interface WebSocketConfig {
  url: string
  token?: string
  userId?: string
}

export class LispIMWebSocket {
  private socket: Socket | null = null
  private config: WebSocketConfig
  private messageHandlers: Map<string, Set<(data: unknown) => void>> = new Map()
  private maxReconnectAttempts = 5
  private reconnectDelay = 1000

  constructor(config: WebSocketConfig) {
    this.config = config
  }

  connect(): Promise<void> {
    return new Promise((resolve, reject) => {
      try {
        this.socket = io(this.config.url, {
          transports: ['websocket'],
          auth: {
            token: this.config.token
          },
          reconnection: true,
          reconnectionAttempts: this.maxReconnectAttempts,
          reconnectionDelay: this.reconnectDelay
        })

        this.socket.on('connect', () => {
          console.log('[WebSocket] Connected')
          resolve()
        })

        this.socket.on('disconnect', (reason) => {
          console.log('[WebSocket] Disconnected:', reason)
          this.emit('disconnect', { reason })
        })

        this.socket.on('connect_error', (error) => {
          console.error('[WebSocket] Connection error:', error)
          reject(error)
        })

        // 消息处理
        this.socket.on('message', (data: Message) => {
          this.handleIncomingMessage(data)
        })

        // 会话更新
        this.socket.on('conversation:update', (data: Conversation) => {
          this.emit('conversation:update', data)
        })

        // 用户状态变化
        this.socket.on('user:status', (data: { userId: string; status: string }) => {
          this.emit('user:status', data)
        })

        // 已读回执
        this.socket.on('message:read', (data: { messageId: number; userId: string; timestamp: number }) => {
          this.emit('message:read', data)
        })

        // 心跳响应
        this.socket.on('pong', () => {
          this.emit('heartbeat', { timestamp: Date.now() })
        })

      } catch (error) {
        reject(error)
      }
    })
  }

  disconnect(): void {
    if (this.socket) {
      this.socket.disconnect()
      this.socket = null
    }
  }

  sendMessage(conversationId: number, content: string, type: 'text' | 'image' | 'file' = 'text'): void {
    if (!this.socket?.connected) {
      console.error('[WebSocket] Not connected')
      return
    }

    const message: WebSocketMessage = {
      type: 'message:send',
      payload: {
        conversationId,
        content,
        messageType: type,
        timestamp: Date.now()
      },
      timestamp: Date.now()
    }

    this.socket.emit('message:send', message.payload)
  }

  sendEncryptedMessage(conversationId: number, content: string, recipientKey: string): void {
    const encrypted = encryptMessage(content, recipientKey)
    this.sendMessage(conversationId, encrypted, 'text')
  }

  readMessage(messageId: number): void {
    if (!this.socket?.connected) return
    this.socket.emit('message:read', { messageId, timestamp: Date.now() })
  }

  subscribe(conversationId: number): void {
    if (!this.socket?.connected) return
    this.socket.emit('conversation:subscribe', { conversationId })
  }

  unsubscribe(conversationId: number): void {
    if (!this.socket?.connected) return
    this.socket.emit('conversation:unsubscribe', { conversationId })
  }

  sendHeartbeat(): void {
    if (!this.socket?.connected) return
    this.socket.emit('heartbeat')
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

  private async handleIncomingMessage(message: Message): Promise<void> {
    try {
      // 如果是加密消息，解密
      if (message.encrypted && message.content) {
        // 解密逻辑在 store 中处理
      }
      this.emit('message', message)
    } catch (error) {
      console.error('[WebSocket] Error handling message:', error)
    }
  }

  isConnected(): boolean {
    return this.socket?.connected ?? false
  }
}

// 创建单例
let wsInstance: LispIMWebSocket | null = null

export function getWebSocket(config: WebSocketConfig): LispIMWebSocket {
  if (!wsInstance) {
    wsInstance = new LispIMWebSocket(config)
  }
  return wsInstance
}
