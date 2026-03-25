package com.lispim.app.ui.screens.profile

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.lispim.app.data.model.User
import com.lispim.app.ui.viewmodel.ProfileViewModel
import com.lispim.app.ui.viewmodel.ProfileUiState
import com.lispim.app.ui.viewmodel.ProfileAction
import com.lispim.app.ui.viewmodel.UserSettings

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ProfileScreen(
    viewModel: ProfileViewModel = hiltViewModel(),
    onNavigateToSettings: () -> Unit = {},
    onNavigateToLogin: () -> Unit = {}
) {
    val profileState by viewModel.profileState.collectAsState()
    val settings by viewModel.settings.collectAsState()
    val actionState by viewModel.actionState.collectAsState()

    var authToken by remember { mutableStateOf("") } // Would get from auth repository
    var showEditProfileDialog by remember { mutableStateOf(false) }
    var showChangePasswordDialog by remember { mutableStateOf(false) }

    // Handle action results
    LaunchedEffect(actionState) {
        when (actionState) {
            is ProfileAction.Success -> {
                // Show success snackbar
                viewModel.clearActionState()
            }
            is ProfileAction.Error -> {
                // Show error snackbar
                viewModel.clearActionState()
            }
            else -> {}
        }
    }

    // Load profile on first launch
    LaunchedEffect(Unit) {
        if (authToken.isNotEmpty()) {
            viewModel.loadProfile(authToken)
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("我") },
                actions = {
                    IconButton(onClick = onNavigateToSettings) {
                        Icon(Icons.Default.Settings, contentDescription = "设置")
                    }
                }
            )
        }
    ) { paddingValues ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(paddingValues)
                .verticalScroll(rememberScrollState())
        ) {
            // Profile header
            when (val state = profileState) {
                is ProfileUiState.Loading -> {
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(200.dp),
                        contentAlignment = Alignment.Center
                    ) {
                        CircularProgressIndicator()
                    }
                }
                is ProfileUiState.Success -> {
                    ProfileHeader(
                        user = state.user,
                        onEditClick = { showEditProfileDialog = true }
                    )
                }
                is ProfileUiState.Error -> {
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(200.dp),
                        contentAlignment = Alignment.Center
                    ) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            Icon(
                                Icons.Default.Error,
                                contentDescription = null,
                                tint = MaterialTheme.colorScheme.error
                            )
                            Spacer(modifier = Modifier.height(8.dp))
                            Text(state.message)
                        }
                    }
                }
            }

            Spacer(modifier = Modifier.height(16.dp))

            // Menu items
            ProfileMenuItem(
                icon = Icons.Default.Person,
                title = "个人信息",
                subtitle = "编辑个人资料",
                onClick = { showEditProfileDialog = true }
            )

            ProfileMenuItem(
                icon = Icons.Default.Lock,
                title = "修改密码",
                subtitle = "定期修改密码更安全",
                onClick = { showChangePasswordDialog = true }
            )

            ProfileMenuItem(
                icon = Icons.Default.Notifications,
                title = "通知设置",
                subtitle = if (settings.notificationsEnabled) "已开启" else "已关闭",
                onClick = { /* Navigate to notification settings */ }
            )

            ProfileMenuItem(
                icon = Icons.Default.Language,
                title = "语言",
                subtitle = settings.language,
                onClick = { /* Show language selector */ }
            )

            ProfileMenuItem(
                icon = Icons.Default.Palette,
                title = "主题",
                subtitle = when (settings.theme) {
                    "light" -> "浅色"
                    "dark" -> "深色"
                    else -> "跟随系统"
                },
                onClick = { /* Show theme selector */ }
            )

            Divider(modifier = Modifier.padding(vertical = 8.dp))

            ProfileMenuItem(
                icon = Icons.Default.Info,
                title = "关于我们",
                subtitle = "版本 1.0.0",
                onClick = { /* Show about dialog */ }
            )

            ProfileMenuItem(
                icon = Icons.Default.Help,
                title = "帮助与反馈",
                subtitle = "",
                onClick = { /* Show help */ }
            )

            Spacer(modifier = Modifier.height(16.dp))

            // Logout button
            Button(
                onClick = onNavigateToLogin,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp),
                colors = ButtonDefaults.buttonColors(
                    containerColor = MaterialTheme.colorScheme.error
                )
            ) {
                Icon(Icons.Default.Logout, contentDescription = null)
                Spacer(modifier = Modifier.width(8.dp))
                Text("退出登录")
            }

            Spacer(modifier = Modifier.height(24.dp))
        }
    }

    // Edit profile dialog
    if (showEditProfileDialog && profileState is ProfileUiState.Success) {
        val user = (profileState as ProfileUiState.Success).user
        EditProfileDialog(
            user = user,
            onDismiss = { showEditProfileDialog = false },
            onSave = { displayName, email, status ->
                viewModel.updateProfile(authToken, displayName, email, status)
                showEditProfileDialog = false
            }
        )
    }

    // Change password dialog
    if (showChangePasswordDialog) {
        ChangePasswordDialog(
            onDismiss = { showChangePasswordDialog = false },
            onChangePassword = { currentPassword, newPassword ->
                viewModel.changePassword(authToken, currentPassword, newPassword)
                showChangePasswordDialog = false
            }
        )
    }
}

