import React, { useState, useEffect, useRef } from 'react'
import { getApiClient } from '@/utils/api-client'

interface CallModalProps {
  isOpen: boolean
  onClose: () => void
  calleeId: string
  calleeName: string
  callType?: 'voice' | 'video'
  onCallStart?: (callId: string) => void
}

const CallModal: React.FC<CallModalProps> = ({
  isOpen,
  onClose,
  calleeId,
  calleeName,
  callType = 'voice',
  onCallStart
}) => {
  const api = getApiClient()
  const [callStatus, setCallStatus] = useState<'calling' | 'connected' | 'ended' | 'rejected'>('calling')
  const [duration, setDuration] = useState(0)
  const [isMuted, setIsMuted] = useState(false)
  const [isSpeakerOn, setIsSpeakerOn] = useState(false)
  const callIdRef = useRef<string | null>(null)
  const durationTimerRef = useRef<number | null>(null)
  const pcRef = useRef<RTCPeerConnection | null>(null)
  const localStreamRef = useRef<MediaStream | null>(null)
  const remoteStreamRef = useRef<MediaStream | null>(null)

  useEffect(() => {
    if (isOpen) {
      startCall()
    }
    return () => {
      endCall()
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isOpen])

  const startCall = async () => {
    try {
      const result = await api.createCall({
        calleeId,
        type: callType,
        offer: true // Request WebRTC offer
      })

      if (result.success && result.data) {
        callIdRef.current = result.data.id
        onCallStart?.(result.data.id)

        // Get local media stream
        await getLocalMedia()

        // Create WebRTC peer connection
        await createPeerConnection()

        // Start duration timer when connected
        setTimeout(() => {
          setCallStatus('connected')
          startDurationTimer()
        }, 2000) // Simulate connection delay
      }
    } catch (err) {
      console.error('Failed to start call:', err)
      setCallStatus('ended')
    }
  }

  const getLocalMedia = async () => {
    try {
      const stream = await navigator.mediaDevices.getUserMedia({
        audio: true,
        video: callType === 'video'
      })
      localStreamRef.current = stream
    } catch (err) {
      console.error('Failed to get local media:', err)
    }
  }

  const createPeerConnection = async () => {
    try {
      pcRef.current = new RTCPeerConnection({
        iceServers: [
          { urls: 'stun:stun.l.google.com:19302' },
          { urls: 'stun:stun1.l.google.com:19302' }
        ]
      })

      // Add local tracks
      if (localStreamRef.current) {
        localStreamRef.current.getTracks().forEach(track => {
          pcRef.current?.addTrack(track, localStreamRef.current!)
        })
      }

      // Handle ICE candidates
      pcRef.current.onicecandidate = async (event) => {
        if (event.candidate) {
          await api.sendIceCandidate(callIdRef.current!, event.candidate)
        }
      }

      // Handle remote stream
      pcRef.current.ontrack = (event) => {
        remoteStreamRef.current = event.streams[0]
      }

      // Create and send offer
      const offer = await pcRef.current.createOffer()
      await pcRef.current.setLocalDescription(offer)

      await api.sendOffer(callIdRef.current!, {
        sdp: offer.sdp,
        type: offer.type
      })
    } catch (err) {
      console.error('Failed to create peer connection:', err)
    }
  }

  const startDurationTimer = () => {
    durationTimerRef.current = window.setInterval(() => {
      setDuration(prev => prev + 1)
    }, 1000)
  }

  const stopDurationTimer = () => {
    if (durationTimerRef.current) {
      clearInterval(durationTimerRef.current)
      durationTimerRef.current = null
    }
  }

  const endCall = async () => {
    stopDurationTimer()

    if (callIdRef.current) {
      try {
        await api.endCall(callIdRef.current)
      } catch (err) {
        console.error('Failed to end call:', err)
      }
    }

    // Clean up WebRTC
    if (pcRef.current) {
      pcRef.current.close()
      pcRef.current = null
    }

    if (localStreamRef.current) {
      localStreamRef.current.getTracks().forEach(track => track.stop())
      localStreamRef.current = null
    }

    setCallStatus('ended')
    setTimeout(() => {
      onClose()
    }, 1000)
  }

  const toggleMute = () => {
    if (localStreamRef.current) {
      const audioTrack = localStreamRef.current.getAudioTracks()[0]
      if (audioTrack) {
        audioTrack.enabled = !audioTrack.enabled
        setIsMuted(!audioTrack.enabled)
      }
    }
  }

  const toggleSpeaker = () => {
    setIsSpeakerOn(!isSpeakerOn)
  }

  const formatDuration = (secs: number) => {
    const mins = Math.floor(secs / 60)
    const remainingSecs = secs % 60
    return `${mins.toString().padStart(2, '0')}:${remainingSecs.toString().padStart(2, '0')}`
  }

  if (!isOpen) return null

  return (
    <div className="fixed inset-0 bg-black/80 flex items-center justify-center z-50">
      <div className="bg-gradient-to-b from-gray-800 to-gray-900 rounded-3xl p-8 w-full max-w-md mx-4 shadow-2xl">
        {/* Caller/Callee Info */}
        <div className="text-center mb-8">
          <div className="w-24 h-24 rounded-full bg-gradient-to-br from-blue-500 to-purple-600 mx-auto mb-4 flex items-center justify-center text-white text-3xl font-bold">
            {calleeName.charAt(0).toUpperCase()}
          </div>
          <h2 className="text-2xl font-semibold text-white mb-2">{calleeName}</h2>
          <p className="text-gray-400">
            {callStatus === 'calling' && '正在呼叫...'}
            {callStatus === 'connected' && formatDuration(duration)}
            {callStatus === 'ended' && '通话已结束'}
            {callStatus === 'rejected' && '已拒绝'}
          </p>
        </div>

        {/* Video Preview (for video calls) */}
        {callType === 'video' && (
          <div className="mb-6 rounded-2xl overflow-hidden bg-gray-700 aspect-video">
            <video
              ref={(el) => {
                if (el && localStreamRef.current) {
                  el.srcObject = localStreamRef.current
                  el.play()
                }
              }}
              className="w-full h-full object-cover transform scale-x-[-1]"
              autoPlay
              muted
            />
          </div>
        )}

        {/* Call Controls */}
        <div className="flex items-center justify-center space-x-6">
          {/* Mute Button */}
          <button
            onClick={toggleMute}
            className={`p-4 rounded-full transition-colors ${
              isMuted ? 'bg-white text-gray-900' : 'bg-gray-700 text-white hover:bg-gray-600'
            }`}
          >
            {isMuted ? (
              <svg className="w-6 h-6" fill="currentColor" viewBox="0 0 20 20">
                <path fillRule="evenodd" d="M9.383 3.076A1 1 0 0110 4v12a1 1 0 01-1.707.707L4.586 13H2a1 1 0 01-1-1V8a1 1 0 011-1h2.586l3.707-3.707a1 1 0 011.09-.217zM14.657 2.929a1 1 0 011.414 0A9.972 9.972 0 0119 10a9.972 9.972 0 01-2.929 7.071 1 1 0 01-1.414-1.414A7.971 7.971 0 0017 10c0-2.21-.894-4.208-2.343-5.657a1 1 0 010-1.414zm-2.829 2.828a1 1 0 011.415 0A5.983 5.983 0 0115 10a5.984 5.984 0 01-1.757 4.243 1 1 0 01-1.415-1.415A3.984 3.984 0 0013 10a3.983 3.983 0 00-1.172-2.828 1 1 0 010-1.414z" clipRule="evenodd" />
              </svg>
            ) : (
              <svg className="w-6 h-6" fill="currentColor" viewBox="0 0 20 20">
                <path fillRule="evenodd" d="M7 4a3 3 0 016 0v4a3 3 0 11-6 0V4zm4 10.93A7.001 7.001 0 0017 8a1 1 0 10-2 0A5 5 0 015 8a1 1 0 00-2 0 7.001 7.001 0 006 6.93V17H6a1 1 0 100 2h8a1 1 0 100-2h-3v-2.07z" clipRule="evenodd" />
              </svg>
            )}
          </button>

          {/* End Call Button */}
          <button
            onClick={endCall}
            className="p-6 bg-red-500 hover:bg-red-600 rounded-full text-white transition-colors shadow-lg"
          >
            <svg className="w-8 h-8" fill="currentColor" viewBox="0 0 20 20">
              <path fillRule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM7 9a1 1 0 000 2h6a1 1 0 100-2H7z" clipRule="evenodd" />
              <path d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z" />
            </svg>
          </button>

          {/* Speaker Button */}
          <button
            onClick={toggleSpeaker}
            className={`p-4 rounded-full transition-colors ${
              isSpeakerOn ? 'bg-white text-gray-900' : 'bg-gray-700 text-white hover:bg-gray-600'
            }`}
          >
            <svg className="w-6 h-6" fill="currentColor" viewBox="0 0 20 20">
              <path fillRule="evenodd" d="M9.383 3.076A1 1 0 0110 4v12a1 1 0 01-1.707.707L4.586 13H2a1 1 0 01-1-1V8a1 1 0 011-1h2.586l3.707-3.707a1 1 0 011.09-.217zM12.293 5.293a1 1 0 011.414 0L15 6.586l1.293-1.293a1 1 0 111.414 1.414L16.414 8l1.293 1.293a1 1 0 01-1.414 1.414L15 9.414l-1.293 1.293a1 1 0 01-1.414-1.414L13.586 8l-1.293-1.293a1 1 0 010-1.414z" clipRule="evenodd" />
            </svg>
          </button>
        </div>

        {/* Call Type Indicator */}
        <div className="mt-6 text-center">
          <span className={`inline-flex items-center px-4 py-2 rounded-full text-sm font-medium ${
            callType === 'video'
              ? 'bg-purple-500/20 text-purple-400'
              : 'bg-blue-500/20 text-blue-400'
          }`}>
            {callType === 'video' ? (
              <>
                <svg className="w-4 h-4 mr-2" fill="currentColor" viewBox="0 0 20 20">
                  <path d="M2 6a2 2 0 012-2h6a2 2 0 012 2v8a2 2 0 01-2 2H4a2 2 0 01-2-2V6zM14.553 7.106A1 1 0 0014 8v4a1 1 0 00.553.894l2 1A1 1 0 0018 13V7a1 1 0 00-1.447-.894l-2 1z" />
                </svg>
                视频通话
              </>
            ) : (
              <>
                <svg className="w-4 h-4 mr-2" fill="currentColor" viewBox="0 0 20 20">
                  <path d="M2 3a1 1 0 011-1h2.153a1 1 0 01.986.836l.74 4.435a1 1 0 01-.54 1.06l-1.548.773a11.037 11.037 0 006.105 6.105l.774-1.548a1 1 0 011.059-.54l4.435.74a1 1 0 01.836.986V17a1 1 0 01-1 1h-2C7.82 18 2 12.18 2 5V3z" />
                </svg>
                语音通话
              </>
            )}
          </span>
        </div>
      </div>
    </div>
  )
}

export default CallModal
