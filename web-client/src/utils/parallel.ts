/**
 * LispIM Utils - Parallel Processing Utilities
 *
 * 提供高级并行处理能力的工具函数
 */


/**
 * 限流器配置
 */
export interface RateLimiterOptions {
  /** 时间窗口（毫秒） */
  windowMs: number;
  /** 时间窗口内最大请求数 */
  maxRequests: number;
}

/**
 * 限流器类
 *
 * @example
 * const limiter = new RateLimiter({ windowMs: 1000, maxRequests: 10 });
 * await limiter.throttle(() => fetch('/api/endpoint'));
 */
export class RateLimiter {
  private windowMs: number;
  private maxRequests: number;
  private timestamps: number[] = [];

  constructor(options: RateLimiterOptions) {
    this.windowMs = options.windowMs;
    this.maxRequests = options.maxRequests;
  }

  async throttle<T>(fn: () => Promise<T>): Promise<T> {
    await this.acquire();
    return fn();
  }

  private async acquire(): Promise<void> {
    const now = Date.now();

    // 移除窗口外的时间戳
    this.timestamps = this.timestamps.filter(
      (timestamp) => now - timestamp < this.windowMs
    );

    if (this.timestamps.length >= this.maxRequests) {
      // 计算需要等待的时间
      const oldestTimestamp = this.timestamps[0];
      const waitTime = this.windowMs - (now - oldestTimestamp);

      if (waitTime > 0) {
        await new Promise((resolve) => setTimeout(resolve, waitTime));
        return this.acquire();
      }
    }

    this.timestamps.push(now);
  }
}

/**
 * 批量处理器配置
 */
export interface BatchProcessorOptions<T> {
  /** 批次大小 */
  batchSize?: number;
  /** 批次间延迟（毫秒） */
  batchDelay?: number;
  /** 最大并发批次数量 */
  maxConcurrent?: number;
  /** 进度回调 */
  onProgress?: (processed: number, total: number) => void;
  /** 错误回调 */
  onError?: (error: Error, item: T, index: number) => void;
}

/**
 * 批量处理器
 *
 * @example
 * const processor = new BatchProcessor({ batchSize: 10, maxConcurrent: 3 });
 * const results = await processor.process(items, async (item) => {
 *   return await api.post('/endpoint', item);
 * });
 */
export class BatchProcessor<T, R> {
  private options: Required<BatchProcessorOptions<T>>;

  constructor(options: BatchProcessorOptions<T> = {}) {
    this.options = {
      batchSize: options.batchSize || 10,
      batchDelay: options.batchDelay || 0,
      maxConcurrent: options.maxConcurrent || 1,
      onProgress: options.onProgress || (() => {}),
      onError: options.onError || (() => {})
    };
  }

  async process(
    items: T[],
    processor: (item: T, index: number) => Promise<R>
  ): Promise<R[]> {
    const { batchSize, batchDelay, maxConcurrent, onProgress, onError } = this.options;
    const results: (R | undefined)[] = [];

    // 分割成批次
    const batches: T[][] = [];
    for (let i = 0; i < items.length; i += batchSize) {
      batches.push(items.slice(i, i + batchSize));
    }

    // 并发处理批次
    const batchPromises: Promise<void>[] = [];

    for (let batchIndex = 0; batchIndex < batches.length; batchIndex++) {
      const batch = batches[batchIndex];
      const batchStartIndex = batchIndex * batchSize;

      // 如果达到最大并发数，等待
      if (batchPromises.length >= maxConcurrent) {
        await Promise.race(batchPromises);
        // 移除已完成的 Promise
        const completedIndex = batchPromises.findIndex((p) => {
          const state = (p as any).state;
          return state === 'fulfilled' || state === 'rejected';
        });
        if (completedIndex !== -1) {
          batchPromises.splice(completedIndex, 1);
        }
      }

      // 批次间延迟
      if (batchIndex > 0 && batchDelay > 0) {
        await new Promise((resolve) => setTimeout(resolve, batchDelay));
      }

      // 处理当前批次
      const batchPromise = this.processBatch(
        batch,
        processor,
        batchStartIndex,
        onProgress,
        onError
      ).then((batchResults) => {
        batchResults.forEach((result, index) => {
          results[batchStartIndex + index] = result;
        });
      });

      batchPromises.push(batchPromise);
    }

    await Promise.all(batchPromises);
    onProgress(items.length, items.length);

    return results.filter((r): r is R => r !== undefined);
  }

  private async processBatch(
    batch: T[],
    processor: (item: T, index: number) => Promise<R>,
    startIndex: number,
    onProgress: (processed: number, total: number) => void,
    onError: (error: Error, item: T, index: number) => void
  ): Promise<(R | undefined)[]> {
    const results = await Promise.all(
      batch.map((item, index) =>
        processor(item, startIndex + index).catch((error) => {
          onError(error, item, startIndex + index);
          return undefined;
        })
      )
    );

    onProgress(startIndex + batch.length, startIndex + batch.length);
    return results;
  }
}

/**
 * 并行执行器
 *
 * @example
 * const executor = new ParallelExecutor({ maxConcurrent: 5 });
 * const results = await executor.execute(tasks, async (task) => {
 *   return await task.run();
 * });
 */
export class ParallelExecutor<T, R> {
  private maxConcurrent: number;

  constructor(maxConcurrent: number = 5) {
    this.maxConcurrent = maxConcurrent;
  }

