/**
 * MessageReactionPicker Component
 *
 * 消息表情回应选择器 - 类似 Telegram/Discord 的表情反应功能
 * 支持内置表情和自定义表情包
 */

import React, { useState, useCallback, useEffect, useRef } from 'react';
import { useApi } from '../hooks/useApi';
import type { MessageReaction, ReactionGroup } from '../types';

interface MessageReactionPickerProps {
  messageId: number;
  onClose: () => void;
  onReactionSelect: (emoji: string) => void;
  position?: { x: number; y: number };
}

// 常用表情列表
const COMMON_REACTIONS = [
  '👍', '👎', '❤️', '😂', '😮', '😢', '😡', '🎉',
  '🔥', '⭐', '💯', '✨', '💪', '🙏', '😊', '🤔',
];

export function MessageReactionPicker({
  onClose,
  onReactionSelect,
  position,
}: MessageReactionPickerProps) {
  const api = useApi();
  const [activeTab, setActiveTab] = useState<'common' | 'frequent' | 'custom'>('common');
  const [frequentReactions, setFrequentReactions] = useState<Array<{ emoji: string; count: number }>>([]);
  const [customPacks, setCustomPacks] = useState<Array<{ id: number; name: string; emojis: Array<{ id: string; url: string }> }>>([]);
  const [selectedPack, setSelectedPack] = useState<number | null>(null);
  const pickerRef = useRef<HTMLDivElement>(null);

  // 加载常用表情
  const loadFrequentReactions = useCallback(async () => {
    try {
      const response = await api.getFrequentReactions(20);
      if (response.data) {
        setFrequentReactions(response.data);
      }
    } catch (error) {
      console.error('Failed to load frequent reactions:', error);
    }
  }, [api]);

  // 加载自定义表情包
  const loadCustomPacks = useCallback(async () => {
    try {
      const response = await api.getCustomEmojiPacks();
      if (response.data) {
        setCustomPacks(response.data);
      }
    } catch (error) {
      console.error('Failed to load custom emoji packs:', error);
    }
  }, [api]);

  useEffect(() => {
    if (activeTab === 'frequent') {
      loadFrequentReactions();
    } else if (activeTab === 'custom') {
      loadCustomPacks();
    }
  }, [activeTab, loadFrequentReactions, loadCustomPacks]);

  // 点击外部关闭
  useEffect(() => {
    const handleClickOutside = (event: MouseEvent) => {
      if (pickerRef.current && !pickerRef.current.contains(event.target as Node)) {
        onClose();
      }
    };

    document.addEventListener('mousedown', handleClickOutside);
    return () => document.removeEventListener('mousedown', handleClickOutside);
  }, [onClose]);

  const handleSelectEmoji = (emoji: string) => {
    onReactionSelect(emoji);
    onClose();
  };

  return (
    <div
      ref={pickerRef}
      className="absolute z-50 bg-white rounded-2xl shadow-xl border border-gray-200 overflow-hidden"
      style={{
        left: position?.x || 0,
        top: (position?.y || 0) - 10,
        minWidth: '320px',
        maxHeight: '400px',
      }}
    >
      {/* 标签页 */}
      <div className="flex border-b border-gray-200">
        <button
          onClick={() => setActiveTab('common')}
          className={`flex-1 px-4 py-2 text-sm font-medium transition-colors ${
            activeTab === 'common'
              ? 'text-blue-600 border-b-2 border-blue-600'
              : 'text-gray-500 hover:text-gray-700'
          }`}
        >
          常用
        </button>
        <button
          onClick={() => setActiveTab('frequent')}
          className={`flex-1 px-4 py-2 text-sm font-medium transition-colors ${
            activeTab === 'frequent'
              ? 'text-blue-600 border-b-2 border-blue-600'
              : 'text-gray-500 hover:text-gray-700'
          }`}
        >
          常用表情
        </button>
        <button
          onClick={() => setActiveTab('custom')}
          className={`flex-1 px-4 py-2 text-sm font-medium transition-colors ${
            activeTab === 'custom'
              ? 'text-blue-600 border-b-2 border-blue-600'
              : 'text-gray-500 hover:text-gray-700'
          }`}
        >
          表情包
        </button>
      </div>

      {/* 内容区域 */}
      <div className="p-3 overflow-y-auto max-h-80">
        {activeTab === 'common' && (
          <div className="grid grid-cols-8 gap-1">
            {COMMON_REACTIONS.map((emoji) => (
              <button
                key={emoji}
                onClick={() => handleSelectEmoji(emoji)}
                className="w-10 h-10 flex items-center justify-center text-xl hover:bg-gray-100 rounded-lg transition-colors"
              >
                {emoji}
              </button>
            ))}
          </div>
        )}

        {activeTab === 'frequent' && (
          <div className="grid grid-cols-5 gap-2">
            {frequentReactions.length > 0 ? (
              frequentReactions.map(({ emoji, count }) => (
                <button
                  key={emoji}
                  onClick={() => handleSelectEmoji(emoji)}
                  className="w-12 h-12 flex items-center justify-center text-2xl hover:bg-gray-100 rounded-lg transition-colors relative"
                >
                  {emoji}
                  {count > 1 && (
                    <span className="absolute -bottom-1 -right-1 bg-blue-500 text-white text-xs rounded-full w-4 h-4 flex items-center justify-center">
                      {count}
                    </span>
                  )}
                </button>
              ))
            ) : (
              <div className="col-span-5 text-center text-gray-400 py-8">
                暂无常用表情
              </div>
            )}
          </div>
        )}

        {activeTab === 'custom' && (
          <div>
            {selectedPack !== null ? (
              // 显示选中表情包的细节
              <>
                <button
                  onClick={() => setSelectedPack(null)}
                  className="mb-2 text-sm text-blue-600 hover:underline flex items-center gap-1"
                >
                  <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 19l-7-7 7-7" />
                  </svg>
                  返回
                </button>
                <div className="grid grid-cols-5 gap-2">
                  {customPacks[selectedPack]?.emojis.map((emoji) => (
                    <button
                      key={emoji.id}
                      onClick={() => handleSelectEmoji(emoji.url)}
                      className="w-12 h-12 flex items-center justify-center hover:bg-gray-100 rounded-lg transition-colors"
                    >
                      <img src={emoji.url} alt="emoji" className="w-10 h-10 object-contain" />
                    </button>
                  ))}
                </div>
              </>
            ) : (
              // 显示表情包列表
              <div className="space-y-2">
                {customPacks.map((pack, index) => (
                  <button
                    key={pack.id}
                    onClick={() => setSelectedPack(index)}
                    className="w-full flex items-center gap-3 p-2 hover:bg-gray-100 rounded-lg transition-colors"
                  >
                    {pack.emojis[0] && (
                      <img src={pack.emojis[0].url} alt={pack.name} className="w-8 h-8 object-contain" />
                    )}
                    <span className="font-medium text-gray-700">{pack.name}</span>
                    <span className="text-sm text-gray-400">({pack.emojis.length}个)</span>
                  </button>
                ))}
                {customPacks.length === 0 && (
                  <div className="text-center text-gray-400 py-8">
                    暂无表情包
                  </div>
                )}
              </div>
            )}
          </div>
        )}
      </div>
    </div>
  );
}

