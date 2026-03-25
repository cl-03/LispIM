package com.lispim.app.data.websocket

import android.util.Log
import com.google.gson.Gson
import com.google.gson.annotations.SerializedName
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import okhttp3.*
import okhttp3.internal.ws.WebSocketReal
import java.util.concurrent.TimeUnit
import javax.inject.Inject
import javax.inject.Singleton

/**
 * WebSocket message protocol v1
 */
data class WSMessage(
    @SerializedName("type") val type: String,
    @SerializedName("data") val data: Map<String, Any>? = null,
    @SerializedName("ack") val ack: String? = null,
    @SerializedName("sequence") val sequence: Long? = null
)

/**
 * OkHttp-based WebSocket Manager implementation
 */
@Singleton
class LispIMWebSocketManager @Inject constructor() : WebSocketManager {

    companion object {
        private const val TAG = "LispIMWebSocket"
        private const val WS_URL = "ws://localhost:3000/ws"
        private const val HEARTBEAT_INTERVAL = 30000L // 30 seconds
        private const val RECONNECT_DELAY = 5000L // 5 seconds
        private const val MAX_RECONNECT_ATTEMPTS = 5
    }

    private val _connectionState = MutableStateFlow<ConnectionState>(ConnectionState.Disconnected)
    override val connectionState: StateFlow<ConnectionState> = _connectionState.asStateFlow()

    private var webSocket: WebSocket? = null
    private var heartbeatJob: Job? = null
    private var reconnectJob: Job? = null
    private var messageScope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    private val messageCallbacks = mutableListOf<(WebSocketMessage) -> Unit>()
    private val connectionStateCallbacks = mutableListOf<(ConnectionState) -> Unit>()

    private val gson = Gson()
    private var authToken: String? = null
    private var reconnectAttempts = 0

    private val client = OkHttpClient.Builder()
        .readTimeout(0, TimeUnit.MILLISECONDS)
        .pingInterval(HEARTBEAT_INTERVAL, TimeUnit.MILLISECONDS)
        .build()

