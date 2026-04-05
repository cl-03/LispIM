/**
 * MessageSearch Component
 *
 * 消息搜索组件 - 支持全局搜索和对话内搜索
 * 参考：Telegram 搜索、Discord 搜索、微信聊天记录搜索
 */

import React, { useState, useCallback, useEffect } from 'react';
import { useApi } from '../hooks/useApi';
import type { SearchResult, SearchOptions } from '../types';

interface MessageSearchProps {
  conversationId?: number; // 如果提供，则只在对话内搜索
  onMessageClick?: (messageId: number, conversationId: number) => void;
  onClose?: () => void;
}

interface SearchFilters {
  senderId?: string;
  messageType?: 'text' | 'image' | 'file' | 'link';
  startDate?: number;
  endDate?: number;
}

export function MessageSearch({ conversationId, onMessageClick, onClose }: MessageSearchProps) {
  const api = useApi();
  const [query, setQuery] = useState('');
  const [results, setResults] = useState<SearchResult[]>([]);
  const [loading, setLoading] = useState(false);
  const [offset, setOffset] = useState(0);
  const [hasMore, setHasMore] = useState(true);
  const [filters, setFilters] = useState<SearchFilters>({});
  const [showFilters, setShowFilters] = useState(false);

  // 防抖搜索
  const [debouncedQuery, setDebouncedQuery] = useState(query);

  useEffect(() => {
    const timer = setTimeout(() => {
      setDebouncedQuery(query);
    }, 300);

    return () => clearTimeout(timer);
  }, [query]);

  // 执行搜索
  const performSearch = useCallback(async (searchQuery: string, searchOffset: number) => {
    if (!searchQuery.trim()) {
      setResults([]);
      return;
    }

    setLoading(true);
    try {
      const options: SearchOptions = {
        query: searchQuery,
        conversationId,
        limit: 20,
        offset: searchOffset,
        ...filters,
      };

      const response = conversationId
        ? await api.searchInConversation(conversationId, searchQuery, { limit: 20, offset: searchOffset })
        : await api.searchMessages(options);

      if (response.data) {
        const newResults = searchOffset === 0 ? response.data : [...results, ...response.data];
        setResults(newResults);
        setHasMore(response.data.length === 20);
      }
    } catch (error) {
      console.error('Search failed:', error);
    } finally {
      setLoading(false);
    }
  }, [api, conversationId, filters, results]);

  useEffect(() => {
    if (debouncedQuery) {
      performSearch(debouncedQuery, 0);
    }
  }, [debouncedQuery, performSearch]);

  // 加载更多
  const loadMore = () => {
    if (!loading && hasMore) {
      performSearch(debouncedQuery, offset + 20);
    }
  };

  // 高亮关键词
  const highlightText = (text: string, keyword: string) => {
    if (!keyword.trim()) return text;

    const parts = text.split(new RegExp(`(${escapeRegExp(keyword)})`, 'gi'));
    return parts.map((part, i) =>
      part.toLowerCase() === keyword.toLowerCase() ? (
        <mark key={i} className="bg-yellow-200 text-gray-900 px-0.5 rounded">
          {part}
        </mark>
      ) : (
        part
      )
    );
  };

  const escapeRegExp = (string: string) => {
    return string.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  };

  // 格式化时间
  const formatTime = (timestamp: number) => {
    const date = new Date(timestamp);
    const now = new Date();
    const diff = now.getTime() - date.getTime();
    const days = Math.floor(diff / (1000 * 60 * 60 * 24));

    if (days === 0) {
      return date.toLocaleTimeString('zh-CN', { hour: '2-digit', minute: '2-digit' });
    } else if (days === 1) {
      return '昨天';
    } else if (days < 7) {
      return `${days}天前`;
    } else {
      return date.toLocaleDateString('zh-CN', { month: 'short', day: 'numeric' });
    }
  };

  // 消息类型图标
  const getMessageTypeIcon = (type: string) => {
    switch (type) {
      case 'image':
        return '🖼️';
      case 'file':
        return '📎';
      case 'link':
        return '🔗';
      default:
        return '💬';
    }
  };

  return (
    <div className="flex flex-col h-full bg-white">
      {/* 搜索栏 */}
      <div className="flex items-center gap-2 p-3 border-b border-gray-200">
        <div className="flex-1 relative">
          <input
            type="text"
            value={query}
            onChange={(e) => {
              setQuery(e.target.value);
              setOffset(0);
            }}
            placeholder={conversationId ? '搜索聊天记录...' : '搜索消息...'}
            className="w-full pl-4 pr-10 py-2 bg-gray-100 rounded-full text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
            autoFocus
          />
          {query && (
            <button
              onClick={() => {
                setQuery('');
                setResults([]);
              }}
              className="absolute right-3 top-1/2 -translate-y-1/2 text-gray-400 hover:text-gray-600"
            >
              ✕
            </button>
          )}
        </div>

        <button
          onClick={() => setShowFilters(!showFilters)}
          className={`p-2 rounded-full ${showFilters ? 'bg-blue-100 text-blue-600' : 'text-gray-500 hover:bg-gray-100'}`}
        >
          <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M3 4a1 1 0 011-1h16a1 1 0 011 1v2.586a1 1 0 01-.293.707l-6.414 6.414a1 1 0 00-.293.707V17l-4 4v-6.586a1 1 0 00-.293-.707L3.293 7.293A1 1 0 013 6.586V4z" />
          </svg>
        </button>

        {onClose && (
          <button
            onClick={onClose}
            className="p-2 text-gray-500 hover:text-gray-700"
          >
            关闭
          </button>
        )}
      </div>

      {/* 筛选器 */}
      {showFilters && (
        <div className="p-3 border-b border-gray-200 bg-gray-50">
          <div className="flex flex-wrap gap-2">
            <select
              value={filters.messageType || ''}
              onChange={(e) => {
                setFilters({ ...filters, messageType: e.target.value as any || undefined });
                setOffset(0);
              }}
              className="px-3 py-1.5 bg-white border border-gray-300 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
            >
              <option value="">所有类型</option>
              <option value="text">文本</option>
              <option value="image">图片</option>
              <option value="file">文件</option>
              <option value="link">链接</option>
            </select>

            <select
              value={filters.senderId || ''}
              onChange={(e) => {
                setFilters({ ...filters, senderId: e.target.value || undefined });
                setOffset(0);
              }}
              className="px-3 py-1.5 bg-white border border-gray-300 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
            >
              <option value="">所有发送者</option>
              {/* 可以添加发送者列表 */}
            </select>
          </div>
        </div>
      )}

      {/* 搜索结果 */}
      <div className="flex-1 overflow-y-auto">
        {!query && (
          <div className="flex flex-col items-center justify-center h-full text-gray-400">
            <svg className="w-16 h-16 mb-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
            </svg>
            <p>输入关键词搜索消息</p>
          </div>
        )}

        {loading && offset === 0 && (
          <div className="flex flex-col items-center justify-center h-full text-gray-400">
            <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-blue-500 mb-4"></div>
            <p>搜索中...</p>
          </div>
        )}

        {!loading && results.length === 0 && query && (
          <div className="flex flex-col items-center justify-center h-full text-gray-400">
            <svg className="w-16 h-16 mb-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M9.172 16.172a4 4 0 015.656 0M9 10h.01M15 10h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
            </svg>
            <p>未找到相关消息</p>
          </div>
        )}

        {!loading && results.length > 0 && (
          <div className="divide-y divide-gray-100">
            {results.map((result) => (
              <div
                key={result.messageId}
                onClick={() => onMessageClick?.(result.messageId, result.conversationId)}
                className="p-4 hover:bg-gray-50 cursor-pointer transition-colors"
              >
                <div className="flex items-start gap-3">
                  <span className="text-xl">{getMessageTypeIcon(result.content.split('\n')[0].startsWith('http') ? 'link' : 'text')}</span>

                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-2 mb-1">
                      {result.senderName && (
                        <span className="font-medium text-blue-600">{result.senderName}</span>
                      )}
                      {result.conversationName && conversationId === undefined && (
                        <span className="text-gray-400">in</span>
                      )}
                      {result.conversationName && conversationId === undefined && (
                        <span className="text-gray-600">{result.conversationName}</span>
                      )}
                      <span className="text-xs text-gray-400 ml-auto">
                        {formatTime(result.createdAt)}
                      </span>
                    </div>

                    <p className="text-gray-700 text-sm line-clamp-2">
                      {highlightText(result.content, query)}
                    </p>

                    {result.matchCount > 1 && (
                      <span className="text-xs text-gray-400 mt-1 inline-block">
                        共 {result.matchCount} 处匹配
                      </span>
                    )}
                  </div>
                </div>
              </div>
            ))}

            {loading && (
              <div className="p-4 text-center text-gray-400">
                加载中...
              </div>
            )}

            {!loading && hasMore && results.length > 0 && (
              <button
                onClick={loadMore}
                className="w-full p-3 text-center text-blue-600 hover:bg-gray-50 transition-colors"
              >
                加载更多
              </button>
            )}
          </div>
        )}
      </div>

      {/* 结果统计 */}
      {results.length > 0 && (
        <div className="px-4 py-2 border-t border-gray-200 text-xs text-gray-500 text-center">
          找到 {results.length} 条相关消息
        </div>
      )}
    </div>
  );
}
