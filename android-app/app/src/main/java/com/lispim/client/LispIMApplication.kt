package com.lispim.client

import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import com.lispim.client.data.PreferencesManager
import com.lispim.client.data.Repository
import mu.KotlinLogging

private val logger = KotlinLogging.logger {}

class LispIMApplication : Application() {

    lateinit var repository: Repository
        private set

    override fun onCreate() {
        super.onCreate()
        logger.info { "LispIM Application starting..." }

        // Initialize repository
        repository = Repository(this)

        // Create notification channels
        createNotificationChannels()
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val notificationManager = getSystemService(NotificationManager::class.java)

            // Messages channel
            val messagesChannel = NotificationChannel(
                CHANNEL_MESSAGES,
                "Messages",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "New message notifications"
                enableVibration(true)
            }

            // Connection status channel
            val connectionChannel = NotificationChannel(
                CHANNEL_CONNECTION,
                "Connection Status",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "WebSocket connection status changes"
            }

            notificationManager.createNotificationChannel(messagesChannel)
            notificationManager.createNotificationChannel(connectionChannel)
        }
    }

    companion object {
        const val CHANNEL_MESSAGES = "messages"
        const val CHANNEL_CONNECTION = "connection"

        // Server configuration - using 10.0.2.2 for Android emulator to access host machine
        // For physical devices, user should configure the actual server IP/domain
        val DEFAULT_SERVER_URL: String = PreferencesManager.getDefaultServerUrl()
        val DEFAULT_WS_URL: String = PreferencesManager.getDefaultWsUrl()

        /**
         * Check if running in emulator (for debugging purposes)
         */
        fun isEmulator(): Boolean {
            return (Build.FINGERPRINT.startsWith("generic") ||
                    Build.FINGERPRINT.startsWith("unknown") ||
                    Build.MODEL.contains("google_sdk") ||
                    Build.MODEL.contains("Emulator") ||
                    Build.MODEL.contains("Android SDK built for x86") ||
                    Build.MANUFACTURER.contains("Genymotion") ||
                    (Build.BRAND.startsWith("generic") &&
                     Build.DEVICE.startsWith("generic")) ||
                    "google_sdk" == Build.PRODUCT)
        }
    }
}
