package com.lispim.app.service

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import com.lispim.app.MainActivity
import com.lispim.app.data.repository.DeviceRepository
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

/**
 * Firebase Cloud Messaging Service
 * Handles FCM token registration and push notification reception
 */
class LispIMMessagingService : FirebaseMessagingService() {

    companion object {
        private const val TAG = "LispIMMessaging"
        private const val CHANNEL_ID = "lispim_messages"
        private const val CHANNEL_NAME = "消息通知"
        private const val CHANNEL_DESCRIPTION = "接收新消息通知"
        private const val NOTIFICATION_ID = 1001
    }

    override fun onNewToken(token: String) {
        super.onNewToken(token)
        Log.i(TAG, "New FCM token: ${token.take(10)}...")
        sendRegistrationToServer(token)
    }

    override fun onMessageReceived(message: RemoteMessage) {
        super.onMessageReceived(message)

        Log.d(TAG, "Message received from: ${message.from}")

        // Handle data payload
        if (message.data.isNotEmpty()) {
            Log.d(TAG, "Message data: ${message.data}")
            val conversationId = message.data["conversation_id"]
            val messageId = message.data["message_id"]
            val title = message.data["title"] ?: "新消息"
            val body = message.data["body"] ?: ""
            val senderId = message.data["sender_id"]
            val senderName = message.data["sender_name"]

            // Show notification
            conversationId?.let { cid ->
                showNotification(title, body, cid, messageId, senderName)
            }
        }

        // Handle notification payload
        message.notification?.let {
            Log.d(TAG, "Message notification: ${it.body}")
            showNotification(
                it.title ?: "新消息",
                it.body ?: "",
                it.clickAction ?: "default",
                null,
                null
            )
        }
    }

    private fun sendRegistrationToServer(token: String) {
        // Send token to LispIM server
        CoroutineScope(Dispatchers.IO).launch {
            try {
                val deviceId = getDeviceId()
                val deviceName = getDeviceName()
                val platform = "android"
                val appVersion = packageManager.getPackageInfo(packageName, 0).versionName ?: "1.0.0"
                val osVersion = Build.VERSION.RELEASE

                // Use DeviceRepository to send token
                // This would be injected in a production app
                Log.i(TAG, "Sending FCM token to server: deviceId=$deviceId, platform=$platform")
                // deviceRepository.registerFcmToken(token, deviceId, platform, deviceName, appVersion, osVersion)
            } catch (e: Exception) {
                Log.e(TAG, "Failed to send FCM token to server", e)
            }
        }
    }

    private fun getDeviceId(): String {
        return Build.SERIAL.ifEmpty {
            Settings.Secure.getString(contentResolver, Settings.Secure.ANDROID_ID) ?: "unknown"
        }
    }

    private fun getDeviceName(): String {
        return "${Build.MANUFACTURER} ${Build.MODEL}"
    }

    private fun showNotification(
        title: String?,
        body: String?,
        conversationId: String,
        messageId: String?,
        senderName: String?
    ) {
        createNotificationChannel()

        // Create intent to open chat detail screen on notification click
        val intent = Intent(this, MainActivity::class.java).apply {
            putExtra("conversation_id", conversationId)
            putExtra("message_id", messageId)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
        }

        val pendingIntent = PendingIntent.getActivity(
            this,
            messageId?.hashCode() ?: 0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // Build notification
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_dialog_email)
            .setContentTitle(title ?: senderName ?: "新消息")
            .setContentText(body)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .build()

        // Show notification
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED) {
            NotificationManagerCompat.from(this).notify(
                conversationId.hashCode() + NOTIFICATION_ID,
                notification
            )
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = CHANNEL_DESCRIPTION
                enableLights(true)
                lightColor = android.graphics.Color.RED
                enableVibration(true)
                vibrationPattern = longArrayOf(100, 200, 300, 400, 500)
                setShowBadge(true)
            }

            val notificationManager = NotificationManagerCompat.from(this)
            notificationManager.createNotificationChannel(channel)
        }
    }
}
