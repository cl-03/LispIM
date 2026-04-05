/**
 * useApi Hook
 *
 * 提供 API 客户端实例的 React Hook
 */

import { useMemo } from 'react';
import { getApiClient, createApiClient, ApiClient } from '@/utils/api-client';

// 全局 API 客户端实例
let globalApiClient: ApiClient | null = null;

/**
 * 初始化 API 客户端
 */
export function initializeApiClient(baseURL: string, token?: string): ApiClient {
  globalApiClient = createApiClient({
    baseURL,
    timeout: 30000,
    ...(token && { headers: { Authorization: `Bearer ${token}` } as Record<string, string> }),
  });
  return globalApiClient;
}

/**
 * 获取 API 客户端 Hook
 */
export function useApi(): ApiClient {
  const api = useMemo(() => {
    try {
      return getApiClient();
    } catch {
      // 如果客户端未初始化，返回一个默认配置的客户端
      if (!globalApiClient) {
        globalApiClient = createApiClient({
          baseURL: (import.meta as any).env?.VITE_API_URL || 'http://localhost:3001',
          timeout: 30000,
        });
      }
      return globalApiClient;
    }
  }, []);

  return api;
}

/**
 * 获取认证 Token Hook
 */
export function useAuthToken(): string | null {
  const api = useApi();
  return api.getToken() || null;
}

/**
 * 检查用户是否已认证 Hook
 */
export function useAuthenticated(): boolean {
  const api = useApi();
  return !!api.getToken();
}
