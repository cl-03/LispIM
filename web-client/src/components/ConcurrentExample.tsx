/**
 * 并发功能使用示例组件
 *
 * 这个组件展示了如何使用 LispIM 的并发处理功能
 * 实际使用时可以根据需要选择性地集成到现有组件中
 */

import { useEffect, useState } from 'react';
import {
  useConcurrentMessageLoader,
  useConcurrentGroupMemberLoader,
  useConcurrentReadMarker,
  useConcurrentMessageSender,
  useBatchOperation,
} from '@/hooks/useConcurrentRequest';
import { RateLimiter, BatchProcessor, withTimeout, withRetry } from '@/utils/parallel';
import { getApiClient } from '@/utils/api-client';
import type { Conversation } from '@/types';

/**
 * 示例 1: 并发加载多个会话的消息
 */
export function ConversationListExample() {
  const [conversations, setConversations] = useState<Conversation[]>([]);
  const [loading, setLoading] = useState(false);
  const { loadMessagesConcurrently, cancelPending } = useConcurrentMessageLoader();

  useEffect(() => {
    return () => {
      // 组件卸载时取消待处理的请求
      cancelPending();
    };
  }, [cancelPending]);

  const loadConversations = async () => {
    setLoading(true);
    try {
      const api = getApiClient();
      const response = await api.getConversations();

      if (response.success && response.data) {
        const convs = response.data as unknown as Conversation[];
        setConversations(convs);

        // 并发加载所有会话的最新消息（最多 5 个并发）
        const conversationIds = convs.map((c) => c.id);
        await loadMessagesConcurrently(conversationIds, {
          limitPerConversation: 1,
          maxConcurrent: 5,
        });
      }
    } catch (error) {
      console.error('Failed to load conversations:', error);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div>
      <button onClick={loadConversations} disabled={loading}>
        {loading ? 'Loading...' : 'Load Conversations'}
      </button>
      <ul>
        {conversations.map((conv) => (
          <li key={conv.id}>{conv.name || `Conversation ${conv.id}`}</li>
        ))}
      </ul>
    </div>
  );
}

/**
 * 示例 2: 批量标记消息已读
 */
export function MarkAsReadExample() {
  const { markAsReadConcurrently } = useConcurrentReadMarker();

  const handleMarkAllAsRead = async (
    unreadConversations: Array<{ conversationId: number; messageIds: number[] }>
  ) => {
    // 并发标记所有会话为已读（最多 10 个并发）
    await markAsReadConcurrently(unreadConversations, {
      maxConcurrent: 10,
    });
  };

  return (
    <button onClick={() => handleMarkAllAsRead([
      { conversationId: 1, messageIds: [1, 2, 3] },
      { conversationId: 2, messageIds: [4, 5] },
      { conversationId: 3, messageIds: [6] },
    ])}>
      Mark All As Read
    </button>
  );
}

/**
 * 示例 3: 批量发送消息
 */
export function BatchSendMessageExample() {
  const [sending, setSending] = useState(false);
  const { sendMessagesConcurrently } = useConcurrentMessageSender();

  const handleBroadcastMessage = async (
    conversationIds: number[],
    content: string
  ) => {
    setSending(true);
    try {
      const messages = conversationIds.map((convId) => ({
        conversationId: convId,
        content,
        type: 'text' as const,
      }));

      // 并发发送消息到多个会话（最多 3 个并发，避免服务器压力）
      const results = await sendMessagesConcurrently(messages, {
        maxConcurrent: 3,
      });

      const successCount = results.filter((r) => r.success).length;
      console.log(`Sent ${successCount}/${conversationIds.length} messages`);
    } catch (error) {
      console.error('Failed to send messages:', error);
    } finally {
      setSending(false);
    }
  };

  return (
    <button
      onClick={() => handleBroadcastMessage([1, 2, 3, 4, 5], 'Hello everyone!')}
      disabled={sending}
    >
      {sending ? 'Sending...' : 'Broadcast Message'}
    </button>
  );
}

/**
 * 示例 4: 使用限流器
 */
export function RateLimitedExample() {
  const [loading, setLoading] = useState(false);
  // 创建限流器：每秒最多 10 个请求
  const rateLimiter = new RateLimiter({
    windowMs: 1000,
    maxRequests: 10,
  });

  const handleRateLimitedRequest = async () => {
    setLoading(true);
    try {
      const api = getApiClient();

      // 使用限流器发送请求
      const promises = Array.from({ length: 50 }, (_, i) =>
        rateLimiter.throttle(() =>
          api.get(`/api/v1/users/${i + 1}`)
        )
      );

      await Promise.all(promises);
      console.log('All requests completed with rate limiting');
    } catch (error) {
      console.error('Request failed:', error);
    } finally {
      setLoading(false);
    }
  };

  return (
    <button onClick={handleRateLimitedRequest} disabled={loading}>
      {loading ? 'Loading...' : 'Load 50 Users (Rate Limited)'}
    </button>
  );
}

/**
 * 示例 5: 使用批量处理器
 */
export function BatchProcessorExample() {
  const [processing, setProcessing] = useState(false);
  const [progress, setProgress] = useState(0);

  const handleBatchProcess = async () => {
    setProcessing(true);
    setProgress(0);

    const processor = new BatchProcessor<number, string>({
      batchSize: 10,
      batchDelay: 100, // 批次间延迟 100ms
      maxConcurrent: 3,
      onProgress: (processed, total) => {
        setProgress(Math.round((processed / total) * 100));
      },
      onError: (error: Error, _item: number, index: number) => {
        console.error(`Error processing item ${index}:`, error);
      },
    });

    const items = Array.from({ length: 100 }, (_, i) => i);

    const results = await processor.process(items, async (item) => {
      const api = getApiClient();
      const response = await api.get(`/api/v1/items/${item}`);
      return response.data as string;
    });

    console.log(`Processed ${results.length} items`);
    setProcessing(false);
  };

  return (
    <div>
      <button onClick={handleBatchProcess} disabled={processing}>
        {processing ? `Processing... ${progress}%` : 'Process 100 Items'}
      </button>
      {processing && <progress value={progress} max={100} />}
    </div>
  );
}

/**
 * 示例 6: 使用超时和重试
 */
export function RetryTimeoutExample() {
  const [loading, setLoading] = useState(false);
  const [result, setResult] = useState<string | null>(null);

  const handleRequestWithRetry = async () => {
    setLoading(true);
    try {
      const api = getApiClient();

      // 带重试和超时的请求
      const data = await withTimeout(
        () =>
          withRetry(() => api.get('/api/v1/slow-endpoint') as Promise<any>, {
            retries: 3,
            delay: 1000,
            backoff: 2,
            onRetry: (error: Error, attempt: number) => {
              console.log(`Retry attempt ${attempt}:`, error.message);
            },
          }),
        10000 // 10 秒超时
      );

      setResult(data as unknown as string);
    } catch (error) {
      console.error('Request failed after retries:', error);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div>
      <button onClick={handleRequestWithRetry} disabled={loading}>
        {loading ? 'Loading...' : 'Fetch with Retry & Timeout'}
      </button>
      {result && <div>Result: {result}</div>}
    </div>
  );
}

/**
 * 示例 7: 批量加载群组成员
 */
export function GroupMembersExample() {
  const [groupIds] = useState<number[]>([1, 2, 3, 4, 5]);
  const { loadMembersConcurrently } = useConcurrentGroupMemberLoader();
  const [members, setMembers] = useState<Map<number, any[]>>(new Map());
  const [loading, setLoading] = useState(false);

  const handleLoadMembers = async () => {
    setLoading(true);
    try {
      const results = await loadMembersConcurrently(groupIds, {
        maxConcurrent: 5,
      });
      setMembers(results);
    } catch (error) {
      console.error('Failed to load group members:', error);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div>
      <button onClick={handleLoadMembers} disabled={loading}>
        {loading ? 'Loading...' : 'Load Group Members'}
      </button>
      {Array.from(members.entries()).map(([groupId, members]) => (
        <div key={groupId}>
          <h4>Group {groupId}: {members.length} members</h4>
        </div>
      ))}
    </div>
  );
}

/**
 * 示例 8: 使用批量操作 Hook
 */
export function BatchOperationHookExample() {
  const { executeBatch } = useBatchOperation<string, any>();
  const [processing, setProcessing] = useState(false);

  const handleBatchOperation = async () => {
    setProcessing(true);
    try {
      const items = ['item1', 'item2', 'item3', 'item4', 'item5'];

      const results = await executeBatch(
        items,
        async (item) => {
          const api = getApiClient();
          return api.post('/api/v1/process', { item });
        },
        {
          maxConcurrent: 3,
          onError: (error, item, index) => {
            console.error(`Failed to process ${item} at index ${index}:`, error);
          },
        }
      );

      console.log('Batch operation completed:', results);
    } finally {
      setProcessing(false);
    }
  };

  return (
    <button onClick={handleBatchOperation} disabled={processing}>
      {processing ? 'Processing...' : 'Run Batch Operation'}
    </button>
  );
}

// Default export for backward compatibility
const ConcurrentExample = BatchOperationHookExample;
export default ConcurrentExample;
