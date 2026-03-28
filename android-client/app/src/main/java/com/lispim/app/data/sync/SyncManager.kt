package com.lispim.app.data.sync

import android.content.Context
import android.util.Log
import com.lispim.app.data.api.LispIMApiService
import com.lispim.app.data.local.LispIMDatabase
import com.lispim.app.data.local.entity.MessageEntity
import com.lispim.app.data.local.entity.ConversationEntity
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import retrofit2.HttpException
import java.io.IOException

/**
 * 增量同步管理器
 *
 * 实现基于序列号的增量同步协议，减少流量消耗
 *
 * 功能：
 * - 消息增量同步（基于 sync_seq）
 * - 会话增量同步（基于 sync_seq）
 * - 全量同步（新设备/过期 anchor）
 * - 冲突解决（Last-write-wins）
 * - 同步锚点追踪
 */
class SyncManager(
    private val context: Context,
    private val apiService: LispIMApiService,
    private val database: LispIMDatabase
) {
    companion object {
        private const val TAG = "SyncManager"
        private const val DEFAULT_BATCH_SIZE = 50
        private const val MAX_BATCH_SIZE = 100
    }

    // 同步锚点存储（内存 + 本地存储）
    private val syncAnchors = mutableMapOf<String, Long>()

    // 同步状态
    private var isSyncing = false
    private var lastSyncTime = 0L

    /**
     * 获取同步锚点
     */
    suspend fun getSyncAnchor(userId: String): Long {
        return withContext(Dispatchers.IO) {
            syncAnchors[userId] ?: run {
                // 从本地存储加载
                val anchor = database.syncAnchorDao().getAnchor(userId)
                anchor?.sequence ?: 0L
            }
        }
    }

    /**
     * 设置同步锚点
     */
    suspend fun setSyncAnchor(userId: String, sequence: Long) {
        withContext(Dispatchers.IO) {
            syncAnchors[userId] = sequence
            // 持久化到本地存储
            database.syncAnchorDao().insertOrUpdate(
                SyncAnchorEntity(userId = userId, sequence = sequence, updatedAt = System.currentTimeMillis())
            )
        }
    }

    /**
     * 增量同步消息
     *
     * @param userId 用户 ID
     * @param anchorSeq 同步锚点序列号（0 表示全量同步）
     * @param batchSize 批次大小
     * @return 同步结果（新消息列表 + 新 anchor）
     */
    suspend fun syncMessages(
        userId: String,
        anchorSeq: Long = 0,
        batchSize: Int = DEFAULT_BATCH_SIZE
    ): SyncResult {
        if (isSyncing) {
            Log.w(TAG, "Sync already in progress")
            return SyncResult(false, emptyList(), anchorSeq)
        }

        isSyncing = true
        try {
            Log.d(TAG, "Starting message sync for user $userId from anchor $anchorSeq")

            val response = try {
                if (anchorSeq > 0) {
                    // 增量同步
                    apiService.getIncrementalMessages(userId, anchorSeq, batchSize)
                } else {
                    // 全量同步
                    apiService.getMessages(userId, 0, batchSize)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Sync request failed", e)
                return when (e) {
                    is IOException -> SyncResult(false, emptyList(), anchorSeq, "Network error")
                    is HttpException -> SyncResult(false, emptyList(), anchorSeq, "Server error: ${e.code()}")
                    else -> SyncResult(false, emptyList(), anchorSeq, "Unknown error")
                }
            }

            if (!response.isSuccessful || response.body() == null) {
                Log.e(TAG, "Sync response error: ${response.code()}")
                return SyncResult(false, emptyList(), anchorSeq, "Response error")
            }

            val body = response.body()!!
            val messages = body.messages
            val newAnchor = body.syncAnchor

            Log.d(TAG, "Received ${messages.size} messages, new anchor: $newAnchor")

            // 插入本地数据库
            withContext(Dispatchers.IO) {
                val messageEntities = messages.map { msg ->
                    MessageEntity(
                        id = msg.id,
                        conversationId = msg.conversationId,
                        senderId = msg.senderId,
                        content = msg.content,
                        messageType = msg.type,
                        status = msg.status,
                        createdAt = msg.createdAt,
                        syncSeq = msg.syncSeq
                    )
                }
                database.messageDao().insertAll(*messageEntities.toTypedArray())
            }

            // 更新同步锚点
            setSyncAnchor(userId, newAnchor)

            lastSyncTime = System.currentTimeMillis()

            Log.i(TAG, "Message sync completed: ${messages.size} messages")
            return SyncResult(true, messages, newAnchor)

        } finally {
            isSyncing = false
        }
    }

    /**
     * 增量同步会话
     *
     * @param userId 用户 ID
     * @param anchorSeq 同步锚点序列号
     * @return 同步结果
     */
    suspend fun syncConversations(
        userId: String,
        anchorSeq: Long = 0
    ): SyncResult {
        if (isSyncing) {
            Log.w(TAG, "Sync already in progress")
            return SyncResult(false, emptyList(), anchorSeq)
        }

        isSyncing = true
        try {
            Log.d(TAG, "Starting conversation sync for user $userId from anchor $anchorSeq")

            val response = try {
                if (anchorSeq > 0) {
                    apiService.getIncrementalConversations(userId, anchorSeq)
                } else {
                    apiService.getConversations(userId)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Sync request failed", e)
                return SyncResult(false, emptyList(), anchorSeq, "Network error")
            }

            if (!response.isSuccessful || response.body() == null) {
                return SyncResult(false, emptyList(), anchorSeq, "Response error")
            }

            val body = response.body()!!
            val conversations = body.conversations
            val newAnchor = body.syncAnchor

            // 插入本地数据库
            withContext(Dispatchers.IO) {
                val convEntities = conversations.map { conv ->
                    ConversationEntity(
                        id = conv.id,
                        name = conv.name,
                        type = conv.type,
                        lastMessageId = conv.lastMessageId,
                        lastMessageTime = conv.lastMessageTime,
                        unreadCount = conv.unreadCount,
                        syncSeq = conv.syncSeq
                    )
                }
                database.conversationDao().insertAll(*convEntities.toTypedArray())
            }

            setSyncAnchor("conv:$userId", newAnchor)
            lastSyncTime = System.currentTimeMillis()

            Log.i(TAG, "Conversation sync completed: ${conversations.size} conversations")
            return SyncResult(true, conversations, newAnchor)

        } finally {
            isSyncing = false
        }
    }

    /**
     * 全量同步
     *
     * 用于新设备或 anchor 过期的情况
     */
    suspend fun fullSync(userId: String): SyncResult {
        Log.i(TAG, "Starting full sync for user $userId")

        // 同步消息
        val messageResult = syncMessages(userId, 0, MAX_BATCH_SIZE)
        if (!messageResult.success) {
            return messageResult
        }

        // 同步会话
        val conversationResult = syncConversations(userId, 0)
        if (!conversationResult.success) {
            return conversationResult
        }

        Log.i(TAG, "Full sync completed")
        return SyncResult(true, messageResult.data + conversationResult.data,
                         maxOf(messageResult.newAnchor, conversationResult.newAnchor))
    }

    /**
     * 解决同步冲突
     *
     * 使用 Last-write-wins 策略
     */
    fun resolveConflict(local: SyncEntity, remote: SyncEntity): SyncEntity {
        return if (local.updatedAt >= remote.updatedAt) {
            Log.d(TAG, "Keeping local entity (newer): ${local.id}")
            local
        } else {
            Log.d(TAG, "Using remote entity (newer): ${remote.id}")
            remote
        }
    }

    /**
     * 获取同步统计
     */
    fun getSyncStats(): SyncStats {
        return SyncStats(
            lastSyncTime = lastSyncTime,
            isSyncing = isSyncing,
            totalAnchors = syncAnchors.size
        )
    }

    /**
     * 清除同步数据
     */
    suspend fun clearSyncData() {
        withContext(Dispatchers.IO) {
            syncAnchors.clear()
            database.syncAnchorDao().deleteAll()
        }
        Log.i(TAG, "Sync data cleared")
    }
}

/**
 * 同步结果
 */
data class SyncResult(
    val success: Boolean,
    val data: List<Any>,
    val newAnchor: Long,
    val error: String? = null
)

/**
 * 同步统计
 */
data class SyncStats(
    val lastSyncTime: Long,
    val isSyncing: Boolean,
    val totalAnchors: Int
)

/**
 * 同步实体基类
 */
interface SyncEntity {
    val id: String
    val updatedAt: Long
}

/**
 * 同步锚点实体
 */
data class SyncAnchorEntity(
    val userId: String,
    val sequence: Long,
    val updatedAt: Long
)