@Composable
private fun ProfileHeader(
    user: User,
    onEditClick: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(16.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        // Avatar
        Surface(
            modifier = Modifier
                .size(80.dp)
                .clip(CircleShape),
            color = MaterialTheme.colorScheme.primaryContainer
        ) {
            Box(
                contentAlignment = Alignment.Center
            ) {
                val initial = (user.displayName ?: user.username).firstOrNull()?.uppercase() ?: "?"
                Text(
                    text = initial,
                    style = MaterialTheme.typography.headlineLarge,
                    color = MaterialTheme.colorScheme.onPrimaryContainer
                )
            }
        }

        Spacer(modifier = Modifier.height(12.dp))

        // Display name
        Text(
            text = user.displayName ?: user.username,
            style = MaterialTheme.typography.headlineSmall
        )

        // Username
        Text(
            text = "@${user.username}",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )

        // Status
        user.status?.let { status ->
            Spacer(modifier = Modifier.height(8.dp))
            Surface(
                shape = MaterialTheme.shapes.small,
                color = MaterialTheme.colorScheme.secondaryContainer
            ) {
                Text(
                    text = status,
                    style = MaterialTheme.typography.labelSmall,
                    modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp)
                )
            }
        }

        Spacer(modifier = Modifier.height(8.dp))

        // Edit button
        TextButton(onClick = onEditClick) {
            Icon(Icons.Default.Edit, contentDescription = null)
            Spacer(modifier = Modifier.width(4.dp))
            Text("编辑资料")
        }
    }
}

@Composable
private fun ProfileMenuItem(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    title: String,
    subtitle: String = "",
    onClick: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.primary,
            modifier = Modifier.size(24.dp)
        )

        Spacer(modifier = Modifier.width(16.dp))

        Column(
            modifier = Modifier.weight(1f)
        ) {
            Text(
                text = title,
                style = MaterialTheme.typography.bodyLarge
            )
            if (subtitle.isNotEmpty()) {
                Text(
                    text = subtitle,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }

        Icon(
            imageVector = Icons.Default.ChevronRight,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

@Composable
private fun EditProfileDialog(
    user: User,
    onDismiss: () -> Unit,
    onSave: (String?, String?, String?) -> Unit
) {
    var displayName by remember { mutableStateOf(user.displayName ?: "") }
    var email by remember { mutableStateOf(user.email ?: "") }
    var status by remember { mutableStateOf(user.status ?: "") }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("编辑资料") },
        text = {
            Column {
                OutlinedTextField(
                    value = displayName,
                    onValueChange = { displayName = it },
                    label = { Text("昵称") },
                    modifier = Modifier.fillMaxWidth()
                )
                Spacer(modifier = Modifier.height(8.dp))
                OutlinedTextField(
                    value = email,
                    onValueChange = { email = it },
                    label = { Text("邮箱") },
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = true
                )
                Spacer(modifier = Modifier.height(8.dp))
                OutlinedTextField(
                    value = status,
                    onValueChange = { status = it },
                    label = { Text("状态") },
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = true
                )
            }
        },
        confirmButton = {
            Button(onClick = {
                onSave(
                    displayName.ifBlank { null },
                    email.ifBlank { null },
                    status.ifBlank { null }
                )
            }) {
                Text("保存")
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
private fun ChangePasswordDialog(
    onDismiss: () -> Unit,
    onChangePassword: (String, String) -> Unit
) {
    var currentPassword by remember { mutableStateOf("") }
    var newPassword by remember { mutableStateOf("") }
    var confirmPassword by remember { mutableStateOf("") }
    var error by remember { mutableStateOf<String?>(null) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("修改密码") },
        text = {
            Column {
                OutlinedTextField(
                    value = currentPassword,
                    onValueChange = {
                        currentPassword = it
                        error = null
                    },
                    label = { Text("当前密码") },
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = true,
                    visualTransformation = androidx.compose.ui.text.input.PasswordVisualTransformation()
                )
                Spacer(modifier = Modifier.height(8.dp))
                OutlinedTextField(
                    value = newPassword,
                    onValueChange = {
                        newPassword = it
                        error = null
                    },
                    label = { Text("新密码") },
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = true,
                    visualTransformation = androidx.compose.ui.text.input.PasswordVisualTransformation()
                )
                Spacer(modifier = Modifier.height(8.dp))
                OutlinedTextField(
                    value = confirmPassword,
                    onValueChange = { confirmPassword = it },
                    label = { Text("确认新密码") },
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = true,
                    visualTransformation = androidx.compose.ui.text.input.PasswordVisualTransformation(),
                    isError = newPassword != confirmPassword && confirmPassword.isNotEmpty()
                )
                if (newPassword != confirmPassword && confirmPassword.isNotEmpty()) {
                    Spacer(modifier = Modifier.height(4.dp))
                    Text(
                        text = "两次输入的密码不一致",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.error
                    )
                }
                error?.let {
                    Spacer(modifier = Modifier.height(8.dp))
                    Text(
                        text = it,
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.error
                    )
                }
            }
        },
        confirmButton = {
            Button(
                onClick = {
                    when {
                        currentPassword.isBlank() -> error = "请输入当前密码"
                        newPassword.isBlank() -> error = "请输入新密码"
                        newPassword.length < 6 -> error = "密码至少 6 位"
                        newPassword != confirmPassword -> error = "两次密码不一致"
                        else -> onChangePassword(currentPassword, confirmPassword)
                    }
                },
                enabled = currentPassword.isNotBlank() && newPassword.isNotBlank() &&
                        newPassword == confirmPassword && newPassword.length >= 6
            ) {
                Text("确认修改")
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text("取消")
            }
        }
    )
}
