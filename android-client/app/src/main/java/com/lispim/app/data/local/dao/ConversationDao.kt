package com.lispim.app.data.local.dao

import androidx.room.*
import com.lispim.app.data.local.entity.ConversationEntity
import kotlinx.coroutines.flow.Flow

/**
 * Conversation Data Access Object
 */
@Dao
interface ConversationDao {

    @Query("SELECT * FROM conversations ORDER BY updatedAt DESC")
    fun getAllConversations(): Flow<List<ConversationEntity>>

    @Query("SELECT * FROM conversations WHERE remoteId = :remoteId")
    suspend fun getConversationByRemoteId(remoteId: String): ConversationEntity?

    @Query("SELECT * FROM conversations WHERE type = :type ORDER BY updatedAt DESC")
    fun getConversationsByType(type: String): Flow<List<ConversationEntity>>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(conversation: ConversationEntity)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertAll(conversations: List<ConversationEntity>)

    @Update
    suspend fun update(conversation: ConversationEntity)

    @Delete
    suspend fun delete(conversation: ConversationEntity)

    @Query("DELETE FROM conversations WHERE remoteId = :remoteId")
    suspend fun deleteByRemoteId(remoteId: String)

    @Query("UPDATE conversations SET unreadCount = 0 WHERE remoteId = :remoteId")
    suspend fun markAsRead(remoteId: String)

    @Query("SELECT COUNT(*) FROM conversations WHERE unreadCount > 0")
    fun getUnreadCount(): Flow<Int>
}
