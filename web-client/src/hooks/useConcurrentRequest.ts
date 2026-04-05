/**
 * LispIM React Hooks - Concurrent Request Utilities
 *
 * 提供优化并行处理能力的 React Hooks 和工具函数
 */

import { useCallback, useRef } from 'react';
import { getApiClient } from '@/utils/api-client';
import type { Message, GroupMember } from '@/types';

/**
 * 使用并发控制加载消息
 *
 * @example
 * const { loadMessagesConcurrently } = useConcurrentMessageLoader();
 * await loadMessagesConcurrently([1, 2, 3], 50);
 */
export function useConcurrentMessageLoader() {
  const abortControllerRef = useRef<AbortController | null>(null);

  const cancelPending = useCallback(() => {
    if (abortControllerRef.current) {
      abortControllerRef.current.abort();
    }
  }, []);

  const loadMessagesConcurrently = useCallback(
    async (
      conversationIds: number[],
      options?: {
        limitPerConversation?: number;
        maxConcurrent?: number;
        signal?: AbortSignal;
      }
    ): Promise<Map<number, Message[]>> => {
      cancelPending();

      const abortController = new AbortController();
      abortControllerRef.current = abortController;

      const signal = options?.signal || abortController.signal;
      const maxConcurrent = options?.maxConcurrent || 5;
      const limit = options?.limitPerConversation || 50;

      const api = getApiClient();
      const results = new Map<number, Message[]>();

      // 使用信号量控制并发数
      const semaphore = {
        count: 0,
        queue: Array<() => void>(),
        acquire: (): Promise<void> => {
          if (semaphore.count < maxConcurrent) {
            semaphore.count++;
            return Promise.resolve();
          }
          return new Promise(resolve => semaphore.queue.push(resolve));
        },
        release: (): void => {
          if (semaphore.queue.length > 0) {
            const next = semaphore.queue.shift();
            next?.();
          } else {
            semaphore.count--;
          }
        }
      };

      const promises = conversationIds.map(async (convId) => {
        await semaphore.acquire();
        try {
          const response = await api.getHistory(convId, { limit });
          if (response.success && response.data) {
            results.set(convId, response.data as unknown as Message[]);
          }
        } catch (error) {
          if (signal.aborted) {
            throw new Error('Request cancelled');
          }
          console.warn(`Failed to load messages for conversation ${convId}:`, error);
        } finally {
          semaphore.release();
        }
      });

      await Promise.all(promises);
      return results;
    },
    [cancelPending]
  );

  return {
    loadMessagesConcurrently,
    cancelPending
  };
}

/**
 * 使用并发控制加载群组成员
 */
export function useConcurrentGroupMemberLoader() {
  const loadMembersConcurrently = useCallback(
    async (
      groupIds: number[],
      options?: { maxConcurrent?: number }
    ): Promise<Map<number, GroupMember[]>> => {
      const maxConcurrent = options?.maxConcurrent || 5;
      const api = getApiClient();
      const results = new Map<number, GroupMember[]>();

      const semaphore = {
        count: 0,
        queue: Array<() => void>(),
        acquire: (): Promise<void> => {
          if (semaphore.count < maxConcurrent) {
            semaphore.count++;
            return Promise.resolve();
          }
          return new Promise(resolve => semaphore.queue.push(resolve));
        },
        release: (): void => {
          if (semaphore.queue.length > 0) {
            const next = semaphore.queue.shift();
            next?.();
          } else {
            semaphore.count--;
          }
        }
      };

      const promises = groupIds.map(async (groupId) => {
        await semaphore.acquire();
        try {
          const response = await api.getGroupMembers(groupId);
          if (response.success && response.data) {
            results.set(groupId, response.data as unknown as GroupMember[]);
          }
        } catch (error) {
          console.warn(`Failed to load members for group ${groupId}:`, error);
        } finally {
          semaphore.release();
        }
      });

      await Promise.all(promises);
      return results;
    },
    []
  );

  return { loadMembersConcurrently };
}

/**
 * 使用并发控制标记消息已读
 */
export function useConcurrentReadMarker() {
  const markAsReadConcurrently = useCallback(
    async (
      readMarkers: Array<{ conversationId: number; messageIds: number[] }>,
      options?: { maxConcurrent?: number }
    ): Promise<void> => {
      const maxConcurrent = options?.maxConcurrent || 10;
      const api = getApiClient();

      const semaphore = {
        count: 0,
        queue: Array<() => void>(),
        acquire: (): Promise<void> => {
          if (semaphore.count < maxConcurrent) {
            semaphore.count++;
            return Promise.resolve();
          }
          return new Promise(resolve => semaphore.queue.push(resolve));
        },
        release: (): void => {
          if (semaphore.queue.length > 0) {
            const next = semaphore.queue.shift();
            next?.();
          } else {
            semaphore.count--;
          }
        }
      };

      const promises = readMarkers.map(async ({ conversationId, messageIds }) => {
        await semaphore.acquire();
        try {
          await api.markAsRead(conversationId, messageIds);
        } catch (error) {
          console.warn(`Failed to mark read for conversation ${conversationId}:`, error);
        } finally {
          semaphore.release();
        }
      });

      await Promise.all(promises);
    },
    []
  );

  return { markAsReadConcurrently };
}

