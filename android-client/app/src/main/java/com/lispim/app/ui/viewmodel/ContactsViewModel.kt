package com.lispim.app.ui.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.lispim.app.data.model.Friend
import com.lispim.app.data.model.FriendRequest
import com.lispim.app.data.model.User
import com.lispim.app.data.repository.ContactsRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

/**
 * Contacts UI state
 */
sealed class ContactsUiState {
    object Loading : ContactsUiState()
    data class Success(val friends: List<Friend>) : ContactsUiState()
    data class Error(val message: String) : ContactsUiState()
    object Empty : ContactsUiState()
}

/**
 * Friend requests UI state
 */
sealed class FriendRequestsUiState {
    object Loading : FriendRequestsUiState()
    data class Success(val requests: List<FriendRequest>) : FriendRequestsUiState()
    data class Error(val message: String) : FriendRequestsUiState()
    object Empty : FriendRequestsUiState()
}

/**
 * Search UI state
 */
sealed class SearchUiState {
    object Idle : SearchUiState()
    object Searching : SearchUiState()
    data class Results(val users: List<User>) : SearchUiState()
    data class Error(val message: String) : SearchUiState()
    object NoResults : SearchUiState()
}

/**
 * Action result for friend operations
 */
sealed class FriendAction {
    object Success : FriendAction()
    data class Error(val message: String) : FriendAction()
}

/**
 * ViewModel for contacts and friend management
 */
@HiltViewModel
class ContactsViewModel @Inject constructor(
    private val contactsRepository: ContactsRepository
) : ViewModel() {

    private val _uiState = MutableStateFlow<ContactsUiState>(ContactsUiState.Loading)
    val uiState: StateFlow<ContactsUiState> = _uiState.asStateFlow()

    private val _requestsState = MutableStateFlow<FriendRequestsUiState>(FriendRequestsUiState.Loading)
    val requestsState: StateFlow<FriendRequestsUiState> = _requestsState.asStateFlow()

    private val _searchState = MutableStateFlow<SearchUiState>(SearchUiState.Idle)
    val searchState: StateFlow<SearchUiState> = _searchState.asStateFlow()

    private val _actionState = MutableStateFlow<FriendAction?>(null)
    val actionState: StateFlow<FriendAction?> = _actionState.asStateFlow()

    /**
     * Load friends list
     */
    fun loadFriends(token: String) {
        viewModelScope.launch {
            _uiState.value = ContactsUiState.Loading
            val result = contactsRepository.loadFriends(token)
            _uiState.value = when {
                result.isSuccess -> {
                    val friends = result.getOrNull()!!
                    if (friends.isEmpty()) ContactsUiState.Empty
                    else ContactsUiState.Success(friends)
                }
                else -> ContactsUiState.Error(result.exceptionOrNull()?.message ?: "Failed to load friends")
            }
        }
    }

    /**
     * Load friend requests
     */
    fun loadFriendRequests(token: String) {
        viewModelScope.launch {
            _requestsState.value = FriendRequestsUiState.Loading
            val result = contactsRepository.loadFriendRequests(token)
            _requestsState.value = when {
                result.isSuccess -> {
                    val requests = result.getOrNull()!!
                    if (requests.isEmpty()) FriendRequestsUiState.Empty
                    else FriendRequestsUiState.Success(requests)
                }
                else -> FriendRequestsUiState.Error(result.exceptionOrNull()?.message ?: "Failed to load requests")
            }
        }
    }

    /**
     * Send friend request
     */
    fun sendFriendRequest(token: String, friendId: String, message: String? = null) {
        viewModelScope.launch {
            val result = contactsRepository.sendFriendRequest(token, friendId, message)
            _actionState.value = when {
                result.isSuccess -> FriendAction.Success
                else -> FriendAction.Error(result.exceptionOrNull()?.message ?: "Failed to send request")
            }
        }
    }

    /**
     * Accept friend request
     */
    fun acceptFriendRequest(token: String, requestId: String) {
        viewModelScope.launch {
            val result = contactsRepository.acceptFriendRequest(token, requestId)
            _actionState.value = when {
                result.isSuccess -> FriendAction.Success
                else -> FriendAction.Error(result.exceptionOrNull()?.message ?: "Failed to accept request")
            }
        }
    }

    /**
     * Reject friend request
     */
    fun rejectFriendRequest(token: String, requestId: String) {
        viewModelScope.launch {
            val result = contactsRepository.rejectFriendRequest(token, requestId)
            _actionState.value = when {
                result.isSuccess -> FriendAction.Success
                else -> FriendAction.Error(result.exceptionOrNull()?.message ?: "Failed to reject request")
            }
        }
    }

    /**
     * Delete friend
     */
    fun deleteFriend(token: String, friendId: String) {
        viewModelScope.launch {
            val result = contactsRepository.deleteFriend(token, friendId)
            _actionState.value = when {
                result.isSuccess -> FriendAction.Success
                else -> FriendAction.Error(result.exceptionOrNull()?.message ?: "Failed to delete friend")
            }
        }
    }

    /**
     * Search users
     */
    fun searchUsers(token: String, query: String) {
        viewModelScope.launch {
            if (query.isBlank()) {
                _searchState.value = SearchUiState.Idle
                contactsRepository.clearSearchResults()
                return@launch
            }
            _searchState.value = SearchUiState.Searching
            val result = contactsRepository.searchUsers(token, query)
            _searchState.value = when {
                result.isSuccess -> {
                    val users = result.getOrNull()!!
                    if (users.isEmpty()) SearchUiState.NoResults
                    else SearchUiState.Results(users)
                }
                else -> SearchUiState.Error(result.exceptionOrNull()?.message ?: "Search failed")
            }
        }
    }

    /**
     * Clear search
     */
    fun clearSearch() {
        _searchState.value = SearchUiState.Idle
        contactsRepository.clearSearchResults()
    }

    /**
     * Clear action state
     */
    fun clearActionState() {
        _actionState.value = null
    }
}
