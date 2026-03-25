package com.lispim.client.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * Authentication request matching auth.lisp
 */
@Serializable
data class AuthRequest(
    val username: String,
    val password: String
)

/**
 * Authentication response matching auth.lisp
 * Backend returns: {"success": true, "data": {"userId": "...", "username": "...", "token": "..."}}
 */
@Serializable
data class AuthResponse(
    val success: Boolean,
    val data: AuthData? = null,
    val error: String? = null
) {
    val userId: String? get() = data?.userId
    val username: String? get() = data?.username
    val token: String? get() = data?.token
}

@Serializable
data class AuthData(
    @SerialName("userid")
    val userId: String? = null,
    val username: String? = null,
    val token: String? = null
)

/**
 * User model matching backend user structure
 */
@Serializable
data class User(
    val id: String,
    val username: String,
    @SerialName("display_name")
    val displayName: String,
    val email: String? = null,
    val avatar: String? = null,
    val status: String = "offline"
)

/**
 * Message model matching chat.lisp
 */
@Serializable
data class Message(
    val id: Long,
    val sequence: Long,
    @SerialName("conversation_id")
    val conversationId: Long,
    @SerialName("sender_id")
    val senderId: String,
    @SerialName("message_type")
    val messageType: String = "text",
    val content: String? = null,
    @SerialName("created_at")
    val createdAt: Long = 0,
    @SerialName("edited_at")
    val editedAt: Long? = null,
    @SerialName("read_by")
    val readBy: List<ReadReceipt>? = null
)

/**
 * Read receipt model
 */
@Serializable
data class ReadReceipt(
    @SerialName("user_id")
    val userId: String,
    val timestamp: Long
)

/**
 * Conversation model matching chat.lisp
 */
@Serializable
data class Conversation(
    val id: Long,
    val type: String = "direct",
    val name: String? = null,
    val participants: List<String> = emptyList(),
    @SerialName("last_message")
    val lastMessage: Message? = null,
    @SerialName("last_activity")
    val lastActivity: Long = 0
)

/**
 * Send message request
 */
@Serializable
data class SendMessageRequest(
    @SerialName("conversation_id")
    val conversationId: Long,
    val content: String,
    @SerialName("message_type")
    val messageType: String = "text"
)

/**
 * WebSocket message frame matching gateway.lisp protocol
 */
@Serializable
data class WSMessage(
    val type: String,
    val payload: kotlinx.serialization.json.JsonObject,
    val timestamp: Long
)

/**
 * WebSocket connection state matching gateway.lisp connection-state
 */
enum class WSState {
    DISCONNECTED,
    CONNECTING,
    CONNECTED,
    RECONNECTING,
    CLOSED
}

/**
 * Friend model matching backend friend structure
 */
@Serializable
data class Friend(
    val id: String,
    val username: String,
    @SerialName("display_name")
    val displayName: String,
    val email: String? = null,
    val phone: String? = null,
    @SerialName("avatar_url")
    val avatarUrl: String? = null,
    @SerialName("friend_status")
    val friendStatus: String = "accepted",
    @SerialName("friend_since")
    val friendSince: Long? = null
)

/**
 * Friend request model
 */
@Serializable
data class FriendRequest(
    val id: Long,
    @SerialName("sender_id")
    val senderId: String,
    @SerialName("receiver_id")
    val receiverId: String,
    val message: String? = null,
    val status: String = "pending",
    @SerialName("created_at")
    val createdAt: Long = 0,
    @SerialName("sender_username")
    val senderUsername: String = "",
    @SerialName("sender_display_name")
    val senderDisplayName: String? = null,
    @SerialName("sender_avatar")
    val senderAvatar: String? = null
)

/**
 * User search result model
 */
@Serializable
data class UserSearchResult(
    val id: String,
    val username: String,
    @SerialName("display_name")
    val displayName: String? = null,
    @SerialName("avatar_url")
    val avatarUrl: String? = null
)

/**
 * File upload response model
 */
@Serializable
data class UploadResponse(
    @SerialName("file_id")
    val fileId: String,
    val filename: String,
    val url: String,
    val size: Long
)
