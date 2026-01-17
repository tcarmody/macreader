import { useCallback, useRef } from 'react'
import { useQueryClient } from '@tanstack/react-query'

const POLL_INTERVAL_MS = 2000
const POLL_TIMEOUT_MS = 60000

interface PollOptions<T> {
  /** Function to fetch the latest data */
  fetchFn: () => Promise<T>
  /** Predicate to check if polling is complete */
  isComplete: (data: T) => boolean
  /** Query key to update with the final data */
  queryKey: readonly unknown[]
  /** Additional query keys to invalidate on completion */
  invalidateKeys?: readonly (readonly unknown[])[]
  /** Callback when polling completes successfully */
  onComplete?: (data: T) => void
}

/**
 * Hook for polling an async operation until completion.
 *
 * @example
 * ```tsx
 * const { startPolling, stopPolling } = useSummarizationPolling()
 *
 * // In mutation onSuccess:
 * startPolling({
 *   fetchFn: () => api.getArticle(articleId),
 *   isComplete: (article) => !!article.summary_full,
 *   queryKey: queryKeys.article(articleId),
 *   invalidateKeys: [['articles']],
 * })
 * ```
 */
export function useSummarizationPolling() {
  const queryClient = useQueryClient()
  const intervalsRef = useRef<Map<string, NodeJS.Timeout>>(new Map())
  const timeoutsRef = useRef<Map<string, NodeJS.Timeout>>(new Map())

  const stopPolling = useCallback((key: string) => {
    const interval = intervalsRef.current.get(key)
    const timeout = timeoutsRef.current.get(key)

    if (interval) {
      clearInterval(interval)
      intervalsRef.current.delete(key)
    }
    if (timeout) {
      clearTimeout(timeout)
      timeoutsRef.current.delete(key)
    }
  }, [])

  const startPolling = useCallback(<T>(options: PollOptions<T>) => {
    const { fetchFn, isComplete, queryKey, invalidateKeys, onComplete } = options
    const key = JSON.stringify(queryKey)

    // Stop any existing polling for this key
    stopPolling(key)

    const pollInterval = setInterval(async () => {
      try {
        const data = await fetchFn()
        if (isComplete(data)) {
          stopPolling(key)
          queryClient.setQueryData(queryKey, data)
          invalidateKeys?.forEach(invalidateKey => {
            queryClient.invalidateQueries({ queryKey: invalidateKey as unknown[] })
          })
          onComplete?.(data)
        }
      } catch {
        // Silently ignore polling errors - will retry on next interval
      }
    }, POLL_INTERVAL_MS)

    // Stop polling after timeout
    const timeoutId = setTimeout(() => stopPolling(key), POLL_TIMEOUT_MS)

    intervalsRef.current.set(key, pollInterval)
    timeoutsRef.current.set(key, timeoutId)
  }, [queryClient, stopPolling])

  return { startPolling, stopPolling }
}
