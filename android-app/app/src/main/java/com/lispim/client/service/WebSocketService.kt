package com.lispim.client.service

import android.app.Notification
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.os.Binder
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import com.lispim.client.LispIMApplication
import com.lispim.client.MainActivity
import com.lispim.client.R
import com.lispim.client.data.WebSocketClient
import com.lispim.client.model.WSMessage
import com.lispim.client.model.WSState
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.receiveAsFlow
import mu.KotlinLogging

private val logger = KotlinLogging.logger {}

/**
 * Foreground service for maintaining WebSocket connection in background
 */
class WebSocketService : Service() {

    private val binder = LocalBinder()
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    private var wsClient: WebSocketClient? = null
    private val _connectionState = MutableStateFlow(WSState.DISCONNECTED)
    val connectionState = _connectionState.asStateFlow()

    private val _messages = kotlinx.coroutines.channels.Channel<WSMessage>(kotlinx.coroutines.channels.Channel.BUFFERED)
    val messages = _messages.receiveAsFlow()

    inner class LocalBinder : Binder() {
        fun getService(): WebSocketService = this@WebSocketService
    }

    override fun onBind(intent: Intent?): IBinder {
        logger.debug { "WebSocketService onBind" }
        return binder
    }

    override fun onCreate() {
        super.onCreate()
        logger.info { "WebSocketService onCreate" }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        logger.info { "WebSocketService onStartCommand" }

        when (intent?.action) {
            ACTION_CONNECT -> {
                val token = intent.getStringExtra(EXTRA_TOKEN) ?: ""
                val wsUrl = intent.getStringExtra(EXTRA_WS_URL) ?: ""
                connect(wsUrl, token)
            }
            ACTION_DISCONNECT -> {
                disconnect()
            }
        }

        // Start as foreground service
        startForeground(NOTIFICATION_ID, createNotification())

        return START_STICKY
    }

    override fun onDestroy() {
        logger.info { "WebSocketService onDestroy" }
        scope.cancel()
        wsClient?.close()
        super.onDestroy()
    }

    /**
     * Connect to WebSocket server
     */
    fun connect(wsUrl: String, token: String) {
        scope.launch {
            try {
                _connectionState.value = WSState.CONNECTING

                wsClient = WebSocketClient(wsUrl, token)
                val result = wsClient?.connect()

                result?.fold(
                    onSuccess = {
                        _connectionState.value = WSState.CONNECTED
                        updateNotification()
                        // Start listening for messages
                        listenForMessages()
                    },
                    onFailure = { e ->
                        logger.error(e) { "Failed to connect WebSocket" }
                        _connectionState.value = WSState.DISCONNECTED
                        updateNotification()
                    }
                )
            } catch (e: Exception) {
                logger.error(e) { "Connection failed" }
                _connectionState.value = WSState.DISCONNECTED
            }
        }
    }

    /**
     * Disconnect from WebSocket server
     */
    fun disconnect() {
        scope.launch {
            wsClient?.disconnect()
            wsClient?.close()
            wsClient = null
            _connectionState.value = WSState.DISCONNECTED
            updateNotification()
            stopForeground(2) // STOP_FOREGROUND_REMOVE_TASK
            stopSelf()
        }
    }

    /**
     * Send message via WebSocket
     */
    suspend fun sendMessage(conversationId: Long, content: String): Result<Unit> {
        return wsClient?.sendMessage(conversationId, content)
            ?: Result.failure(IllegalStateException("WebSocket not connected"))
    }

    /**
     * Send read receipt
     */
    suspend fun sendReadReceipt(messageId: Long): Result<Unit> {
        return wsClient?.sendReadReceipt(messageId)
            ?: Result.failure(IllegalStateException("WebSocket not connected"))
    }

    private suspend fun listenForMessages() {
        try {
            wsClient?.messages?.collect { message ->
                _messages.send(message)

                // Show notification for new message
                if (message.type == "message:new") {
                    showNewMessageNotification()
                }
            }
        } catch (e: Exception) {
            logger.error(e) { "Error listening for messages" }
        }
    }

    private fun createNotification(): Notification {
        val intent = Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        return NotificationCompat.Builder(this, LispIMApplication.CHANNEL_CONNECTION)
            .setContentTitle("LispIM")
            .setContentText("Connected to server")
            .setSmallIcon(R.drawable.ic_notification)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .build()
    }

    private fun updateNotification() {
        val notificationManager = getSystemService(NOTIFICATION_SERVICE) as android.app.NotificationManager
        notificationManager.notify(NOTIFICATION_ID, createNotification())
    }

    private fun showNewMessageNotification() {
        val intent = Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        val notification = NotificationCompat.Builder(this, LispIMApplication.CHANNEL_MESSAGES)
            .setContentTitle("New Message")
            .setContentText("You have received a new message")
            .setSmallIcon(R.drawable.ic_notification)
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .build()

        val notificationManager = getSystemService(NOTIFICATION_SERVICE) as android.app.NotificationManager
        notificationManager.notify(NOTIFICATION_MESSAGE_ID, notification)
    }

    companion object {
        const val ACTION_CONNECT = "com.lispim.client.CONNECT"
        const val ACTION_DISCONNECT = "com.lispim.client.DISCONNECT"
        const val EXTRA_TOKEN = "token"
        const val EXTRA_WS_URL = "ws_url"

        private const val NOTIFICATION_ID = 1
        private const val NOTIFICATION_MESSAGE_ID = 2
    }
}
