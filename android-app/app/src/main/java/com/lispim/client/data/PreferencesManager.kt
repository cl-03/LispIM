package com.lispim.client.data

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import com.lispim.client.model.User
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import mu.KotlinLogging

private val Context.dataStore: DataStore<Preferences> by preferencesDataStore(name = "settings")
private val logger = KotlinLogging.logger {}

/**
 * Default server URLs for Android emulator
 * - 10.0.2.2 is the host machine's loopback interface for Android emulator
 * - For physical devices, configure your actual server IP/domain
 */
const val DEFAULT_SERVER_HOST = "10.0.2.2"
const val DEFAULT_SERVER_PORT = "4321"

class PreferencesManager(private val context: Context) {

    companion object {
        val KEY_TOKEN = stringPreferencesKey("auth_token")
        val KEY_USER_ID = stringPreferencesKey("user_id")
        val KEY_USERNAME = stringPreferencesKey("username")
        val KEY_SERVER_URL = stringPreferencesKey("server_url")
        val KEY_WS_URL = stringPreferencesKey("ws_url")

        /**
         * Get default server URL for Android emulator
         */
        fun getDefaultServerUrl(): String {
            return "http://${DEFAULT_SERVER_HOST}:${DEFAULT_SERVER_PORT}"
        }

        /**
         * Get default WebSocket URL for Android emulator
         */
        fun getDefaultWsUrl(): String {
            return "ws://${DEFAULT_SERVER_HOST}:${DEFAULT_SERVER_PORT}/ws"
        }
    }

    val tokenFlow: Flow<String?> = context.dataStore.data.map { preferences ->
        preferences[KEY_TOKEN]
    }

    val userIdFlow: Flow<String?> = context.dataStore.data.map { preferences ->
        preferences[KEY_USER_ID]
    }

    val serverUrlFlow: Flow<String> = context.dataStore.data.map { preferences ->
        preferences[KEY_SERVER_URL] ?: getDefaultServerUrl()
    }

    val wsUrlFlow: Flow<String> = context.dataStore.data.map { preferences ->
        preferences[KEY_WS_URL] ?: getDefaultWsUrl()
    }

    /**
     * Get default server URL based on build configuration
     * - Emulator: uses 10.0.2.2 to access host machine
     * - Physical device: uses configurable IP
     * - Production: uses actual server domain
     */
    private fun getDefaultServerUrlPrivate(): String {
        return getDefaultServerUrl()
    }

    /**
     * Get default WebSocket URL based on build configuration
     */
    private fun getDefaultWsUrlPrivate(): String {
        return getDefaultWsUrl()
    }

    suspend fun saveAuth(token: String, userId: String, username: String) {
        logger.info { "Saving auth token for user: $username" }
        context.dataStore.edit { preferences ->
            preferences[KEY_TOKEN] = token
            preferences[KEY_USER_ID] = userId
            preferences[KEY_USERNAME] = username
        }
    }

    suspend fun saveServerUrls(serverUrl: String, wsUrl: String) {
        context.dataStore.edit { preferences ->
            preferences[KEY_SERVER_URL] = serverUrl
            preferences[KEY_WS_URL] = wsUrl
        }
    }

    suspend fun clearAuth() {
        logger.info { "Clearing auth token" }
        context.dataStore.edit { preferences ->
            preferences.remove(KEY_TOKEN)
            preferences.remove(KEY_USER_ID)
            preferences.remove(KEY_USERNAME)
        }
    }

    suspend fun isLoggedIn(): Boolean {
        return tokenFlow.first() != null
    }

    fun getCurrentUser(): User? {
        // This is a simplified version - in production would use Flow properly
        return null // Would need to read from DataStore synchronously or use coroutine
    }
}
