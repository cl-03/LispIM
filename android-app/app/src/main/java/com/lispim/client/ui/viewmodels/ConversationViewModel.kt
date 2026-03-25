package com.lispim.client.ui.viewmodels

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.lispim.client.LispIMApplication
import com.lispim.client.model.Message
import com.lispim.client.model.WSMessage
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch
import mu.KotlinLogging

private val logger = KotlinLogging.logger {}

data class ConversationUiState(
    val messages: List<Message> = emptyList(),
    val isLoading: Boolean = false,
    val error: String? = null,
    val connectionState: com.lispim.client.model.WSState = com.lispim.client.model.WSState.DISCONNECTED
)

class ConversationViewModel(
    application: Application,
    private val conversationId: Long
) : AndroidViewModel(application) {

    private val repository = (application as LispIMApplication).repository

    private val _uiState = MutableStateFlow(ConversationUiState())
    val uiState: StateFlow<ConversationUiState> = _uiState.asStateFlow()

    private val _messageInput = MutableStateFlow("")
    val messageInput: StateFlow<String> = _messageInput.asStateFlow()

    init {
        viewModelScope.launch {
            // Subscribe to conversation via WebSocket
            repository.subscribeConversation(conversationId)
        }

        viewModelScope.launch {
            // Observe connection state
            repository.connectionState.collect { state ->
                _uiState.value = _uiState.value.copy(connectionState = state)
            }
        }

        viewModelScope.launch {
            // Load message history
            loadMessages()
        }

        viewModelScope.launch {
            // Listen for WebSocket messages
            repository.getWebSocketMessages()?.collect { wsMessage ->
                handleWebSocketMessage(wsMessage)
            }
        }
    }

    private fun handleWebSocketMessage(wsMessage: WSMessage) {
        when (wsMessage.type) {
            "message:new" -> {
                // New message received
                try {
                    val content = wsMessage.payload["content"]?.toString()?.trim('"') ?: return
                    val senderId = wsMessage.payload["sender_id"]?.toString()?.trim('"') ?: return
                    val messageId = wsMessage.payload["id"]?.toString()?.toLongOrNull() ?: return
                    val timestamp = wsMessage.payload["created_at"]?.toString()?.toLongOrNull() ?: System.currentTimeMillis()

                    val newMessage = Message(
                        id = messageId,
                        sequence = 0,
                        conversationId = conversationId,
                        senderId = senderId,
                        messageType = "text",
                        content = content,
                        createdAt = timestamp
                    )

                    _uiState.value = _uiState.value.copy(
                        messages = _uiState.value.messages + newMessage
                    )
                } catch (e: Exception) {
                    logger.error(e) { "Failed to parse new message" }
                }
            }
            "message:read" -> {
                // Message read receipt
                // Update message read status
            }
        }
    }

    fun loadMessages() {
        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(isLoading = true)
            val result = repository.fetchHistory(conversationId)
            result.fold(
                onSuccess = { messages ->
                    _uiState.value = _uiState.value.copy(
                        messages = messages,
                        isLoading = false
                    )
                },
                onFailure = { e ->
                    _uiState.value = _uiState.value.copy(
                        error = e.message,
                        isLoading = false
                    )
                }
            )
        }
    }

    fun setMessageInput(value: String) {
        _messageInput.value = value
    }

    fun sendMessage() {
        val content = _messageInput.value.trim()
        if (content.isEmpty()) return

        viewModelScope.launch {
            // Send via WebSocket first
            val wsResult = repository.sendMessage(conversationId, content)

            if (wsResult.isFailure) {
                // Fallback to API
                logger.warn { "WebSocket send failed, using API fallback" }
                repository.sendMessageViaApi(conversationId, content)
            }

            // Clear input
            _messageInput.value = ""

            // Mark message as read
            // This would be handled by the server in a real implementation
        }
    }

    fun markAsRead(messageIds: List<Long>) {
        viewModelScope.launch {
            repository.markAsRead(messageIds)
            // Also send via WebSocket
            messageIds.forEach { id ->
                repository.sendReadReceipt(id)
            }
        }
    }
}
