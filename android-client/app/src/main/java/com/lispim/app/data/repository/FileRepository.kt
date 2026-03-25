package com.lispim.app.data.repository

import android.content.Context
import android.net.Uri
import android.util.Log
import com.lispim.app.data.api.LispIMApiService
import com.lispim.app.data.model.UploadResponse
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOn
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.MultipartBody
import okhttp3.RequestBody.Companion.asRequestBody
import java.io.File
import java.io.FileOutputStream
import javax.inject.Inject
import javax.inject.Singleton

/**
 * File upload/download result
 */
sealed class FileResult {
    data class Success(val uploadResponse: UploadResponse) : FileResult()
    data class Error(val message: String, val exception: Exception? = null) : FileResult()
}

/**
 * File download result
 */
sealed class DownloadResult {
    data class Success(val file: File, val mimeType: String?, val fileName: String) : DownloadResult()
    data class Error(val message: String, val exception: Exception? = null) : DownloadResult()
}

/**
 * Upload progress state
 */
data class UploadProgress(
    val fileId: String,
    val uploaded: Long,
    val total: Long,
    val percent: Float = (uploaded.toFloat() / total.toFloat()) * 100
)

/**
 * Repository for file upload and download operations
 */
@Singleton
class FileRepository @Inject constructor(
    private val apiService: LispIMApiService,
    @ApplicationContext private val context: Context
) {

    companion object {
        private const val TAG = "FileRepository"
        private const val CACHE_DIR = "file_cache"
    }

    /**
     * Upload file to server
     * @param uri File URI to upload
     * @param authToken User authentication token
     */
    fun uploadFile(uri: Uri, authToken: String): Flow<FileResult> = flow {
        try {
            emit(FileResult.Success(uploadFileInternal(uri, authToken)))
        } catch (e: Exception) {
            Log.e(TAG, "Upload file error", e)
            emit(FileResult.Error("Upload failed: ${e.message}", e))
        }
    }.flowOn(Dispatchers.IO)

    private suspend fun uploadFileInternal(uri: Uri, authToken: String): UploadResponse {
        // Get file from URI
        val file = getFileFromUri(uri)

        // Create request body
        val mimeType = context.contentResolver.getType(uri) ?: "application/octet-stream"
        val requestBody = file.asRequestBody(mimeType.toMediaTypeOrNull())

        // Create multipart part
        val filePart = MultipartBody.Part.createFormData(
            "file",
            file.name,
            requestBody
        )

        // Upload
        val response = apiService.uploadFile("Bearer $authToken", filePart)

        if (response.isSuccessful && response.body() != null) {
            val body = response.body()!!
            if (body.success) {
                body.data?.let {
                    Log.i(TAG, "File uploaded: ${it.fileId}, ${it.filename}, ${it.size} bytes")
                    return it
                }
            }
            throw Exception(body.error?.message ?: "Upload failed")
        } else {
            throw Exception("Upload failed: ${response.code()} ${response.message()}")
        }
    }

    /**
     * Download file from server
     * @param fileId File ID to download
     * @param authToken User authentication token
     */
    fun downloadFile(fileId: String, authToken: String): Flow<DownloadResult> = flow {
        try {
            emit(downloadFileInternal(fileId, authToken))
        } catch (e: Exception) {
            Log.e(TAG, "Download file error", e)
            emit(DownloadResult.Error("Download failed: ${e.message}", e))
        }
    }.flowOn(Dispatchers.IO)

    private suspend fun downloadFileInternal(fileId: String, authToken: String): DownloadResult {
        val response = apiService.getFile("Bearer $authToken", fileId)

        if (response.isSuccessful && response.body() != null) {
            val body = response.body()!!

            // Get content type and filename from headers
            val contentType = response.headers()["Content-Type"]
            val disposition = response.headers()["Content-Disposition"]
            val fileName = extractFileNameFromDisposition(disposition) ?: "file_$fileId"

            // Save to cache
            val cacheFile = File(getCacheDir(), fileName)
            FileOutputStream(cacheFile).use { output ->
                body.byteStream().use { input ->
                    input.copyTo(output)
                }
            }

            Log.i(TAG, "File downloaded: $fileName, ${cacheFile.length()} bytes")
            return DownloadResult.Success(cacheFile, contentType, fileName)
        } else {
            throw Exception("Download failed: ${response.code()} ${response.message()}")
        }
    }

    /**
     * Get file from URI and copy to cache
     */
    private fun getFileFromUri(uri: Uri): File {
        val fileName = getFileNameFromUri(uri)
        val cacheFile = File(getCacheDir(), fileName)

        context.contentResolver.openInputStream(uri)?.use { input ->
            FileOutputStream(cacheFile).use { output ->
                input.copyTo(output)
            }
        }

        return cacheFile
    }

    /**
     * Extract filename from Content-Disposition header
     */
    private fun extractFileNameFromDisposition(disposition: String?): String? {
        if (disposition.isNullOrBlank()) return null

        val pattern = "filename\\*=UTF-8''(.+)|filename=\"(.+?)\"|filename=(.+)".toRegex()
        return pattern.find(disposition)?.groupValues?.let { matches ->
            matches.firstOrNull { it.isNotBlank() }?.trim('"')
        }
    }

    /**
     * Get filename from URI
     */
    private fun getFileNameFromUri(uri: Uri): String {
        context.contentResolver.query(uri, null, null, null, null)?.use { cursor ->
            val nameIndex = cursor.getColumnIndex(android.provider.OpenableColumns.DISPLAY_NAME)
            if (cursor.moveToFirst() && nameIndex >= 0) {
                return cursor.getString(nameIndex)
            }
        }
        return "file_${System.currentTimeMillis()}"
    }

    /**
     * Get cache directory for files
     */
    private fun getCacheDir(): File {
        val dir = File(context.cacheDir, CACHE_DIR)
        if (!dir.exists()) {
            dir.mkdirs()
        }
        return dir
    }

    /**
     * Clear file cache
     */
    fun clearCache() {
        val cacheDir = getCacheDir()
        cacheDir.deleteRecursively()
        cacheDir.mkdirs()
        Log.i(TAG, "File cache cleared")
    }

    /**
     * Get cached file by ID
     */
    fun getCachedFile(fileId: String): File? {
        // This is a simplified implementation
        // In production, you'd maintain a mapping of fileId -> cached file
        return null
    }
}
