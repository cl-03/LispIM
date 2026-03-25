package com.lispim.client.ui.viewmodels

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.lispim.client.LispIMApplication
import com.lispim.client.model.User
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import mu.KotlinLogging

private val logger = KotlinLogging.logger {}

class ProfileViewModel(application: Application) : AndroidViewModel(application) {

    private val repository = (application as LispIMApplication).repository

    private val _user = MutableStateFlow<User?>(null)
    val user: StateFlow<User?> = _user.asStateFlow()

    init {
        viewModelScope.launch {
            repository.currentUser.collect { userId ->
                // Load user info when userId changes
                userId?.let {
                    // TODO: Load user details from API
                    _user.value = User(
                        id = userId,
                        username = "user",
                        displayName = "User"
                    )
                }
            }
        }
    }

    fun logout() {
        viewModelScope.launch {
            repository.logout()
        }
    }
}
