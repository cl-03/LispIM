package com.lispim.app.data.websocket

import kotlinx.coroutines.flow.StateFlow

/**
 * WebSocket connection state
 */
sealed class ConnectionState {
    object Disconnected : ConnectionState()
    object Connecting : ConnectionState()
    object Connected : ConnectionState()
    object Reconnecting : ConnectionState()
    data class Error(val message: String, val code: Int? = null) : ConnectionState()
}

/**
 * WebSocket message types
 */
sealed class WebSocketMessage {
    // Incoming messages
    data class NewMessage(val data: MessageData) : WebSocketMessage()
    data class MessageRead(val messageId: String, val readAt: Long) : WebSocketMessage()
    data class UserPresence(val userId: String, val online: Boolean) : WebSocketMessage()
    data class TypingIndicator(val conversationId: String, val userId: String) : WebSocketMessage()
    data class MessageRecalled(val messageId: String) : WebSocketMessage()

    // Outgoing messages
    data class SendMessage(val conversationId: String, val content: String, val type: String = "text") : WebSocketMessage()
    data class AckMessage(val messageId: String) : WebSocketMessage()
    object Heartbeat : WebSocketMessage()
    data class AuthMessage(val token: String) : WebSocketMessage()
    data class PresenceUpdate(val status: String) : WebSocketMessage()
    data class TypingUpdate(val conversationId: String) : WebSocketMessage()
}

data class MessageData(
    val id: String,
    val conversationId: String,
    val senderId: String,
    val content: String,
    val type: String,
    val createdAt: Long,
    val sequence: Long
)

/**
 * WebSocket Manager Interface
 */
interface WebSocketManager {
    val connectionState: StateFlow<ConnectionState>

    fun connect(token: String)
    fun disconnect()
    fun sendMessage(conversationId: String, content: String, type: String)
    fun sendAck(messageId: String)
    fun sendTypingIndicator(conversationId: String)
    fun updatePresence(status: String)

    // Message listeners
    fun onMessage(callback: (WebSocketMessage) -> Unit)
    fun onConnectionStateChange(callback: (ConnectionState) -> Unit)
}