/**
 * 批量发送消息（带并发控制）
 */
export function useConcurrentMessageSender() {
  const sendMessagesConcurrently = useCallback(
    async (
      messages: Array<{
        conversationId: number;
        content: string;
        type?: 'text' | 'image' | 'file';
      }>,
      options?: { maxConcurrent?: number }
    ): Promise<Array<{ success: boolean; conversationId: number; messageId?: number }>> => {
      const maxConcurrent = options?.maxConcurrent || 3; // 消息发送保守一些
      const api = getApiClient();
      const results: Array<{ success: boolean; conversationId: number; messageId?: number }> = [];

      const semaphore = {
        count: 0,
        queue: Array<() => void>(),
        acquire: (): Promise<void> => {
          if (semaphore.count < maxConcurrent) {
            semaphore.count++;
            return Promise.resolve();
          }
          return new Promise(resolve => semaphore.queue.push(resolve));
        },
        release: (): void => {
          if (semaphore.queue.length > 0) {
            const next = semaphore.queue.shift();
            next?.();
          } else {
            semaphore.count--;
          }
        }
      };

      const promises = messages.map(async ({ conversationId, content, type = 'text' }) => {
        await semaphore.acquire();
        try {
          const response = await api.sendMessage(conversationId, { content, type });
          if (response.success && response.data) {
            results.push({
              success: true,
              conversationId,
              messageId: (response.data as any).id
            });
          } else {
            results.push({ success: false, conversationId });
          }
        } catch (error) {
          console.error('Send message error:', error);
          results.push({ success: false, conversationId });
        } finally {
          semaphore.release();
        }
      });

      await Promise.all(promises);
      return results;
    },
    []
  );

  return { sendMessagesConcurrently };
}

/**
 * 通用批量操作 Hook
 *
 * @example
 * const { executeBatch } = useBatchOperation();
 * const results = await executeBatch(
 *   items,
 *   (item) => api.post('/endpoint', item),
 *   { maxConcurrent: 5 }
 * );
 */
export function useBatchOperation<T, R>() {
  const executeBatch = useCallback(
    async (
      items: T[],
      operation: (item: T, index: number) => Promise<R>,
      options?: {
        maxConcurrent?: number;
        stopOnError?: boolean;
        onError?: (error: Error, item: T, index: number) => void;
      }
    ): Promise<R[]> => {
      const maxConcurrent = options?.maxConcurrent || 5;
      const stopOnError = options?.stopOnError ?? false;
      const results: R[] = [];
      const errors: Array<{ error: Error; item: T; index: number }> = [];

      const semaphore = {
        count: 0,
        queue: Array<() => void>(),
        acquire: (): Promise<void> => {
          if (semaphore.count < maxConcurrent) {
            semaphore.count++;
            return Promise.resolve();
          }
          return new Promise(resolve => semaphore.queue.push(resolve));
        },
        release: (): void => {
          if (semaphore.queue.length > 0) {
            const next = semaphore.queue.shift();
            next?.();
          } else {
            semaphore.count--;
          }
        }
      };

      const promises = items.map(async (item, index) => {
        await semaphore.acquire();
        try {
          const result = await operation(item, index);
          results.push(result);
          return result;
        } catch (error) {
          if (stopOnError) {
            throw error;
          }
          errors.push({ error: error as Error, item, index });
          options?.onError?.(error as Error, item, index);
          return undefined as R;
        } finally {
          semaphore.release();
        }
      });

      await Promise.all(promises);

      if (errors.length > 0 && !stopOnError) {
        console.warn(`Batch operation completed with ${errors.length} errors`);
      }

      return results;
    },
    []
  );

  return { executeBatch };
}

/**
 * 请求去重 Hook
 * 相同参数的请求只会执行一次，其他调用会等待结果
 */
export function useDeduplicatedRequest() {
  const pendingRequests = useRef<Map<string, Promise<any>>>(new Map());

  const deduplicatedRequest = useCallback(
    async <T>(
      key: string,
      requestFn: () => Promise<T>
    ): Promise<T> => {
      // 检查是否有相同的请求正在进行
      if (pendingRequests.current.has(key)) {
        return pendingRequests.current.get(key);
      }

      const promise = requestFn().finally(() => {
        pendingRequests.current.delete(key);
      });

      pendingRequests.current.set(key, promise);
      return promise;
    },
    []
  );

  const clearPending = useCallback(() => {
    pendingRequests.current.clear();
  }, []);

  return {
    deduplicatedRequest,
    clearPending
  };
}
