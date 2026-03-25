package com.lispim.app.ui.screens.settings

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.lispim.app.ui.viewmodel.UserSettings

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(
    settings: UserSettings = UserSettings(),
    onSettingsChanged: (UserSettings) -> Unit = {},
    onNavigateBack: () -> Unit = {}
) {
    var notificationsEnabled by remember { mutableStateOf(settings.notificationsEnabled) }
    var soundEnabled by remember { mutableStateOf(settings.soundEnabled) }
    var vibrationEnabled by remember { mutableStateOf(settings.vibrationEnabled) }
    var doNotDisturb by remember { mutableStateOf(settings.doNotDisturb) }
    var language by remember { mutableStateOf(settings.language) }
    var theme by remember { mutableStateOf(settings.theme) }

    var showLanguageDialog by remember { mutableStateOf(false) }
    var showThemeDialog by remember { mutableStateOf(false) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("设置") },
                navigationIcon = {
                    IconButton(onClick = onNavigateBack) {
                        Icon(Icons.Default.ArrowBack, contentDescription = "返回")
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
            // Notification settings
            Text(
                text = "通知",
                style = MaterialTheme.typography.titleMedium,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)
            )

            SettingsSwitchItem(
                icon = Icons.Default.Notifications,
                title = "通知",
                subtitle = "允许应用发送通知",
                checked = notificationsEnabled,
                onCheckedChange = {
                    notificationsEnabled = it
                    onSettingsChanged(settings.copy(notificationsEnabled = it))
                }
            )

            SettingsSwitchItem(
                icon = Icons.Default.VolumeUp,
                title = "声音",
                subtitle = "新消息提示音",
                checked = soundEnabled && notificationsEnabled,
                enabled = notificationsEnabled,
                onCheckedChange = {
                    soundEnabled = it
                    onSettingsChanged(settings.copy(soundEnabled = it))
                }
            )

            SettingsSwitchItem(
                icon = Icons.Default.Vibration,
                title = "振动",
                subtitle = "新消息振动提醒",
                checked = vibrationEnabled && notificationsEnabled,
                enabled = notificationsEnabled,
                onCheckedChange = {
                    vibrationEnabled = it
                    onSettingsChanged(settings.copy(vibrationEnabled = it))
                }
            )

            SettingsSwitchItem(
                icon = Icons.Default.Nightlight,
                title = "免打扰",
                subtitle = "静音模式，不接收通知",
                checked = doNotDisturb,
                onCheckedChange = {
                    doNotDisturb = it
                    onSettingsChanged(settings.copy(doNotDisturb = it))
                }
            )

            Divider(modifier = Modifier.padding(vertical = 8.dp))

            // Appearance settings
            Text(
                text = "外观",
                style = MaterialTheme.typography.titleMedium,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)
            )

            SettingsItem(
                icon = Icons.Default.Language,
                title = "语言",
                subtitle = when (language) {
                    "zh-CN" -> "简体中文"
                    "zh-TW" -> "繁體中文"
                    "en" -> "English"
                    else -> language
                },
                onClick = { showLanguageDialog = true }
            )

            SettingsItem(
                icon = Icons.Default.Palette,
                title = "主题",
                subtitle = when (theme) {
                    "light" -> "浅色模式"
                    "dark" -> "深色模式"
                    else -> "跟随系统"
                },
                onClick = { showThemeDialog = true }
            )

            Divider(modifier = Modifier.padding(vertical = 8.dp))

            // Privacy settings
            Text(
                text = "隐私",
                style = MaterialTheme.typography.titleMedium,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)
            )

            SettingsItem(
                icon = Icons.Default.Visibility,
                title = "在线状态",
                subtitle = "向我的人显示在线状态",
                onClick = { /* Show privacy settings */ }
            )

            SettingsItem(
                icon = Icons.Default.PersonAddDisabled,
                title = "黑名单",
                subtitle = "管理已屏蔽的用户",
                onClick = { /* Show blacklist */ }
            )

            Divider(modifier = Modifier.padding(vertical = 8.dp))

            // Data and storage
            Text(
                text = "数据和存储",
                style = MaterialTheme.typography.titleMedium,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)
            )

            SettingsItem(
                icon = Icons.Default.Storage,
                title = "存储空间",
                subtitle = "管理缓存和数据",
                onClick = { /* Show storage settings */ }
            )

            SettingsItem(
                icon = Icons.Default.ClearAll,
                title = "清除缓存",
                subtitle = "释放存储空间",
                onClick = { /* Clear cache */ }
            )
        }
    }

    // Language selector dialog
    if (showLanguageDialog) {
        LanguageDialog(
            currentLanguage = language,
            onDismiss = { showLanguageDialog = false },
            onLanguageSelected = {
                language = it
                onSettingsChanged(settings.copy(language = it))
                showLanguageDialog = false
            }
        )
    }

    // Theme selector dialog
    if (showThemeDialog) {
        ThemeDialog(
            currentTheme = theme,
            onDismiss = { showThemeDialog = false },
            onThemeSelected = {
                theme = it
                onSettingsChanged(settings.copy(theme = it))
                showThemeDialog = false
            }
        )
    }
}

