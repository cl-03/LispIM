package com.lispim.client.data

import android.content.Context
import com.lispim.client.model.Conversation
import com.lispim.client.model.Friend
import com.lispim.client.model.FriendRequest
import com.lispim.client.model.Message
import com.lispim.client.model.UploadResponse
import com.lispim.client.model.UserSearchResult
import com.lispim.client.model.WSMessage
import com.lispim.client.model.WSState
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import mu.KotlinLogging

private val logger = KotlinLogging.logger {}

/**
 * Main repository combining API client and WebSocket client
 * Matches Tauri client command patterns
 */
class Repository(context: Context) {

    private val preferencesManager = PreferencesManager(context)
    private var apiClient: ApiClient? = null
    private var wsClient: WebSocketClient? = null

    private val _connectionState = MutableStateFlow(WSState.DISCONNECTED)
    val connectionState: StateFlow<WSState> = _connectionState.asStateFlow()

    private val _currentUser = MutableStateFlow<String?>(null)
    val currentUser: StateFlow<String?> = _currentUser.asStateFlow()

    private val _conversations = MutableStateFlow<List<Conversation>>(emptyList())
    val conversations: StateFlow<List<Conversation>> = _conversations.asStateFlow()

    private val _messages = MutableStateFlow<List<Message>>(emptyList())
    val messages: StateFlow<List<Message>> = _messages.asStateFlow()

    private val scope = kotlinx.coroutines.CoroutineScope(
        kotlinx.coroutines.Dispatchers.IO + kotlinx.coroutines.SupervisorJob()
    )

    init {
        // Observe connection state
        scope.launch {
            wsClient?.state?.collect { state ->
                _connectionState.value = state
            }
        }
    }

    /**
     * Login and setup clients
     */
    suspend fun login(username: String, password: String, serverUrl: String): Result<Unit> {
        return try {
            logger.info { "Login attempt for user: $username" }

            // Create API client and login
            val client = ApiClient(serverUrl)
            val authResult = client.login(username, password)

            authResult.fold(
                onSuccess = { authResponse ->
                    val token = authResponse.token
                    val userId = authResponse.userId
                    val usernameVal = authResponse.username

                    if (authResponse.success && token != null && userId != null) {
                        // Save auth token
                        preferencesManager.saveAuth(
                            token,
                            userId,
                            usernameVal ?: username
                        )

                        // Setup clients with token
                        apiClient = ApiClient(serverUrl, token)
                        _currentUser.value = userId

                        logger.info { "User $usernameVal logged in successfully" }
                        Result.success(Unit)
                    } else {
                        logger.warn { "Login failed: ${authResponse.error}" }
                        Result.failure(Exception(authResponse.error ?: "Login failed"))
                    }
                },
                onFailure = { e ->
                    logger.error(e) { "Login request failed" }
                    Result.failure(e)
                }
            )
        } catch (e: Exception) {
            logger.error(e) { "Login failed" }
            Result.failure(e)
        }
    }

    /**
     * Logout and cleanup
     */
    suspend fun logout() {
        logger.info { "User logging out" }

        // Disconnect WebSocket
        wsClient?.disconnect()
        wsClient?.close()
        wsClient = null

        // Close API client
        apiClient?.close()
        apiClient = null

        // Clear auth
        preferencesManager.clearAuth()
        _currentUser.value = null
        _conversations.value = emptyList()
        _messages.value = emptyList()
    }

    /**
     * Connect to WebSocket
     */
    suspend fun connectWebSocket(wsUrl: String): Result<Unit> {
        return try {
            val token = preferencesManager.tokenFlow.first()
            if (token == null) {
                return Result.failure(Exception("Not authenticated"))
            }

            wsClient?.close()
            wsClient = WebSocketClient(wsUrl, token)
            val result = wsClient?.connect()
            result ?: Result.failure(Exception("Failed to create WebSocket client"))
        } catch (e: Exception) {
            logger.error(e) { "Failed to connect WebSocket" }
            Result.failure(e)
        }
    }

    /**
     * Disconnect WebSocket
     */
    suspend fun disconnectWebSocket() {
        wsClient?.disconnect()
    }

