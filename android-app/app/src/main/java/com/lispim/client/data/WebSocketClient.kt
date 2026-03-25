package com.lispim.client.data

import com.lispim.client.model.WSMessage
import com.lispim.client.model.WSState
import io.ktor.client.*
import io.ktor.client.plugins.websocket.*
import io.ktor.client.request.*
import io.ktor.http.*
import io.ktor.websocket.*
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.receiveAsFlow
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import mu.KotlinLogging

private val logger = KotlinLogging.logger {}

/**
 * WebSocket client matching gateway.lisp protocol
 * Reference: Tauri websocket.rs implementation
 */
class WebSocketClient(
    private val wsUrl: String,
    private val token: String
) {
    private val client = HttpClient {
        install(WebSockets) {
            pingInterval = 30000 // 30 seconds
            maxFrameSize = Long.MAX_VALUE
        }
    }

    private val _state = MutableStateFlow(WSState.DISCONNECTED)
    val state: StateFlow<WSState> = _state.asStateFlow()

    private val _messages = kotlinx.coroutines.channels.Channel<WSMessage>(kotlinx.coroutines.channels.Channel.BUFFERED)
    val messages = _messages.receiveAsFlow()

    private var session: WebSocketSession? = null
    private var receiveJob: Job? = null
    private var heartbeatJob: Job? = null

    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    /**
     * Connect to WebSocket server matching gateway.lisp
     * URL format: ws://host:port/ws?token=xxx
     */
    suspend fun connect(): Result<Unit> {
        logger.info { "Connecting to WebSocket: $wsUrl" }
        _state.value = WSState.CONNECTING

        try {
            val url = buildString {
                append(wsUrl)
                append(if (wsUrl.contains('?')) "&" else "?")
                append("token=")
                append(token)
            }

            session = client.webSocketSession(url)
            _state.value = WSState.CONNECTED
            logger.info { "WebSocket connected" }

            // Start receiving messages
            receiveJob = scope.launch {
                receiveMessages()
            }

            // Start heartbeat
            heartbeatJob = scope.launch {
                sendHeartbeat()
            }

            return Result.success(Unit)
        } catch (e: Exception) {
            logger.error(e) { "Failed to connect to WebSocket" }
            _state.value = WSState.DISCONNECTED
            return Result.failure(e)
        }
    }

    private suspend fun receiveMessages() {
        try {
            session?.let { ws ->
                for (frame in ws.incoming) {
                    when (frame) {
                        is Frame.Text -> {
                            val text = frame.readText()
                            logger.info { "Received: $text" }
                            try {
                                val message = Json.decodeFromString<WSMessage>(text)
                                _messages.send(message)
                            } catch (e: Exception) {
                                logger.error(e) { "Failed to parse message" }
                            }
                        }
                        is Frame.Binary -> {
                            logger.debug { "Received binary: ${frame.data.size} bytes" }
                        }
                        is Frame.Close -> {
                            logger.info { "WebSocket close received" }
                            _state.value = WSState.CLOSED
                            break
                        }
                        is Frame.Ping -> {
                            logger.debug { "Ping received" }
                            // Pong is sent automatically by Ktor
                        }
                        is Frame.Pong -> {
                            logger.debug { "Pong received" }
                        }
                        else -> {}
                    }
                }
            }
        } catch (e: Exception) {
            logger.error(e) { "Error receiving messages" }
            _state.value = WSState.DISCONNECTED
        }
    }

    private suspend fun sendHeartbeat() {
        while (scope.coroutineContext.isActive && _state.value == WSState.CONNECTED) {
            delay(30000) // 30 seconds
            try {
                sendHeartbeatMessage()
            } catch (e: Exception) {
                logger.error(e) { "Failed to send heartbeat" }
            }
        }
    }

    private suspend fun sendHeartbeatMessage() {
        val message = WSMessage(
            type = "heartbeat",
            payload = buildJsonObject {
                put("timestamp", System.currentTimeMillis())
            },
            timestamp = System.currentTimeMillis()
        )
        send(message)
    }

    /**
     * Send WebSocket message matching gateway.lisp protocol
     */
    suspend fun send(message: WSMessage): Result<Unit> {
        if (_state.value != WSState.CONNECTED) {
            return Result.failure(IllegalStateException("WebSocket not connected"))
        }

        return try {
            val json = Json.encodeToString(WSMessage.serializer(), message)
            session?.outgoing?.send(Frame.Text(json))
            logger.debug { "Sent: $json" }
            Result.success(Unit)
        } catch (e: Exception) {
            logger.error(e) { "Failed to send message" }
            Result.failure(e)
        }
    }

    /**
     * Send message via WebSocket matching gateway.lisp message:send
     */
    suspend fun sendMessage(conversationId: Long, content: String, messageType: String = "text"): Result<Unit> {
        val message = WSMessage(
            type = "message:send",
            payload = buildJsonObject {
                put("conversation_id", conversationId)
                put("content", content)
                put("message_type", messageType)
            },
            timestamp = System.currentTimeMillis()
        )
        return send(message)
    }

    /**
     * Send read receipt matching gateway.lisp message:read
     */
    suspend fun sendReadReceipt(messageId: Long): Result<Unit> {
        val message = WSMessage(
            type = "message:read",
            payload = buildJsonObject {
                put("message_id", messageId)
                put("timestamp", System.currentTimeMillis())
            },
            timestamp = System.currentTimeMillis()
        )
        return send(message)
    }

    /**
     * Subscribe to conversation matching gateway.lisp conversation:subscribe
     */
    suspend fun subscribeConversation(conversationId: Long): Result<Unit> {
        val message = WSMessage(
            type = "conversation:subscribe",
            payload = buildJsonObject {
                put("conversation_id", conversationId)
            },
            timestamp = System.currentTimeMillis()
        )
        return send(message)
    }

    /**
     * Disconnect from WebSocket
     */
    suspend fun disconnect() {
        logger.info { "Disconnecting WebSocket" }

        // Cancel jobs
        receiveJob?.cancel()
        heartbeatJob?.cancel()

        // Close session
        try {
            session?.close()
        } catch (e: Exception) {
            logger.error(e) { "Error closing session" }
        }

        _state.value = WSState.DISCONNECTED
        logger.info { "WebSocket disconnected" }
    }

    /**
     * Close client and cleanup
     */
    fun close() {
        scope.cancel()
        client.close()
    }
}
