package com.lispim.app.ui.viewmodel

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.lispim.app.data.local.entity.MessageEntity
import com.lispim.app.data.repository.ChatRepository
import com.lispim.app.data.websocket.ConnectionState
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch
import javax.inject.Inject

@HiltViewModel
class ChatViewModel @Inject constructor(
    private val chatRepository: ChatRepository,
    savedStateHandle: SavedStateHandle
) : ViewModel() {

    private val conversationId: String = savedStateHandle["conversationId"] ?: ""

    val messages: StateFlow<List<MessageEntity>> = chatRepository.messages
        .map { it[conversationId] ?: emptyList() }
        .stateIn(viewModelScope, SharingStarted.Lazily, emptyList())

    val connectionState: StateFlow<ConnectionState> = chatRepository.getConnectionState()

    val typingUsers: StateFlow<Set<String>> = chatRepository.typingUsers
        .map { it[conversationId] ?: emptySet() }
        .stateIn(viewModelScope, SharingStarted.Lazily, emptySet())

    private val _authToken = MutableStateFlow<String?>(null)
    val authToken: StateFlow<String?> = _authToken.asStateFlow()

    fun setAuthToken(token: String?) {
        _authToken.value = token
    }

    fun connect(token: String) {
        setAuthToken(token)
        chatRepository.connect(token)
    }

    fun disconnect() {
        chatRepository.disconnect()
    }

    fun sendMessage(content: String, type: String = "text") {
        if (conversationId.isEmpty()) return
        chatRepository.sendMessage(conversationId, content, type)
    }

    /**
     * Send file message
     */
    fun sendFileMessage(
        fileId: String,
        fileName: String,
        fileSize: Long,
        mimeType: String
    ) {
        if (conversationId.isEmpty()) return
        chatRepository.sendFileMessage(conversationId, fileId, fileName, fileSize, mimeType)
    }

    fun sendTypingIndicator() {
        if (conversationId.isEmpty()) return
        chatRepository.sendTypingIndicator(conversationId)
    }

    fun sendAck(messageId: String) {
        chatRepository.sendAck(messageId)
    }

    fun getLocalMessages(): Flow<List<MessageEntity>> {
        return chatRepository.getLocalMessages(conversationId)
    }
}
