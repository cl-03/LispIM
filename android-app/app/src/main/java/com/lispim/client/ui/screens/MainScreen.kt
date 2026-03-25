package com.lispim.client.ui.screens

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import com.lispim.client.ui.navigation.Screen

@Composable
fun MainScreen(
    navController: NavHostController,
    onNavigateToConversation: (Long) -> Unit,
    onLogout: () -> Unit
) {
    var selectedTab by remember { mutableStateOf(0) }

    val tabs = listOf("消息", "联系人", "发现", "我")

    Scaffold(
        modifier = Modifier.fillMaxSize(),
        bottomBar = {
            NavigationBar {
                tabs.forEachIndexed { index, title ->
                    NavigationBarItem(
                        icon = {
                            Icon(
                                when (index) {
                                    0 -> if (selectedTab == 0) Icons.Filled.Message else Icons.Outlined.Message
                                    1 -> if (selectedTab == 1) Icons.Filled.People else Icons.Outlined.People
                                    2 -> if (selectedTab == 2) Icons.Filled.Explore else Icons.Outlined.Explore
                                    3 -> if (selectedTab == 3) Icons.Filled.Person else Icons.Outlined.Person
                                    else -> Icons.Outlined.Circle
                                },
                                contentDescription = title
                            )
                        },
                        label = { Text(title) },
                        selected = selectedTab == index,
                        onClick = { selectedTab = index }
                    )
                }
            }
        }
    ) { paddingValues ->
        // 直接使用 when 表达式显示不同的屏幕，而不是使用 NavHost
        when (selectedTab) {
            0 -> HomeScreen(
                modifier = Modifier.padding(paddingValues),
                onNavigateToConversation = onNavigateToConversation,
                onLogout = onLogout
            )
            1 -> ContactsScreen(
                modifier = Modifier.padding(paddingValues),
                onNavigateToAddFriend = {
                    // Navigate to add friend screen
                }
            )
            2 -> DiscoverScreen()
            3 -> ProfileScreen(
                modifier = Modifier.padding(paddingValues),
                onLogout = onLogout
            )
        }
    }
}
