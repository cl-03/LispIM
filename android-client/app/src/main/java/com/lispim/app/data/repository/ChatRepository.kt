package com.lispim.app.data.repository

import com.lispim.app.data.local.dao.ConversationDao
import com.lispim.app.data.local.dao.MessageDao
import com.lispim.app.data.local.entity.ConversationEntity
import com.lispim.app.data.local.entity.MessageEntity
import com.lispim.app.data.websocket.ConnectionState
import com.lispim.app.data.websocket.MessageData
import com.lispim.app.data.websocket.WebSocketManager
import com.lispim.app.data.websocket.WebSocketMessage
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Chat Repository - Handles real-time messaging via WebSocket
 */
@Singleton
class ChatRepository @Inject constructor(
    private val webSocketManager: WebSocketManager,
    private val messageDao: MessageDao,
    private val conversationDao: ConversationDao
) {
    private val _messages = MutableStateFlow<Map<String, List<MessageEntity>>>(emptyMap())
    val messages: StateFlow<Map<String, List<MessageEntity>>> = _messages.asStateFlow()

    private val _typingUsers = MutableStateFlow<Map<String, Set<String>>>(emptyMap())
    val typingUsers: StateFlow<Map<String, Set<String>>> = _typingUsers.asStateFlow()

    init {
        // Listen for incoming WebSocket messages
        webSocketManager.onMessage { message ->
            when (message) {
                is WebSocketMessage.NewMessage -> {
                    handleNewMessage(message.data)
                }
                is WebSocketMessage.MessageRead -> {
                    // Handle message read receipt
                }
                is WebSocketMessage.UserPresence -> {
                    // Handle presence update
                }
                is WebSocketMessage.TypingIndicator -> {
                    handleTypingIndicator(message.conversationId, message.userId)
                }
                is WebSocketMessage.MessageRecalled -> {
                    handleMessageRecalled(message.messageId)
                }
                else -> {}
            }
        }
    }

    /**
     * Connect to WebSocket server
     */
    fun connect(token: String) {
        webSocketManager.connect(token)
    }

    /**
     * Disconnect from WebSocket server
     */
    fun disconnect() {
        webSocketManager.disconnect()
    }

    /**
     * Get connection state flow
     */
    fun getConnectionState(): StateFlow<ConnectionState> {
        return webSocketManager.connectionState
    }

    /**
     * Send a message via WebSocket
     */
    fun sendMessage(conversationId: String, content: String, type: String) {
        webSocketManager.sendMessage(conversationId, content, type)
    }

    /**
     * Send message via HTTP API (fallback)
     */
    suspend fun sendMessageHttp(
        token: String,
        conversationId: String,
        content: String,
        type: String
    ): Result<MessageEntity> {
        // This would call the API service directly
        // For now, we'll use WebSocket as primary method
        sendMessage(conversationId, content, type)
        return Result.success(
            MessageEntity(
                remoteId = System.currentTimeMillis().toString(),
                conversationId = conversationId,
                senderId = "", // Would need current user ID
                senderName = "",
                content = content,
                type = type,
                createdAt = System.currentTimeMillis()
            )
        )
    }

    /**
     * Send read receipt
     */
    fun sendAck(messageId: String) {
        webSocketManager.sendAck(messageId)
    }

    /**
     * Send typing indicator
     */
    fun sendTypingIndicator(conversationId: String) {
        webSocketManager.sendTypingIndicator(conversationId)
    }

    /**
     * Send file message via WebSocket
     * @param conversationId Conversation ID
     * @param fileId File ID from upload
     * @param fileName Original file name
     * @param fileSize File size in bytes
     * @param mimeType MIME type of the file
     */
    fun sendFileMessage(
        conversationId: String,
        fileId: String,
        fileName: String,
        fileSize: Long,
        mimeType: String
    ) {
        // Create file message content as JSON
        val content = """{"fileId":"$fileId","filename":"$fileName","size":$fileSize,"mimeType":"$mimeType"}"""
        val messageType = when {
            mimeType.startsWith("image/") -> "image"
            mimeType.startsWith("video/") -> "video"
            mimeType.startsWith("audio/") -> "audio"
            else -> "file"
        }
        webSocketManager.sendMessage(conversationId, content, messageType)
    }

    /**
     * Get messages for a conversation from local database
     */
    fun getLocalMessages(conversationId: String): Flow<List<MessageEntity>> {
        return messageDao.getMessagesByConversationId(conversationId)
    }

    /**
     * Get conversations from local database
     */
    fun getLocalConversations(): Flow<List<ConversationEntity>> {
        return conversationDao.getAllConversations()
    }

    private fun handleNewMessage(messageData: MessageData) {
        val messageEntity = MessageEntity(
            remoteId = messageData.id,
            conversationId = messageData.conversationId,
            senderId = messageData.senderId,
            senderName = "", // Would need to fetch from user repository
            content = messageData.content,
            type = messageData.type,
            createdAt = messageData.createdAt,
            isRead = false
        )

        // Insert into local database
        kotlinx.coroutines.GlobalScope.launch {
            messageDao.insert(messageEntity)

            // Update conversation's last message
            conversationDao.getConversationByRemoteId(messageData.conversationId)?.let { conv ->
                conversationDao.update(
                    conv.copy(
                        lastMessage = messageData.content,
                        updatedAt = System.currentTimeMillis(),
                        unreadCount = conv.unreadCount + 1
                    )
                )
            }

            // Update messages state
            updateMessagesState(messageData.conversationId)
        }
    }

    private fun handleTypingIndicator(conversationId: String, userId: String) {
        val current = _typingUsers.value.toMutableMap()
        val users = current.getOrPut(conversationId) { emptySet() }.toMutableSet()
        users.add(userId)
        current[conversationId] = users
        _typingUsers.value = current

        // Clear typing indicator after 5 seconds
        kotlinx.coroutines.GlobalScope.launch {
            kotlinx.coroutines.delay(5000)
            val updated = _typingUsers.value.toMutableMap()
            updated[conversationId]?.minusAssign(userId)
            if (updated[conversationId].isNullOrEmpty()) {
                updated.remove(conversationId)
            }
            _typingUsers.value = updated
        }
    }

    private fun handleMessageRecalled(messageId: String) {
        kotlinx.coroutines.GlobalScope.launch {
            messageDao.markMessageAsRecalled(messageId)
        }
    }

    private fun updateMessagesState(conversationId: String) {
        kotlinx.coroutines.GlobalScope.launch {
            val currentMessages = _messages.value.toMutableMap()
            currentMessages[conversationId] = messageDao.getMessagesByConversationId(conversationId).value
            _messages.value = currentMessages
        }
    }
}
