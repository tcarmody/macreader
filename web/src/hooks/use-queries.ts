import { useQuery, useInfiniteQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import * as api from '@/api/client'
import type { FilterType, GroupBy, SortBy, Article, ArticleDetail, GroupedArticlesResponse } from '@/types'
import { useSummarizationPolling } from './use-polling'

// Query Keys
export const queryKeys = {
  status: ['status'] as const,
  authStatus: ['authStatus'] as const,
  stats: ['stats'] as const,
  settings: ['settings'] as const,
  feeds: ['feeds'] as const,
  articles: (filter: FilterType, sortBy: SortBy) => ['articles', filter, sortBy] as const,
  articlesGrouped: (groupBy: GroupBy) => ['articles', 'grouped', groupBy] as const,
  article: (id: number) => ['article', id] as const,
  articleChat: (id: number) => ['articleChat', id] as const,
  search: (query: string) => ['search', query] as const,
  library: (params?: { content_type?: string; bookmarked_only?: boolean }) =>
    ['library', params] as const,
  libraryItem: (id: number) => ['libraryItem', id] as const,
}

/**
 * Invalidate article-related queries: feeds (unread counts), articles list, and stats.
 * Use this after operations that affect article read state or counts.
 */
export function invalidateArticleRelated(queryClient: ReturnType<typeof useQueryClient>) {
  queryClient.invalidateQueries({ queryKey: queryKeys.feeds })
  queryClient.invalidateQueries({ queryKey: ['articles'] })
  queryClient.invalidateQueries({ queryKey: queryKeys.stats })
}

// Status & Settings
export function useStatus() {
  return useQuery({
    queryKey: queryKeys.status,
    queryFn: api.getStatus,
    staleTime: 30000, // 30 seconds
  })
}

export function useAuthStatus() {
  return useQuery({
    queryKey: queryKeys.authStatus,
    queryFn: api.getAuthStatus,
    staleTime: 30000,
    retry: false,  // Don't retry on 401
  })
}

export function useLogout() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: api.logout,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: queryKeys.authStatus })
      queryClient.invalidateQueries({ queryKey: queryKeys.status })
    },
  })
}

export function useStats() {
  return useQuery({
    queryKey: queryKeys.stats,
    queryFn: api.getStats,
    staleTime: 10000, // 10 seconds
  })
}

export function useSettings() {
  return useQuery({
    queryKey: queryKeys.settings,
    queryFn: api.getSettings,
  })
}

export function useUpdateSettings() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: api.updateSettings,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: queryKeys.settings })
    },
  })
}

// Feeds
export function useFeeds() {
  return useQuery({
    queryKey: queryKeys.feeds,
    queryFn: api.getFeeds,
    staleTime: 5000, // Reduced from 30s to 5s for faster updates
  })
}

export function useInvalidateFeeds() {
  const queryClient = useQueryClient()
  return () => {
    queryClient.invalidateQueries({ queryKey: queryKeys.feeds })
  }
}

export function useAddFeed() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: ({ url, name, category }: { url: string; name?: string; category?: string }) =>
      api.addFeed(url, name, category),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: queryKeys.feeds })
    },
  })
}

export function useDeleteFeed() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: api.deleteFeed,
    onSuccess: () => {
      invalidateArticleRelated(queryClient)
    },
  })
}

export function useUpdateFeed() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: ({ feedId, data }: { feedId: number; data: { name?: string; category?: string } }) =>
      api.updateFeed(feedId, data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: queryKeys.feeds })
    },
  })
}

export function useRefreshFeeds() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: api.refreshFeeds,
    onSuccess: () => {
      // Delay invalidation to allow backend to start fetching
      setTimeout(() => invalidateArticleRelated(queryClient), 2000)
    },
  })
}

export function useImportOpml() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: api.importOpml,
    onSuccess: () => {
      invalidateArticleRelated(queryClient)
    },
  })
}

export function useExportOpml() {
  return useMutation({
    mutationFn: api.exportOpml,
  })
}

export function useBulkDeleteFeeds() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: api.bulkDeleteFeeds,
    onSuccess: () => {
      invalidateArticleRelated(queryClient)
    },
  })
}

