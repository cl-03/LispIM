package com.lispim.app.ui.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.lispim.app.data.local.StorageManager
import com.lispim.app.data.repository.LispIMRepository
import com.lispim.app.data.repository.ChatRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

/**
 * Login Screen ViewModel
 */
@HiltViewModel
class LoginViewModel @Inject constructor(
    private val repository: LispIMRepository,
    private val chatRepository: ChatRepository,
    private val storageManager: StorageManager
) : ViewModel() {

    private val _loginState = MutableStateFlow<LoginState>(LoginState.Idle)
    val loginState: StateFlow<LoginState> = _loginState

    fun login(username: String, password: String, onSuccess: () -> Unit) {
        viewModelScope.launch {
            _loginState.value = LoginState.Loading
            val result = repository.login(username, password)
            result.fold(
                onSuccess = { data ->
                    // Save auth token and user info to local storage
                    storageManager.saveAuthToken(data.token)
                    storageManager.saveUserInfo(data.userId, data.username)

                    // Connect to WebSocket
                    chatRepository.connect(data.token)

                    _loginState.value = LoginState.Success(data)
                    onSuccess()
                },
                onFailure = { error ->
                    _loginState.value = LoginState.Error(error.message ?: "Login failed")
                }
            )
        }
    }

    fun autoLogin(onSuccess: () -> Unit, onFailure: () -> Unit) {
        viewModelScope.launch {
            _loginState.value = LoginState.Loading

            val token = storageManager.authToken.firstOrNull()
            val userId = storageManager.userId.firstOrNull()

            if (token != null && userId != null) {
                // Verify token by getting current user
                val result = repository.getCurrentUser("Bearer $token")
                result.fold(
                    onSuccess = { user ->
                        // Token is valid, connect to WebSocket
                        chatRepository.connect(token)
                        _loginState.value = LoginState.Success(
                            com.lispim.app.data.model.LoginData(
                                userId = user.id,
                                username = user.username,
                                token = token
                            )
                        )
                        onSuccess()
                    },
                    onFailure = {
                        // Token is invalid, clear auth
                        storageManager.clearAuth()
                        _loginState.value = LoginState.Idle
                        onFailure()
                    }
                )
            } else {
                _loginState.value = LoginState.Idle
                onFailure()
            }
        }
    }
}

sealed class LoginState {
    object Idle : LoginState()
    object Loading : LoginState()
    data class Success(val data: com.lispim.app.data.model.LoginData) : LoginState()
    data class Error(val message: String) : LoginState()
}
