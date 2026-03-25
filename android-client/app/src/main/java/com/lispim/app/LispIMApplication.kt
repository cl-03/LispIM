package com.lispim.app

import android.app.Application
import dagger.hilt.android.HiltAndroidApp

/**
 * LispIM Application class
 * Entry point for Hilt dependency injection
 */
@HiltAndroidApp
class LispIMApplication : Application() {

    override fun onCreate() {
        super.onCreate()
        // Initialize app-level components
    }
}
