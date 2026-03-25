package com.lispim.app.ui.screens.chat

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.core.graphics.drawable.toBitmap
import androidx.hilt.navigation.compose.hiltViewModel
import coil.ImageLoader
import coil.request.ImageRequest
import coil.request.SuccessResult
import com.lispim.app.data.local.entity.MessageEntity
import com.lispim.app.ui.screens.file.ImagePreviewDialog
import com.lispim.app.ui.screens.file.getFileTypeFromMimeType
import com.lispim.app.ui.screens.file.formatFileSize
import com.lispim.app.ui.viewmodel.ChatViewModel
import com.lispim.app.ui.viewmodel.FileUploadViewModel
import java.text.SimpleDateFormat
import java.util.*
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch
import org.json.JSONObject

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ChatScreen() {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Text(
            text = "消息",
            style = MaterialTheme.typography.headlineMedium
        )
        Spacer(modifier = Modifier.height(8.dp))
        Text(
            text = "暂无消息",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ChatDetailScreen(
    conversationId: String,
    viewModel: ChatViewModel = hiltViewModel(),
    fileUploadViewModel: FileUploadViewModel = hiltViewModel()
) {
    val messages by viewModel.messages.collectAsState()
    val connectionState by viewModel.connectionState.collectAsState()
    val typingUsers by viewModel.typingUsers.collectAsState()
    var messageText by remember { mutableStateOf("") }
    val authToken by viewModel.authToken.collectAsState()

    // File picker launcher
    val context = LocalContext.current
    val filePickerLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.GetContent()
    ) { uri: Uri? ->
        uri?.let { fileUri ->
            // Upload the selected file
            fileUploadViewModel.uploadFile(fileUri, authToken ?: "")
        }
    }

    // Observe file upload result
    val uploadState by fileUploadViewModel.uploadState.collectAsState()
    LaunchedEffect(uploadState) {
        when (val state = uploadState) {
            is com.lispim.app.ui.viewmodel.FileUploadState.Success -> {
                // Send file message
                viewModel.sendFileMessage(
                    fileId = state.fileId,
                    fileName = state.filename,
                    fileSize = state.size,
                    mimeType = context.contentResolver.getType(
                        Uri.parse(state.url)
                    ) ?: "application/octet-stream"
                )
                fileUploadViewModel.resetUploadState()
            }
            is com.lispim.app.ui.viewmodel.FileUploadState.Error -> {
                fileUploadViewModel.resetUploadState()
            }
            else -> {}
        }
    }

    // Format date
    val dateFormat = SimpleDateFormat("HH:mm", Locale.getDefault())

    Column(modifier = Modifier.fillMaxSize()) {
        // Connection status indicator
        ConnectionStatusIndicator(connectionState)

        // Messages list
        LazyColumn(
            modifier = Modifier
                .weight(1f)
                .padding(horizontal = 8.dp),
            contentPadding = PaddingValues(vertical = 8.dp)
        ) {
            items(messages, key = { it.remoteId }) { message ->
                MessageBubble(
                    message = message,
                    isFromMe = false, // Would need to check against current user ID
                    time = dateFormat.format(Date(message.createdAt)),
                    onImageClick = { imageUrl ->
                        // Handle image click - show preview
                    }
                )
            }
        }

        // Typing indicator
        if (typingUsers.isNotEmpty()) {
            TypingIndicator(userCount = typingUsers.size)
        }

        // Message input
        MessageInputRow(
            messageText = messageText,
            onMessageTextChange = { messageText = it },
            onSendMessage = {
                if (messageText.isNotBlank()) {
                    viewModel.sendMessage(messageText)
                    messageText = ""
                }
            },
            onPickFile = { filePickerLauncher.launch("*/*") },
            enabled = connectionState is com.lispim.app.data.websocket.ConnectionState.Connected
        )
    }
}

@Composable
private fun ConnectionStatusIndicator(connectionState: com.lispim.app.data.websocket.ConnectionState) {
    val (text, color) = when (connectionState) {
        is com.lispim.app.data.websocket.ConnectionState.Connected ->
            "已连接" to MaterialTheme.colorScheme.primary
        is com.lispim.app.data.websocket.ConnectionState.Connecting,
        is com.lispim.app.data.websocket.ConnectionState.Reconnecting ->
            "连接中..." to MaterialTheme.colorScheme.secondary
        is com.lispim.app.data.websocket.ConnectionState.Disconnected,
        is com.lispim.app.data.websocket.ConnectionState.Error ->
            "已断开" to MaterialTheme.colorScheme.error
    }

    Box(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 4.dp, horizontal = 8.dp)
    ) {
        Text(
            text = text,
            style = MaterialTheme.typography.bodySmall,
            color = color,
            modifier = Modifier.align(Alignment.Center)
        )
    }
}

