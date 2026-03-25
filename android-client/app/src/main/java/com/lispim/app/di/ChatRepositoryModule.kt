package com.lispim.app.di

import com.lispim.app.data.api.LispIMApiService
import com.lispim.app.data.local.dao.ConversationDao
import com.lispim.app.data.local.dao.MessageDao
import com.lispim.app.data.repository.ChatRepository
import com.lispim.app.data.websocket.WebSocketManager
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

/**
 * Hilt module for ChatRepository
 */
@Module
@InstallIn(SingletonComponent::class)
object ChatRepositoryModule {

    @Provides
    @Singleton
    fun provideChatRepository(
        webSocketManager: WebSocketManager,
        messageDao: MessageDao,
        conversationDao: ConversationDao
    ): ChatRepository {
        return ChatRepository(webSocketManager, messageDao, conversationDao)
    }
}