// 消息反应展示组件
interface MessageReactionsDisplayProps {
  messageId: number;
  initialReactions?: ReactionGroup[];
}

export function MessageReactionsDisplay({ messageId, initialReactions }: MessageReactionsDisplayProps) {
  const api = useApi();
  const [reactions, setReactions] = useState<ReactionGroup[]>(initialReactions || []);
  const [showPicker, setShowPicker] = useState(false);
  const [showDetail, setShowDetail] = useState(false);
  const [pickerPosition, setPickerPosition] = useState({ x: 0, y: 0 });
  const buttonRef = useRef<HTMLButtonElement>(null);

  // 加载反应详情
  const loadReactions = useCallback(async () => {
    try {
      const response = await api.getMessageReactionsDetail(messageId);
      if (response.data) {
        // 按表情分组
        const grouped: Record<string, ReactionGroup> = {};
        response.data.forEach((reaction) => {
          if (!grouped[reaction.emoji]) {
            grouped[reaction.emoji] = {
              emoji: reaction.emoji,
              count: 0,
              userNames: [],
              isSelf: false,
            };
          }
          grouped[reaction.emoji].count++;
          grouped[reaction.emoji].userNames.push(reaction.username || '未知用户');
          if (reaction.userId === 'me') {
            grouped[reaction.emoji].isSelf = true;
          }
        });
        setReactions(Object.values(grouped));
      }
    } catch (error) {
      console.error('Failed to load reactions:', error);
    }
  }, [api, messageId]);

  useEffect(() => {
    if (!initialReactions) {
      loadReactions();
    }
  }, [messageId, loadReactions, initialReactions]);

  // 添加反应
  const handleAddReaction = async (emoji: string) => {
    try {
      await api.addReaction(messageId, emoji);
      loadReactions();
    } catch (error) {
      console.error('Failed to add reaction:', error);
    }
  };

  // 移除反应
  const handleRemoveReaction = async (emoji: string) => {
    try {
      await api.removeReaction(messageId, emoji);
      loadReactions();
    } catch (error) {
      console.error('Failed to remove reaction:', error);
    }
  };

  // 打开表情选择器
  const openPicker = () => {
    if (buttonRef.current) {
      const rect = buttonRef.current.getBoundingClientRect();
      setPickerPosition({
        x: rect.left,
        y: rect.top - 10,
      });
    }
    setShowPicker(true);
  };

  return (
    <>
      {/* 反应列表 */}
      {reactions.length > 0 && (
        <div className="flex flex-wrap gap-1 mt-2">
          {reactions.map((reaction) => (
            <button
              key={reaction.emoji}
              onClick={() => {
                if (reaction.isSelf) {
                  handleRemoveReaction(reaction.emoji);
                } else {
                  // 显示反应详情
                  setShowDetail(true);
                }
              }}
              className={`flex items-center gap-1 px-2 py-1 rounded-full border transition-colors ${
                reaction.isSelf
                  ? 'bg-blue-100 border-blue-300 text-blue-700'
                  : 'bg-gray-50 border-gray-200 text-gray-700 hover:bg-gray-100'
              }`}
              title={reaction.userNames.slice(0, 5).join(', ') + (reaction.userNames.length > 5 ? ` 等${reaction.userNames.length}人` : '')}
            >
              <span className="text-lg">{reaction.emoji}</span>
              <span className="text-xs font-medium">{reaction.count}</span>
            </button>
          ))}

          {/* 添加反应按钮 */}
          <button
            ref={buttonRef}
            onClick={openPicker}
            className="w-7 h-7 flex items-center justify-center rounded-full bg-gray-100 hover:bg-gray-200 transition-colors"
          >
            <svg className="w-4 h-4 text-gray-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 4v16m8-8H4" />
            </svg>
          </button>
        </div>
      )}

      {/* 没有反应时显示添加按钮 */}
      {reactions.length === 0 && (
        <button
          ref={buttonRef}
          onClick={openPicker}
          className="mt-2 text-sm text-gray-400 hover:text-gray-600 flex items-center gap-1"
        >
          <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M14.828 14.828a4 4 0 01-5.656 0M9 10h.01M15 10h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
          </svg>
          添加反应
        </button>
      )}

      {/* 表情选择器 */}
      {showPicker && (
        <MessageReactionPicker
          messageId={messageId}
          onClose={() => setShowPicker(false)}
          onReactionSelect={handleAddReaction}
          position={pickerPosition}
        />
      )}

      {/* 反应详情弹窗 */}
      {showDetail && (
        <ReactionDetailModal
          messageId={messageId}
          onClose={() => setShowDetail(false)}
        />
      )}
    </>
  );
}

