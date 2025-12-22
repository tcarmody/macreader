import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import * as api from '@/api/client'
import type { FilterType, GroupBy } from '@/types'

// Query Keys
export const queryKeys = {
  status: ['status'] as const,
  stats: ['stats'] as const,
  settings: ['settings'] as const,
  feeds: ['feeds'] as const,
  articles: (filter: FilterType) => ['articles', filter] as const,
  articlesGrouped: (groupBy: GroupBy) => ['articles', 'grouped', groupBy] as const,
  article: (id: number) => ['article', id] as const,
  search: (query: string) => ['search', query] as const,
  library: (params?: { content_type?: string; bookmarked_only?: boolean }) =>
    ['library', params] as const,
  libraryItem: (id: number) => ['libraryItem', id] as const,
}

// Status & Settings
export function useStatus() {
  return useQuery({
    queryKey: queryKeys.status,
    queryFn: api.getStatus,
    staleTime: 30000, // 30 seconds
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
    staleTime: 30000,
  })
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
      queryClient.invalidateQueries({ queryKey: queryKeys.feeds })
      queryClient.invalidateQueries({ queryKey: ['articles'] })
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
      setTimeout(() => {
        queryClient.invalidateQueries({ queryKey: queryKeys.feeds })
        queryClient.invalidateQueries({ queryKey: ['articles'] })
        queryClient.invalidateQueries({ queryKey: queryKeys.stats })
      }, 2000)
    },
  })
}

export function useImportOpml() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: api.importOpml,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: queryKeys.feeds })
      queryClient.invalidateQueries({ queryKey: ['articles'] })
      queryClient.invalidateQueries({ queryKey: queryKeys.stats })
    },
  })
}

export function useExportOpml() {
  return useMutation({
    mutationFn: api.exportOpml,
  })
}

// Articles
export function useArticles(filter: FilterType) {
  return useQuery({
    queryKey: queryKeys.articles(filter),
    queryFn: () => {
      const params: Parameters<typeof api.getArticles>[0] = {}

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

export function useMarkArticleRead() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: ({ articleId, isRead }: { articleId: number; isRead: boolean }) =>
      api.markArticleRead(articleId, isRead),
    onSuccess: (_, { articleId }) => {
      queryClient.invalidateQueries({ queryKey: ['articles'] })
      queryClient.invalidateQueries({ queryKey: queryKeys.article(articleId) })
      queryClient.invalidateQueries({ queryKey: queryKeys.feeds })
      queryClient.invalidateQueries({ queryKey: queryKeys.stats })
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
      queryClient.invalidateQueries({ queryKey: ['articles'] })
      queryClient.invalidateQueries({ queryKey: queryKeys.feeds })
      queryClient.invalidateQueries({ queryKey: queryKeys.stats })
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
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: api.summarizeArticle,
    onSuccess: (_, articleId) => {
      // Poll for completion
      const pollInterval = setInterval(async () => {
        const article = await api.getArticle(articleId)
        if (article.summary_full) {
          clearInterval(pollInterval)
          queryClient.setQueryData(queryKeys.article(articleId), article)
          queryClient.invalidateQueries({ queryKey: ['articles'] })
        }
      }, 2000)

      // Stop polling after 60 seconds
      setTimeout(() => clearInterval(pollInterval), 60000)
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
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: api.summarizeLibraryItem,
    onSuccess: (_, itemId) => {
      // Poll for completion
      const pollInterval = setInterval(async () => {
        const item = await api.getLibraryItem(itemId)
        if (item.summary_full) {
          clearInterval(pollInterval)
          queryClient.setQueryData(queryKeys.libraryItem(itemId), item)
          queryClient.invalidateQueries({ queryKey: ['library'] })
        }
      }, 2000)

      setTimeout(() => clearInterval(pollInterval), 60000)
    },
  })
}
