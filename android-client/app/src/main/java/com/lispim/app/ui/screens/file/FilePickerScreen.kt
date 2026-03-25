package com.lispim.app.ui.screens.file

import android.Manifest
import android.content.pm.PackageManager
import android.net.Uri
import android.util.Log
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.hilt.navigation.compose.hiltViewModel
import coil.compose.AsyncImage
import com.lispim.app.ui.viewmodel.FileUploadState
import com.lispim.app.ui.viewmodel.FileUploadViewModel
import java.io.File

/**
 * File type enum
 */
enum class FileType {
    IMAGE, VIDEO, AUDIO, DOCUMENT, OTHER
}

/**
 * File info data class
 */
data class FileInfo(
    val uri: Uri,
    val name: String,
    val size: Long,
    val type: FileType,
    val mimeType: String
)

/**
 * File picker and upload screen
 */
@Composable
fun FilePickerScreen(
    authToken: String,
    onFileSelected: (String, String, Long) -> Unit, // fileId, filename, size
    onNavigateBack: () -> Unit,
    viewModel: FileUploadViewModel = hiltViewModel()
) {
    val uploadState by viewModel.uploadState.collectAsState()
    val context = LocalContext.current

    // Handle upload result
    LaunchedEffect(uploadState) {
        when (val state = uploadState) {
            is FileUploadState.Success -> {
                onFileSelected(state.fileId, state.filename, state.size)
                viewModel.resetUploadState()
            }
            is FileUploadState.Error -> {
                // Show error
                viewModel.resetUploadState()
            }
            else -> {}
        }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(16.dp)
    ) {
        // Header
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            IconButton(onClick = onNavigateBack) {
                Icon(Icons.Default.ArrowBack, contentDescription = "Back")
            }
            Text(
                text = "Select File",
                style = MaterialTheme.typography.headlineSmall
            )
            Spacer(modifier = Modifier.width(48.dp))
        }

        Spacer(modifier = Modifier.height(16.dp))

        // File type filter chips
        FileFilterRow()

        Spacer(modifier = Modifier.height(16.dp))

        // File grid
        FileGrid(
            onFileSelected = { fileInfo ->
                // Upload the file
                viewModel.uploadFile(fileInfo.uri, authToken)
            }
        )

        // Upload progress
        when (val state = uploadState) {
            is FileUploadState.Uploading -> {
                Spacer(modifier = Modifier.height(16.dp))
                LinearProgressIndicator(
                    modifier = Modifier.fillMaxWidth()
                )
                Text(
                    text = "Uploading... ${state.progress.percent.toInt()}%",
                    style = MaterialTheme.typography.bodySmall,
                    modifier = Modifier.padding(top = 4.dp)
                )
            }
            is FileUploadState.Error -> {
                Spacer(modifier = Modifier.height(16.dp))
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    colors = CardDefaults.cardColors(
                        containerColor = MaterialTheme.colorScheme.errorContainer
                    )
                ) {
                    Text(
                        text = "Upload failed: ${state.message}",
                        modifier = Modifier.padding(16.dp),
                        style = MaterialTheme.typography.bodyMedium
                    )
                }
            }
            else -> {}
        }
    }
}

/**
 * File type filter chips row
 */
@Composable
fun FileFilterRow() {
    val fileTypes = listOf("All", "Images", "Videos", "Docs", "Audio")
    var selectedType by remember { mutableStateOf("All") }

    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        fileTypes.forEach { type ->
            FilterChip(
                selected = selectedType == type,
                onClick = { selectedType = type },
                label = { Text(type) }
            )
        }
    }
}

/**
 * File grid for browsing files
 * Note: This is a simplified version. Full implementation would require
 * actual file system access which requires additional permissions.
 */
@Composable
fun FileGrid(
    onFileSelected: (FileInfo) -> Unit
) {
    // Placeholder files for demonstration
    // In production, this would query the actual file system
    val placeholderFiles = remember { emptyList<FileInfo>() }

    if (placeholderFiles.isEmpty()) {
        Box(
            modifier = Modifier.fillMaxSize(),
            contentAlignment = Alignment.Center
        ) {
            Column(
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Icon(
                    Icons.Default.FolderOpen,
                    contentDescription = null,
                    modifier = Modifier.size(64.dp),
                    tint = Color.Gray
                )
                Spacer(modifier = Modifier.height(8.dp))
                Text(
                    text = "Tap below to select a file",
                    style = MaterialTheme.typography.bodyMedium,
                    color = Color.Gray
                )
            }
        }
    } else {
        LazyVerticalGrid(
            columns = GridCells.Fixed(3),
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(8.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            items(placeholderFiles) { file ->
                FileItem(file = file, onClick = { onFileSelected(file) })
            }
        }
    }
}

/**
 * Single file item composable
 */
@Composable
fun FileItem(
    file: FileInfo,
    onClick: () -> Unit
) {
    Card(
        modifier = Modifier
            .aspectRatio(1f)
            .clickable(onClick = onClick),
        shape = RoundedCornerShape(8.dp)
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(8.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            // File icon or thumbnail
            Box(
                modifier = Modifier
                    .size(48.dp)
                    .clip(RoundedCornerShape(4.dp))
                    .background(MaterialTheme.colorScheme.surfaceVariant),
                contentAlignment = Alignment.Center
            ) {
                when (file.type) {
                    FileType.IMAGE -> {
                        // For images, show thumbnail
                        AsyncImage(
                            model = file.uri,
                            contentDescription = file.name,
                            modifier = Modifier.fillMaxSize()
                        )
                    }
                    FileType.VIDEO -> {
                        Icon(Icons.Default.VideoLibrary, contentDescription = null)
                    }
                    FileType.AUDIO -> {
                        Icon(Icons.Default.MusicNote, contentDescription = null)
                    }
                    FileType.DOCUMENT -> {
                        Icon(Icons.Default.Description, contentDescription = null)
                    }
                    else -> {
                        Icon(Icons.Default.InsertDriveFile, contentDescription = null)
                    }
                }
            }

            Spacer(modifier = Modifier.height(4.dp))

            // File name
            Text(
                text = file.name,
                style = MaterialTheme.typography.labelMedium,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.widthIn(max = 100.dp)
            )

            // File size
            Text(
                text = formatFileSize(file.size),
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

/**
 * Format file size for display
 */
fun formatFileSize(bytes: Long): String {
    return when {
        bytes < 1024 -> "$bytes B"
        bytes < 1024 * 1024 -> "${bytes / 1024} KB"
        bytes < 1024 * 1024 * 1024 -> "${bytes / (1024 * 1024)} MB"
        else -> "${bytes / (1024 * 1024 * 1024)} GB"
    }
}

/**
 * Get file type from MIME type
 */
fun getFileTypeFromMimeType(mimeType: String): FileType {
    return when {
        mimeType.startsWith("image/") -> FileType.IMAGE
        mimeType.startsWith("video/") -> FileType.VIDEO
        mimeType.startsWith("audio/") -> FileType.AUDIO
        mimeType.startsWith("application/") || mimeType == "text/plain" -> FileType.DOCUMENT
        else -> FileType.OTHER
    }
}

/**
 * Get icon for file type
 */
fun getFileIcon(fileType: FileType): ImageVector {
    return when (fileType) {
        FileType.IMAGE -> Icons.Default.Image
        FileType.VIDEO -> Icons.Default.VideoLibrary
        FileType.AUDIO -> Icons.Default.MusicNote
        FileType.DOCUMENT -> Icons.Default.Description
        FileType.OTHER -> Icons.Default.InsertDriveFile
    }
}
