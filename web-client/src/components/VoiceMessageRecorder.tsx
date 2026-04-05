/**
 * VoiceMessageRecorder Component
 *
 * 语音消息录制组件 - 支持录音、波形可视化、预览播放
 * 参考：Telegram 语音消息、WhatsApp 语音消息、微信语音
 */

import React, { useState, useRef, useEffect } from 'react';

interface VoiceMessageRecorderProps {
  onRecordingStart?: () => void;
  onRecordingEnd?: () => void;
  onSend: (audioBlob: Blob, duration: number, waveform: number[]) => void;
  onCancel?: () => void;
  onClose?: () => void;
  className?: string;
}


export function VoiceMessageRecorder({
  onRecordingStart,
  onRecordingEnd,
  onSend,
  onCancel,
  onClose,
  className = '',
}: VoiceMessageRecorderProps) {
  const [isRecording, setIsRecording] = useState(false);
  const [isPaused, setIsPaused] = useState(false);
  const [isPreview, setIsPreview] = useState(false);
  const [recordingTime, setRecordingTime] = useState(0);
  const [waveform, setWaveform] = useState<number[]>([]);
  const [isPlaying, setIsPlaying] = useState(false);
  const [playbackTime, setPlaybackTime] = useState(0);

  const mediaRecorderRef = useRef<MediaRecorder & { audioBlob?: Blob; audioUrl?: string; duration?: number } | null>(null);
  const audioContextRef = useRef<AudioContext | null>(null);
  const analyserRef = useRef<AnalyserNode | null>(null);
  const animationFrameRef = useRef<number>();
  const timerRef = useRef<number>();
  const chunksRef = useRef<Blob[]>([]);
  const startTimeRef = useRef<number>(0);
  const pausedTimeRef = useRef<number>(0);

  // 开始录制
  const startRecording = async () => {
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });

      const mediaRecorder = new MediaRecorder(stream);
      mediaRecorderRef.current = mediaRecorder;
      chunksRef.current = [];

      // 设置音频分析
      audioContextRef.current = new AudioContext();
      const source = audioContextRef.current.createMediaStreamSource(stream);
      analyserRef.current = audioContextRef.current.createAnalyser();
      analyserRef.current.fftSize = 256;
      source.connect(analyserRef.current);

      mediaRecorder.ondataavailable = (event) => {
        if (event.data.size > 0) {
          chunksRef.current.push(event.data);
        }
      };

      mediaRecorder.onstop = () => {
        const audioBlob = new Blob(chunksRef.current, { type: 'audio/webm' });
        const duration = recordingTime;

        // 停止所有音轨
        stream.getTracks().forEach((track) => track.stop());

        // 生成预览 URL
        const audioUrl = URL.createObjectURL(audioBlob);

        setIsPreview(true);
        setIsRecording(false);
        setIsPaused(false);

        onRecordingEnd?.();

        // 存储音频数据供发送使用
        (mediaRecorder as any).audioBlob = audioBlob;
        (mediaRecorder as any).audioUrl = audioUrl;
        (mediaRecorder as any).duration = duration;
      };

      mediaRecorder.start(100); // 每 100ms 收集一次数据
      startTimeRef.current = Date.now();

      // 开始可视化
      visualize();

      // 开始计时
      timerRef.current = window.setInterval(() => {
        if (!isPaused) {
          setRecordingTime((Date.now() - startTimeRef.current) / 1000);
        }
      }, 100);

      setIsRecording(true);
      onRecordingStart?.();
    } catch (error) {
      console.error('Failed to start recording:', error);
      alert('无法访问麦克风，请检查权限设置');
    }
  };

  // 停止录制
  const stopRecording = () => {
    if (mediaRecorderRef.current && isRecording) {
      mediaRecorderRef.current.stop();
      cancelAnimationFrame(animationFrameRef.current!);
      clearInterval(timerRef.current);

      // 关闭音频上下文
      if (audioContextRef.current) {
        audioContextRef.current.close();
      }
    }
  };

  // 暂停/继续录制
  const togglePause = () => {
    if (!mediaRecorderRef.current) return;

    if (isPaused) {
      mediaRecorderRef.current.resume();
      startTimeRef.current = Date.now() - pausedTimeRef.current * 1000;
      setIsPaused(false);
    } else {
      mediaRecorderRef.current.pause();
      pausedTimeRef.current = (Date.now() - startTimeRef.current) / 1000;
      setIsPaused(true);
    }
  };

  // 取消录制
  const cancelRecording = () => {
    stopRecording();
    setIsRecording(false);
    setIsPaused(false);
    setIsPreview(false);
    setRecordingTime(0);
    setWaveform([]);
    onCancel?.();
  };

  // 发送语音消息
  const sendVoiceMessage = () => {
    if (mediaRecorderRef.current?.audioBlob) {
      onSend(mediaRecorderRef.current.audioBlob, recordingTime, waveform);
      resetRecorder();
    }
  };

  // 重置录制器
  const resetRecorder = () => {
    setIsRecording(false);
    setIsPaused(false);
    setIsPreview(false);
    setIsPlaying(false);
    setRecordingTime(0);
    setPlaybackTime(0);
    setWaveform([]);
    mediaRecorderRef.current = null;
  };

  // 音频可视化
  const visualize = () => {
    if (!analyserRef.current) return;

    const dataArray = new Uint8Array(analyserRef.current.frequencyBinCount);

    const draw = () => {
      analyserRef.current!.getByteFrequencyData(dataArray);

      // 将音频数据转换为波形
      const normalizedData = Array.from(dataArray).map((v) => v / 255);
      const averagedData = [];

      // 降采样以创建更简洁的波形
      for (let i = 0; i < normalizedData.length; i += 4) {
        const avg =
          (normalizedData[i] +
            (normalizedData[i + 1] || 0) +
            (normalizedData[i + 2] || 0) +
            (normalizedData[i + 3] || 0)) /
          4;
        averagedData.push(avg);
      }

      setWaveform(averagedData.slice(0, 50)); // 限制波形点数

      animationFrameRef.current = requestAnimationFrame(draw);
    };

    draw();
  };

  // 播放预览
  const playPreview = () => {
    if (!mediaRecorderRef.current?.audioUrl) return;

    const audio = new Audio(mediaRecorderRef.current.audioUrl);

    audio.onended = () => {
      setIsPlaying(false);
      setPlaybackTime(0);
    };

    audio.ontimeupdate = () => {
      setPlaybackTime(audio.currentTime);
    };

    audio.play();
    setIsPlaying(true);

    return audio;
  };


  // 格式化时间
  const formatTime = (seconds: number) => {
    const mins = Math.floor(seconds / 60);
    const secs = Math.floor(seconds % 60);
    return `${mins}:${secs.toString().padStart(2, '0')}`;
  };

  // 渲染波形
  const renderWaveform = (data: number[], isLive = false) => {
    const currentTime = isLive ? recordingTime : playbackTime;
    const progress = isLive ? 1 : currentTime / recordingTime;

    return (
      <div className="flex items-center gap-0.5 h-12 flex-1">
        {data.length > 0 ? (
          data.map((value, index) => {
            const barIndex = Math.floor(index / data.length * 100);
            const isPlayed = barIndex < progress * 100;

            return (
              <div
                key={index}
                className={`w-1 rounded-full transition-all duration-75 ${
                  isPlayed ? 'bg-blue-500' : 'bg-gray-300'
                }`}
                style={{
                  height: `${Math.max(20, value * 100)}%`,
                  opacity: isLive ? 0.5 + value * 0.5 : 1,
                }}
              />
            );
          })
        ) : (
          <div className="flex items-center justify-center w-full text-gray-400 text-sm">
            {isRecording ? '正在录音...' : '点击麦克风开始录音'}
          </div>
        )}
      </div>
    );
  };

  // 清理
  useEffect(() => {
    return () => {
      if (animationFrameRef.current) {
        cancelAnimationFrame(animationFrameRef.current);
      }
      if (timerRef.current) {
        clearInterval(timerRef.current);
      }
      if (mediaRecorderRef.current) {
        mediaRecorderRef.current.stream?.getTracks().forEach((track) => track.stop());
      }
    };
  }, []);

  return (
    <div className={`flex items-center gap-2 p-3 bg-gray-50 rounded-xl ${className}`}>
      {!isPreview ? (
        // 录音状态
        <>
          {isRecording ? (
            <>
              {/* 波形显示 */}
              {renderWaveform(waveform, true)}

              {/* 录制时间 */}
              <span className={`text-sm font-mono w-12 text-center ${isPaused ? 'text-gray-400' : 'text-red-500'}`}>
                {formatTime(recordingTime)}
              </span>

              {/* 暂停/继续按钮 */}
              <button
                onClick={togglePause}
                className={`p-2 rounded-full ${
                  isPaused ? 'bg-yellow-100 text-yellow-600' : 'bg-gray-200 text-gray-600'
                }`}
              >
                {isPaused ? (
                  <svg className="w-5 h-5" fill="currentColor" viewBox="0 0 24 24">
                    <path d="M8 5v14l11-7z" />
                  </svg>
                ) : (
                  <svg className="w-5 h-5" fill="currentColor" viewBox="0 0 24 24">
                    <path d="M6 19h4V5H6v14zm8-14v14h4V5h-4z" />
                  </svg>
                )}
              </button>

              {/* 停止录制按钮 */}
              <button
                onClick={stopRecording}
                className="p-3 bg-red-500 text-white rounded-full hover:bg-red-600 transition-colors"
              >
                <svg className="w-5 h-5" fill="currentColor" viewBox="0 0 24 24">
                  <rect x="6" y="6" width="12" height="12" rx="2" />
                </svg>
              </button>
            </>
          ) : (
            // 未录音状态
            <>
              {/* 录音按钮 */}
              <button
                onMouseDown={startRecording}
                onMouseUp={stopRecording}
                onMouseLeave={stopRecording}
                onTouchStart={startRecording}
                onTouchEnd={stopRecording}
                className="p-4 bg-red-500 text-white rounded-full hover:bg-red-600 active:scale-95 transition-all"
              >
                <svg className="w-6 h-6" fill="currentColor" viewBox="0 0 24 24">
                  <path d="M12 14c1.66 0 3-1.34 3-3V5c0-1.66-1.34-3-3-3S9 3.34 9 5v6c0 1.66 1.34 3 3 3z" />
                  <path d="M17 11c0 2.76-2.24 5-5 5s-5-2.24-5-5H5c0 3.53 2.61 6.43 6 6.92V21h2v-3.08c3.39-.49 6-3.39 6-6.92h-2z" />
                </svg>
              </button>

              <span className="text-gray-500 text-sm ml-2">按住说话</span>

              <button
                onClick={onClose}
                className="ml-auto p-2 text-gray-400 hover:text-gray-600"
              >
                <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
                </svg>
              </button>
            </>
          )}
        </>
      ) : (
        // 预览状态
        <>
          {/* 播放/暂停按钮 */}
          <button
            onClick={() => {
              const audio = playPreview();
              if (audio) {
                audio.onended = () => {
                  setIsPlaying(false);
                  setPlaybackTime(0);
                };
              }
            }}
            className="p-3 bg-blue-500 text-white rounded-full hover:bg-blue-600 transition-colors"
          >
            {isPlaying ? (
              <svg className="w-5 h-5" fill="currentColor" viewBox="0 0 24 24">
                <path d="M6 19h4V5H6v14zm8-14v14h4V5h-4z" />
              </svg>
            ) : (
              <svg className="w-5 h-5" fill="currentColor" viewBox="0 0 24 24">
                <path d="M8 5v14l11-7z" />
              </svg>
            )}
          </button>

          {/* 波形和进度 */}
          {renderWaveform(waveform, false)}

          {/* 播放时间 */}
          <span className="text-sm font-mono text-gray-600 w-12 text-center">
            {formatTime(playbackTime)} / {formatTime(recordingTime)}
          </span>

          {/* 取消按钮 */}
          <button
            onClick={() => {
              cancelRecording();
              onClose?.();
            }}
            className="p-2 text-gray-400 hover:text-gray-600"
          >
            <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
            </svg>
          </button>

          {/* 发送按钮 */}
          <button
            onClick={sendVoiceMessage}
            className="p-3 bg-green-500 text-white rounded-full hover:bg-green-600 transition-colors"
          >
            <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 19l9 2-9-18-9 18 9-2zm0 0v-8" />
            </svg>
          </button>
        </>
      )}
    </div>
  );
}

