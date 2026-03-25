package com.lispim.app.ui.screens.contacts

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.lispim.app.ui.viewmodel.ContactsViewModel
import com.lispim.app.ui.viewmodel.ContactsUiState
import com.lispim.app.ui.viewmodel.FriendRequestsUiState
import com.lispim.app.ui.viewmodel.SearchUiState
import com.lispim.app.ui.viewmodel.FriendAction

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ContactsScreen(
    viewModel: ContactsViewModel = hiltViewModel(),
    onNavigateToChat: (String) -> Unit = {},
    onNavigateToUserProfile: (String) -> Unit = {}
) {
    val uiState by viewModel.uiState.collectAsState()
    val requestsState by viewModel.requestsState.collectAsState()
    val searchState by viewModel.searchState.collectAsState()
    val actionState by viewModel.actionState.collectAsState()

    var showAddFriendDialog by remember { mutableStateOf(false) }
    var showRequestsSheet by remember { mutableStateOf(false) }
    var authToken by remember { mutableStateOf("") } // Would get from auth repository

    // Handle action results
    LaunchedEffect(actionState) {
        when (actionState) {
            is FriendAction.Success -> {
                // Show success snackbar
                viewModel.clearActionState()
            }
            is FriendAction.Error -> {
                // Show error snackbar
                viewModel.clearActionState()
            }
            else -> {}
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("联系人") },
                actions = {
                    IconButton(onClick = { showRequestsSheet = true }) {
                        Icon(Icons.Filled.PersonAdd, contentDescription = "好友请求")
                    }
                    IconButton(onClick = { showAddFriendDialog = true }) {
                        Icon(Icons.Filled.Add, contentDescription = "添加好友")
                    }
                }
            )
        }
    ) { paddingValues ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(paddingValues)
        ) {
            // Search bar
            SearchBar(
                onSearch = { query -> viewModel.searchUsers(authToken, query) },
                onClear = { viewModel.clearSearch() }
            )

            when (val state = uiState) {
                is ContactsUiState.Loading -> {
                    Box(
                        modifier = Modifier.fillMaxSize(),
                        contentAlignment = Alignment.Center
                    ) {
                        CircularProgressIndicator()
                    }
                }
                is ContactsUiState.Empty -> {
                    EmptyContactsList(onAddFriend = { showAddFriendDialog = true })
                }
                is ContactsUiState.Error -> {
                    ErrorView(
                        message = state.message,
                        onRetry = { viewModel.loadFriends(authToken) }
                    )
                }
                is ContactsUiState.Success -> {
                    FriendsList(
                        friends = state.friends,
                        onFriendClick = { onNavigateToUserProfile(it.id) },
                        onChatClick = { onNavigateToChat(it.id) },
                        onDeleteFriend = { viewModel.deleteFriend(authToken, it.id) }
                    )
                }
            }
        }
    }

    // Add friend dialog
    if (showAddFriendDialog) {
        AddFriendDialog(
            onDismiss = { showAddFriendDialog = false },
            onConfirm = { friendId, message ->
                viewModel.sendFriendRequest(authToken, friendId, message)
                showAddFriendDialog = false
            }
        )
    }

    // Friend requests bottom sheet
    if (showRequestsSheet) {
        FriendRequestsSheet(
            requestsState = requestsState,
            onAccept = { viewModel.acceptFriendRequest(authToken, it.id) },
            onReject = { viewModel.rejectFriendRequest(authToken, it.id) },
            onDismiss = { showRequestsSheet = false }
        )
    }
}

@Composable
private fun SearchBar(
    onSearch: (String) -> Unit,
    onClear: () -> Unit
) {
    var query by remember { mutableStateOf("") }

    OutlinedTextField(
        value = query,
        onValueChange = {
            query = it
            onSearch(it)
        },
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 8.dp),
        placeholder = { Text("搜索用户...") },
        leadingIcon = {
            Icon(Icons.Default.Search, contentDescription = null)
        },
        trailingIcon = {
            if (query.isNotEmpty()) {
                IconButton(onClick = {
                    query = ""
                    onClear()
                }) {
                    Icon(Icons.Default.Clear, contentDescription = "清除")
                }
            }
        },
        singleLine = true,
        shape = MaterialTheme.shapes.medium
    )
}

@Composable
private fun FriendsList(
    friends: List<com.lispim.app.data.model.Friend>,
    onFriendClick: (com.lispim.app.data.model.Friend) -> Unit,
    onChatClick: (com.lispim.app.data.model.Friend) -> Unit,
    onDeleteFriend: (String) -> Unit
) {
    LazyColumn(
        modifier = Modifier.fillMaxSize()
    ) {
        items(friends, key = { it.id }) { friend ->
            FriendItem(
                friend = friend,
                onClick = { onFriendClick(friend) },
                onChatClick = { onChatClick(friend) },
                onDeleteClick = { onDeleteFriend(friend.id) }
            )
        }
    }
}

@Composable
private fun FriendItem(
    friend: com.lispim.app.data.model.Friend,
    onClick: () -> Unit,
    onChatClick: () -> Unit,
    onDeleteClick: () -> Unit
) {
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 4.dp)
            .clickable(onClick = onClick),
        elevation = CardDefaults.cardElevation(defaultElevation = 1.dp)
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            // Avatar
            Avatar(friend.avatar, friend.displayName ?: friend.username)

            Spacer(modifier = Modifier.width(12.dp))

            // Info
            Column(
                modifier = Modifier.weight(1f)
            ) {
                Text(
                    text = friend.displayName ?: friend.username,
                    style = MaterialTheme.typography.bodyLarge
                )
                Text(
                    text = "@${friend.username}",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                friend.status?.let { status ->
                    Text(
                        text = status,
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.primary
                    )
                }
            }

            // Actions
            IconButton(onClick = onChatClick) {
                Icon(Icons.Default.ChatBubble, contentDescription = "发消息")
            }
            IconButton(onClick = onDeleteClick) {
                Icon(Icons.Default.MoreVert, contentDescription = "更多")
            }
        }
    }
}