    /**
     * Send message via WebSocket
     */
    suspend fun sendMessage(conversationId: Long, content: String): Result<Unit> {
        return wsClient?.sendMessage(conversationId, content)
            ?: Result.failure(Exception("WebSocket not connected"))
    }

    /**
     * Send read receipt via WebSocket
     */
    suspend fun sendReadReceipt(messageId: Long): Result<Unit> {
        return wsClient?.sendReadReceipt(messageId)
            ?: Result.failure(Exception("WebSocket not connected"))
    }

    /**
     * Subscribe to conversation via WebSocket
     */
    suspend fun subscribeConversation(conversationId: Long): Result<Unit> {
        return wsClient?.subscribeConversation(conversationId)
            ?: Result.failure(Exception("WebSocket not connected"))
    }

    /**
     * Get WebSocket messages
     */
    suspend fun getWebSocketMessages(): Flow<WSMessage>? {
        return wsClient?.messages
    }

    /**
     * Get conversations from API
     */
    suspend fun fetchConversations(): Result<List<Conversation>> {
        return apiClient?.getConversations()
            ?: Result.failure(Exception("API client not initialized"))
    }

    /**
     * Get message history from API
     */
    suspend fun fetchHistory(conversationId: Long, limit: Int = 50): Result<List<Message>> {
        return apiClient?.getHistory(conversationId, limit)
            ?: Result.failure(Exception("API client not initialized"))
    }

    /**
     * Send message via API (fallback)
     */
    suspend fun sendMessageViaApi(conversationId: Long, content: String): Result<Message> {
        return apiClient?.sendMessage(conversationId, content)
            ?: Result.failure(Exception("API client not initialized"))
    }

    /**
     * Mark messages as read via API
     */
    suspend fun markAsRead(messageIds: List<Long>): Result<Unit> {
        return apiClient?.markAsRead(messageIds)
            ?: Result.failure(Exception("API client not initialized"))
    }

    /**
     * Check if user is logged in
     */
    suspend fun isLoggedIn(): Boolean {
        return preferencesManager.isLoggedIn()
    }

    /**
     * Get current server URL
     */
    suspend fun getServerUrl(): String {
        return preferencesManager.serverUrlFlow.first()
    }

    /**
     * Get current WebSocket URL
     */
    suspend fun getWsUrl(): String {
        return preferencesManager.wsUrlFlow.first()
    }

    /**
     * Save server URL
     */
    suspend fun saveServerUrl(serverUrl: String) {
        val wsUrl = deriveWsUrl(serverUrl)
        preferencesManager.saveServerUrls(serverUrl, wsUrl)
    }

    /**
     * Derive WebSocket URL from HTTP server URL
     */
    private fun deriveWsUrl(httpUrl: String): String {
        return httpUrl
            .replace("http://", "ws://")
            .replace("https://", "wss://")
            .trimEnd('/') + "/ws"
    }

    // ==================== Friend Management ====================

    /**
     * Get friends list
     */
    suspend fun getFriends(): Result<List<Friend>> {
        return apiClient?.getFriends()
            ?: Result.failure(Exception("API client not initialized"))
    }

    /**
     * Send friend request
     */
    suspend fun sendFriendRequest(friendId: String, message: String?): Result<Unit> {
        return apiClient?.sendFriendRequest(friendId, message)
            ?: Result.failure(Exception("API client not initialized"))
    }

    /**
     * Get friend requests
     */
    suspend fun getFriendRequests(): Result<List<FriendRequest>> {
        return apiClient?.getFriendRequests()
            ?: Result.failure(Exception("API client not initialized"))
    }

    /**
     * Accept friend request
     */
    suspend fun acceptFriendRequest(requestId: Long): Result<Unit> {
        return apiClient?.acceptFriendRequest(requestId)
            ?: Result.failure(Exception("API client not initialized"))
    }

    /**
     * Search users
     */
    suspend fun searchUsers(query: String, limit: Int = 20): Result<List<UserSearchResult>> {
        return apiClient?.searchUsers(query, limit)
            ?: Result.failure(Exception("API client not initialized"))
    }

    // ==================== File Upload ====================

    /**
     * Upload file
     */
    suspend fun uploadFile(file: java.io.File, filename: String): Result<UploadResponse> {
        return apiClient?.uploadFile(file, filename)
            ?: Result.failure(Exception("API client not initialized"))
    }
}
