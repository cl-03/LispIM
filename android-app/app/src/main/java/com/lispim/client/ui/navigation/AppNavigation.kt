package com.lispim.client.ui.navigation

import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.navigation.NavHostController
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import com.lispim.client.ui.screens.*

@Composable
fun AppNavigation() {
    val navController = rememberNavController()

    NavHost(
        navController = navController,
        startDestination = "splash"
    ) {
        composable("splash") {
            // Splash screen - check auth status
            val context = android.content.ContextWrapper(androidx.compose.ui.platform.LocalContext.current)
            val app = context.applicationContext as com.lispim.client.LispIMApplication
            val isLoggedIn by app.repository.currentUser.collectAsState()

            if (isLoggedIn != null) {
                navController.navigate(Screen.Main.route) {
                    popUpTo("splash") { inclusive = true }
                }
            } else {
                navController.navigate(Screen.Login.route) {
                    popUpTo("splash") { inclusive = true }
                }
            }
        }

        composable(Screen.Login.route) {
            LoginScreen(
                onLoginSuccess = {
                    navController.navigate(Screen.Main.route) {
                        popUpTo(Screen.Login.route) { inclusive = true }
                    }
                }
            )
        }

        composable(Screen.Main.route) {
            MainScreen(
                navController = navController,
                onNavigateToConversation = { conversationId ->
                    navController.navigate(Screen.Conversation.createRoute(conversationId))
                },
                onLogout = {
                    navController.navigate(Screen.Login.route) {
                        popUpTo(Screen.Main.route) { inclusive = true }
                    }
                }
            )
        }

        composable(
            route = Screen.Conversation.route,
            arguments = listOf(
                navArgument("conversationId") {
                    type = NavType.LongType
                }
            )
        ) { backStackEntry ->
            val conversationId = backStackEntry.arguments?.getLong("conversationId") ?: return@composable
            ConversationScreen(
                conversationId = conversationId,
                onNavigateBack = {
                    navController.popBackStack()
                }
            )
        }
    }
}
