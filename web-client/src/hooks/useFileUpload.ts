/**
 * useFileUpload - Hook for chunked file upload
 * Supports large file upload with progress tracking and resume capability
 */

import { useState, useCallback } from 'react'
import { getApiClient } from '@/utils/api-client'

export interface UploadProgress {
  uploadedChunks: number
  totalChunks: number
  progress: number // 0-100
  uploadedBytes: number
  totalBytes: number
  speed?: number // bytes per second
  eta?: number // estimated time in seconds
}

export interface UploadState {
  isUploading: boolean
  isPaused: boolean
  isCompleted: boolean
  isError: boolean
  progress: UploadProgress
  fileId?: string
  downloadUrl?: string
  error?: string
}

const DEFAULT_CHUNK_SIZE = 1024 * 1024 // 1MB default chunk size
const MAX_CONCURRENT_CHUNKS = 4 // 最大并发上传分块数（优化提高上传速度）
const CHUNK_RETRY_LIMIT = 3 // 分块重试次数上限

export function useFileUpload() {
  const [state, setState] = useState<UploadState>({
    isUploading: false,
    isPaused: false,
    isCompleted: false,
    isError: false,
    progress: {
      uploadedChunks: 0,
      totalChunks: 0,
      progress: 0,
      uploadedBytes: 0,
      totalBytes: 0
    }
  })

  const [uploadSpeeds, setUploadSpeeds] = useState<number[]>([])

  const calculateSpeed = useCallback((uploadedBytes: number, elapsedMs: number) => {
    if (elapsedMs <= 0) return 0
    return uploadedBytes / (elapsedMs / 1000)
  }, [])

  const calculateETA = useCallback((remainingBytes: number, speed: number) => {
    if (speed <= 0) return Infinity
    return remainingBytes / speed
  }, [])

  const reset = useCallback(() => {
    setState({
      isUploading: false,
      isPaused: false,
      isCompleted: false,
      isError: false,
      progress: {
        uploadedChunks: 0,
        totalChunks: 0,
        progress: 0,
        uploadedBytes: 0,
        totalBytes: 0
      }
    })
    setUploadSpeeds([])
  }, [])

  const uploadFile = useCallback(async (
    file: File,
    options?: {
      chunkSize?: number
      onProgress?: (progress: UploadProgress) => void
      onComplete?: (fileId: string, downloadUrl: string) => void
      onError?: (error: string) => void
    }
  ): Promise<{ fileId: string; downloadUrl: string } | null> => {
    const apiClient = getApiClient()
    const chunkSize = options?.chunkSize || DEFAULT_CHUNK_SIZE
    const totalChunks = Math.ceil(file.size / chunkSize)

    const startTime = Date.now()

    setState(prev => ({
      ...prev,
      isUploading: true,
      isPaused: false,
      isCompleted: false,
      isError: false,
      progress: {
        uploadedChunks: 0,
        totalChunks,
        progress: 0,
        uploadedBytes: 0,
        totalBytes: file.size
      }
    }))

    setUploadSpeeds([])

    try {
      // Step 1: Initialize file transfer
      const initResponse = await apiClient.initFileUpload({
        filename: file.name,
        fileSize: file.size,
        fileType: file.type || 'application/octet-stream',
        chunkSize
      })

      if (!initResponse.success || !initResponse.data) {
        throw new Error(initResponse.message || 'Failed to initialize upload')
      }

      const { fileId, totalChunks: serverTotalChunks } = initResponse.data
      const actualTotalChunks = serverTotalChunks || totalChunks

      setState(prev => ({
        ...prev,
        fileId,
        progress: {
          ...prev.progress,
          totalChunks: actualTotalChunks
        }
      }))

      // Step 2: Upload chunks with concurrency control（优化：并发上传分块）
      const uploadedChunks = new Set<number>()
      const chunkQueue: number[] = Array.from({ length: actualTotalChunks }, (_, i) => i)
      let activeChunkUploads = 0

      const uploadChunk = async (chunkIndex: number): Promise<boolean> => {
        let retries = 0

        while (retries < CHUNK_RETRY_LIMIT) {
          try {
            const start = chunkIndex * chunkSize
            const end = Math.min(start + chunkSize, file.size)
            const chunk = file.slice(start, end)

            // Convert chunk to base64
            const chunkData = await new Promise<string>((resolve, reject) => {
              const reader = new FileReader()
              reader.onload = () => {
                const arrayBuffer = reader.result as ArrayBuffer
                const base64 = btoa(
                  new Uint8Array(arrayBuffer)
                    .reduce((data, byte) => data + String.fromCharCode(byte), '')
                )
                resolve(base64)
              }
              reader.onerror = reject
              reader.readAsArrayBuffer(chunk)
            })

            const chunkUploadStart = Date.now()
            const chunkResponse = await apiClient.uploadChunk({
              fileId,
              chunkIndex,
              chunkData
            })

            if (!chunkResponse.success) {
              throw new Error(chunkResponse.message || `Failed to upload chunk ${chunkIndex}`)
            }

            // Calculate speed
            const chunkUploadEnd = Date.now()
            const chunkDuration = chunkUploadEnd - chunkUploadStart
            const speed = calculateSpeed(chunk.size, chunkDuration)
            setUploadSpeeds(prev => [...prev.slice(-9), speed])

            uploadedChunks.add(chunkIndex)

            const uploadedBytes = Array.from(uploadedChunks)
              .reduce((sum, idx) => sum + Math.min(chunkSize, file.size - idx * chunkSize), 0)
            const remainingBytes = file.size - uploadedBytes
            const avgSpeed = uploadSpeeds.length > 0
              ? uploadSpeeds.reduce((a, b) => a + b, 0) / uploadSpeeds.length
              : speed

            const progress: UploadProgress = {
              uploadedChunks: uploadedChunks.size,
              totalChunks: actualTotalChunks,
              progress: Math.round((uploadedChunks.size / actualTotalChunks) * 100),
              uploadedBytes,
              totalBytes: file.size,
              speed: avgSpeed,
              eta: calculateETA(remainingBytes, avgSpeed)
            }

            setState(prev => ({
              ...prev,
              progress
            }))

            options?.onProgress?.(progress)

            return true
          } catch (error) {
            retries++
            if (retries >= CHUNK_RETRY_LIMIT) {
              console.error(`Chunk ${chunkIndex} failed after ${retries} retries`)
              return false
            }
            // 指数退避等待
            await new Promise(resolve => setTimeout(resolve, Math.pow(2, retries) * 100))
          }
        }
        return false
      }

      const processQueue = async (): Promise<void> => {
        while (chunkQueue.length > 0 && !state.isPaused) {
          if (activeChunkUploads >= MAX_CONCURRENT_CHUNKS) {
            await new Promise(resolve => setTimeout(resolve, 50))
            continue
          }

          const chunkIndex = chunkQueue.shift()!
          if (uploadedChunks.has(chunkIndex)) continue

          activeChunkUploads++

          uploadChunk(chunkIndex).then(() => {
            activeChunkUploads--
          }).catch(() => {
            activeChunkUploads--
          })
        }
      }

      await processQueue()

      // Wait for all chunks to complete
      while (uploadedChunks.size < actualTotalChunks) {
        await new Promise(resolve => setTimeout(resolve, 50))
      }

      // Step 3: Complete upload
      const completeResponse = await apiClient.completeFileUpload({
        fileId: fileId!
      })

      if (!completeResponse.success || !completeResponse.data) {
        throw new Error(completeResponse.message || 'Failed to complete upload')
      }

      const { downloadUrl } = completeResponse.data

      const totalTime = (Date.now() - startTime) / 1000
      console.log(`[FileUpload] Completed in ${totalTime.toFixed(2)}s, avg speed: ${(file.size / totalTime / 1024 / 1024).toFixed(2)} MB/s`)

      setState(prev => ({
        ...prev,
        isUploading: false,
        isCompleted: true,
        progress: {
          ...prev.progress,
          progress: 100
        },
        downloadUrl
      }))

      options?.onComplete?.(fileId, downloadUrl)

      return { fileId, downloadUrl }
    } catch (error) {
      const errorMessage = error instanceof Error
        ? error.message
        : 'Upload failed'

      setState(prev => ({
        ...prev,
        isUploading: false,
        isError: true,
        error: errorMessage
      }))

      options?.onError?.(errorMessage)
      return null
    }
  }, [calculateETA, calculateSpeed, state.isPaused, uploadSpeeds])

  const pause = useCallback(() => {
    setState(prev => ({ ...prev, isPaused: true }))
  }, [])

  const resume = useCallback(() => {
    setState(prev => ({ ...prev, isPaused: false }))
  }, [])

  const cancel = useCallback(() => {
    setState({
      isUploading: false,
      isPaused: false,
      isCompleted: false,
      isError: false,
      progress: {
        uploadedChunks: 0,
        totalChunks: 0,
        progress: 0,
        uploadedBytes: 0,
        totalBytes: 0
      }
    })
    setUploadSpeeds([])
  }, [])

  return {
    ...state,
    uploadFile,
    pause,
    resume,
    cancel,
    reset
  }
}

export default useFileUpload