    override fun connect(token: String) {
        if (_connectionState.value is ConnectionState.Connected) {
            Log.w(TAG, "Already connected")
            return
        }

        authToken = token
        _connectionState.value = ConnectionState.Connecting

        val request = Request.Builder()
            .url(WS_URL)
            .addHeader("Authorization", "Bearer $token")
            .addHeader("Sec-WebSocket-Protocol", "lispim-v1")
            .build()

        webSocket = client.newWebSocket(request, object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                Log.i(TAG, "WebSocket connected")
                reconnectAttempts = 0
                _connectionState.value = ConnectionState.Connected
                sendAuthMessage(token)
                startHeartbeat()
            }

            override fun onMessage(webSocket: WebSocket, text: String) {
                Log.d(TAG, "Message received: $text")
                handleIncomingMessage(text)
            }

            override fun onMessage(webSocket: WebSocket, bytes: ByteString) {
                Log.d(TAG, "Binary message received: ${bytes.size} bytes")
            }

            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                Log.e(TAG, "WebSocket error: ${t.message}", t)
                val code = response?.code
                _connectionState.value = ConnectionState.Error(t.message ?: "Unknown error", code)

                if (_connectionState.value is ConnectionState.Connected) {
                    scheduleReconnect()
                }
            }

            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                Log.i(TAG, "WebSocket closed: $code / $reason")
                _connectionState.value = ConnectionState.Disconnected
                stopHeartbeat()
            }
        })
    }

    override fun disconnect() {
        Log.i(TAG, "Disconnecting...")
        stopHeartbeat()
        reconnectJob?.cancel()
        webSocket?.close(1000, "User disconnected")
        webSocket = null
        _connectionState.value = ConnectionState.Disconnected
    }

    override fun sendMessage(conversationId: String, content: String, type: String) {
        sendWSMessage(WSMessage(
            type = "chat",
            data = mapOf(
                "conversation_id" to conversationId,
                "content" to content,
                "type" to type
            )
        ))
    }

    override fun sendAck(messageId: String) {
        sendWSMessage(WSMessage(
            type = "ack",
            data = mapOf("message_id" to messageId)
        ))
    }

    override fun sendTypingIndicator(conversationId: String) {
        sendWSMessage(WSMessage(
            type = "typing",
            data = mapOf("conversation_id" to conversationId)
        ))
    }

    override fun updatePresence(status: String) {
        sendWSMessage(WSMessage(
            type = "presence",
            data = mapOf("status" to status)
        ))
    }

    override fun onMessage(callback: (WebSocketMessage) -> Unit) {
        synchronized(messageCallbacks) {
            messageCallbacks.add(callback)
        }
    }

    override fun onConnectionStateChange(callback: (ConnectionState) -> Unit) {
        synchronized(connectionStateCallbacks) {
            connectionStateCallbacks.add(callback)
        }

        // Emit current state immediately
        callback(_connectionState.value)
    }

    private fun sendWSMessage(message: WSMessage) {
        val json = gson.toJson(message)
        Log.d(TAG, "Sending: $json")

        val sent = webSocket?.send(json)
        if (sent == false) {
            Log.e(TAG, "Failed to send message")
        }
    }

    private fun sendAuthMessage(token: String) {
        sendWSMessage(WSMessage(
            type = "auth",
            data = mapOf("token" to token)
        ))
    }

    private fun startHeartbeat() {
        heartbeatJob?.cancel()
        heartbeatJob = messageScope.launch {
            while (isActive) {
                delay(HEARTBEAT_INTERVAL)
                sendWSMessage(WSMessage(type = "ping"))
            }
        }
    }

    private fun stopHeartbeat() {
        heartbeatJob?.cancel()
        heartbeatJob = null
    }

    private fun scheduleReconnect() {
        if (reconnectAttempts >= MAX_RECONNECT_ATTEMPTS) {
            Log.e(TAG, "Max reconnect attempts reached")
            _connectionState.value = ConnectionState.Error("Connection lost", null)
            return
        }

        reconnectJob?.cancel()
        reconnectJob = messageScope.launch {
            delay(RECONNECT_DELAY)
            reconnectAttempts++
            Log.i(TAG, "Reconnecting (attempt $reconnectAttempts/$MAX_RECONNECT_ATTEMPTS)")
            _connectionState.value = ConnectionState.Reconnecting
            authToken?.let { connect(it) }
        }
    }

    private fun handleIncomingMessage(text: String) {
        try {
            val json = gson.fromJson(text, Map::class.java)
            val type = json["type"] as? String ?: return

            val message = when (type) {
                "new_message" -> {
                    val data = json["data"] as? Map<*, *> ?: return
                    WebSocketMessage.NewMessage(
                        MessageData(
                            id = data["id"] as? String ?: "",
                            conversationId = data["conversation_id"] as? String ?: "",
                            senderId = data["sender_id"] as? String ?: "",
                            content = data["content"] as? String ?: "",
                            type = data["type"] as? String ?: "text",
                            createdAt = (data["created_at"] as? Number)?.toLong() ?: 0L,
                            sequence = (data["sequence"] as? Number)?.toLong() ?: 0L
                        )
                    )
                }
                "message_read" -> {
                    val data = json["data"] as? Map<*, *> ?: return
                    WebSocketMessage.MessageRead(
                        data["message_id"] as? String ?: "",
                        (data["read_at"] as? Number)?.toLong() ?: 0L
                    )
                }
                "presence" -> {
                    val data = json["data"] as? Map<*, *> ?: return
                    WebSocketMessage.UserPresence(
                        data["user_id"] as? String ?: "",
                        (data["online"] as? Boolean) ?: false
                    )
                }
                "typing" -> {
                    val data = json["data"] as? Map<*, *> ?: return
                    WebSocketMessage.TypingIndicator(
                        data["conversation_id"] as? String ?: "",
                        data["user_id"] as? String ?: ""
                    )
                }
                "message_recalled" -> {
                    val data = json["data"] as? Map<*, *> ?: return
                    WebSocketMessage.MessageRecalled(data["message_id"] as? String ?: "")
                }
                "pong" -> {
                    Log.d(TAG, "Heartbeat ACK received")
                    return
                }
                else -> {
                    Log.w(TAG, "Unknown message type: $type")
                    return
                }
            }

            notifyMessageListeners(message)

        } catch (e: Exception) {
            Log.e(TAG, "Error parsing message", e)
        }
    }

    private fun notifyMessageListeners(message: WebSocketMessage) {
        synchronized(messageCallbacks) {
            messageCallbacks.forEach { callback ->
                try {
                    callback(message)
                } catch (e: Exception) {
                    Log.e(TAG, "Error in message callback", e)
                }
            }
        }
    }

    private fun notifyConnectionStateListeners(state: ConnectionState) {
        synchronized(connectionStateCallbacks) {
            connectionStateCallbacks.forEach { callback ->
                try {
                    callback(state)
                } catch (e: Exception) {
                    Log.e(TAG, "Error in connection state callback", e)
                }
            }
        }
    }
}
