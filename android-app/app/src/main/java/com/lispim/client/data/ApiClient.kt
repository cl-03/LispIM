package com.lispim.client.data

import android.content.Context
import com.lispim.client.model.AuthResponse
import com.lispim.client.model.Conversation
import com.lispim.client.model.Friend
import com.lispim.client.model.FriendRequest
import com.lispim.client.model.Message
import com.lispim.client.model.UploadResponse
import com.lispim.client.model.User
import com.lispim.client.model.UserSearchResult
import io.ktor.client.*
import io.ktor.client.call.*
import io.ktor.client.engine.android.*
import io.ktor.client.plugins.*
import io.ktor.client.plugins.contentnegotiation.*
import io.ktor.client.plugins.logging.*
import io.ktor.client.request.*
import io.ktor.client.statement.*
import io.ktor.http.*
import io.ktor.serialization.kotlinx.*
import io.ktor.serialization.kotlinx.json.*
import kotlinx.serialization.json.Json
import mu.KotlinLogging

private val logger = KotlinLogging.logger {}

/**
 * HTTP API client matching Tauri client implementation
 */
class ApiClient(private val baseUrl: String, private val token: String? = null) {

    private val json = Json {
        ignoreUnknownKeys = true
        isLenient = true
        encodeDefaults = true
    }

    private val client = HttpClient(Android) {
        install(ContentNegotiation) {
            json(json)
        }
        install(Logging) {
            logger = Logger.DEFAULT
            level = LogLevel.BODY
        }
        install(HttpTimeout) {
            requestTimeoutMillis = 30000
            connectTimeoutMillis = 15000
            socketTimeoutMillis = 15000
        }
        defaultRequest {
            url {
                takeFrom(baseUrl)
            }
            token?.let {
                header("Authorization", "Bearer $it")
            }
        }
    }

    /**
     * Login - matches Tauri login command
     */
    suspend fun login(username: String, password: String): Result<AuthResponse> {
        return try {
            logger.info { "Logging in user: $username to $baseUrl/api/v1/auth/login" }
            val response = client.post("/api/v1/auth/login") {
                contentType(ContentType.Application.Json)
                setBody(mapOf("username" to username, "password" to password))
            }
            val bodyText = response.bodyAsText()
            logger.info { "Login response status: ${response.status}, body: $bodyText" }
            val result: AuthResponse = json.decodeFromString(bodyText)
            logger.info { "Login response: success=${result.success}" }
            Result.success(result)
        } catch (e: Exception) {
            logger.error(e) { "Login failed: ${e.message}" }
            Result.failure(e)
        }
    }

    /**
     * Logout
     */
    suspend fun logout(): Result<Unit> {
        return try {
            logger.info { "Logging out" }
            client.post("/api/v1/auth/logout")
            Result.success(Unit)
        } catch (e: Exception) {
            logger.error(e) { "Logout failed" }
            Result.failure(e)
        }
    }

    /**
     * Get user info - matches Tauri get_user_info command
     */
    suspend fun getUserInfo(userId: String): Result<User> {
        return try {
            logger.info { "Getting user info: $userId" }
            val response = client.get("/api/v1/users/$userId")
            val user: User = json.decodeFromString(response.bodyAsText())
            Result.success(user)
        } catch (e: Exception) {
            logger.error(e) { "Failed to get user info" }
            Result.failure(e)
        }
    }

    /**
     * Get conversations - matches Tauri get_conversations command
     */
    suspend fun getConversations(): Result<List<Conversation>> {
        return try {
            logger.info { "Getting conversations" }
            val response = client.get("/api/v1/chat/conversations")
            val conversations: List<Conversation> = json.decodeFromString(response.bodyAsText())
            Result.success(conversations)
        } catch (e: Exception) {
            logger.error(e) { "Failed to get conversations" }
            Result.failure(e)
        }
    }

    /**
     * Get message history - matches Tauri get_history command
     */
    suspend fun getHistory(conversationId: Long, limit: Int = 50): Result<List<Message>> {
        return try {
            logger.info { "Getting history for conversation: $conversationId" }
            val response = client.get("/api/v1/chat/conversations/$conversationId/messages") {
                parameter("limit", limit)
            }
            val messages: List<Message> = json.decodeFromString(response.bodyAsText())
            Result.success(messages)
        } catch (e: Exception) {
            logger.error(e) { "Failed to get history" }
            Result.failure(e)
        }
    }

    /**
     * Send message - matches Tauri send_message command
     */
    suspend fun sendMessage(conversationId: Long, content: String, messageType: String = "text"): Result<Message> {
        return try {
            logger.info { "Sending message to conversation: $conversationId" }
            val response = client.post("/api/v1/chat/conversations/$conversationId/messages") {
                contentType(ContentType.Application.Json)
                setBody(mapOf(
                    "conversation_id" to conversationId,
                    "content" to content,
                    "message_type" to messageType
                ))
            }
            val message: Message = json.decodeFromString(response.bodyAsText())
            Result.success(message)
        } catch (e: Exception) {
            logger.error(e) { "Failed to send message" }
            Result.failure(e)
        }
    }

