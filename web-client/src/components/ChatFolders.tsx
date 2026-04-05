/**
 * ChatFolders Component
 *
 * 聊天文件夹组件 - 类似 Telegram 聊天文件夹功能
 * 支持自定义文件夹分类管理聊天
 */

import React, { useState, useCallback, useEffect } from 'react';
import { useApi } from '../hooks/useApi';
import type { ChatFolder } from '../types';

interface ChatFoldersProps {
  onSelectFolder?: (folder: ChatFolder) => void;
  activeFolderId?: number | null;
  onClose?: () => void;
}

export function ChatFolders({
  onSelectFolder,
  activeFolderId,
}: ChatFoldersProps) {
  const api = useApi();
  const [folders, setFolders] = useState<ChatFolder[]>([]);
  const [showCreateModal, setShowCreateModal] = useState(false);

  // 加载文件夹列表
  const loadFolders = useCallback(async () => {
    try {
      const response = await api.getChatFolders();
      if (response.data) {
        setFolders(response.data);
      }
    } catch (error) {
      console.error('Failed to load chat folders:', error);
    }
  }, [api]);

  useEffect(() => {
    loadFolders();
  }, [loadFolders]);

  // 加载文件夹内的对话
  const loadFolderConversations = useCallback(async (_folderId: number) => {
    // TODO: Implement folder conversations loading if needed
  }, []);

  // 删除文件夹
  const handleDeleteFolder = async (folderId: number) => {
    if (!confirm('确定要删除这个文件夹吗？')) return;

    try {
      await api.deleteChatFolder(folderId);
      setFolders((prev) => prev.filter((f) => f.id !== folderId));
    } catch (error) {
      console.error('Failed to delete folder:', error);
      alert('删除文件夹失败');
    }
  };

  // 文件夹图标映射
  const getFolderIcon = (icon?: string, name?: string) => {
    if (icon) return icon;

    // 根据名称默认图标
    const defaultIcons: Record<string, string> = {
      '未读': '📌',
      '个人': '👤',
      '工作': '💼',
      '群组': '👥',
      '收藏': '⭐',
    };

    return defaultIcons[name || ''] || '📁';
  };

  return (
    <>
      {/* 文件夹标签栏 */}
      <div className="flex items-center gap-2 px-3 py-2 border-b border-gray-200 bg-white overflow-x-auto scrollbar-hide">
        {/* 全部聊天 */}
        <button
          onClick={() => onSelectFolder?.({ id: 0, name: '全部', conversationIds: [], createdAt: 0 })}
          className={`px-3 py-1.5 rounded-full text-sm whitespace-nowrap transition-colors ${
            activeFolderId === 0 || activeFolderId === undefined
              ? 'bg-blue-500 text-white'
              : 'bg-gray-100 text-gray-600 hover:bg-gray-200'
          }`}
        >
          💬 全部
        </button>

        {/* 文件夹列表 */}
        {folders.map((folder) => (
          <div
            key={folder.id}
            className="relative group"
          >
            <button
              onClick={() => {
                onSelectFolder?.(folder);
                loadFolderConversations(folder.id);
              }}
              className={`px-3 py-1.5 rounded-full text-sm whitespace-nowrap transition-colors flex items-center gap-1 ${
                activeFolderId === folder.id
                  ? 'bg-blue-500 text-white'
                  : 'bg-gray-100 text-gray-600 hover:bg-gray-200'
              }`}
            >
              <span>{getFolderIcon(folder.icon, folder.name)}</span>
              <span>{folder.name}</span>
              {folder.conversationIds.length > 0 && (
                <span className="text-xs opacity-60">
                  ({folder.conversationIds.length})
                </span>
              )}
            </button>

            {/* 删除按钮（悬停显示） */}
            {!folder.isDefault && (
              <button
                onClick={(e) => {
                  e.stopPropagation();
                  handleDeleteFolder(folder.id);
                }}
                className="absolute -top-1 -right-1 opacity-0 group-hover:opacity-100 bg-red-500 text-white rounded-full p-0.5 hover:bg-red-600 transition-opacity"
              >
                <svg className="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
                </svg>
              </button>
            )}
          </div>
        ))}

        {/* 创建文件夹按钮 */}
        <button
          onClick={() => setShowCreateModal(true)}
          className="p-1.5 rounded-full bg-gray-100 text-gray-600 hover:bg-gray-200 transition-colors"
        >
          <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 4v16m8-8H4" />
          </svg>
        </button>
      </div>

      {/* 创建文件夹模态框 */}
      {showCreateModal && (
        <CreateFolderModal
          onClose={() => setShowCreateModal(false)}
          onCreate={(folder) => {
            setFolders((prev) => [...prev, folder]);
            setShowCreateModal(false);
          }}
        />
      )}
    </>
  );
}

// 创建文件夹模态框
interface CreateFolderModalProps {
  onClose: () => void;
  onCreate: (folder: ChatFolder) => void;
}