export function useRefreshSingleFeed() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: api.refreshSingleFeed,
    onSuccess: () => {
      // Delay invalidation to allow backend to start fetching
      setTimeout(() => invalidateArticleRelated(queryClient), 2000)
    },
  })
}

// Articles - paginated with infinite scroll
const ARTICLES_PAGE_SIZE = 50

export function useArticles(filter: FilterType, sortBy: SortBy = 'newest') {
  return useInfiniteQuery({
    queryKey: queryKeys.articles(filter, sortBy),
    queryFn: ({ pageParam = 0 }) => {
      const params: Parameters<typeof api.getArticles>[0] = {
        sort_by: sortBy,
        limit: ARTICLES_PAGE_SIZE,
        offset: pageParam,
      }

      if (filter === 'unread') {
        params.unread_only = true
      } else if (filter === 'bookmarked') {
        params.bookmarked_only = true
      } else if (filter === 'summarized') {
        params.summarized_only = true
      } else if (typeof filter === 'object' && filter.type === 'feed') {
        params.feed_id = filter.feedId
      }

      return api.getArticles(params)
    },
    initialPageParam: 0,
    getNextPageParam: (lastPage, allPages) => {
      // If last page has fewer items than page size, we've reached the end
      if (lastPage.length < ARTICLES_PAGE_SIZE) {
        return undefined
      }
      // Return the offset for the next page
      return allPages.flat().length
    },
    staleTime: 30000,
  })
}

export function useArticlesGrouped(groupBy: GroupBy) {
  return useQuery({
    queryKey: queryKeys.articlesGrouped(groupBy),
    queryFn: () => api.getArticlesGrouped(groupBy),
    enabled: groupBy !== 'none',
    staleTime: 30000,
  })
}

export function useArticle(articleId: number | null) {
  return useQuery({
    queryKey: queryKeys.article(articleId!),
    queryFn: () => api.getArticle(articleId!),
    enabled: articleId !== null,
  })
}

// Type for infinite query data structure
interface InfiniteArticleData {
  pages: Article[][]
  pageParams: number[]
}

export function useMarkArticleRead() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: ({ articleId, isRead }: { articleId: number; isRead: boolean }) =>
      api.markArticleRead(articleId, isRead),
    onMutate: async ({ articleId, isRead }) => {
      // Optimistically update article in all article list caches (infinite query structure)
      // This prevents the article from disappearing from unread view immediately
      queryClient.setQueriesData<InfiniteArticleData>(
        { queryKey: ['articles'] },
        (old) => {
          if (!old) return old
          return {
            ...old,
            pages: old.pages.map(page =>
              page.map(article =>
                article.id === articleId ? { ...article, is_read: isRead } : article
              )
            )
          }
        }
      )

      // Also update the individual article cache
      queryClient.setQueryData<ArticleDetail>(
        queryKeys.article(articleId),
        (old) => old ? { ...old, is_read: isRead } : old
      )
    },
    onSuccess: (_, { articleId }) => {
      // Refresh feeds and stats to update unread counts
      // But don't invalidate articles - let the optimistic update stand
      queryClient.invalidateQueries({ queryKey: queryKeys.article(articleId) })
      queryClient.invalidateQueries({ queryKey: queryKeys.feeds })
      queryClient.invalidateQueries({ queryKey: queryKeys.stats })
    },
    onError: (_, { articleId }) => {
      // On error, refetch to restore correct state
      queryClient.invalidateQueries({ queryKey: ['articles'] })
      queryClient.invalidateQueries({ queryKey: queryKeys.article(articleId) })
    },
  })
}

export function useToggleBookmark() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: api.toggleArticleBookmark,
    onSuccess: (_, articleId) => {
      queryClient.invalidateQueries({ queryKey: ['articles'] })
      queryClient.invalidateQueries({ queryKey: queryKeys.article(articleId) })
    },
  })
}

export function useMarkAllRead() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: api.markAllRead,
    onSuccess: () => {
      invalidateArticleRelated(queryClient)
    },
  })
}

