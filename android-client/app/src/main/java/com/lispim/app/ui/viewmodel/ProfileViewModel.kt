package com.lispim.app.ui.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.lispim.app.data.model.User
import com.lispim.app.data.model.UserSettings
import com.lispim.app.data.api.LispIMApiService
import com.lispim.app.data.model.ChangePasswordRequest
import com.lispim.app.data.model.UpdateProfileRequest
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

/**
 * Profile UI state
 */
sealed class ProfileUiState {
    object Loading : ProfileUiState()
    data class Success(val user: User) : ProfileUiState()
    data class Error(val message: String) : ProfileUiState()
}

/**
 * Settings UI state
 */
sealed class SettingsUiState {
    object Loading : SettingsUiState()
    data class Success(val settings: UserSettings) : SettingsUiState()
    data class Error(val message: String) : SettingsUiState()
}

/**
 * Action result
 */
sealed class ProfileAction {
    object Success : ProfileAction()
    data class Error(val message: String) : ProfileAction()
}

/**
 * ViewModel for user profile and settings
 */
@HiltViewModel
class ProfileViewModel @Inject constructor(
    private val apiService: LispIMApiService
) : ViewModel() {

    private val _profileState = MutableStateFlow<ProfileUiState>(ProfileUiState.Loading)
    val profileState: StateFlow<ProfileUiState> = _profileState.asStateFlow()

    private val _settings = MutableStateFlow(UserSettings())
    val settings: StateFlow<UserSettings> = _settings.asStateFlow()

    private val _actionState = MutableStateFlow<ProfileAction?>(null)
    val actionState: StateFlow<ProfileAction?> = _actionState.asStateFlow()

    /**
     * Load current user profile
     */
    fun loadProfile(token: String) {
        viewModelScope.launch {
            _profileState.value = ProfileUiState.Loading
            try {
                val response = apiService.getCurrentUser("Bearer $token")
                if (response.isSuccessful && response.body() != null) {
                    val body = response.body()!!
                    if (body.success && body.data != null) {
                        _profileState.value = ProfileUiState.Success(body.data)
                    } else {
                        _profileState.value = ProfileUiState.Error(
                            body.error?.message ?: "Failed to load profile"
                        )
                    }
                } else {
                    _profileState.value = ProfileUiState.Error(
                        "Failed to load profile: ${response.code()}"
                    )
                }
            } catch (e: Exception) {
                _profileState.value = ProfileUiState.Error(e.message ?: "Unknown error")
            }
        }
    }

    /**
     * Update profile
     */
    fun updateProfile(
        token: String,
        displayName: String?,
        email: String?,
        status: String?
    ) {
        viewModelScope.launch {
            try {
                val request = UpdateProfileRequest(displayName, email, status)
                val response = apiService.updateProfile("Bearer $token", request)
                if (response.isSuccessful && response.body() != null) {
                    val body = response.body()!!
                    if (body.success && body.data != null) {
                        _profileState.value = ProfileUiState.Success(body.data)
                        _actionState.value = ProfileAction.Success
                    } else {
                        _actionState.value = ProfileAction.Error(
                            body.error?.message ?: "Failed to update profile"
                        )
                    }
                } else {
                    _actionState.value = ProfileAction.Error(
                        "Failed to update profile: ${response.code()}"
                    )
                }
            } catch (e: Exception) {
                _actionState.value = ProfileAction.Error(e.message ?: "Unknown error")
            }
        }
    }

    /**
     * Change password
     */
    fun changePassword(
        token: String,
        currentPassword: String,
        newPassword: String
    ) {
        viewModelScope.launch {
            try {
                val request = ChangePasswordRequest(currentPassword, newPassword)
                val response = apiService.changePassword("Bearer $token", request)
                if (response.isSuccessful && response.body() != null) {
                    val body = response.body()!!
                    if (body.success) {
                        _actionState.value = ProfileAction.Success
                    } else {
                        _actionState.value = ProfileAction.Error(
                            body.error?.message ?: "Failed to change password"
                        )
                    }
                } else {
                    _actionState.value = ProfileAction.Error(
                        "Failed to change password: ${response.code()}"
                    )
                }
            } catch (e: Exception) {
                _actionState.value = ProfileAction.Error(e.message ?: "Unknown error")
            }
        }
    }

    /**
     * Update settings
     */
    fun updateSettings(settings: UserSettings) {
        _settings.value = settings
        // In production, save to server here
    }

    /**
     * Toggle language
     */
    fun setLanguage(language: String) {
        _settings.value = _settings.value.copy(language = language)
    }

    /**
     * Toggle theme
     */
    fun setTheme(theme: String) {
        _settings.value = _settings.value.copy(theme = theme)
    }

    /**
     * Toggle notifications
     */
    fun setNotificationsEnabled(enabled: Boolean) {
        _settings.value = _settings.value.copy(notificationsEnabled = enabled)
    }

    /**
     * Clear action state
     */
    fun clearActionState() {
        _actionState.value = null
    }
}
