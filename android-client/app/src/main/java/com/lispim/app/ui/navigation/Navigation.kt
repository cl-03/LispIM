package com.lispim.app.ui.navigation

import androidx.compose.runtime.Composable
import androidx.navigation.NavHostController
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import com.lispim.app.ui.screens.chat.ChatScreen
import com.lispim.app.ui.screens.contacts.ContactsScreen
import com.lispim.app.ui.screens.discover.DiscoverScreen
import com.lispim.app.ui.screens.login.LoginScreen
import com.lispim.app.ui.screens.profile.ProfileScreen
import com.lispim.app.ui.screens.register.RegisterScreen

/**
 * App Navigation Routes
 */
object Routes {
    const val LOGIN = "login"
    const val REGISTER = "register"
    const val MAIN = "main"
    const val CHAT = "chat"
    const val CONTACTS = "contacts"
    const val DISCOVER = "discover"
    const val PROFILE = "profile"
    const val CHAT_DETAIL = "chat_detail/{conversationId}"
}

/**
 * Main Navigation Host
 */
@Composable
fun LispIMNavHost(
    navController: NavHostController = rememberNavController(),
    startDestination: String = Routes.LOGIN
) {
    NavHost(
        navController = navController,
        startDestination = startDestination
    ) {
        // Auth screens
        composable(Routes.LOGIN) {
            LoginScreen(
                onLoginSuccess = {
                    navController.navigate(Routes.MAIN) {
                        popUpTo(Routes.LOGIN) { inclusive = true }
                    }
                },
                onNavigateToRegister = {
                    navController.navigate(Routes.REGISTER)
                }
            )
        }

        composable(Routes.REGISTER) {
            RegisterScreen(
                onRegisterSuccess = {
                    navController.navigate(Routes.MAIN) {
                        popUpTo(Routes.REGISTER) { inclusive = true }
                    }
                },
                onNavigateToLogin = {
                    navController.popBackStack()
                }
            )
        }

        // Main screens with bottom navigation
        composable(Routes.MAIN) {
            MainScreen()
        }

        composable(Routes.CHAT) {
            ChatScreen()
        }

        composable(Routes.CONTACTS) {
            ContactsScreen()
        }

        composable(Routes.DISCOVER) {
            DiscoverScreen()
        }

        composable(Routes.PROFILE) {
            ProfileScreen()
        }

        // Detail screens
        composable(
            route = Routes.CHAT_DETAIL,
            arguments = listOf(
                navArgument("conversationId") { type = NavType.StringType }
            )
        ) { backStackEntry ->
            val conversationId = backStackEntry.arguments?.getString("conversationId") ?: return@composable
            ChatDetailScreen(conversationId = conversationId)
        }
    }
}