  async execute(
    items: T[],
    executor: (item: T, index: number, signal: AbortSignal) => Promise<R>
  ): Promise<R[]> {
    const results: (R | undefined)[] = [];
    const abortController = new AbortController();
    const maxConcurrent = this.maxConcurrent;

    const semaphore = {
      count: 0,
      queue: Array<() => void>(),
      acquire: (): Promise<void> => {
        if (maxConcurrent > 0 && semaphore.count < maxConcurrent) {
          semaphore.count++;
          return Promise.resolve();
        }
        return new Promise((resolve) => semaphore.queue.push(resolve));
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
        const result = await executor(item, index, abortController.signal);
        results.push(result);
        return result;
      } catch (error) {
        if (abortController.signal.aborted) {
          throw error;
        }
        throw error;
      } finally {
        semaphore.release();
      }
    });

    await Promise.all(promises);
    return results.filter((r): r is R => r !== undefined);
  }

  cancel(): void {
    // 可以实现取消逻辑
  }
}

/**
 * 请求池
 * 管理一组可重用的请求槽位
 */
export class RequestPool {
  private maxConcurrent: number;
  private running: number = 0;
  private queue: Array<{
    fn: () => Promise<any>;
    resolve: (value: any) => void;
    reject: (reason: any) => void;
  }> = [];

  constructor(maxConcurrent: number = 10) {
    this.maxConcurrent = maxConcurrent;
  }

  async execute<T>(fn: () => Promise<T>): Promise<T> {
    if (this.running < this.maxConcurrent) {
      return this._execute(fn);
    }

    return new Promise<T>((resolve, reject) => {
      this.queue.push({ fn, resolve, reject });
    });
  }

  private async _execute<T>(fn: () => Promise<T>): Promise<T> {
    this.running++;
    try {
      return await fn();
    } finally {
      this.running--;
      this.processQueue();
    }
  }

  private processQueue(): void {
    if (this.queue.length === 0 || this.running >= this.maxConcurrent) {
      return;
    }

    const next = this.queue.shift()!;
    this._execute(next.fn).then(next.resolve).catch(next.reject);
  }

  getRunningCount(): number {
    return this.running;
  }

  getQueuedCount(): number {
    return this.queue.length;
  }
}

/**
 * 防抖函数（支持立即执行）
 */
export function debounce<T extends (...args: any[]) => any>(
  fn: T,
  wait: number,
  options: { immediate?: boolean } = {}
): (...args: Parameters<T>) => void {
  let timeout: ReturnType<typeof setTimeout> | null = null;

  return function (this: any, ...args: Parameters<T>) {
    const callNow = options.immediate && !timeout;

    if (timeout) {
      clearTimeout(timeout);
    }

    timeout = setTimeout(() => {
      timeout = null;
      if (!options.immediate) {
        fn.apply(this, args);
      }
    }, wait);

    if (callNow) {
      fn.apply(this, args);
    }
  };
}

/**
 * 节流函数
 */
export function throttle<T extends (...args: any[]) => any>(
  fn: T,
  limit: number,
  options: { leading?: boolean; trailing?: boolean } = { leading: true, trailing: true }
): (...args: Parameters<T>) => void {
  let inThrottle = false;
  let lastArgs: Parameters<T> | null = null;
  let timeout: ReturnType<typeof setTimeout> | null = null;

  return function (this: any, ...args: Parameters<T>) {
    if (!inThrottle) {
      inThrottle = true;
      if (options.leading) {
        fn.apply(this, args);
      }

      if (options.trailing) {
        if (timeout) {
          clearTimeout(timeout);
        }
        timeout = setTimeout(() => {
          inThrottle = false;
          if (lastArgs) {
            fn.apply(this, lastArgs);
            lastArgs = null;
          }
        }, limit);
      } else {
        setTimeout(() => {
          inThrottle = false;
        }, limit);
      }
    } else if (options.trailing) {
      lastArgs = args;
    }
  };
}

/**
 * 重试处理器
 *
 * @example
 * const result = await withRetry(
 *   () => fetch('/api/endpoint'),
 *   { retries: 3, delay: 1000 }
 * );
 */
export async function withRetry<T>(
  fn: () => Promise<T>,
  options: {
    retries?: number;
    delay?: number;
    backoff?: number;
    onRetry?: (error: Error, attempt: number) => void;
  } = {}
): Promise<T> {
  const {
    retries = 3,
    delay = 1000,
    backoff = 2,
    onRetry
  } = options;

  let lastError: Error;

  for (let attempt = 0; attempt <= retries; attempt++) {
    try {
      return await fn();
    } catch (error) {
      lastError = error as Error;

      if (attempt < retries) {
        onRetry?.(lastError, attempt + 1);
        const waitTime = delay * Math.pow(backoff, attempt);
        await new Promise((resolve) => setTimeout(resolve, waitTime));
      }
    }
  }

  throw lastError;
}

/**
 * 超时处理器
 *
 * @example
 * const result = await withTimeout(
 *   () => fetch('/api/endpoint'),
 *   5000
 * );
 */
export async function withTimeout<T>(
  fn: () => Promise<T>,
  timeout: number
): Promise<T> {
  const abortController = new AbortController();

  const timeoutPromise = new Promise<never>((_, reject) => {
    setTimeout(() => {
      abortController.abort();
      reject(new Error(`Timeout after ${timeout}ms`));
    }, timeout);
  });

  const fnPromise = fn();

  return Promise.race([fnPromise, timeoutPromise]);
}