// 反应详情弹窗
interface ReactionDetailModalProps {
  messageId: number;
  onClose: () => void;
}

function ReactionDetailModal({ messageId, onClose }: ReactionDetailModalProps) {
  const api = useApi();
  const [reactions, setReactions] = useState<MessageReaction[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const loadDetail = async () => {
      try {
        const response = await api.getMessageReactionsDetail(messageId);
        if (response.data) {
          setReactions(response.data);
        }
      } catch (error) {
        console.error('Failed to load reaction detail:', error);
      } finally {
        setLoading(false);
      }
    };

    loadDetail();
  }, [api, messageId]);

  return (
    <div className="fixed inset-0 bg-black/50 z-50 flex items-center justify-center">
      <div className="bg-white rounded-2xl w-full max-w-md mx-4 max-h-96 flex flex-col">
        {/* 头部 */}
        <div className="flex items-center justify-between p-4 border-b">
          <h3 className="font-semibold">反应详情</h3>
          <button onClick={onClose} className="text-gray-400 hover:text-gray-600">
            <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>

        {/* 内容 */}
        <div className="flex-1 overflow-y-auto p-4">
          {loading ? (
            <div className="text-center text-gray-400 py-8">加载中...</div>
          ) : reactions.length === 0 ? (
            <div className="text-center text-gray-400 py-8">暂无反应</div>
          ) : (
            <div className="space-y-3">
              {/* 按表情分组显示 */}
              {Object.values(
                reactions.reduce((acc, reaction) => {
                  if (!acc[reaction.emoji]) {
                    acc[reaction.emoji] = { emoji: reaction.emoji, users: [] };
                  }
                  acc[reaction.emoji].users.push(reaction);
                  return acc;
                }, {} as Record<string, { emoji: string; users: MessageReaction[] }>)
              ).map((group) => (
                <div key={group.emoji} className="flex items-start gap-3">
                  <span className="text-2xl w-8 text-center">{group.emoji}</span>
                  <div className="flex-1">
                    {group.users.map((reaction) => (
                      <div
                        key={reaction.id}
                        className="flex items-center gap-2 py-1"
                      >
                        <img
                          src={reaction.userAvatar || '/default-avatar.png'}
                          alt={reaction.username}
                          className="w-6 h-6 rounded-full"
                        />
                        <span className="text-sm text-gray-700">{reaction.username}</span>
                      </div>
                    ))}
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