@Composable
private fun MessageBubble(
    message: MessageEntity,
    isFromMe: Boolean,
    time: String,
    onImageClick: (String) -> Unit
) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 4.dp, horizontal = 8.dp)
    ) {
        Column(
            modifier = Modifier
                .align(if (isFromMe) Alignment.CenterEnd else Alignment.CenterStart)
                .widthIn(max = 300.dp)
        ) {
            if (!isFromMe) {
                Text(
                    text = message.senderName ?: "未知",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.secondary,
                    modifier = Modifier.padding(start = 4.dp, bottom = 2.dp)
                )
            }

            Surface(
                modifier = Modifier.wrapContentWidth(),
                shape = if (isFromMe) {
                    MaterialTheme.shapes.medium
                } else {
                    MaterialTheme.shapes.medium
                },
                color = if (isFromMe) {
                    MaterialTheme.colorScheme.primaryContainer
                } else {
                    MaterialTheme.colorScheme.surfaceVariant
                }
            ) {
                Column(
                    modifier = Modifier.padding(12.dp)
                ) {
                    if (message.isRecalled) {
                        Text(
                            text = "消息已撤回",
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    } else {
                        // Handle different message types
                        when (message.type) {
                            "image" -> {
                                ImageMessageContent(message, onImageClick)
                            }
                            "video" -> {
                                FileMessageContent(message, Icons.Default.VideoLibrary)
                            }
                            "audio" -> {
                                FileMessageContent(message, Icons.Default.MusicNote)
                            }
                            "file" -> {
                                FileMessageContent(message, Icons.Default.InsertDriveFile)
                            }
                            else -> {
                                Text(
                                    text = message.content,
                                    style = MaterialTheme.typography.bodyMedium
                                )
                            }
                        }
                    }

                    Text(
                        text = time,
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.align(Alignment.End).padding(top = 4.dp)
                    )
                }
            }
        }
    }
}

/**
 * Image message content with thumbnail preview
 */
@Composable
private fun ImageMessageContent(
    message: MessageEntity,
    onImageClick: (String) -> Unit
) {
    val context = LocalContext.current
    val coroutineScope = rememberCoroutineScope()

    // Parse file info from content
    val fileInfo = remember(message.content) {
        try {
            JSONObject(message.content)
        } catch (e: Exception) {
            null
        }
    }

    val fileId = fileInfo?.optString("fileId") ?: ""
    val fileName = fileInfo?.optString("filename") ?: "图片"
    val fileSize = fileInfo?.optLong("size") ?: 0L

    // Load and display image thumbnail
    val imageUrl = "http://localhost:3000/api/v1/files/$fileId"

    Card(
        modifier = Modifier
            .width(200.dp)
            .height(200.dp)
            .clickable { onImageClick(imageUrl) },
        shape = RoundedCornerShape(8.dp)
    ) {
        AsyncImage(
            model = ImageRequest.Builder(context)
                .data(imageUrl)
                .crossfade(true)
                .build(),
            contentDescription = fileName,
            contentScale = ContentScale.Crop,
            modifier = Modifier.fillMaxSize()
        )
    }

    Text(
        text = "$fileName (${formatFileSize(fileSize)})",
        style = MaterialTheme.typography.labelSmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.padding(top = 4.dp)
    )
}

/**
 * Generic file message content
 */
@Composable
private fun FileMessageContent(
    message: MessageEntity,
    icon: androidx.compose.ui.graphics.vector.ImageVector
) {
    // Parse file info from content
    val fileInfo = remember(message.content) {
        try {
            JSONObject(message.content)
        } catch (e: Exception) {
            null
        }
    }

    val fileName = fileInfo?.optString("filename") ?: "文件"
    val fileSize = fileInfo?.optLong("size") ?: 0L

    Row(
        modifier = Modifier
            .padding(4.dp)
            .clickable { /* Handle file click - download/open */ },
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            modifier = Modifier.size(32.dp),
            tint = MaterialTheme.colorScheme.primary
        )

        Spacer(modifier = Modifier.width(8.dp))

        Column {
            Text(
                text = fileName,
                style = MaterialTheme.typography.bodyMedium,
                maxLines = 1
            )
            Text(
                text = formatFileSize(fileSize),
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

@Composable
private fun TypingIndicator(userCount: Int) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        CircularProgressIndicator(
            modifier = Modifier.size(16.dp),
            strokeWidth = 2.dp,
            color = MaterialTheme.colorScheme.secondary
        )
        Spacer(modifier = Modifier.width(8.dp))
        Text(
            text = if (userCount == 1) "对方正在输入..." else "多人正在输入...",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

/**
 * Message input row with attachment button
 */
@Composable
private fun MessageInputRow(
    messageText: String,
    onMessageTextChange: (String) -> Unit,
    onSendMessage: () -> Unit,
    onPickFile: () -> Unit,
    enabled: Boolean
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(8.dp),
        verticalAlignment = Alignment.Bottom
    ) {
        // Attachment button
        IconButton(
            onClick = onPickFile,
            enabled = enabled
        ) {
            Icon(
                imageVector = Icons.Default.AttachFile,
                contentDescription = "添加附件",
                tint = if (enabled)
                    MaterialTheme.colorScheme.onSurfaceVariant
                else MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f)
            )
        }

        // Message input
        OutlinedTextField(
            value = messageText,
            onValueChange = onMessageTextChange,
            modifier = Modifier
                .weight(1f)
                .imeNestedScroll(),
            placeholder = { Text("输入消息...") },
            maxLines = 4,
            shape = MaterialTheme.shapes.medium
        )

        Spacer(modifier = Modifier.width(8.dp))

        // Send button
        IconButton(
            onClick = onSendMessage,
            enabled = enabled
        ) {
            Icon(
                imageVector = Icons.Default.Send,
                contentDescription = "发送",
                tint = if (enabled)
                    MaterialTheme.colorScheme.primary
                else MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

// Import AsyncImage from Coil
import coil.compose.AsyncImage
