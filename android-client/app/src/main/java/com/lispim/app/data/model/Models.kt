package com.lispim.app.data.model

import com.google.gson.annotations.SerializedName

/**
 * User data model
 */
data class User(
    @SerializedName("id") val id: String,
    @SerializedName("username") val username: String,
    @SerializedName("displayName") val displayName: String?,
    @SerializedName("email") val email: String?,
    @SerializedName("avatar") val avatar: String?,
    @SerializedName("status") val status: String?
)

/**
 * Login request
 */
data class LoginRequest(
    @SerializedName("username") val username: String,
    @SerializedName("password") val password: String
)

/**
 * Login response
 */
data class LoginResponse(
    @SerializedName("success") val success: Boolean,
    @SerializedName("data") val data: LoginData?,
    @SerializedName("error") val error: ErrorData?
)

data class LoginData(
    @SerializedName("userId") val userId: String,
    @SerializedName("username") val username: String,
    @SerializedName("token") val token: String
)

/**
 * Register request
 */
data class RegisterRequest(
    @SerializedName("method") val method: String = "username",
    @SerializedName("username") val username: String,
    @SerializedName("password") val password: String,
    @SerializedName("email") val email: String,
    @SerializedName("display-name") val displayName: String?
)

/**
 * Register response
 */
data class RegisterResponse(
    @SerializedName("success") val success: Boolean,
    @SerializedName("data") val data: RegisterData?,
    @SerializedName("error") val error: ErrorData?
)

data class RegisterData(
    @SerializedName("userId") val userId: String,
    @SerializedName("token") val token: String?
)

/**
 * Generic API response wrapper
 */
data class ApiResponse<T>(
    @SerializedName("success") val success: Boolean,
    @SerializedName("data") val data: T?,
    @SerializedName("error") val error: ErrorData?,
    @SerializedName("message") val message: String?
)

/**
 * Error data model
 */
data class ErrorData(
    @SerializedName("code") val code: String,
    @SerializedName("message") val message: String,
    @SerializedName("details") val details: String?
)

/**
 * Conversation data model
 */
data class Conversation(
    @SerializedName("id") val id: String,
    @SerializedName("name") val name: String?,
    @SerializedName("type") val type: String,
    @SerializedName("lastMessage") val lastMessage: String?,
    @SerializedName("unreadCount") val unreadCount: Int,
    @SerializedName("avatarUrl") val avatarUrl: String?,
    @SerializedName("createdAt") val createdAt: Long
)

/**
 * Message data model
 */
data class Message(
    @SerializedName("id") val id: String,
    @SerializedName("conversationId") val conversationId: String,
    @SerializedName("senderId") val senderId: String,
    @SerializedName("content") val content: String,
    @SerializedName("type") val type: String,
    @SerializedName("createdAt") val createdAt: Long,
    @SerializedName("sender") val sender: User?
)

/**
 * FCM Token registration request
 */
data class FcmTokenRequest(
    @SerializedName("fcmToken") val fcmToken: String,
    @SerializedName("deviceId") val deviceId: String,
    @SerializedName("platform") val platform: String = "android",
    @SerializedName("deviceName") val deviceName: String,
    @SerializedName("appVersion") val appVersion: String,
    @SerializedName("osVersion") val osVersion: String
)

/**
 * Friend data model
 */
data class Friend(
    @SerializedName("id") val id: String,
    @SerializedName("username") val username: String,
    @SerializedName("displayName") val displayName: String?,
    @SerializedName("avatar") val avatar: String?,
    @SerializedName("status") val status: String?,
    @SerializedName("email") val email: String?
)

/**
 * Friend request data model
 */
data class FriendRequest(
    @SerializedName("id") val id: String,
    @SerializedName("senderId") val senderId: String,
    @SerializedName("senderUsername") val senderUsername: String,
    @SerializedName("senderDisplayName") val senderDisplayName: String?,
    @SerializedName("message") val message: String?,
    @SerializedName("createdAt") val createdAt: Long?
)

/**
 * Friend requests response
 */
data class FriendRequestsResponse(
    @SerializedName("requests") val requests: List<FriendRequest>
)

/**
 * Add friend request
 */
data class AddFriendRequest(
    @SerializedName("friendId") val friendId: String,
    @SerializedName("message") val message: String?
)

/**
 * Accept friend request
 */
data class AcceptFriendRequest(
    @SerializedName("requestId") val requestId: String
)

/**
 * User search response
 */
data class UserSearchResponse(
    @SerializedName("users") val users: List<User>
)

/**
 * Update profile request
 */
data class UpdateProfileRequest(
    @SerializedName("displayName") val displayName: String?,
    @SerializedName("email") val email: String?,
    @SerializedName("status") val status: String?
)

/**
 * Change password request
 */
data class ChangePasswordRequest(
    @SerializedName("currentPassword") val currentPassword: String,
    @SerializedName("newPassword") val newPassword: String
)

/**
 * Upload avatar request
 */
data class UploadAvatarRequest(
    @SerializedName("avatarUrl") val avatarUrl: String
)

/**
 * User settings
 */
data class UserSettings(
    @SerializedName("language") val language: String = "zh-CN",
    @SerializedName("theme") val theme: String = "system",
    @SerializedName("notificationsEnabled") val notificationsEnabled: Boolean = true,
    @SerializedName("soundEnabled") val soundEnabled: Boolean = true,
    @SerializedName("vibrationEnabled") val vibrationEnabled: Boolean = true,
    @SerializedName("doNotDisturb") val doNotDisturb: Boolean = false
)
