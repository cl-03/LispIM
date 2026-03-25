package com.lispim.app.ui.viewmodel

import android.net.Uri
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.lispim.app.data.repository.DownloadResult
import com.lispim.app.data.repository.FileRepository
import com.lispim.app.data.repository.FileResult
import com.lispim.app.data.repository.UploadProgress
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.io.File
import javax.inject.Inject

/**
 * File upload state
 */
sealed class FileUploadState {
    object Idle : FileUploadState()
    data class Uploading(val progress: UploadProgress) : FileUploadState()
    data class Success(val fileId: String, val filename: String, val url: String, val size: Long) : FileUploadState()
    data class Error(val message: String) : FileUploadState()
}

/**
 * File download state
 */
sealed class FileDownloadState {
    object Idle : FileDownloadState()
    object Downloading : FileDownloadState()
    data class Success(val file: File, val fileName: String, val mimeType: String?) : FileDownloadState()
    data class Error(val message: String) : FileDownloadState()
}

/**
 * ViewModel for file upload and download operations
 */
@HiltViewModel
class FileUploadViewModel @Inject constructor(
    private val fileRepository: FileRepository
) : ViewModel() {

    private val _uploadState = MutableStateFlow<FileUploadState>(FileUploadState.Idle)
    val uploadState: StateFlow<FileUploadState> = _uploadState.asStateFlow()

    private val _downloadState = MutableStateFlow<FileDownloadState>(FileDownloadState.Idle)
    val downloadState: StateFlow<FileDownloadState> = _downloadState.asStateFlow()

    /**
     * Upload file
     */
    fun uploadFile(uri: Uri, authToken: String) {
        viewModelScope.launch {
            _uploadState.value = FileUploadState.Uploading(
                UploadProgress(fileId = "", uploaded = 0, total = 0)
            )

            fileRepository.uploadFile(uri, authToken).collect { result ->
                when (result) {
                    is FileResult.Success -> {
                        _uploadState.value = FileUploadState.Success(
                            fileId = result.uploadResponse.fileId,
                            filename = result.uploadResponse.filename,
                            url = result.uploadResponse.url,
                            size = result.uploadResponse.size
                        )
                    }
                    is FileResult.Error -> {
                        _uploadState.value = FileUploadState.Error(result.message)
                    }
                }
            }
        }
    }

    /**
     * Download file
     */
    fun downloadFile(fileId: String, authToken: String) {
        viewModelScope.launch {
            _downloadState.value = FileDownloadState.Downloading

            fileRepository.downloadFile(fileId, authToken).collect { result ->
                when (result) {
                    is DownloadResult.Success -> {
                        _downloadState.value = FileDownloadState.Success(
                            file = result.file,
                            fileName = result.fileName,
                            mimeType = result.mimeType
                        )
                    }
                    is DownloadResult.Error -> {
                        _downloadState.value = FileDownloadState.Error(result.message)
                    }
                }
            }
        }
    }

    /**
     * Reset upload state
     */
    fun resetUploadState() {
        _uploadState.value = FileUploadState.Idle
    }

    /**
     * Reset download state
     */
    fun resetDownloadState() {
        _downloadState.value = FileDownloadState.Idle
    }

    /**
     * Clear file cache
     */
    fun clearCache() {
        fileRepository.clearCache()
    }
}