@Composable
private fun Avatar(avatarUrl: String?, name: String) {
    val initial = name.firstOrNull()?.uppercase() ?: "?"

    Surface(
        modifier = Modifier.size(48.dp),
        shape = MaterialTheme.shapes.medium,
        color = MaterialTheme.colorScheme.primaryContainer
    ) {
        Box(
            contentAlignment = Alignment.Center
        ) {
            if (avatarUrl != null) {
                // Would load image with Coil
                Text(
                    text = initial,
                    style = MaterialTheme.typography.titleMedium,
                    color = MaterialTheme.colorScheme.onPrimaryContainer
                )
            } else {
                Text(
                    text = initial,
                    style = MaterialTheme.typography.titleMedium,
                    color = MaterialTheme.colorScheme.onPrimaryContainer
                )
            }
        }
    }
}

@Composable
private fun EmptyContactsList(onAddFriend: () -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Icon(
            imageVector = Icons.Default.People,
            contentDescription = null,
            modifier = Modifier.size(64.dp),
            tint = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Spacer(modifier = Modifier.height(16.dp))
        Text(
            text = "暂无联系人",
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Spacer(modifier = Modifier.height(8.dp))
        Button(onClick = onAddFriend) {
            Icon(Icons.Default.Add, contentDescription = null)
            Spacer(modifier = Modifier.width(8.dp))
            Text("添加好友")
        }
    }
}

@Composable
private fun ErrorView(message: String, onRetry: () -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Icon(
            imageVector = Icons.Default.Error,
            contentDescription = null,
            modifier = Modifier.size(64.dp),
            tint = MaterialTheme.colorScheme.error
        )
        Spacer(modifier = Modifier.height(16.dp))
        Text(
            text = message,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Spacer(modifier = Modifier.height(16.dp))
        Button(onClick = onRetry) {
            Text("重试")
        }
    }
}

@Composable
private fun AddFriendDialog(
    onDismiss: () -> Unit,
    onConfirm: (String, String?) -> Unit
) {
    var friendId by remember { mutableStateOf("") }
    var message by remember { mutableStateOf("") }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("添加好友") },
        text = {
            Column {
                OutlinedTextField(
                    value = friendId,
                    onValueChange = { friendId = it },
                    label = { Text("用户 ID 或用户名") },
                    modifier = Modifier.fillMaxWidth()
                )
                Spacer(modifier = Modifier.height(8.dp))
                OutlinedTextField(
                    value = message,
                    onValueChange = { message = it },
                    label = { Text("验证消息（可选）") },
                    modifier = Modifier.fillMaxWidth(),
                    maxLines = 3
                )
            }
        },
        confirmButton = {
            Button(
                onClick = { onConfirm(friendId, message.ifBlank { null }) },
                enabled = friendId.isNotBlank()
            ) {
                Text("发送请求")
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text("取消")
            }
        }
    )
}

@Composable
private fun FriendRequestsSheet(
    requestsState: FriendRequestsUiState,
    onAccept: (com.lispim.app.data.model.FriendRequest) -> Unit,
    onReject: (com.lispim.app.data.model.FriendRequest) -> Unit,
    onDismiss: () -> Unit
) {
    ModalNavigationDrawer(
        drawerContent = {
            Box(modifier = Modifier.fillMaxSize()) {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(16.dp)
                ) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            text = "好友请求",
                            style = MaterialTheme.typography.titleLarge
                        )
                        IconButton(onClick = onDismiss) {
                            Icon(Icons.Default.Clear, contentDescription = "关闭")
                        }
                    }
                    Spacer(modifier = Modifier.height(16.dp))

                    when (requestsState) {
                        is FriendRequestsUiState.Loading -> {
                            Box(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .height(200.dp),
                                contentAlignment = Alignment.Center
                            ) {
                                CircularProgressIndicator()
                            }
                        }
                        is FriendRequestsUiState.Empty -> {
                            Text(
                                text = "暂无好友请求",
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                modifier = Modifier.padding(vertical = 32.dp)
                            )
                        }
                        is FriendRequestsUiState.Success -> {
                            LazyColumn {
                                items(requestsState.requests, key = { it.id }) { request ->
                                    FriendRequestItem(
                                        request = request,
                                        onAccept = { onAccept(request) },
                                        onReject = { onReject(request) }
                                    )
                                }
                            }
                        }
                        is FriendRequestsUiState.Error -> {
                            Text(
                                text = requestsState.message,
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.error
                            )
                        }
                    }
                }
            }
        }
    ) {
        // Empty content - this is just a drawer
    }
}

@Composable
private fun FriendRequestItem(
    request: com.lispim.app.data.model.FriendRequest,
    onAccept: () -> Unit,
    onReject: () -> Unit
) {
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 4.dp),
        elevation = CardDefaults.cardElevation(defaultElevation = 1.dp)
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp)
        ) {
            Text(
                text = request.senderDisplayName ?: request.senderUsername,
                style = MaterialTheme.typography.bodyLarge
            )
            Text(
                text = "@${request.senderUsername}",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            if (!request.message.isNullOrBlank()) {
                Spacer(modifier = Modifier.height(8.dp))
                Text(
                    text = request.message!!,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            Spacer(modifier = Modifier.height(12.dp))
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.End
            ) {
                TextButton(onClick = onReject) {
                    Text("拒绝")
                }
                Spacer(modifier = Modifier.width(8.dp))
                Button(onClick = onAccept) {
                    Text("接受")
                }
            }
        }
    }
}
