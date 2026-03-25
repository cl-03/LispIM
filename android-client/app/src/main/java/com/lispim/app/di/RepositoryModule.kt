package com.lispim.app.di

import com.lispim.app.data.api.LispIMApiService
import com.lispim.app.data.local.dao.ConversationDao
import com.lispim.app.data.local.dao.MessageDao
import com.lispim.app.data.repository.ChatRepository
import com.lispim.app.data.repository.ContactsRepository
import com.lispim.app.data.repository.DeviceRepository
import com.lispim.app.data.repository.LispIMRepository
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

/**
 * Hilt module for providing repository dependencies
 */
@Module
@InstallIn(SingletonComponent::class)
object RepositoryModule {

    @Provides
    @Singleton
    fun provideLispIMRepository(
        apiService: LispIMApiService,
        conversationDao: ConversationDao,
        messageDao: MessageDao
    ): LispIMRepository {
        return LispIMRepository(apiService, conversationDao, messageDao)
    }

    @Provides
    @Singleton
    fun provideContactsRepository(
        apiService: LispIMApiService
    ): ContactsRepository {
        return ContactsRepository(apiService)
    }

    @Provides
    @Singleton
    fun provideDeviceRepository(
        apiService: LispIMApiService
    ): DeviceRepository {
        return DeviceRepository(apiService)
    }
}