@Composable
private fun SettingsItem(
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
private fun SettingsSwitchItem(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    title: String,
    subtitle: String = "",
    checked: Boolean,
    enabled: Boolean = true,
    onCheckedChange: (Boolean) -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(enabled = enabled) { onCheckedChange(!checked) }
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = if (enabled) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f),
            modifier = Modifier.size(24.dp)
        )

        Spacer(modifier = Modifier.width(16.dp))

        Column(
            modifier = Modifier.weight(1f)
        ) {
            Text(
                text = title,
                style = MaterialTheme.typography.bodyLarge,
                color = if (enabled) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f)
            )
            if (subtitle.isNotEmpty()) {
                Text(
                    text = subtitle,
                    style = MaterialTheme.typography.bodySmall,
                    color = if (enabled) MaterialTheme.colorScheme.onSurfaceVariant else MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f)
                )
            }
        }

        Switch(
            checked = checked,
            onCheckedChange = onCheckedChange,
            enabled = enabled
        )
    }
}

@Composable
private fun LanguageDialog(
    currentLanguage: String,
    onDismiss: () -> Unit,
    onLanguageSelected: (String) -> Unit
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("选择语言") },
        text = {
            Column {
                LanguageOption("简体中文", "zh-CN", currentLanguage, onLanguageSelected)
                LanguageOption("繁體中文", "zh-TW", currentLanguage, onLanguageSelected)
                LanguageOption("English", "en", currentLanguage, onLanguageSelected)
            }
        },
        confirmButton = {
            TextButton(onClick = onDismiss) {
                Text("取消")
            }
        }
    )
}

@Composable
private fun LanguageOption(
    label: String,
    value: String,
    selected: String,
    onSelect: (String) -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable { onSelect(value) }
            .padding(vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        RadioButton(
            selected = selected == value,
            onClick = { onSelect(value) }
        )
        Spacer(modifier = Modifier.width(8.dp))
        Text(label)
    }
}

@Composable
private fun ThemeDialog(
    currentTheme: String,
    onDismiss: () -> Unit,
    onThemeSelected: (String) -> Unit
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("选择主题") },
        text = {
            Column {
                ThemeOption("跟随系统", "system", currentTheme, onThemeSelected)
                ThemeOption("浅色模式", "light", currentTheme, onThemeSelected)
                ThemeOption("深色模式", "dark", currentTheme, onThemeSelected)
            }
        },
        confirmButton = {
            TextButton(onClick = onDismiss) {
                Text("取消")
            }
        }
    )
}

@Composable
private fun ThemeOption(
    label: String,
    value: String,
    selected: String,
    onSelect: (String) -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable { onSelect(value) }
            .padding(vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        RadioButton(
            selected = selected == value,
            onClick = { onSelect(value) }
        )
        Spacer(modifier = Modifier.width(8.dp))
        Text(label)
    }
}