    /**
     * Mark messages as read - matches Tauri mark_as_read command
     */
    suspend fun markAsRead(messageIds: List<Long>): Result<Unit> {
        return try {
            logger.info { "Marking messages as read: $messageIds" }
            client.post("/api/v1/chat/conversations/:id/read") {
                contentType(ContentType.Application.Json)
                setBody(mapOf("message_ids" to messageIds))
            }
            Result.success(Unit)
        } catch (e: Exception) {
            logger.error(e) { "Failed to mark as read" }
            Result.failure(e)
        }
    }

    // ==================== Friend Management API ====================

    /**
     * Get friends list
     */
    suspend fun getFriends(): Result<List<Friend>> {
        return try {
            logger.info { "Getting friends list" }
            val response = client.get("/api/v1/friends")
            val result: Map<String, Any?> = json.decodeFromString(response.bodyAsText())
            val success = result["success"] as? Boolean ?: false
            if (success) {
                val data = result["data"] as? List<Map<String, Any?>> ?: emptyList()
                val friends = data.map { item ->
                    Friend(
                        id = (item["id"] as? String) ?: "",
                        username = (item["username"] as? String) ?: "",
                        displayName = (item["display_name"] as? String) ?: "",
                        email = item["email"] as? String,
                        phone = item["phone"] as? String,
                        avatarUrl = item["avatar_url"] as? String,
                        friendStatus = (item["friend_status"] as? String) ?: "accepted",
                        friendSince = (item["friend_since"] as? Long)
                    )
                }
                Result.success(friends)
            } else {
                Result.success(emptyList())
            }
        } catch (e: Exception) {
            logger.error(e) { "Failed to get friends" }
            Result.failure(e)
        }
    }

    /**
     * Send friend request
     */
    suspend fun sendFriendRequest(friendId: String, message: String?): Result<Unit> {
        return try {
            logger.info { "Sending friend request to: $friendId" }
            client.post("/api/v1/friends/add") {
                contentType(ContentType.Application.Json)
                setBody(mapOf("friendId" to friendId, "message" to message))
            }
            Result.success(Unit)
        } catch (e: Exception) {
            logger.error(e) { "Failed to send friend request" }
            Result.failure(e)
        }
    }

    /**
     * Get friend requests
     */
    suspend fun getFriendRequests(): Result<List<FriendRequest>> {
        return try {
            logger.info { "Getting friend requests" }
            val response = client.get("/api/v1/friends/requests")
            val result: Map<String, Any?> = json.decodeFromString(response.bodyAsText())
            val success = result["success"] as? Boolean ?: false
            if (success) {
                val data = result["data"] as? List<Map<String, Any?>> ?: emptyList()
                val requests = data.map { item ->
                    FriendRequest(
                        id = (item["id"] as? Long) ?: 0L,
                        senderId = (item["sender_id"] as? String) ?: "",
                        receiverId = (item["receiver_id"] as? String) ?: "",
                        message = item["message"] as? String,
                        status = (item["status"] as? String) ?: "pending",
                        createdAt = (item["created_at"] as? Long) ?: 0L,
                        senderUsername = (item["sender_username"] as? String) ?: "",
                        senderDisplayName = item["sender_display_name"] as? String,
                        senderAvatar = item["sender_avatar"] as? String
                    )
                }
                Result.success(requests)
            } else {
                Result.success(emptyList())
            }
        } catch (e: Exception) {
            logger.error(e) { "Failed to get friend requests" }
            Result.failure(e)
        }
    }

    /**
     * Accept friend request
     */
    suspend fun acceptFriendRequest(requestId: Long): Result<Unit> {
        return try {
            logger.info { "Accepting friend request: $requestId" }
            client.post("/api/v1/friends/accept") {
                contentType(ContentType.Application.Json)
                setBody(mapOf("requestId" to requestId))
            }
            Result.success(Unit)
        } catch (e: Exception) {
            logger.error(e) { "Failed to accept friend request" }
            Result.failure(e)
        }
    }

    /**
     * Search users
     */
    suspend fun searchUsers(query: String, limit: Int = 20): Result<List<UserSearchResult>> {
        return try {
            logger.info { "Searching users with query: $query" }
            val response = client.get("/api/v1/users/search") {
                parameter("q", query)
                parameter("limit", limit)
            }
            val result: Map<String, Any?> = json.decodeFromString(response.bodyAsText())
            val success = result["success"] as? Boolean ?: false
            if (success) {
                val data = result["data"] as? List<Map<String, Any?>> ?: emptyList()
                val users = data.map { item ->
                    UserSearchResult(
                        id = (item["id"] as? String) ?: "",
                        username = (item["username"] as? String) ?: "",
                        displayName = item["display_name"] as? String,
                        avatarUrl = item["avatar_url"] as? String
                    )
                }
                Result.success(users)
            } else {
                Result.success(emptyList())
            }
        } catch (e: Exception) {
            logger.error(e) { "Failed to search users" }
            Result.failure(e)
        }
    }

    /**
     * Upload file
     */
    suspend fun uploadFile(file: java.io.File, filename: String): Result<UploadResponse> {
        return try {
            logger.info { "Uploading file: $filename" }
            // TODO: Implement multipart file upload using Ktor
            // For now, return placeholder
            Result.success(UploadResponse(
                fileId = "temp-${System.currentTimeMillis()}",
                filename = filename,
                url = "/api/v1/files/temp",
                size = file.length()
            ))
        } catch (e: Exception) {
            logger.error(e) { "Failed to upload file" }
            Result.failure(e)
        }
    }

    fun close() {
        client.close()
    }
}
