package com.lispim.app.data.repository

import com.lispim.app.data.api.LispIMApiService
import com.lispim.app.data.model.FcmTokenRequest
import com.lispim.app.data.model.FcmTokensResponse
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Device Repository - Handles device registration and FCM token management
 */
@Singleton
class DeviceRepository @Inject constructor(
    private val apiService: LispIMApiService
) {

    private val _fcmTokens = MutableStateFlow<List<FcmToken>>(emptyList())
    val fcmTokens: StateFlow<List<FcmToken>> = _fcmTokens.asStateFlow()

    /**
     * Register FCM token with server
     */
    suspend fun registerFcmToken(
        token: String,
        deviceId: String,
        platform: String = "android",
        deviceName: String,
        appVersion: String,
        osVersion: String,
        authToken: String
    ): Result<Unit> {
        return try {
            val request = FcmTokenRequest(
                fcmToken = token,
                deviceId = deviceId,
                platform = platform,
                deviceName = deviceName,
                appVersion = appVersion,
                osVersion = osVersion
            )
            val response = apiService.registerFcmToken("Bearer $authToken", request)
            if (response.isSuccessful && response.body() != null) {
                val body = response.body()!!
                if (body.success) {
                    Result.success(Unit)
                } else {
                    Result.failure(Exception(body.error?.message ?: "Failed to register FCM token"))
                }
            } else {
                Result.failure(Exception("Failed to register FCM token: ${response.code()}"))
            }
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    /**
     * Remove FCM token
     */
    suspend fun removeFcmToken(deviceId: String, authToken: String): Result<Unit> {
        return try {
            val request = com.lispim.app.data.model.FcmTokenRemoveRequest(deviceId)
            val response = apiService.removeFcmToken("Bearer $authToken", request)
            if (response.isSuccessful && response.body() != null) {
                val body = response.body()!!
                if (body.success) {
                    Result.success(Unit)
                } else {
                    Result.failure(Exception(body.error?.message ?: "Failed to remove FCM token"))
                }
            } else {
                Result.failure(Exception("Failed to remove FCM token: ${response.code()}"))
            }
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    /**
     * Get FCM tokens for current user
     */
    suspend fun loadFcmTokens(authToken: String): Result<List<FcmToken>> {
        return try {
            val response = apiService.getFcmTokens("Bearer $authToken")
            if (response.isSuccessful && response.body() != null) {
                val body = response.body()!!
                if (body.success && body.data != null) {
                    val tokens = body.data.devices.map { device ->
                        FcmToken(
                            deviceId = device.deviceId,
                            platform = device.platform,
                            fcmToken = device.fcmToken,
                            deviceName = device.deviceName,
                            pushEnabled = device.pushEnabled
                        )
                    }
                    _fcmTokens.value = tokens
                    Result.success(tokens)
                } else {
                    Result.failure(Exception(body.error?.message ?: "Failed to load FCM tokens"))
                }
            } else {
                Result.failure(Exception("Failed to load FCM tokens: ${response.code()}"))
            }
        } catch (e: Exception) {
            Result.failure(e)
        }
    }
}

/**
 * FCM token data model
 */
data class FcmToken(
    val deviceId: String,
    val platform: String,
    val fcmToken: String,
    val deviceName: String?,
    val pushEnabled: Boolean
)
