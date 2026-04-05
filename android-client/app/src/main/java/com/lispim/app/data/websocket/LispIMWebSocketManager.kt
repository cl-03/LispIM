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
import java.util.concurrent.ConcurrentHashMap
import javax.inject.Inject
import javax.inject.Singleton
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkRequest
import android.content.Context
import com.lispim.app.LispIMApplication

/**
 * WebSocket message protocol v1
 */
data class WSMessage(
    @SerializedName("type") val type: String,
    @SerializedName("data") val data: Map<String, Any>? = null,
    @SerializedName("ack") val ack: String? = null,
    @SerializedName("sequence") val sequence: Long? = null,
    @SerializedName("messageId") val messageId: String? = null
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
        private const val MAX_RECONNECT_ATTEMPTS = 10
        // 指数退避：1s, 2s, 4s, 8s, 16s, 30s, 30s...
        private const val RECONNECT_DELAY_BASE = 1000L
        private const val RECONNECT_DELAY_MAX = 30000L

        // 消息去重缓存
        private const val MESSAGE_TTL = 5 * 60 * 1000L // 5 分钟
        private const val MAX_SEEN_MESSAGES = 1000
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
    private var lastSequenceReceived: Long = 0  // 序列号跟踪

    // 消息去重缓存：messageId -> timestamp
    private val seenMessageIds = ConcurrentHashMap<String, Long>()

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
            // 指数退避：1s, 2s, 4s, 8s, 16s, max 30s
            val delay = minOf(
                RECONNECT_DELAY_BASE * (1L shl reconnectAttempts),
                RECONNECT_DELAY_MAX
            )
            Log.i(TAG, "Reconnecting in ${delay}ms (attempt ${reconnectAttempts + 1}/$MAX_RECONNECT_ATTEMPTS)")
            delay(delay)

            // 检查网络状态
            if (!isNetworkAvailable()) {
                Log.w(TAG, "No network available, waiting...")
                return@launch
            }

            reconnectAttempts++
            _connectionState.value = ConnectionState.Reconnecting
            authToken?.let { connect(it) }
        }
    }

    /**
     * 检查网络是否可用
     */
    private fun isNetworkAvailable(): Boolean {
        return try {
            val cm = LispIMApplication.instance.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            val network = cm.activeNetwork ?: return false
            val capabilities = cm.getNetworkCapabilities(network) ?: return false
            capabilities.hasCapability(android.net.NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
            capabilities.hasCapability(android.net.NetworkCapabilities.NET_CAPABILITY_VALIDATED)
        } catch (e: Exception) {
            Log.e(TAG, "Error checking network", e)
            false
        }
    }

    private fun handleIncomingMessage(text: String) {
        try {
            val json = gson.fromJson(text, Map::class.java)
            val type = json["type"] as? String ?: return

            // 消息去重检查
            val messageId = (json["messageId"] as? String) ?: (json["data"] as? Map<*, *>)?.get("id") as? String
            if (messageId != null) {
                if (isDuplicateMessage(messageId)) {
                    Log.d(TAG, "Duplicate message ignored: $messageId")
                    return
                }
                markMessageAsSeen(messageId)
            }

            // 序列号验证
            val sequence = (json["sequence"] as? Number)?.toLong()
            if (sequence != null && !verifySequence(sequence)) {
                Log.w(TAG, "Out of order message, sequence=$sequence, last=$lastSequenceReceived")
                return
            }

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

    /**
     * 验证序列号连续性
     */
    private fun verifySequence(sequence: Long): Boolean {
        if (sequence <= lastSequenceReceived) {
            return false
        }
        lastSequenceReceived = sequence
        return true
    }

    /**
     * 检查消息是否重复
     */
    private fun isDuplicateMessage(messageId: String): Boolean {
        val now = System.currentTimeMillis()
        val seenTime = seenMessageIds[messageId]

        if (seenTime != null) {
            // 检查是否过期
            if (now - seenTime > MESSAGE_TTL) {
                seenMessageIds.remove(messageId)
                return false
            }
            return true  // 重复消息
        }
        return false
    }

    /**
     * 标记消息为已见
     */
    private fun markMessageAsSeen(messageId: String) {
        val now = System.currentTimeMillis()
        seenMessageIds[messageId] = now

        // 定期清理过期记录
        if (seenMessageIds.size > MAX_SEEN_MESSAGES) {
            val cutoff = now - MESSAGE_TTL
            seenMessageIds.entries.removeAll { it.value < cutoff }
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
