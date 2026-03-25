package com.lispim.app.ui.viewmodel

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.google.firebase.messaging.FirebaseMessaging
import com.lispim.app.data.repository.DeviceRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.tasks.await
import javax.inject.Inject

/**
 * Push notification UI state
 */
sealed class PushNotificationUiState {
    object Idle : PushNotificationUiState()
    object Loading : PushNotificationUiState()
    data class Success(val message: String) : PushNotificationUiState()
    data class Error(val message: String) : PushNotificationUiState()
}

/**
 * ViewModel for push notification management
 */
@HiltViewModel
class PushNotificationViewModel @Inject constructor(
    application: Application,
    private val deviceRepository: DeviceRepository
) : AndroidViewModel(application) {

    private val _uiState = MutableStateFlow<PushNotificationUiState>(PushNotificationUiState.Idle)
    val uiState: StateFlow<PushNotificationUiState> = _uiState.asStateFlow()

    private val _pushEnabled = MutableStateFlow(true)
    val pushEnabled: StateFlow<Boolean> = _pushEnabled.asStateFlow()

    private var currentFcmToken: String? = null

    /**
     * Register FCM token
     */
    fun registerFcmToken(authToken: String) {
        viewModelScope.launch {
            _uiState.value = PushNotificationUiState.Loading

            try {
                // Get FCM token
                val token = FirebaseMessaging.getInstance().token.await()
                currentFcmToken = token

                // Get device info
                val deviceId = android.os.Build.SERIAL.ifEmpty {
                    android.provider.Settings.Secure.getString(
                        getApplication<Application>().contentResolver,
                        android.provider.Settings.Secure.ANDROID_ID
                    ) ?: "unknown"
                }
                val deviceName = "${android.os.Build.MANUFACTURER} ${android.os.Build.MODEL}"
                val platform = "android"
                val appVersion = getApplication<Application>().packageManager
                    .getPackageInfo(getApplication<Application>().packageName, 0).versionName ?: "1.0.0"
                val osVersion = android.os.Build.VERSION.RELEASE

                // Register with server
                val result = deviceRepository.registerFcmToken(
                    token = token,
                    deviceId = deviceId,
                    platform = platform,
                    deviceName = deviceName,
                    appVersion = appVersion,
                    osVersion = osVersion,
                    authToken = authToken
                )

                _uiState.value = if (result.isSuccess) {
                    PushNotificationUiState.Success("FCM token registered")
                } else {
                    PushNotificationUiState.Error(result.exceptionOrNull()?.message ?: "Failed to register")
                }
            } catch (e: Exception) {
                _uiState.value = PushNotificationUiState.Error(e.message ?: "Failed to register FCM")
            }
        }
    }

    /**
     * Remove FCM token
     */
    fun removeFcmToken(deviceId: String, authToken: String) {
        viewModelScope.launch {
            _uiState.value = PushNotificationUiState.Loading

            val result = deviceRepository.removeFcmToken(deviceId, authToken)

            _uiState.value = if (result.isSuccess) {
                PushNotificationUiState.Success("FCM token removed")
            } else {
                PushNotificationUiState.Error(result.exceptionOrNull()?.message ?: "Failed to remove")
            }
        }
    }

    /**
     * Load FCM tokens
     */
    fun loadFcmTokens(authToken: String) {
        viewModelScope.launch {
            _uiState.value = PushNotificationUiState.Loading

            val result = deviceRepository.loadFcmTokens(authToken)

            _uiState.value = if (result.isSuccess) {
                val tokens = result.getOrNull()!!
                if (tokens.any { it.fcmToken == currentFcmToken }) {
                    _pushEnabled.value = tokens.first { it.fcmToken == currentFcmToken }.pushEnabled
                }
                PushNotificationUiState.Success("Loaded ${tokens.size} devices")
            } else {
                PushNotificationUiState.Error(result.exceptionOrNull()?.message ?: "Failed to load")
            }
        }
    }

    /**
     * Toggle push notifications
     */
    fun togglePushNotifications(enabled: Boolean) {
        _pushEnabled.value = enabled
        // In production, update server setting here
    }

    /**
     * Clear state
     */
    fun clearState() {
        _uiState.value = PushNotificationUiState.Idle
    }
}
