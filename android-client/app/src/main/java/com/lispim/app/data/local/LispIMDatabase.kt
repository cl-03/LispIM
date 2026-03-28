package com.lispim.app.di

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase
import com.lispim.app.data.local.dao.MessageDao
import com.lispim.app.data.local.dao.ConversationDao
import com.lispim.app.data.local.dao.OfflineMessageDao
import com.lispim.app.data.local.dao.SyncAnchorDao
import com.lispim.app.data.local.entity.MessageEntity
import com.lispim.app.data.local.entity.ConversationEntity
import com.lispim.app.data.local.entity.OfflineMessageEntity
import com.lispim.app.data.local.entity.SyncAnchorEntity
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

/**
 * Local Room Database
 */
@Database(
    entities = [
        ConversationEntity::class,
        MessageEntity::class,
        OfflineMessageEntity::class,
        SyncAnchorEntity::class
    ],
    version = 2,
    exportSchema = false
)
abstract class LispIMDatabase : RoomDatabase() {

    abstract fun conversationDao(): ConversationDao
    abstract fun messageDao(): MessageDao
    abstract fun offlineMessageDao(): OfflineMessageDao
    abstract fun syncAnchorDao(): SyncAnchorDao

    companion object {
        private const val DATABASE_NAME = "lispim_db"
    }
}

/**
 * Hilt module for providing database dependencies
 */
@Module
@InstallIn(SingletonComponent::class)
object DatabaseModule {

    @Provides
    @Singleton
    fun provideDatabase(
        @ApplicationContext context: Context
    ): LispIMDatabase {
        return Room.databaseBuilder(
            context,
            LispIMDatabase::class.java,
            LispIMDatabase.DATABASE_NAME
        ).build()
    }

    @Provides
    @Singleton
    fun provideConversationDao(database: LispIMDatabase): ConversationDao {
        return database.conversationDao()
    }

    @Provides
    @Singleton
    fun provideMessageDao(database: LispIMDatabase): MessageDao {
        return database.messageDao()
    }

    @Provides
    @Singleton
    fun provideOfflineMessageDao(database: LispIMDatabase): OfflineMessageDao {
        return database.offlineMessageDao()
    }

    @Provides
    @Singleton
    fun provideSyncAnchorDao(database: LispIMDatabase): SyncAnchorDao {
        return database.syncAnchorDao()
    }
}
