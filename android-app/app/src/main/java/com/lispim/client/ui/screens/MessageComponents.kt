package com.lispim.client.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.unit.dp
import com.lispim.client.model.Message

/**
 * Message content renderer - handles different message types
 */
@Composable
fun MessageContent(
    message: Message,
    isMe: Boolean
) {
    when (message.messageType) {
        "text" -> {
            message.content?.let { content ->
                Text(
                    text = content,
                    style = MaterialTheme.typography.bodyMedium,
                    color = if (isMe) {
                        MaterialTheme.colorScheme.onPrimary
                    } else {
                        MaterialTheme.colorScheme.onSurfaceVariant
                    }
                )
            }
        }
        "image" -> {
            ImageMessageContent(message = message, isMe = isMe)
        }
        "voice" -> {
            VoiceMessageContent(message = message, isMe = isMe)
        }
        "video" -> {
            VideoMessageContent(message = message, isMe = isMe)
        }
        "file" -> {
            FileMessageContent(message = message, isMe = isMe)
        }
        else -> {
            message.content?.let { content ->
                Text(
                    text = content,
                    style = MaterialTheme.typography.bodyMedium,
                    color = if (isMe) {
                        MaterialTheme.colorScheme.onPrimary
                    } else {
                        MaterialTheme.colorScheme.onSurfaceVariant
                    }
                )
            }
        }
    }
}

/**
 * Image message display
 */
@Composable
fun ImageMessageContent(
    message: Message,
    isMe: Boolean
) {
    // TODO: Use Coil or Glide to load image
    Surface(
        modifier = Modifier
            .widthIn(max = 200.dp)
            .heightIn(max = 200.dp),
        shape = RoundedCornerShape(8.dp),
        color = Color.LightGray
    ) {
        Box(
            modifier = Modifier.fillMaxSize(),
            contentAlignment = Alignment.Center
        ) {
            Column(
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Icon(
                    imageVector = Icons.Default.Image,
                    contentDescription = "Image",
                    modifier = Modifier.size(48.dp),
                    tint = Color.DarkGray
                )
                Spacer(modifier = Modifier.height(4.dp))
                Text(
                    text = "[图片]",
                    style = MaterialTheme.typography.bodySmall,
                    color = Color.DarkGray
                )
            }
        }
    }
}

/**
 * Voice message display with duration
 */
@Composable
fun VoiceMessageContent(
    message: Message,
    isMe: Boolean
) {
    Row(
        modifier = Modifier
            .widthIn(max = 160.dp)
            .padding(4.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(
            imageVector = if (isMe) Icons.Default.Mic else Icons.Default.MicExternalOn,
            contentDescription = "Voice",
            tint = if (isMe) {
                MaterialTheme.colorScheme.onPrimary
            } else {
                MaterialTheme.colorScheme.onSurfaceVariant
            },
            modifier = Modifier.size(24.dp)
        )
        Spacer(modifier = Modifier.width(8.dp))
        Text(
            text = "1:23", // TODO: Parse duration from message
            style = MaterialTheme.typography.bodyMedium,
            color = if (isMe) {
                MaterialTheme.colorScheme.onPrimary
            } else {
                MaterialTheme.colorScheme.onSurfaceVariant
            }
        )
    }
}

/**
 * Video message display with thumbnail and duration
 */
@Composable
fun VideoMessageContent(
    message: Message,
    isMe: Boolean
) {
    Surface(
        modifier = Modifier
            .widthIn(max = 200.dp)
            .heightIn(max = 200.dp),
        shape = RoundedCornerShape(8.dp),
        color = Color.DarkGray
    ) {
        Box(
            modifier = Modifier.fillMaxSize(),
            contentAlignment = Alignment.Center
        ) {
            Column(
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Icon(
                    imageVector = Icons.Default.PlayCircle,
                    contentDescription = "Video",
                    modifier = Modifier.size(48.dp),
                    tint = Color.White
                )
                Spacer(modifier = Modifier.height(4.dp))
                Text(
                    text = "[视频]",
                    style = MaterialTheme.typography.bodySmall,
                    color = Color.White
                )
            }
        }
    }
}

/**
 * File message display with filename and size
 */
@Composable
fun FileMessageContent(
    message: Message,
    isMe: Boolean
) {
    Row(
        modifier = Modifier
            .widthIn(max = 200.dp)
            .padding(8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(
            imageVector = Icons.Default.InsertDriveFile,
            contentDescription = "File",
            tint = if (isMe) {
                MaterialTheme.colorScheme.onPrimary
            } else {
                MaterialTheme.colorScheme.onSurfaceVariant
            },
            modifier = Modifier.size(32.dp)
        )
        Spacer(modifier = Modifier.width(12.dp))
        Column {
            Text(
                text = message.content ?: "未知文件",
                style = MaterialTheme.typography.bodyMedium,
                color = if (isMe) {
                    MaterialTheme.colorScheme.onPrimary
                } else {
                    MaterialTheme.colorScheme.onSurfaceVariant
                },
                maxLines = 1
            )
            Text(
                text = "0 KB", // TODO: Parse file size from attachments
                style = MaterialTheme.typography.bodySmall,
                color = if (isMe) {
                    MaterialTheme.colorScheme.onPrimary.copy(alpha = 0.7f)
                } else {
                    MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f)
                }
            )
        }
    }
}
