package com.lispim.app.di

import com.lispim.app.data.api.ApiProvider
import com.lispim.app.data.api.LispIMApiService
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

/**
 * Hilt module for providing API dependencies
 */
@Module
@InstallIn(SingletonComponent::class)
object ApiModule {

    @Provides
    @Singleton
    fun provideLispIMApiService(): LispIMApiService {
        return ApiProvider.apiService
    }
}
