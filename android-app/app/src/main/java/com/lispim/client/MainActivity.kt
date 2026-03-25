package com.lispim.client

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.ui.Modifier
import com.lispim.client.ui.navigation.AppNavigation
import com.lispim.client.ui.theme.LispIMTheme
import mu.KotlinLogging

private val logger = KotlinLogging.logger {}

class MainActivity : ComponentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        logger.info { "MainActivity onCreate" }

        setContent {
            LispIMTheme {
                Surface(
                    modifier = Modifier.fillMaxSize(),
                    color = MaterialTheme.colorScheme.background
                ) {
                    AppNavigation()
                }
            }
        }
    }

    override fun onStart() {
        super.onStart()
        logger.debug { "MainActivity onStart" }
    }

    override fun onStop() {
        super.onStop()
        logger.debug { "MainActivity onStop" }
    }
}
