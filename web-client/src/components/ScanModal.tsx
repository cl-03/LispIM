import React, { useState, useRef, useEffect } from 'react'
import { getApiClient } from '@/utils/api-client'

interface ScanModalProps {
  onClose: () => void
}

const ScanModal: React.FC<ScanModalProps> = ({ onClose }) => {
  const videoRef = useRef<HTMLVideoElement>(null)
  const fileInputRef = useRef<HTMLInputElement>(null)
  const [manualInput, setManualInput] = useState('')
  const [isScanning, setIsScanning] = useState(false)
  const [scanStatus, setScanStatus] = useState<'idle' | 'scanning' | 'success' | 'error'>('idle')
  const [resultData, setResultData] = useState<any>(null)
  const [uploading, setUploading] = useState(false)

  const handleScan = async () => {
    if (!manualInput.trim()) {
      return
    }

    setScanStatus('scanning')
    try {
      const api = getApiClient()
      const response = await api.post('/api/v1/qr/scan', {
        qrJson: manualInput
      })

      if (response.success && response.data) {
        setScanStatus('success')
        setResultData(response.data)
      } else {
        setScanStatus('error')
      }
    } catch (error) {
      console.error('Scan error:', error)
      setScanStatus('error')
    }
  }

  const handleAddFriend = async () => {
    if (!resultData?.user?.id) return

    setUploading(true) // 复用 uploading 状态表示加载中
    try {
      const api = getApiClient()
      const response = await api.sendFriendRequest(resultData.user.id, '您好，我扫了您的二维码')

      if (response.success) {
        // 显示成功提示
        const successDiv = document.createElement('div')
        successDiv.className = 'fixed top-20 left-1/2 transform -translate-x-1/2 bg-gradient-to-r from-green-500 to-emerald-600 text-white px-6 py-4 rounded-2xl shadow-[0_10px_40px_rgba(16,185,129,0.4)] z-[100] animate-scale-up border border-green-400/30 backdrop-blur-xl flex items-center gap-3'
        successDiv.innerHTML = `
          <svg class="w-6 h-6" fill="currentColor" viewBox="0 0 20 20">
            <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clip-rule="evenodd"/>
          </svg>
          <span class="font-medium">好友请求已发送</span>
        `
        document.body.appendChild(successDiv)

        // 2 秒后移除提示
        setTimeout(() => {
          successDiv.style.opacity = '0'
          successDiv.style.transition = 'opacity 0.3s ease'
          setTimeout(() => successDiv.remove(), 300)
        }, 2000)

        // 关闭弹窗
        setTimeout(() => onClose(), 500)
      } else {
        // 显示错误提示
        const errorDiv = document.createElement('div')
        errorDiv.className = 'fixed top-20 left-1/2 transform -translate-x-1/2 bg-gradient-to-r from-red-500 to-rose-600 text-white px-6 py-4 rounded-2xl shadow-[0_10px_40px_rgba(239,68,68,0.4)] z-[100] animate-scale-up border border-red-400/30 backdrop-blur-xl flex items-center gap-3'
        errorDiv.innerHTML = `
          <svg class="w-6 h-6" fill="currentColor" viewBox="0 0 20 20">
            <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z" clip-rule="evenodd"/>
          </svg>
          <span class="font-medium">${response.message || '发送失败，请稍后重试'}</span>
        `
        document.body.appendChild(errorDiv)

        setTimeout(() => {
          errorDiv.style.opacity = '0'
          errorDiv.style.transition = 'opacity 0.3s ease'
          setTimeout(() => errorDiv.remove(), 300)
        }, 3000)
      }
    } catch (error: any) {
      console.error('Add friend error:', error)
      // 显示错误提示
      const errorDiv = document.createElement('div')
      errorDiv.className = 'fixed top-20 left-1/2 transform -translate-x-1/2 bg-gradient-to-r from-red-500 to-rose-600 text-white px-6 py-4 rounded-2xl shadow-[0_10px_40px_rgba(239,68,68,0.4)] z-[100] animate-scale-up border border-red-400/30 backdrop-blur-xl flex items-center gap-3'
      errorDiv.innerHTML = `
        <svg class="w-6 h-6" fill="currentColor" viewBox="0 0 20 20">
          <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z" clip-rule="evenodd"/>
        </svg>
        <span class="font-medium">${error?.message || '发送好友请求失败'}</span>
      `
      document.body.appendChild(errorDiv)

      setTimeout(() => {
        errorDiv.style.opacity = '0'
        errorDiv.style.transition = 'opacity 0.3s ease'
        setTimeout(() => errorDiv.remove(), 300)
      }, 3000)
    } finally {
      setUploading(false)
    }
  }

  const startCamera = async () => {
    try {
      const stream = await navigator.mediaDevices.getUserMedia({
        video: { facingMode: 'environment' } // 使用后置摄像头
      })
      if (videoRef.current) {
        videoRef.current.srcObject = stream
        setIsScanning(true)
        setScanStatus('scanning')
      }
    } catch (error) {
      console.error('Camera error:', error)
      alert('无法访问摄像头，请手动输入二维码内容或上传图片')
    }
  }

  const stopCamera = () => {
    if (videoRef.current?.srcObject) {
      const stream = videoRef.current.srcObject as MediaStream
      stream.getTracks().forEach(track => track.stop())
      setIsScanning(false)
    }
  }

  // 处理图片上传
  const handleImageUpload = async (event: React.ChangeEvent<HTMLInputElement>) => {
    const file = event.target.files?.[0]
    if (!file) return

    // 验证文件类型
    if (!file.type.startsWith('image/')) {
      alert('请上传图片文件')
      return
    }

    setUploading(true)
    setScanStatus('scanning')

    try {
      const api = getApiClient()

      // 使用现有的 uploadFile 方法上传图片
      const uploadResponse = await api.uploadFile(file, file.name)

      if (uploadResponse.success && uploadResponse.data) {
        const imageUrl = uploadResponse.data.url

        // 调用后端 API 识别二维码
        const scanResponse = await api.post('/api/v1/qr/scan-image', {
          imageUrl
        })

        if (scanResponse.success && scanResponse.data) {
          setScanStatus('success')
          setResultData(scanResponse.data)
        } else {
          setScanStatus('error')
          alert('无法识别二维码，请检查图片是否正确')
        }
      } else {
        setScanStatus('error')
        alert('图片上传失败')
      }
    } catch (error) {
      console.error('Upload/Scan error:', error)
      setScanStatus('error')
      alert('识别失败，请重试')
    } finally {
      setUploading(false)
      // 清空 input，允许重复上传同一文件
      if (fileInputRef.current) {
        fileInputRef.current.value = ''
      }
    }
  }

  const triggerFileUpload = () => {
    fileInputRef.current?.click()
  }

  useEffect(() => {
    startCamera()
    return () => stopCamera()
  }, [])

  return (
    <div className="fixed inset-0 bg-black bg-opacity-90 flex items-center justify-center z-50">
      <div className="bg-gray-800 rounded-xl p-6 max-w-sm w-full mx-4 border border-gray-700">
        {/* Header */}
        <div className="flex items-center justify-between mb-4">
          <h2 className="text-xl font-semibold text-white">扫一扫</h2>
          <button onClick={onClose} className="text-gray-400 hover:text-white">
            <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>

        {/* Camera View */}
        <div className="relative aspect-square bg-gray-900 rounded-lg mb-4 overflow-hidden">
          {isScanning ? (
            <>
              <video
                ref={videoRef}
                autoPlay
                playsInline
                muted
                className="w-full h-full object-cover"
              />
              {/* Scan Frame Overlay */}
              <div className="absolute inset-0 flex items-center justify-center">
                <div className="w-48 h-48 border-2 border-blue-500 rounded-lg">
                  <div className="absolute top-0 left-0 w-4 h-4 border-t-4 border-l-4 border-blue-500 -mt-0.5 -ml-0.5" />
                  <div className="absolute top-0 right-0 w-4 h-4 border-t-4 border-r-4 border-blue-500 -mt-0.5 -mr-0.5" />
                  <div className="absolute bottom-0 left-0 w-4 h-4 border-b-4 border-l-4 border-blue-500 -mb-0.5 -ml-0.5" />
                  <div className="absolute bottom-0 right-0 w-4 h-4 border-b-4 border-r-4 border-blue-500 -mb-0.5 -mr-0.5" />
                </div>
              </div>
              {/* Scan Line Animation */}
              <div className="absolute left-8 right-8 h-0.5 bg-gradient-to-r from-transparent via-blue-500 to-transparent animate-scan" />
            </>
          ) : (
            <div className="w-full h-full flex items-center justify-center text-gray-500">
              <svg className="w-16 h-16" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M3 9a2 2 0 012-2h.93a2 2 0 001.664-.89l.812-1.22A2 2 0 0110.07 4h3.86a2 2 0 011.664.89l.812 1.22A2 2 0 0018.07 7H19a2 2 0 012 2v9a2 2 0 01-2 2H5a2 2 0 01-2-2V9z" />
              </svg>
            </div>
          )}
        </div>

        {/* Status Messages */}
        {scanStatus === 'success' && resultData && (
          <div className="mb-4 p-4 bg-green-900/30 border border-green-700 rounded-lg">
            <div className="flex items-center gap-3">
              <div className="w-12 h-12 rounded-full bg-blue-500 flex items-center justify-center text-white text-xl font-medium">
                {resultData.user?.avatar ? (
                  <img src={resultData.user.avatar} alt={resultData.user.displayName} className="w-12 h-12 rounded-full object-cover" />
                ) : (
                  (resultData.user?.displayName || resultData.user?.username || '?').charAt(0).toUpperCase()
                )}
              </div>
              <div>
                <div className="text-white font-medium">{resultData.user?.displayName || resultData.user?.username}</div>
                <div className="text-gray-400 text-sm">@{resultData.user?.username}</div>
              </div>
            </div>
          </div>
        )}

        {scanStatus === 'error' && (
          <div className="mb-4 p-3 bg-red-900/30 border border-red-700 rounded-lg text-red-400 text-center">
            无效的二维码或已过期
          </div>
        )}

        {uploading && (
          <div className="mb-4 p-3 bg-blue-900/30 border border-blue-700 rounded-lg text-blue-400 text-center flex items-center justify-center gap-2">
            <svg className="animate-spin h-5 w-5" viewBox="0 0 24 24">
              <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" fill="none" />
              <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z" />
            </svg>
            正在识别二维码...
          </div>
        )}

        {/* Manual Input */}
        <div className="mb-4">
          <input
            type="text"
            value={manualInput}
            onChange={(e) => setManualInput(e.target.value)}
            placeholder="或手动输入二维码内容"
            className="w-full px-4 py-2 bg-gray-700 border border-gray-600 rounded-lg text-white placeholder-gray-400 focus:outline-none focus:border-blue-500"
          />
        </div>

        {/* Action Buttons */}
        <div className="flex gap-3 mb-4">
          {scanStatus === 'success' ? (
            <>
              <button
                onClick={handleAddFriend}
                className="flex-1 py-3 bg-blue-500 text-white rounded-lg hover:bg-blue-600 font-medium"
              >
                添加为好友
              </button>
              <button
                onClick={onClose}
                className="px-6 py-3 bg-gray-700 text-white rounded-lg hover:bg-gray-600 font-medium"
              >
                关闭
              </button>
            </>
          ) : (
            <>
              <button
                onClick={handleScan}
                disabled={!manualInput.trim()}
                className="flex-1 py-3 bg-blue-500 text-white rounded-lg hover:bg-blue-600 font-medium disabled:opacity-50 disabled:cursor-not-allowed"
              >
                扫描
              </button>
              <button
                onClick={triggerFileUpload}
                disabled={uploading}
                className="flex-1 py-3 bg-gray-700 text-white rounded-lg hover:bg-gray-600 font-medium disabled:opacity-50 disabled:cursor-not-allowed flex items-center justify-center gap-2"
              >
                <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z" />
                </svg>
                相册
              </button>
              <button
                onClick={onClose}
                className="px-6 py-3 bg-gray-600 text-white rounded-lg hover:bg-gray-500 font-medium"
              >
                取消
              </button>
            </>
          )}
        </div>

        {/* Hidden File Input */}
        <input
          ref={fileInputRef}
          type="file"
          accept="image/*"
          capture="environment"
          onChange={handleImageUpload}
          className="hidden"
        />

        {/* Tips */}
        <div className="mt-4 text-center text-gray-500 text-sm">
          将二维码放入框内即可自动扫描，或从相册选择图片
        </div>
      </div>

      <style>{`
        @keyframes scan {
          0% { top: 2rem; }
          50% { top: calc(100% - 2rem); }
          100% { top: 2rem; }
        }
        .animate-scan {
          animation: scan 2s ease-in-out infinite;
        }
      `}</style>
    </div>
  )
}

export default ScanModal
