/**
 * UserStatusStories Component
 *
 * 用户状态/动态组件 - 类似 WhatsApp Status、微信视频动态、Instagram Stories
 * 支持 24 小时过期状态分享
 */

import React, { useState, useCallback, useEffect } from 'react';
import { useApi } from '../hooks/useApi';
import type { UserStatus } from '../types';

interface UserStatusStoriesProps {
  onStatusClick?: (status: UserStatus) => void;
  onClose?: () => void;
}

interface StatusItem {
  id: number;
  userId: string;
  username: string;
  userAvatar?: string;
  content: string;
  mediaType?: 'image' | 'video' | 'text';
  mediaUrl?: string;
  thumbnailUrl?: string;
  createdAt: number;
  expiresAt: number;
  hasViewed: boolean;
  viewerCount?: number;
}

export function UserStatusStories({ onClose }: UserStatusStoriesProps) {
  // eslint-disable-next-line @typescript-eslint/no-unused-vars
  const _onClose = onClose;
  const api = useApi();
  const [statuses, setStatuses] = useState<StatusItem[]>([]);
  const [showViewer, setShowViewer] = useState(false);
  const [currentStatusIndex, setCurrentStatusIndex] = useState(0);
  const [selectedStatus, setSelectedStatus] = useState<UserStatus | null>(null);

  // 加载好友状态
  const loadStatuses = useCallback(async () => {
    try {
      const response = await api.getStatusUpdates();
      if (response.data) {
        setStatuses(
          response.data.map((status) => ({
            ...status,
            username: status.username || 'unknown',
            hasViewed: false, // 可以从后端获取已读状态
          }))
        );
      }
    } catch (error) {
      console.error('Failed to load status updates:', error);
    }
  }, [api]);

  useEffect(() => {
    loadStatuses();
  }, [loadStatuses]);

  // 打开状态查看器
  const openStatusViewer = (status: UserStatus, index: number) => {
    setSelectedStatus(status);
    setCurrentStatusIndex(index);
    setShowViewer(true);

    // 标记为已读
    api.viewStatus(status.id).catch(console.error);
  };

  // 关闭查看器
  const closeViewer = () => {
    setShowViewer(false);
    setSelectedStatus(null);

    // 更新本地状态
    setStatuses((prev) =>
      prev.map((s, i) =>
        i === currentStatusIndex ? { ...s, hasViewed: true } : s
      )
    );
  };

  // 导航到上一个/下一个
  const navigate = (direction: 'prev' | 'next') => {
    if (direction === 'next' && currentStatusIndex < statuses.length - 1) {
      const nextIndex = currentStatusIndex + 1;
      setCurrentStatusIndex(nextIndex);
      setSelectedStatus(statuses[nextIndex] as any);
      api.viewStatus(statuses[nextIndex].id).catch(console.error);
    } else if (direction === 'prev' && currentStatusIndex > 0) {
      const prevIndex = currentStatusIndex - 1;
      setCurrentStatusIndex(prevIndex);
      setSelectedStatus(statuses[prevIndex] as any);
    } else {
      closeViewer();
    }
  };

  // 格式化过期时间
  const formatExpiresAt = (expiresAt: number) => {
    const now = Date.now();
    const remaining = expiresAt - now;

    if (remaining < 0) return '已过期';

    const hours = Math.floor(remaining / (1000 * 60 * 60));
    const minutes = Math.floor((remaining % (1000 * 60 * 60)) / (1000 * 60));

    if (hours > 0) {
      return `${hours}小时后过期`;
    } else {
      return `${minutes}分钟后过期`;
    }
  };

  // 好友状态
  const friendStatuses = statuses.filter((s) => s.userId !== 'me');

  return (
    <>
      {/* 状态列表 */}
      <div className="border-b border-gray-200 bg-white">
        <div className="flex items-center gap-3 p-3 overflow-x-auto scrollbar-hide">
          {/* 我的状态 */}
          <button
            onClick={() => {/* 打开创建状态对话框 */ }}
            className="flex flex-col items-center gap-1 flex-shrink-0"
          >
            <div className="relative">
              <div className="w-16 h-16 rounded-full bg-gray-100 border-2 border-dashed border-gray-300 flex items-center justify-center">
                <svg className="w-8 h-8 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 4v16m8-8H4" />
                </svg>
              </div>
            </div>
            <span className="text-xs text-gray-600">我的状态</span>
          </button>

          {/* 分隔线 */}
          {friendStatuses.length > 0 && (
            <div className="w-px h-12 bg-gray-200 flex-shrink-0" />
          )}

          {/* 好友状态 */}
          {friendStatuses.map((status, index) => (
            <button
              key={status.id}
              onClick={() => openStatusViewer(status as any, index)}
              className="flex flex-col items-center gap-1 flex-shrink-0"
            >
              <div
                className={`relative p-0.5 rounded-full ${
                  status.hasViewed
                    ? 'bg-gray-300'
                    : 'bg-gradient-to-r from-blue-400 to-blue-600'
                }`}
              >
                <div className="bg-white rounded-full p-0.5">
                  <img
                    src={status.userAvatar || '/default-avatar.png'}
                    alt={status.username}
                    className="w-14 h-14 rounded-full object-cover"
                  />
                </div>
              </div>
              <span className="text-xs text-gray-600 max-w-16 truncate">
                {status.username}
              </span>
            </button>
          ))}
        </div>
      </div>

      {/* 状态查看器 */}
      {showViewer && selectedStatus && (
        <div className="fixed inset-0 bg-black z-50 flex items-center justify-center">
          {/* 顶部进度条 */}
          <div className="absolute top-0 left-0 right-0 p-2 z-10">
            <div className="flex gap-1">
              {friendStatuses.map((_, index) => (
                <div
                  key={index}
                  className="flex-1 h-0.5 bg-white/30 rounded-full overflow-hidden"
                >
                  <div
                    className={`h-full bg-white transition-all duration-100 ${
                      index === currentStatusIndex
                        ? 'animate-pulse'
                        : index < currentStatusIndex
                        ? 'w-full'
                        : 'w-0'
                    }`}
                    style={{
                      width: index === currentStatusIndex ? '100%' : undefined,
                      transition: index === currentStatusIndex ? 'width 5s linear' : 'none',
                    }}
                  />
                </div>
              ))}
            </div>
          </div>

          {/* 顶部信息 */}
          <div className="absolute top-4 left-4 right-4 flex items-center justify-between z-10">
            <div className="flex items-center gap-3">
              <img
                src={selectedStatus.userAvatar || '/default-avatar.png'}
                alt={selectedStatus.username}
                className="w-10 h-10 rounded-full"
              />
              <div>
                <p className="text-white font-medium">{selectedStatus.username}</p>
                <p className="text-white/60 text-xs">
                  {formatExpiresAt(selectedStatus.expiresAt)}
                </p>
              </div>
            </div>

            <button onClick={closeViewer} className="text-white/80 hover:text-white">
              <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
              </svg>
            </button>
          </div>

          {/* 状态内容 */}
          <div
            className="absolute inset-0 flex items-center justify-center"
            onClick={() => navigate('next')}
          >
            {selectedStatus.mediaType === 'image' || selectedStatus.mediaUrl ? (
              <img
                src={selectedStatus.mediaUrl || selectedStatus.thumbnailUrl}
                alt={selectedStatus.content}
                className="max-w-full max-h-full object-contain"
              />
            ) : selectedStatus.mediaType === 'video' ? (
              <video
                src={selectedStatus.mediaUrl || undefined}
                className="max-w-full max-h-full"
                autoPlay
                loop
                muted
              />
            ) : (
              <div className="bg-gradient-to-br from-blue-500 to-purple-600 w-full h-full flex items-center justify-center p-8">
                <p className="text-white text-xl text-center max-w-md">
                  {selectedStatus.content}
                </p>
              </div>
            )}
          </div>

          {/* 内容覆盖层 */}
          {selectedStatus.mediaType !== 'text' && selectedStatus.content && (
            <div className="absolute bottom-20 left-4 right-4">
              <p className="text-white text-lg drop-shadow-lg">{selectedStatus.content}</p>
            </div>
          )}

          {/* 导航按钮 */}
          <button
            onClick={(e) => {
              e.stopPropagation();
              navigate('prev');
            }}
            className="absolute left-2 top-1/2 -translate-y-1/2 text-white/60 hover:text-white p-2"
          >
            <svg className="w-8 h-8" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 19l-7-7 7-7" />
            </svg>
          </button>

          <button
            onClick={(e) => {
              e.stopPropagation();
              navigate('next');
            }}
            className="absolute right-2 top-1/2 -translate-y-1/2 text-white/60 hover:text-white p-2"
          >
            <svg className="w-8 h-8" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 5l7 7-7 7" />
            </svg>
          </button>

          {/* 底部操作 */}
          <div className="absolute bottom-4 left-4 right-4 flex items-center gap-4">
            <input
              type="text"
              placeholder="发送消息..."
              className="flex-1 bg-white/20 backdrop-blur rounded-full px-4 py-2 text-white placeholder-white/60 focus:outline-none focus:ring-2 focus:ring-white/40"
            />
            <button className="text-white/80 hover:text-white">
              <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4.318 6.318a4.5 4.5 0 000 6.364L12 20.364l7.682-7.682a4.5 4.5 0 00-6.364-6.364L12 7.636l-1.318-1.318a4.5 4.5 0 00-6.364 0z" />
              </svg>
            </button>
          </div>
        </div>
      )}
    </>
  );
}

