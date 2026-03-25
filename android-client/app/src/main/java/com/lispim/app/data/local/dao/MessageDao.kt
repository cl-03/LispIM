package com.lispim.app.data.local.dao

import androidx.room.*
import com.lispim.app.data.local.entity.MessageEntity
import kotlinx.coroutines.flow.Flow

/**
 * Message Data Access Object
 */
@Dao
interface MessageDao {

    @Query("SELECT * FROM messages WHERE conversationId = :conversationId ORDER BY createdAt DESC")
    fun getMessagesByConversationId(conversationId: String): Flow<List<MessageEntity>>

    @Query("SELECT * FROM messages WHERE remoteId = :remoteId")
    suspend fun getMessageByRemoteId(remoteId: String): MessageEntity?

    @Query("SELECT * FROM messages WHERE conversationId = :conversationId AND createdAt < :before ORDER BY createdAt DESC LIMIT :limit")
    suspend fun getMessagesBefore(
        conversationId: String,
        before: Long,
        limit: Int
    ): List<MessageEntity>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(message: MessageEntity)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertAll(messages: List<MessageEntity>)

    @Update
    suspend fun update(message: MessageEntity)

    @Delete
    suspend fun delete(message: MessageEntity)

    @Query("DELETE FROM messages WHERE conversationId = :conversationId")
    suspend fun deleteByConversationId(conversationId: String)

    @Query("UPDATE messages SET isRead = 1 WHERE conversationId = :conversationId")
    suspend fun markConversationAsRead(conversationId: String)

    @Query("UPDATE messages SET isRecalled = 1 WHERE remoteId = :remoteId")
    suspend fun markMessageAsRecalled(remoteId: String)

    @Query("SELECT COUNT(*) FROM messages WHERE conversationId = :conversationId AND isRead = 0")
    fun getUnreadCountForConversation(conversationId: String): Flow<Int>
}