export function useFetchContent() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: api.fetchArticleContent,
    onSuccess: (data) => {
      queryClient.setQueryData(queryKeys.article(data.id), data)
    },
  })
}

export function useSummarizeArticle() {
  const { startPolling } = useSummarizationPolling()
  return useMutation({
    mutationFn: api.summarizeArticle,
    onSuccess: (_, articleId) => {
      startPolling({
        fetchFn: () => api.getArticle(articleId),
        isComplete: (article) => !!article.summary_full,
        queryKey: queryKeys.article(articleId),
        invalidateKeys: [['articles']],
      })
    },
  })
}

export function useFindRelatedLinks() {
  const { startPolling } = useSummarizationPolling()
  return useMutation({
    mutationFn: api.findRelatedLinks,
    onSuccess: (_, articleId) => {
      startPolling({
        fetchFn: () => api.getArticle(articleId),
        // Stop polling when we get results OR an error
        isComplete: (article) =>
          (!!article.related_links && article.related_links.length > 0) ||
          !!article.related_links_error,
        queryKey: queryKeys.article(articleId),
        invalidateKeys: [['articles']],
      })
    },
  })
}

// Search
export function useSearch(query: string) {
  return useQuery({
    queryKey: queryKeys.search(query),
    queryFn: () => api.searchArticles(query),
    enabled: query.length >= 2,
    staleTime: 60000,
  })
}

// Library
export function useLibrary(params?: { content_type?: string; bookmarked_only?: boolean }) {
  return useQuery({
    queryKey: queryKeys.library(params),
    queryFn: () => api.getLibraryItems(params),
    staleTime: 30000,
  })
}

export function useLibraryItem(itemId: number | null) {
  return useQuery({
    queryKey: queryKeys.libraryItem(itemId!),
    queryFn: () => api.getLibraryItem(itemId!),
    enabled: itemId !== null,
  })
}

export function useAddLibraryUrl() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: api.addLibraryUrl,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['library'] })
    },
  })
}

export function useUploadLibraryFile() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: api.uploadLibraryFile,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['library'] })
    },
  })
}

export function useDeleteLibraryItem() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: api.deleteLibraryItem,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['library'] })
    },
  })
}

export function useSummarizeLibraryItem() {
  const { startPolling } = useSummarizationPolling()
  return useMutation({
    mutationFn: api.summarizeLibraryItem,
    onSuccess: (_, itemId) => {
      startPolling({
        fetchFn: () => api.getLibraryItem(itemId),
        isComplete: (item) => !!item.summary_full,
        queryKey: queryKeys.libraryItem(itemId),
        invalidateKeys: [['library']],
      })
    },
  })
}

// Chat hooks
export function useChatHistory(articleId: number | null) {
  return useQuery({
    queryKey: queryKeys.articleChat(articleId!),
    queryFn: () => api.getChatHistory(articleId!),
    enabled: articleId !== null,
    staleTime: 30000,
  })
}

export function useSendChatMessage() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: ({ articleId, message }: { articleId: number; message: string }) =>
      api.sendChatMessage(articleId, message),
    onSuccess: (newMessage, { articleId }) => {
      // Update chat history with the new messages
      queryClient.setQueryData<api.ChatHistoryResponse>(
        queryKeys.articleChat(articleId),
        (old) => {
          if (!old) {
            return {
              article_id: articleId,
              messages: [
                // Note: user message was already added by the service
                newMessage,
              ],
              has_chat: true,
            }
          }
          return {
            ...old,
            messages: [...old.messages, newMessage],
            has_chat: true,
          }
        }
      )
      // Also invalidate to get the full updated history (includes user message)
      queryClient.invalidateQueries({ queryKey: queryKeys.articleChat(articleId) })
    },
  })
}

export function useClearChatHistory() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: api.clearChatHistory,
    onSuccess: (_, articleId) => {
      // Clear the chat history in cache
      queryClient.setQueryData<api.ChatHistoryResponse>(
        queryKeys.articleChat(articleId),
        {
          article_id: articleId,
          messages: [],
          has_chat: false,
        }
      )
    },
  })
}
