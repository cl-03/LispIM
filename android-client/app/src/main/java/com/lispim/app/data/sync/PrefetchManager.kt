package com.lispim.app.data.sync

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.LruCache
import android.util.Log
import com.lispim.app.data.api.LispIMApiService
import com.lispim.app.data.local.LispIMDatabase
import com.lispim.app.data.local.entity.MessageEntity
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.io.FileOutputStream

/**
 * 预加载管理器
 *
 * 实现智能预加载策略，提升用户体验
 *
 * 功能：
 * - 消息预加载（前后各 10 条）
 * - 媒体文件预加载（缩略图）
 * - 联系人信息预加载
 * - 智能预加载时机（空闲时）
 * - 内存/磁盘缓存
 */
class PrefetchManager(
    private val context: Context,
    private val apiService: LispIMApiService,
    private val database: LispIMDatabase
) {
    companion object {
        private const val TAG = "PrefetchManager"

        // 内存缓存配置
        private val MAX_MEMORY_CACHE_SIZE = 10 * 1024 * 1024L // 10MB
        private val MAX_DISK_CACHE_SIZE = 100 * 1024 * 1024L // 100MB

        // 预加载配置
        private const val PREFETCH_MESSAGE_COUNT = 10
        private const val PREFETCH_CONVERSATION_COUNT = 20
        private const val PREFETCH_CONTACT_COUNT = 50
    }

    // 内存缓存
    private val memoryCache: LruCache<String, Bitmap>
    private val messageCache: LruCache<String, MessageEntity>

    // 磁盘缓存目录
    private val diskCacheDir: File

    // 预加载队列
    private val prefetchQueue = mutableListOf<PrefetchTask>()

    // 预加载状态
    private var isPrefetching = false

    init {
        // 初始化内存缓存
        val maxMemory = (Runtime.getRuntime().maxMemory() / 1024).toInt()
        val cacheSize = maxMemory / 8 // 使用 1/8 可用内存

        memoryCache = object : LruCache<String, Bitmap>(cacheSize) {
            override fun sizeOf(key: String, bitmap: Bitmap): Int {
                return bitmap.byteCount / 1024
            }
        }

        messageCache = LruCache(100) // 缓存 100 条消息

        // 初始化磁盘缓存
        diskCacheDir = File(context.cacheDir, "prefetch")
        if (!diskCacheDir.exists()) {
            diskCacheDir.mkdirs()
        }

        Log.i(TAG, "PrefetchManager initialized, memory cache: ${cacheSize}KB")
    }

    /**
     * 预加载会话消息
     *
     * @param conversationId 会话 ID
     * @param currentMessageId 当前消息 ID
     */
    suspend fun prefetchMessages(conversationId: String, currentMessageId: String? = null) {
        if (isPrefetching) {
            Log.w(TAG, "Prefetch already in progress")
            return
        }

        isPrefetching = true
        try {
            Log.d(TAG, "Prefetching messages for conversation $conversationId")

            // 检查缓存
            val cachedMessages = database.messageDao()
                .getMessagesByConversation(conversationId, PREFETCH_MESSAGE_COUNT)

            if (cachedMessages.isNotEmpty()) {
                Log.d(TAG, "Found ${cachedMessages.size} cached messages")
                // 添加到内存缓存
                cachedMessages.forEach { msg ->
                    messageCache.put("${conversationId}:${msg.id}", msg)
                }
                return
            }

            // 从 API 加载
            val response = withContext(Dispatchers.IO) {
                if (currentMessageId != null) {
                    apiService.getMessagesBefore(conversationId, currentMessageId, PREFETCH_MESSAGE_COUNT)
                } else {
                    apiService.getMessages(conversationId, 0, PREFETCH_MESSAGE_COUNT)
                }
            }

            if (response.isSuccessful && response.body() != null) {
                val messages = response.body()!!.messages

                // 存入数据库
                withContext(Dispatchers.IO) {
                    val entities = messages.map { msg ->
                        MessageEntity(
                            id = msg.id,
                            conversationId = msg.conversationId,
                            senderId = msg.senderId,
                            content = msg.content,
                            messageType = msg.type,
                            status = msg.status,
                            createdAt = msg.createdAt
                        )
                    }
                    database.messageDao().insertAll(*entities.toTypedArray())
                }

                Log.i(TAG, "Prefetched ${messages.size} messages")
            }

        } finally {
            isPrefetching = false
        }
    }

    /**
     * 预加载媒体文件
     *
     * @param messageId 消息 ID
     * @param mediaUrl 媒体 URL
     */
    suspend fun prefetchMedia(messageId: String, mediaUrl: String, type: String = "image") {
        val cacheKey = "media:$messageId"

        // 检查内存缓存
        if (type == "image" && memoryCache.get(cacheKey) != null) {
            Log.d(TAG, "Media found in memory cache: $messageId")
            return
        }

        // 检查磁盘缓存
        val cacheFile = File(diskCacheDir, messageId)
        if (cacheFile.exists()) {
            Log.d(TAG, "Media found in disk cache: $messageId")

            if (type == "image") {
                val bitmap = BitmapFactory.decodeFile(cacheFile.absolutePath)
                memoryCache.put(cacheKey, bitmap)
            }
            return
        }

        // 下载媒体文件
        try {
            Log.d(TAG, "Downloading media: $mediaUrl")

            val response = withContext(Dispatchers.IO) {
                apiService.downloadFile(mediaUrl)
            }

            if (response.isSuccessful && response.body() != null) {
                withContext(Dispatchers.IO) {
                    val bytes = response.body()!!.bytes()

                    // 写入磁盘缓存
                    FileOutputStream(cacheFile).use { fos ->
                        fos.write(bytes)
                    }

                    // 如果是图片，加载到内存缓存
                    if (type == "image") {
                        val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                        memoryCache.put(cacheKey, bitmap)
                    }

                    Log.i(TAG, "Media prefetched: $messageId (${bytes.size} bytes)")
                }
            }

        } catch (e: Exception) {
            Log.e(TAG, "Failed to prefetch media", e)
        }
    }

    /**
     * 预加载联系人列表
     */
    suspend fun prefetchContacts() {
        Log.d(TAG, "Prefetching contacts")

        val response = try {
            withContext(Dispatchers.IO) {
                apiService.getContacts()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to prefetch contacts", e)
            return
        }

        if (response.isSuccessful && response.body() != null) {
            val contacts = response.body()!!.contacts
            Log.i(TAG, "Prefetched ${contacts.size} contacts")

            // 缓存联系人头像
            contacts.forEach { contact ->
                if (contact.avatarUrl != null) {
                    launch {
                        prefetchMedia("avatar:${contact.id}", contact.avatarUrl!!, "image")
                    }
                }
            }
        }
    }

    /**
     * 预加载会话列表
     */
    suspend fun prefetchConversations() {
        Log.d(TAG, "Prefetching conversations")

        val response = try {
            withContext(Dispatchers.IO) {
                apiService.getConversations()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to prefetch conversations", e)
            return
        }

        if (response.isSuccessful && response.body() != null) {
            val conversations = response.body()!!.conversations
            Log.i(TAG, "Prefetched ${conversations.size} conversations")

            // 预加载最后一条消息
            conversations.forEach { conv ->
                if (conv.lastMessageId != null) {
                    launch {
                        prefetchMessages(conv.id, conv.lastMessageId)
                    }
                }
            }
        }
    }

    /**
     * 智能预加载
     *
     * 在系统空闲时自动执行预加载
     */
    fun smartPrefetch() {
        // 检查网络状态
        // 检查电量状态
        // 在合适时机执行预加载

        launch {
            // 预加载会话列表
            prefetchConversations()

            // 预加载联系人
            prefetchContacts()
        }
    }

    /**
     * 获取缓存统计
     */
    fun getCacheStats(): CacheStats {
        return CacheStats(
            memoryCacheSize = memoryCache.size(),
            memoryCacheMaxSize = memoryCache.maxSize(),
            diskCacheSize = calculateDiskCacheSize(),
            prefetchQueueSize = prefetchQueue.size,
            isPrefetching = isPrefetching
        )
    }

    /**
     * 清除缓存
     */
    fun clearCache() {
        memoryCache.evictAll()
        messageCache.evictAll()

        withContext(Dispatchers.IO) {
            diskCacheDir.deleteRecursively()
            diskCacheDir.mkdirs()
        }

        Log.i(TAG, "Cache cleared")
    }

    /**
     * 计算磁盘缓存大小
     */
    private fun calculateDiskCacheSize(): Long {
        return diskCacheDir.walkTopDown()
            .filter { it.isFile }
            .sumOf { it.length() }
    }

    /**
     * 获取磁盘缓存文件
     */
    fun getDiskCacheFile(messageId: String): File? {
        val file = File(diskCacheDir, messageId)
        return if (file.exists()) file else null
    }
}

/**
 * 缓存统计
 */
data class CacheStats(
    val memoryCacheSize: Long,
    val memoryCacheMaxSize: Long,
    val diskCacheSize: Long,
    val prefetchQueueSize: Int,
    val isPrefetching: Boolean
)

/**
 * 预加载任务
 */
data class PrefetchTask(
    val type: String,
    val targetId: String,
    val priority: Priority = Priority.NORMAL
) {
    enum class Priority {
        LOW, NORMAL, HIGH
    }
}