// 创建状态组件
export function CreateStatusModal({ onClose }: { onClose: () => void }) {
  const api = useApi();
  const [content, setContent] = useState('');
  const [mediaType, setMediaType] = useState<'image' | 'video' | 'text'>('text');
  const [mediaFile, setMediaFile] = useState<File | null>(null);
  const [mediaPreview, setMediaPreview] = useState<string | null>(null);
  const [expiresIn, setExpiresIn] = useState(24 * 60 * 60); // 24 小时
  const [loading, setLoading] = useState(false);

  const handleFileSelect = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (file) {
      setMediaFile(file);

      // 创建预览
      const reader = new FileReader();
      reader.onload = (e) => {
        setMediaPreview(e.target?.result as string);
      };
      reader.readAsDataURL(file);

      // 自动设置媒体类型
      if (file.type.startsWith('image/')) {
        setMediaType('image');
      } else if (file.type.startsWith('video/')) {
        setMediaType('video');
      }
    }
  };

  const handleSubmit = async () => {
    if (!content.trim() && !mediaFile) {
      alert('请输入内容或选择媒体文件');
      return;
    }

    setLoading(true);
    try {
      await api.createStatus({
        content,
        mediaType: mediaFile ? mediaType : 'text',
        mediaFile: mediaFile || undefined,
        expiresIn,
      });
      onClose();
    } catch (error) {
      console.error('Failed to create status:', error);
      alert('发布状态失败，请重试');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="fixed inset-0 bg-black/50 z-50 flex items-center justify-center">
      <div className="bg-white rounded-2xl w-full max-w-md mx-4">
        {/* 头部 */}
        <div className="flex items-center justify-between p-4 border-b">
          <h2 className="text-lg font-semibold">发布状态</h2>
          <button onClick={onClose} className="text-gray-400 hover:text-gray-600">
            <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>

        {/* 内容 */}
        <div className="p-4">
          {/* 媒体预览 */}
          {mediaPreview && (
            <div className="mb-4 relative">
              {mediaType === 'image' ? (
                <img src={mediaPreview} alt="Preview" className="w-full rounded-lg" />
              ) : mediaType === 'video' ? (
                <video src={mediaPreview} className="w-full rounded-lg" controls />
              ) : null}
              <button
                onClick={() => {
                  setMediaFile(null);
                  setMediaPreview(null);
                }}
                className="absolute top-2 right-2 bg-black/50 text-white p-1 rounded-full hover:bg-black/70"
              >
                <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
                </svg>
              </button>
            </div>
          )}

          {/* 文本输入 */}
          <textarea
            value={content}
            onChange={(e) => setContent(e.target.value)}
            placeholder="分享你的想法..."
            className="w-full h-32 p-3 border border-gray-300 rounded-lg resize-none focus:outline-none focus:ring-2 focus:ring-blue-500"
          />

          {/* 媒体选择 */}
          <div className="mt-4 flex gap-2">
            <label className="flex-1 flex items-center justify-center gap-2 p-3 border-2 border-dashed border-gray-300 rounded-lg cursor-pointer hover:border-blue-500 transition-colors">
              <svg className="w-6 h-6 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z" />
              </svg>
              <span className="text-sm text-gray-500">图片/视频</span>
              <input
                type="file"
                accept="image/*,video/*"
                onChange={handleFileSelect}
                className="hidden"
              />
            </label>

            <button
              onClick={() => setMediaType('text')}
              className={`px-4 py-2 rounded-lg ${
                mediaType === 'text' && !mediaFile
                  ? 'bg-blue-500 text-white'
                  : 'bg-gray-100 text-gray-600'
              }`}
            >
              纯文本
            </button>
          </div>

          {/* 过期时间选择 */}
          <div className="mt-4">
            <label className="text-sm text-gray-500 mb-2 block">可见时长</label>
            <div className="flex gap-2">
              {[6, 12, 24].map((hours) => (
                <button
                  key={hours}
                  onClick={() => setExpiresIn(hours * 60 * 60)}
                  className={`flex-1 py-2 rounded-lg ${
                    expiresIn === hours * 60 * 60
                      ? 'bg-blue-500 text-white'
                      : 'bg-gray-100 text-gray-600'
                  }`}
                >
                  {hours}小时
                </button>
              ))}
            </div>
          </div>
        </div>

        {/* 底部按钮 */}
        <div className="p-4 border-t">
          <button
            onClick={handleSubmit}
            disabled={loading || (!content.trim() && !mediaFile)}
            className="w-full py-3 bg-blue-500 text-white rounded-lg font-medium hover:bg-blue-600 disabled:bg-gray-300 disabled:cursor-not-allowed transition-colors"
          >
            {loading ? '发布中...' : '发布状态'}
          </button>
        </div>
      </div>
    </div>
  );
}
