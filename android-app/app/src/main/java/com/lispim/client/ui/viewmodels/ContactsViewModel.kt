package com.lispim.client.ui.viewmodels

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.lispim.client.LispIMApplication
import com.lispim.client.model.Friend
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import mu.KotlinLogging

private val logger = KotlinLogging.logger {}

class ContactsViewModel(application: Application) : AndroidViewModel(application) {

    private val repository = (application as LispIMApplication).repository

    private val _uiState = MutableStateFlow<List<Friend>>(emptyList())
    val uiState: StateFlow<List<Friend>> = _uiState.asStateFlow()

    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()

    fun loadFriends() {
        viewModelScope.launch {
            _isLoading.value = true
            // TODO: Implement repository method for getting friends
            // For now, use empty list
            _uiState.value = emptyList()
            _isLoading.value = false
        }
    }

    fun sendFriendRequest(friendId: String, message: String?) {
        viewModelScope.launch {
            // TODO: Implement repository method
            logger.info { "Send friend request to: $friendId" }
        }
    }
}
