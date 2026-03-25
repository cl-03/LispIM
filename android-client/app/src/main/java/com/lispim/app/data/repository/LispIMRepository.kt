package com.lispim.app.data.repository

import com.lispim.app.data.api.LispIMApiService
import com.lispim.app.data.local.dao.ConversationDao
import com.lispim.app.data.local.dao.MessageDao
import com.lispim.app.data.local.entity.ConversationEntity
import com.lispim.app.data.local.entity.MessageEntity
import com.lispim.app.data.model.*
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Main Repository for app data
 * Handles data operations between API and local database
 */
@Singleton
class LispIMRepository @Inject constructor(
    private val apiService: LispIMApiService,
    private val conversationDao: ConversationDao,
    private val messageDao: MessageDao
) {

    // ========== Authentication ==========

    suspend fun login(username: String, password: String): Result<LoginData> {
        return try {
            val response = apiService.login(LoginRequest(username, password))
            if (response.isSuccessful && response.body()?.success == true) {
                response.body()?.data?.let { Result.success(it) }
                    ?: Result.failure(Exception("Login failed"))
            } else {
                Result.failure(Exception(response.body()?.error?.message ?: "Login failed"))
            }
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    suspend fun register(
        username: String,
        password: String,
        email: String,
        displayName: String? = null
    ): Result<RegisterData> {
        return try {
            val response = apiService.register(
                RegisterRequest(
                    method = "username",
                    username = username,
                    password = password,
                    email = email,
                    displayName = displayName
                )
            )
            if (response.isSuccessful && response.body()?.success == true) {
                response.body()?.data?.let { Result.success(it) }
                    ?: Result.failure(Exception("Registration failed"))
            } else {
                Result.failure(Exception(response.body()?.error?.message ?: "Registration failed"))
            }
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    suspend fun logout(token: String): Result<Unit> {
        return try {
            val response = apiService.logout("Bearer $token")
            if (response.isSuccessful) {
                Result.success(Unit)
            } else {
                Result.failure(Exception("Logout failed"))
            }
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    suspend fun getCurrentUser(token: String): Result<User> {
        return try {
            val response = apiService.getCurrentUser("Bearer $token")
            if (response.isSuccessful && response.body()?.success == true) {
                response.body()?.data?.let { Result.success(it) }
                    ?: Result.failure(Exception("User not found"))
            } else {
                Result.failure(Exception("Failed to get user"))
            }
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    // ========== Conversations ==========

    suspend fun getConversations(
        token: String,
        type: String? = null,
        page: Int = 1,
        pageSize: Int = 20
    ): Result<List<Conversation>> {
        return try {
            val response = apiService.getConversations("Bearer $token", type, page, pageSize)
            if (response.isSuccessful && response.body()?.success == true) {
                val conversations = response.body()?.data?.conversations ?: emptyList()
                // Cache to local database
                cacheConversations(conversations)
                Result.success(conversations)
            } else {
                // Fallback to local cache
                Result.success(getLocalConversations().map { it.toConversation() })
            }
        } catch (e: Exception) {
            // Fallback to local cache
            Result.success(getLocalConversations().map { it.toConversation() })
        }
    }

    suspend fun getMessages(
        token: String,
        conversationId: String,
        before: String? = null,
        limit: Int = 20
    ): Result<List<Message>> {
        return try {
            val response = apiService.getMessages("Bearer $token", conversationId, before, limit)
            if (response.isSuccessful && response.body()?.success == true) {
                val messages = response.body()?.data?.messages ?: emptyList()
                // Cache to local database
                cacheMessages(conversationId, messages)
                Result.success(messages)
            } else {
                Result.failure(Exception("Failed to get messages"))
            }
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    suspend fun sendMessage(
        token: String,
        conversationId: String,
        content: String,
        type: String = "text"
    ): Result<Message> {
        return try {
            val response = apiService.sendMessage(
                "Bearer $token",
                conversationId,
                SendMessageRequest(content, type)
            )
            if (response.isSuccessful && response.body()?.success == true) {
                val message = response.body()?.data
                if (message != null) {
                    // Cache to local database
                    cacheMessage(conversationId, message)
                }
                Result.success(message ?: throw Exception("Empty response"))
            } else {
                Result.failure(Exception(response.body()?.error?.message ?: "Failed to send message"))
            }
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    suspend fun markAsRead(token: String, conversationId: String): Result<Unit> {
        return try {
            val response = apiService.markAsRead("Bearer $token", conversationId)
            if (response.isSuccessful) {
                // Update local cache
                conversationDao.markAsRead(conversationId)
                Result.success(Unit)
            } else {
                Result.failure(Exception("Failed to mark as read"))
            }
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    // ========== Local Cache ==========

    suspend fun getLocalConversations(): List<ConversationEntity> {
        return conversationDao.getAllConversations().value
    }

    suspend fun getLocalMessages(conversationId: String): List<MessageEntity> {
        return messageDao.getMessagesByConversationId(conversationId).value
    }

    private fun cacheConversations(conversations: List<Conversation>) {
        conversations.forEach { conv ->
            conversationDao.insert(
                ConversationEntity(
                    remoteId = conv.id,
                    name = conv.name,
                    type = conv.type,
                    lastMessage = conv.lastMessage,
                    unreadCount = conv.unreadCount,
                    avatarUrl = conv.avatarUrl,
                    createdAt = conv.createdAt,
                    updatedAt = System.currentTimeMillis()
                )
            )
        }
    }

    private fun cacheMessages(conversationId: String, messages: List<Message>) {
        messages.forEach { msg ->
            messageDao.insert(
                MessageEntity(
                    remoteId = msg.id,
                    conversationId = conversationId,
                    senderId = msg.senderId,
                    senderName = msg.sender?.displayName ?: msg.sender?.username,
                    content = msg.content,
                    type = msg.type,
                    createdAt = msg.createdAt,
                    isRead = true
                )
            )
        }
    }

    private fun cacheMessage(conversationId: String, message: Message) {
        messageDao.insert(
            MessageEntity(
                remoteId = message.id,
                conversationId = conversationId,
                senderId = message.senderId,
                senderName = message.sender?.displayName ?: message.sender?.username,
                content = message.content,
                type = message.type,
                createdAt = message.createdAt,
                isRead = true
            )
        )
    }
}

// Helper extension
private fun ConversationEntity.toConversation(): Conversation {
    return Conversation(
        id = remoteId,
        name = name,
        type = type,
        lastMessage = lastMessage,
        unreadCount = unreadCount,
        avatarUrl = avatarUrl,
        createdAt = createdAt
    )
}