// 语音播放组件
export function VoiceMessagePlayer({
  url,
  duration,
  waveform,
}: {
  url: string;
  duration: number;
  waveform?: number[];
}) {
  const [isPlaying, setIsPlaying] = useState(false);
  const [currentTime, setCurrentTime] = useState(0);
  const audioRef = useRef<HTMLAudioElement | null>(null);

  useEffect(() => {
    audioRef.current = new Audio(url);

    audioRef.current.onended = () => {
      setIsPlaying(false);
      setCurrentTime(0);
    };

    audioRef.current.ontimeupdate = () => {
      setCurrentTime(audioRef.current!.currentTime);
    };

    return () => {
      if (audioRef.current) {
        audioRef.current.pause();
        audioRef.current = null;
      }
    };
  }, [url]);

  const togglePlay = () => {
    if (!audioRef.current) return;

    if (isPlaying) {
      audioRef.current.pause();
    } else {
      audioRef.current.play();
    }
    setIsPlaying(!isPlaying);
  };

  const formatTime = (seconds: number) => {
    const mins = Math.floor(seconds / 60);
    const secs = Math.floor(seconds % 60);
    return `${mins}:${secs.toString().padStart(2, '0')}`;
  };

  const progress = duration > 0 ? currentTime / duration : 0;

  return (
    <div className="flex items-center gap-3 p-3 bg-gray-100 rounded-xl max-w-md">
      <button
        onClick={togglePlay}
        className="p-2 bg-blue-500 text-white rounded-full hover:bg-blue-600 transition-colors flex-shrink-0"
      >
        {isPlaying ? (
          <svg className="w-5 h-5" fill="currentColor" viewBox="0 0 24 24">
            <path d="M6 19h4V5H6v14zm8-14v14h4V5h-4z" />
          </svg>
        ) : (
          <svg className="w-5 h-5" fill="currentColor" viewBox="0 0 24 24">
            <path d="M8 5v14l11-7z" />
          </svg>
        )}
      </button>

      {/* 波形 */}
      <div className="flex items-center gap-0.5 h-8 flex-1">
        {waveform && waveform.length > 0 ? (
          waveform.map((value, index) => {
            const barIndex = Math.floor((index / waveform.length) * 100);
            const isPlayed = barIndex < progress * 100;

            return (
              <div
                key={index}
                className={`w-0.5 rounded-full transition-all ${
                  isPlayed ? 'bg-blue-500' : 'bg-gray-300'
                }`}
                style={{
                  height: `${Math.max(20, value * 100)}%`,
                }}
              />
            );
          })
        ) : (
          <div className="flex items-center justify-center w-full h-full bg-gray-200 rounded">
            <div className="flex gap-0.5">
              {[...Array(20)].map((_, i) => (
                <div
                  key={i}
                  className={`w-1 bg-gray-400 rounded-full ${
                    isPlaying ? 'animate-pulse' : ''
                  }`}
                  style={{
                    height: `${20 + Math.random() * 60}%`,
                    animationDelay: `${i * 50}ms`,
                  }}
                />
              ))}
            </div>
          </div>
        )}
      </div>

      <span className="text-sm font-mono text-gray-600 flex-shrink-0">
        {formatTime(duration)}
      </span>
    </div>
  );
}
