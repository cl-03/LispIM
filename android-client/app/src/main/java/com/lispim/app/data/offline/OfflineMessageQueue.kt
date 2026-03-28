package com.lispim.app.data.offline

import android.content.Context
import android.util.Log
import com.lispim.app.data.api.LispIMApiService
import com.lispim.app.data.local.LispIMDatabase
import com.lispim.app.data.local.entity.OfflineMessageEntity
import com.lispim.app.data.model.Message
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import retrofit2.HttpException
import java.io.IOException

/**
 * 离线消息队列管理器
 *
 * 实现离线消息的持久化存储和自动重发
 *
 * 功能：
 * - 离线消息入队/出队
 * - 本地数据库持久化
 * - 自动重试机制（指数退避）
 * - 消息 TTL 过期（24 小时）
 * - 队列统计监控
 */
class OfflineMessageQueue(
    private val context: Context,
    private val apiService: LispIMApiService,
    private val database: LispIMDatabase
) {
    companion object {
        private const val TAG = "OfflineMessageQueue"

        // 重试配置
        private const val MAX_RETRY_COUNT = 5
        private val RETRY_DELAYS = listOf(5000L, 15000L, 45000L, 135000L, 405000L) // 5s, 15s, 45s, 135s, 405s

        // TTL 配置
        private const val MESSAGE_TTL_MS = 24 * 60 * 60 * 1000L // 24 小时
    }

    // 队列统计
    private var enqueueCount = 0
    private var dequeueCount = 0
    private var successCount = 0
    private var failCount = 0

    /**
     * 入队离线消息
     *
     * @param message 消息对象
     * @return 消息 ID
     */
    suspend fun enqueue(message: Message): String {
        return withContext(Dispatchers.IO) {
            val entity = OfflineMessageEntity(
                id = message.id,
                conversationId = message.conversationId,
                senderId = message.senderId,
                recipientId = message.recipientId,
                content = message.content,
                messageType = message.type,
                status = "pending",
                retryCount = 0,
                createdAt = System.currentTimeMillis(),
                nextRetryAt = System.currentTimeMillis() // 立即重试
            )

            database.offlineMessageDao().insert(entity)
            enqueueCount++

            Log.i(TAG, "Message enqueued: ${message.id}")
            message.id
        }
    }

    /**
     * 出队并发送离线消息
     *
     * @param limit 最大出队数量
     * @return 发送结果列表
     */
    suspend fun dequeueAndSend(limit: Int = 10): List<SendResult> {
        return withContext(Dispatchers.IO) {
            val messages = database.offlineMessageDao()
                .getPendingMessages(limit, System.currentTimeMillis())

            if (messages.isEmpty()) {
                Log.d(TAG, "No pending messages to send")
                return@withContext emptyList()
            }

            Log.d(TAG, "Processing ${messages.size} pending messages")

            val results = mutableListOf<SendResult>()

            for (entity in messages) {
                val result = sendMessage(entity)
                results.add(result)

                when (result) {
                    is SendResult.Success -> {
                        successCount++
                        database.offlineMessageDao().delete(entity)
                        Log.i(TAG, "Message sent successfully: ${entity.id}")
                    }
                    is SendResult.Failure -> {
                        if (entity.retryCount >= MAX_RETRY_COUNT) {
                            // 超过最大重试次数，标记为失败
                            database.offlineMessageDao().updateStatus(entity.id, "failed", result.error)
                            failCount++
                            Log.e(TAG, "Message failed after max retries: ${entity.id}")
                        } else {
                            // 更新重试计数和下次重试时间
                            val newRetryCount = entity.retryCount + 1
                            val nextRetryAt = System.currentTimeMillis() + RETRY_DELAYS[newRetryCount]
                            database.offlineMessageDao().updateRetryInfo(
                                entity.id,
                                newRetryCount,
                                nextRetryAt,
                                result.error
                            )
                            Log.w(TAG, "Message send failed, will retry: ${entity.id} (attempt ${newRetryCount + 1})")
                        }
                    }
                }

                dequeueCount++
            }

            results
        }
    }

    /**
     * 发送单条消息
     */
    private suspend fun sendMessage(entity: OfflineMessageEntity): SendResult {
        return try {
            val message = Message(
                id = entity.id,
                conversationId = entity.conversationId,
                senderId = entity.senderId,
                recipientId = entity.recipientId,
                content = entity.content,
                type = entity.messageType,
                status = "sending",
                createdAt = entity.createdAt
            )

            val response = apiService.sendMessage(message)

            if (response.isSuccessful) {
                SendResult.Success(entity.id)
            } else {
                SendResult.Failure(entity.id, "Server error: ${response.code()}")
            }

        } catch (e: IOException) {
            SendResult.Failure(entity.id, "Network error: ${e.message}")
        } catch (e: HttpException) {
            SendResult.Failure(entity.id, "HTTP error: ${e.code()}")
        } catch (e: Exception) {
            SendResult.Failure(entity.id, "Unknown error: ${e.message}")
        }
    }

    /**
     * 获取待发送消息数量
     */
    suspend fun getPendingCount(): Int {
        return withContext(Dispatchers.IO) {
            database.offlineMessageDao().getPendingCount()
        }
    }

    /**
     * 获取所有离线消息
     */
    suspend fun getAllMessages(): List<OfflineMessageEntity> {
        return withContext(Dispatchers.IO) {
            database.offlineMessageDao().getAllMessages()
        }
    }

    /**
     * 清理过期消息
     */
    suspend fun cleanupExpired() {
        return withContext(Dispatchers.IO) {
            val currentTime = System.currentTimeMillis()
            val expiredTime = currentTime - MESSAGE_TTL_MS

            val count = database.offlineMessageDao().deleteExpired(expiredTime)
            if (count > 0) {
                Log.i(TAG, "Cleaned up $count expired messages")
            }
        }
    }

    /**
     * 取消消息
     *
     * @param messageId 消息 ID
     */
    suspend fun cancel(messageId: String) {
        return withContext(Dispatchers.IO) {
            database.offlineMessageDao().deleteById(messageId)
            Log.i(TAG, "Message cancelled: $messageId")
        }
    }

    /**
     * 清空队列
     */
    suspend fun clear() {
        return withContext(Dispatchers.IO) {
            database.offlineMessageDao().deleteAll()
            Log.i(TAG, "Queue cleared")
        }
    }

    /**
     * 获取队列统计
     */
    fun getStats(): QueueStats {
        return QueueStats(
            enqueueCount = enqueueCount,
            dequeueCount = dequeueCount,
            successCount = successCount,
            failCount = failCount,
            pendingCount = 0 // Will be updated by caller
        )
    }

    /**
     * 获取详细的队列统计（包括数据库查询）
     */
    suspend fun getDetailedStats(): DetailedQueueStats {
        return withContext(Dispatchers.IO) {
            val pendingCount = database.offlineMessageDao().getPendingCount()
            val failedCount = database.offlineMessageDao().getFailedCount()
            val totalSize = database.offlineMessageDao().getTotalCount()

            DetailedQueueStats(
                enqueueCount = enqueueCount,
                dequeueCount = dequeueCount,
                successCount = successCount,
                failCount = failCount,
                pendingCount = pendingCount,
                failedCount = failedCount,
                totalSize = totalSize
            )
        }
    }
}

/**
 * 发送结果
 */
sealed class SendResult {
    data class Success(val messageId: String) : SendResult()
    data class Failure(val messageId: String, val error: String) : SendResult()
}

/**
 * 队列统计
 */
data class QueueStats(
    val enqueueCount: Int,
    val dequeueCount: Int,
    val successCount: Int,
    val failCount: Int,
    val pendingCount: Int
)

/**
 * 详细队列统计
 */
data class DetailedQueueStats(
    val enqueueCount: Int,
    val dequeueCount: Int,
    val successCount: Int,
    val failCount: Int,
    val pendingCount: Int,
    val failedCount: Int,
    val totalSize: Int
)
