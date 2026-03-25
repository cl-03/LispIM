package com.lispim.app.di

import com.lispim.app.data.websocket.LispIMWebSocketManager
import com.lispim.app.data.websocket.WebSocketManager
import dagger.Binds
import dagger.Module
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

/**
 * Hilt module for WebSocket bindings
 */
@Module
@InstallIn(SingletonComponent::class)
abstract class WebSocketModule {

    @Binds
    @Singleton
    abstract fun bindWebSocketManager(
        webSocketManager: LispIMWebSocketManager
    ): WebSocketManager
}
