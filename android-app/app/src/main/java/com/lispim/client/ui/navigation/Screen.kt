package com.lispim.client.ui.navigation

sealed class Screen(val route: String) {
    object Login : Screen("login")
    object Main : Screen("main")  // Bottom navigation host
    object Home : Screen("home")  // Messages tab - recent chats
    object Contacts : Screen("contacts")  // Contacts tab - friends list
    object Discover : Screen("discover")  // Discover tab - extended features
    object Profile : Screen("profile")  // Profile tab - settings
    object Conversation : Screen("conversation/{conversationId}") {
        fun createRoute(conversationId: Long) = "conversation/$conversationId"
    }
    object AddFriend : Screen("add_friend")  // Add friend screen
}
