package com.lispim.app.data.api

import com.lispim.app.data.model.*
import retrofit2.Response
import retrofit2.http.*

/**
 * LispIM API Service
 * Base URL: http://localhost:3000/api/v1/
 */
interface LispIMApiService {

    // ========== Authentication ==========

    /**
     * Login with username and password
     * POST /api/v1/auth/login
     */
    @POST("auth/login")
    suspend fun login(@Body request: LoginRequest): Response<LoginResponse>

    /**
     * Register new user
     * POST /api/v1/auth/register
     */
    @POST("auth/register")
    suspend fun register(@Body request: RegisterRequest): Response<RegisterResponse>

    /**
     * Logout current session
     * POST /api/v1/auth/logout
     */
    @POST("auth/logout")
    suspend fun logout(@Header("Authorization") token: String): Response<ApiResponse<Unit>>

    /**
     * Get current user info
     * GET /api/v1/users/me
     */
    @GET("users/me")
    suspend fun getCurrentUser(@Header("Authorization") token: String): Response<ApiResponse<User>>

    // ========== User ==========

    /**
     * Get current user info
     * GET /api/v1/users/me
     */
    @GET("users/me")
    suspend fun getCurrentUser(@Header("Authorization") token: String): Response<ApiResponse<User>>

    /**
     * Update user profile
     * PUT /api/v1/users/profile
     */
    @PUT("users/profile")
    suspend fun updateProfile(
        @Header("Authorization") token: String,
        @Body profile: UpdateProfileRequest
    ): Response<ApiResponse<User>>

    /**
     * Change password
     * POST /api/v1/users/change-password
     */
    @POST("users/change-password")
    suspend fun changePassword(
        @Header("Authorization") token: String,
        @Body request: ChangePasswordRequest
    ): Response<ApiResponse<Unit>>

    /**
     * Upload avatar
     * POST /api/v1/users/avatar
     */
    @POST("users/avatar")
    suspend fun uploadAvatar(
        @Header("Authorization") token: String,
        @Body request: UploadAvatarRequest
    ): Response<ApiResponse<User>>

    // ========== Conversations ==========

    /**
     * Get conversations list
     * GET /api/v1/chat/conversations
     */
    @GET("chat/conversations")
    suspend fun getConversations(
        @Header("Authorization") token: String,
        @Query("type") type: String? = null,
        @Query("page") page: Int = 1,
        @Query("page_size") pageSize: Int = 20
    ): Response<ApiResponse<ConversationsResponse>>

    /**
     * Get conversation messages
     * GET /api/v1/chat/conversations/{conversationId}/messages
     */
    @GET("chat/conversations/{conversationId}/messages")
    suspend fun getMessages(
        @Header("Authorization") token: String,
        @Path("conversationId") conversationId: String,
        @Query("before") before: String? = null,
        @Query("limit") limit: Int = 20
    ): Response<ApiResponse<MessagesResponse>>

    /**
     * Send message
     * POST /api/v1/chat/conversations/{conversationId}/messages
     */
    @POST("chat/conversations/{conversationId}/messages")
    suspend fun sendMessage(
        @Header("Authorization") token: String,
        @Path("conversationId") conversationId: String,
        @Body message: SendMessageRequest
    ): Response<ApiResponse<Message>>

    /**
     * Mark conversation as read
     * POST /api/v1/chat/conversations/{conversationId}/read
     */
    @POST("chat/conversations/{conversationId}/read")
    suspend fun markAsRead(
        @Header("Authorization") token: String,
        @Path("conversationId") conversationId: String
    ): Response<ApiResponse<Unit>>

    /**
     * Recall message
     * POST /api/v1/chat/messages/{messageId}/recall
     */
    @POST("chat/messages/{messageId}/recall")
    suspend fun recallMessage(
        @Header("Authorization") token: String,
        @Path("messageId") messageId: String
    ): Response<ApiResponse<Unit>>

    // ========== Friends ==========

    /**
     * Get friends list
     * GET /api/v1/friends
     */
    @GET("friends")
    suspend fun getFriends(@Header("Authorization") token: String): Response<ApiResponse<List<Friend>>>

    /**
     * Add friend request
     * POST /api/v1/friends/add
     */
    @POST("friends/add")
    suspend fun addFriend(
        @Header("Authorization") token: String,
        @Body request: AddFriendRequest
    ): Response<ApiResponse<Unit>>

    /**
     * Get friend requests
     * GET /api/v1/friends/requests
     */
    @GET("friends/requests")
    suspend fun getFriendRequests(@Header("Authorization") token: String): Response<ApiResponse<FriendRequestsResponse>>

