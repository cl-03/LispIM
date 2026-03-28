package com.lispim.app.data.local.dao

import androidx.room.*
import com.lispim.app.data.local.entity.OfflineMessageEntity
import kotlinx.coroutines.flow.Flow

/**
 * Offline Message Data Access Object
 */
@Dao
interface OfflineMessageDao {

    @Query("SELECT * FROM offline_messages WHERE status = 'pending' AND nextRetryAt <= :currentTime ORDER BY createdAt ASC LIMIT :limit")
    suspend fun getPendingMessages(limit: Int, currentTime: Long): List<OfflineMessageEntity>

    @Query("SELECT * FROM offline_messages ORDER BY createdAt DESC")
    suspend fun getAllMessages(): List<OfflineMessageEntity>

    @Query("SELECT COUNT(*) FROM offline_messages WHERE status = 'pending'")
    suspend fun getPendingCount(): Int

    @Query("SELECT COUNT(*) FROM offline_messages WHERE status = 'failed'")
    suspend fun getFailedCount(): Int

    @Query("SELECT COUNT(*) FROM offline_messages")
    suspend fun getTotalCount(): Int

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(message: OfflineMessageEntity)

    @Update
    suspend fun update(message: OfflineMessageEntity)

    @Delete
    suspend fun delete(message: OfflineMessageEntity)

    @Query("DELETE FROM offline_messages WHERE id = :id")
    suspend fun deleteById(id: String)

    @Query("DELETE FROM offline_messages")
    suspend fun deleteAll()

    @Query("UPDATE offline_messages SET status = :status, lastError = :error WHERE id = :id")
    suspend fun updateStatus(id: String, status: String, error: String? = null)

    @Query("UPDATE offline_messages SET retryCount = :retryCount, nextRetryAt = :nextRetryAt, lastError = :error WHERE id = :id")
    suspend fun updateRetryInfo(id: String, retryCount: Int, nextRetryAt: Long, error: String? = null)

    @Query("DELETE FROM offline_messages WHERE createdAt < :expiredTime")
    suspend fun deleteExpired(expiredTime: Long): Int
}