function CreateFolderModal({ onClose, onCreate }: CreateFolderModalProps) {
  const api = useApi();
  const [name, setName] = useState('');
  const [icon, setIcon] = useState('📁');
  const [loading, setLoading] = useState(false);

  const emojiOptions = ['📁', '👥', '💼', '📌', '⭐', '🏠', '✈️', '🎮', '🎵', '📷'];

  const handleSubmit = async () => {
    if (!name.trim()) {
      alert('请输入文件夹名称');
      return;
    }

    setLoading(true);
    try {
      const response = await api.createChatFolder({
        name,
        icon,
        conversationIds: [],
      });
      onCreate(response.data);
    } catch (error) {
      console.error('Failed to create folder:', error);
      alert('创建文件夹失败');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="fixed inset-0 bg-black/50 z-50 flex items-center justify-center">
      <div className="bg-white rounded-2xl w-full max-w-md mx-4">
        {/* 头部 */}
        <div className="flex items-center justify-between p-4 border-b">
          <h2 className="text-lg font-semibold">创建文件夹</h2>
          <button onClick={onClose} className="text-gray-400 hover:text-gray-600">
            <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>

        {/* 内容 */}
        <div className="p-4 space-y-4">
          {/* 文件夹名称 */}
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">
              文件夹名称
            </label>
            <input
              type="text"
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder="例如：工作、朋友、家人"
              className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500"
              autoFocus
            />
          </div>

          {/* 图标选择 */}
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">
              图标
            </label>
            <div className="flex gap-2 flex-wrap">
              {emojiOptions.map((emoji) => (
                <button
                  key={emoji}
                  onClick={() => setIcon(emoji)}
                  className={`w-10 h-10 flex items-center justify-center text-xl rounded-lg transition-colors ${
                    icon === emoji
                      ? 'bg-blue-500 text-white'
                      : 'bg-gray-100 hover:bg-gray-200'
                  }`}
                >
                  {emoji}
                </button>
              ))}
            </div>
          </div>

          {/* 聊天选择 */}
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">
              添加聊天（可选）
            </label>
            <div className="max-h-48 overflow-y-auto border border-gray-300 rounded-lg">
              {/* 这里可以添加聊天列表供选择 */}
              <div className="p-4 text-center text-gray-400 text-sm">
                可以在创建后添加聊天
              </div>
            </div>
          </div>
        </div>

        {/* 底部按钮 */}
        <div className="p-4 border-t flex gap-2">
          <button
            onClick={onClose}
            className="flex-1 py-2.5 border border-gray-300 text-gray-700 rounded-lg hover:bg-gray-50 transition-colors"
          >
            取消
          </button>
          <button
            onClick={handleSubmit}
            disabled={loading || !name.trim()}
            className="flex-1 py-2.5 bg-blue-500 text-white rounded-lg hover:bg-blue-600 disabled:bg-gray-300 disabled:cursor-not-allowed transition-colors"
          >
            {loading ? '创建中...' : '创建'}
          </button>
        </div>
      </div>
    </div>
  );
}

// 频道组件
interface GroupChannelsProps {
  groupId: number;
  activeChannelId?: number;
  onChannelSelect?: (channelId: number) => void;
}

export function GroupChannels({ groupId, activeChannelId, onChannelSelect }: GroupChannelsProps) {
  const api = useApi();
  const [channels, setChannels] = useState<Array<{
    id: number;
    name: string;
    type: 'text' | 'voice' | 'category';
    description?: string;
    position: number;
    isMuted?: boolean;
  }>>([]);
  const [loading, setLoading] = useState(true);
  const [showCreateModal, setShowCreateModal] = useState(false);

  // 加载频道列表
  const loadChannels = useCallback(async () => {
    try {
      const response = await api.getGroupChannels(groupId);
      if (response.data) {
        setChannels(response.data.sort((a, b) => a.position - b.position));
      }
    } catch (error) {
      console.error('Failed to load channels:', error);
    } finally {
      setLoading(false);
    }
  }, [api, groupId]);

  useEffect(() => {
    loadChannels();
  }, [loadChannels]);

  // 频道图标
  const getChannelIcon = (type: 'text' | 'voice' | 'category') => {
    switch (type) {
      case 'text':
        return '#';
      case 'voice':
        return '🔊';
      case 'category':
        return '📁';
    }
  };

  return (
    <div className="bg-white border-r border-gray-200 w-48 flex-shrink-0">
      {/* 头部 */}
      <div className="flex items-center justify-between p-3 border-b border-gray-200">
        <h3 className="font-semibold text-gray-700">频道</h3>
        <button
          onClick={() => setShowCreateModal(true)}
          className="text-gray-400 hover:text-gray-600"
        >
          <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 4v16m8-8H4" />
          </svg>
        </button>
      </div>

      {/* 频道列表 */}
      <div className="overflow-y-auto">
        {loading ? (
          <div className="p-4 text-center text-gray-400 text-sm">加载中...</div>
        ) : channels.length === 0 ? (
          <div className="p-4 text-center text-gray-400 text-sm">
            暂无频道
            <button
              onClick={() => setShowCreateModal(true)}
              className="block w-full mt-2 text-blue-500 hover:underline"
            >
              创建第一个频道
            </button>
          </div>
        ) : (
          <div className="divide-y divide-gray-100">
            {channels.map((channel) => (
              <button
                key={channel.id}
                onClick={() => onChannelSelect?.(channel.id)}
                className={`w-full flex items-center gap-2 p-3 hover:bg-gray-50 transition-colors ${
                  activeChannelId === channel.id ? 'bg-blue-50' : ''
                }`}
              >
                <span className="text-gray-400">{getChannelIcon(channel.type)}</span>
                <div className="flex-1 text-left">
                  <p className="text-sm font-medium text-gray-700">{channel.name}</p>
                  {channel.description && (
                    <p className="text-xs text-gray-400 truncate">{channel.description}</p>
                  )}
                </div>
                {channel.isMuted && (
                  <svg className="w-4 h-4 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5.586 15H4a1 1 0 01-1-1v-4a1 1 0 011-1h1.586l4.707-4.707C10.923 3.663 12 4.109 12 5v14c0 .891-1.077 1.337-1.707.707L5.586 15z" />
                  </svg>
                )}
              </button>
            ))}
          </div>
        )}
      </div>

      {/* 创建频道模态框 */}
      {showCreateModal && (
        <CreateChannelModal
          groupId={groupId}
          onClose={() => setShowCreateModal(false)}
          onCreate={() => {
            loadChannels();
            setShowCreateModal(false);
          }}
        />
      )}
    </div>
  );
}

// 创建频道模态框
interface CreateChannelModalProps {
  groupId: number;
  onClose: () => void;
  onCreate: () => void;
}

function CreateChannelModal({ groupId, onClose, onCreate }: CreateChannelModalProps) {
  const api = useApi();
  const [name, setName] = useState('');
  const [description, setDescription] = useState('');
  const [type, setType] = useState<'text' | 'voice'>('text');
  const [loading, setLoading] = useState(false);

  const handleSubmit = async () => {
    if (!name.trim()) {
      alert('请输入频道名称');
      return;
    }

    setLoading(true);
    try {
      await api.createChannel(groupId, {
        name,
        type,
      });
      onCreate();
    } catch (error) {
      console.error('Failed to create channel:', error);
      alert('创建频道失败');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="fixed inset-0 bg-black/50 z-50 flex items-center justify-center">
      <div className="bg-white rounded-2xl w-full max-w-md mx-4">
        {/* 头部 */}
        <div className="flex items-center justify-between p-4 border-b">
          <h2 className="text-lg font-semibold">创建频道</h2>
          <button onClick={onClose} className="text-gray-400 hover:text-gray-600">
            <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>

        {/* 内容 */}
        <div className="p-4 space-y-4">
          {/* 频道名称 */}
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">
              频道名称
            </label>
            <input
              type="text"
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder="例如：-general、voice-chat"
              className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500"
              autoFocus
            />
          </div>

          {/* 频道描述 */}
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">
              描述（可选）
            </label>
            <input
              type="text"
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              placeholder="频道用途说明"
              className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500"
            />
          </div>

          {/* 频道类型 */}
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-2">
              频道类型
            </label>
            <div className="grid grid-cols-2 gap-2">
              <button
                onClick={() => setType('text')}
                className={`p-3 rounded-lg border-2 transition-colors ${
                  type === 'text'
                    ? 'border-blue-500 bg-blue-50'
                    : 'border-gray-200 hover:border-gray-300'
                }`}
              >
                <div className="text-2xl mb-1">#</div>
                <div className="text-sm font-medium">文本频道</div>
              </button>
              <button
                onClick={() => setType('voice')}
                className={`p-3 rounded-lg border-2 transition-colors ${
                  type === 'voice'
                    ? 'border-blue-500 bg-blue-50'
                    : 'border-gray-200 hover:border-gray-300'
                }`}
              >
                <div className="text-2xl mb-1">🔊</div>
                <div className="text-sm font-medium">语音频道</div>
              </button>
            </div>
          </div>
        </div>

        {/* 底部按钮 */}
        <div className="p-4 border-t flex gap-2">
          <button
            onClick={onClose}
            className="flex-1 py-2.5 border border-gray-300 text-gray-700 rounded-lg hover:bg-gray-50 transition-colors"
          >
            取消
          </button>
          <button
            onClick={handleSubmit}
            disabled={loading || !name.trim()}
            className="flex-1 py-2.5 bg-blue-500 text-white rounded-lg hover:bg-blue-600 disabled:bg-gray-300 disabled:cursor-not-allowed transition-colors"
          >
            {loading ? '创建中...' : '创建'}
          </button>
        </div>
      </div>
    </div>
  );
}