    /**
     * Accept friend request
     * POST /api/v1/friends/accept
     */
    @POST("friends/accept")
    suspend fun acceptFriendRequest(
        @Header("Authorization") token: String,
        @Body request: AcceptFriendRequest
    ): Response<ApiResponse<Unit>>

    /**
     * Reject friend request
     * POST /api/v1/friends/reject
     */
    @POST("friends/reject")
    suspend fun rejectFriendRequest(
        @Header("Authorization") token: String,
        @Body request: AcceptFriendRequest
    ): Response<ApiResponse<Unit>>

    /**
     * Delete friend
     * POST /api/v1/friends/delete
     */
    @POST("friends/delete")
    suspend fun deleteFriend(
        @Header("Authorization") token: String,
        @Body request: AddFriendRequest
    ): Response<ApiResponse<Unit>>

    /**
     * Search users
     * GET /api/v1/users/search
     */
    @GET("users/search")
    suspend fun searchUsers(
        @Header("Authorization") token: String,
        @Query("q") query: String,
        @Query("limit") limit: Int = 20
    ): Response<ApiResponse<List<User>>>

    // ========== File Upload ==========

    /**
     * Upload file
     * POST /api/v1/upload
     */
    @Multipart
    @POST("upload")
    suspend fun uploadFile(
        @Header("Authorization") token: String,
        @Part file: okhttp3.MultipartBody.Part
    ): Response<ApiResponse<UploadResponse>>

    /**
     * Get file
     * GET /api/v1/files/{fileId}
     */
    @GET("files/{fileId}")
    suspend fun getFile(
        @Header("Authorization") token: String,
        @Path("fileId") fileId: String
    ): Response<okhttp3.ResponseBody>

    // ========== Device / FCM ==========

    /**
     * Register FCM token
     * POST /api/v1/device/fcm-token
     */
    @POST("device/fcm-token")
    suspend fun registerFcmToken(
        @Header("Authorization") token: String,
        @Body request: FcmTokenRequest
    ): Response<ApiResponse<Unit>>

    /**
     * Remove FCM token
     * DELETE /api/v1/device/fcm-token
     */
    @DELETE("device/fcm-token")
    suspend fun removeFcmToken(
        @Header("Authorization") token: String,
        @Body request: FcmTokenRemoveRequest
    ): Response<ApiResponse<Unit>>

    /**
     * Get FCM tokens
     * GET /api/v1/device/fcm-token
     */
    @GET("device/fcm-token")
    suspend fun getFcmTokens(@Header("Authorization") token: String): Response<ApiResponse<FcmTokensResponse>>
}

// ========== Request/Response Helpers ==========

data class ConversationsResponse(
    @SerializedName("conversations") val conversations: List<Conversation>,
    @SerializedName("total") val total: Int
)

data class MessagesResponse(
    @SerializedName("messages") val messages: List<Message>,
    @SerializedName("has-more") val hasMore: Boolean
)

data class SendMessageRequest(
    @SerializedName("content") val content: String,
    @SerializedName("type") val type: String = "text"
)

data class AddFriendRequest(
    @SerializedName("friendId") val friendId: String,
    @SerializedName("message") val message: String?
)

data class FriendRequestsResponse(
    @SerializedName("requests") val requests: List<FriendRequest>
)

data class FriendRequest(
    @SerializedName("id") val id: String,
    @SerializedName("senderId") val senderId: String,
    @SerializedName("senderUsername") val senderUsername: String,
    @SerializedName("senderDisplayName") val senderDisplayName: String?,
    @SerializedName("message") val message: String?
)

data class FriendRequestAction(
    @SerializedName("requestId") val requestId: String
)

/**
 * Accept friend request
 */
data class AcceptFriendRequest(
    @SerializedName("requestId") val requestId: String
)

/**
 * Add friend request
 */
data class AddFriendRequest(
    @SerializedName("friendId") val friendId: String,
    @SerializedName("message") val message: String?
)

data class UploadResponse(
    @SerializedName("fileId") val fileId: String,
    @SerializedName("filename") val filename: String,
    @SerializedName("url") val url: String,
    @SerializedName("size") val size: Long
)

data class FcmTokenRemoveRequest(
    @SerializedName("deviceId") val deviceId: String
)

data class FcmTokensResponse(
    @SerializedName("devices") val devices: List<FcmDevice>
)

data class FcmDevice(
    @SerializedName("device-id") val deviceId: String,
    @SerializedName("platform") val platform: String,
    @SerializedName("fcm-token") val fcmToken: String,
    @SerializedName("device-name") val deviceName: String?,
    @SerializedName("push-enabled") val pushEnabled: Boolean
)
