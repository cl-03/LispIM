package com.lispim.app.data.local.entity

import androidx.room.Entity
import androidx.room.PrimaryKey
import androidx.room.Index

/**
 * Conversation entity for local storage
 */
@Entity(
    tableName = "conversations",
    indices = [Index(value = ["remoteId"], unique = true)]
)
data class ConversationEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val remoteId: String,
    val name: String?,
    val type: String,
    val lastMessage: String?,
    val unreadCount: Int = 0,
    val avatarUrl: String?,
    val createdAt: Long,
    val updatedAt: Long = System.currentTimeMillis()
)

/**
 * Message entity for local storage
 */
@Entity(
    tableName = "messages",
    indices = [
        Index(value = ["conversationId"]),
        Index(value = ["remoteId"], unique = true),
        Index(value = ["conversationId", "createdAt"])
    ]
)
data class MessageEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val remoteId: String,
    val conversationId: String,
    val senderId: String,
    val senderName: String?,
    val content: String,
    val type: String = "text",
    val createdAt: Long,
    val isRead: Boolean = false,
    val isRecalled: Boolean = false,
    val localCreatedAt: Long = System.currentTimeMillis()
)
