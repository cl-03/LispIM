package com.lispim.client.ui.viewmodels

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.lispim.client.LispIMApplication
import com.lispim.client.model.Conversation
import com.lispim.client.model.Message
import com.lispim.client.model.WSMessage
import com.lispim.client.model.WSState
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch
import mu.KotlinLogging

private val logger = KotlinLogging.logger {}

sealed class LoginUiState {
    object Idle : LoginUiState()
    object Loading : LoginUiState()
    object Success : LoginUiState()
    data class Error(val message: String) : LoginUiState()
}

class LoginViewModel(application: Application) : AndroidViewModel(application) {

    private val repository = (application as LispIMApplication).repository

    private val _username = MutableStateFlow("")
    val username: StateFlow<String> = _username.asStateFlow()

    private val _password = MutableStateFlow("")
    val password: StateFlow<String> = _password.asStateFlow()

    private val _serverUrl = MutableStateFlow(LispIMApplication.DEFAULT_SERVER_URL)
    val serverUrl: StateFlow<String> = _serverUrl.asStateFlow()

    private val _uiState = MutableStateFlow<LoginUiState>(LoginUiState.Idle)
    val uiState: StateFlow<LoginUiState> = _uiState.asStateFlow()

    init {
        // Load saved server URL from preferences
        viewModelScope.launch {
            repository.getServerUrl().let { savedUrl ->
                if (savedUrl.isNotEmpty()) {
                    _serverUrl.value = savedUrl
                }
            }
        }
    }

    fun setUsername(value: String) {
        _username.value = value
    }

    fun setPassword(value: String) {
        _password.value = value
    }

    fun setServerUrl(value: String) {
        _serverUrl.value = value
    }

    fun login() {
        viewModelScope.launch {
            _uiState.value = LoginUiState.Loading

            val result = repository.login(
                username = _username.value,
                password = _password.value,
                serverUrl = _serverUrl.value
            )

            result.fold(
                onSuccess = {
                    // Save server URL for next login
                    repository.saveServerUrl(_serverUrl.value)

                    // Connect WebSocket after successful login
                    val wsUrl = deriveWsUrl(_serverUrl.value)
                    val wsResult = repository.connectWebSocket(wsUrl)

                    if (wsResult.isSuccess) {
                        _uiState.value = LoginUiState.Success
                    } else {
                        // Login succeeded but WebSocket failed - still consider login successful
                        logger.warn { "WebSocket connection failed, but login succeeded" }
                        _uiState.value = LoginUiState.Success
                    }
                },
                onFailure = { e ->
                    _uiState.value = LoginUiState.Error(e.message ?: "Login failed")
                }
            )
        }
    }

    private fun deriveWsUrl(httpUrl: String): String {
        return httpUrl
            .replace("http://", "ws://")
            .replace("https://", "wss://")
            .trimEnd('/') + "/ws"
    }
}
