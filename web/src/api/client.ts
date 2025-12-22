import type {
  Feed,
  Article,
  ArticleDetail,
  ArticleGroup,
  StandaloneItem,
  StandaloneItemDetail,
  AppSettings,
  StatusResponse,
  StatsResponse,
  GroupBy,
  ApiKeyConfig,
} from '@/types'

// Get API configuration from localStorage
function getApiConfig(): ApiKeyConfig {
  const stored = localStorage.getItem('apiConfig')
  if (stored) {
    return JSON.parse(stored)
  }
  // Default to local development
  return {
    backendUrl: import.meta.env.DEV ? '/api' : (import.meta.env.VITE_API_URL || ''),
  }
}

// Build headers with API keys
function getHeaders(): HeadersInit {
  const config = getApiConfig()
  const headers: HeadersInit = {
    'Content-Type': 'application/json',
  }

  // Pass API keys via headers for the backend to use
  if (config.anthropicKey) {
    headers['X-Anthropic-Key'] = config.anthropicKey
  }
  if (config.openaiKey) {
    headers['X-OpenAI-Key'] = config.openaiKey
  }
  if (config.googleKey) {
    headers['X-Google-Key'] = config.googleKey
  }
  if (config.preferredProvider) {
    headers['X-Preferred-Provider'] = config.preferredProvider
  }

  return headers
}

async function fetchApi<T>(
  endpoint: string,
  options: RequestInit = {}
): Promise<T> {
  const config = getApiConfig()
  const url = `${config.backendUrl}${endpoint}`

  const response = await fetch(url, {
    ...options,
    headers: {
      ...getHeaders(),
      ...options.headers,
    },
  })

  if (!response.ok) {
    const error = await response.json().catch(() => ({ detail: 'Request failed' }))
    throw new Error(error.detail || `HTTP ${response.status}`)
  }

  return response.json()
}

// Status & Settings
export async function getStatus(): Promise<StatusResponse> {
  return fetchApi('/status')
}

export async function getStats(): Promise<StatsResponse> {
  return fetchApi('/stats')
}

export async function getSettings(): Promise<AppSettings> {
  return fetchApi('/settings')
}

export async function updateSettings(settings: Partial<AppSettings>): Promise<AppSettings> {
  return fetchApi('/settings', {
    method: 'PUT',
    body: JSON.stringify(settings),
  })
}

// Feeds
export async function getFeeds(): Promise<Feed[]> {
  return fetchApi('/feeds')
}

export async function addFeed(url: string, name?: string, category?: string): Promise<Feed> {
  const params = new URLSearchParams({ url })
  if (name) params.append('name', name)
  if (category) params.append('category', category)

  return fetchApi(`/feeds?${params}`, { method: 'POST' })
}

export async function deleteFeed(feedId: number): Promise<void> {
  await fetchApi(`/feeds/${feedId}`, { method: 'DELETE' })
}

export async function updateFeed(
  feedId: number,
  data: { name?: string; category?: string }
): Promise<Feed> {
  return fetchApi(`/feeds/${feedId}`, {
    method: 'PUT',
    body: JSON.stringify(data),
  })
}

export async function refreshFeeds(): Promise<{ message: string }> {
  return fetchApi('/feeds/refresh', { method: 'POST' })
}

export async function refreshFeed(feedId: number): Promise<{ message: string }> {
  return fetchApi(`/feeds/${feedId}/refresh`, { method: 'POST' })
}

export async function importOpml(file: File): Promise<{ imported: number; failed: number }> {
  const formData = new FormData()
  formData.append('file', file)

  const config = getApiConfig()
  const response = await fetch(`${config.backendUrl}/feeds/import-opml`, {
    method: 'POST',
    body: formData,
  })

  if (!response.ok) {
    throw new Error('Failed to import OPML')
  }

  return response.json()
}

export async function exportOpml(): Promise<Blob> {
  const config = getApiConfig()
  const response = await fetch(`${config.backendUrl}/feeds/export-opml`, {
    headers: getHeaders(),
  })

  if (!response.ok) {
    throw new Error('Failed to export OPML')
  }

  return response.blob()
}

// Articles
export async function getArticles(params: {
  feed_id?: number
  unread_only?: boolean
  bookmarked_only?: boolean
  summarized_only?: boolean
  limit?: number
  offset?: number
}): Promise<Article[]> {
  const searchParams = new URLSearchParams()
  if (params.feed_id) searchParams.append('feed_id', params.feed_id.toString())
  if (params.unread_only) searchParams.append('unread_only', 'true')
  if (params.bookmarked_only) searchParams.append('bookmarked_only', 'true')
  if (params.summarized_only) searchParams.append('summarized_only', 'true')
  if (params.limit) searchParams.append('limit', params.limit.toString())
  if (params.offset) searchParams.append('offset', params.offset.toString())

  return fetchApi(`/articles?${searchParams}`)
}

export async function getArticlesGrouped(groupBy: GroupBy): Promise<ArticleGroup[]> {
  return fetchApi(`/articles/grouped?group_by=${groupBy}`)
}

export async function getArticle(articleId: number): Promise<ArticleDetail> {
  return fetchApi(`/articles/${articleId}`)
}

export async function markArticleRead(
  articleId: number,
  isRead: boolean
): Promise<{ success: boolean; is_read: boolean }> {
  return fetchApi(`/articles/${articleId}/read?is_read=${isRead}`, {
    method: 'POST',
  })
}

export async function toggleArticleBookmark(
  articleId: number
): Promise<{ success: boolean; is_bookmarked: boolean }> {
  return fetchApi(`/articles/${articleId}/bookmark`, { method: 'POST' })
}

export async function markAllRead(): Promise<{ success: boolean; count: number }> {
  return fetchApi('/articles/all/read', { method: 'POST' })
}

export async function markFeedRead(
  feedId: number
): Promise<{ success: boolean; count: number }> {
  return fetchApi(`/articles/feed/${feedId}/read`, { method: 'POST' })
}

export async function fetchArticleContent(
  articleId: number
): Promise<ArticleDetail> {
  return fetchApi(`/articles/${articleId}/fetch-content`, { method: 'POST' })
}

export async function summarizeArticle(
  articleId: number
): Promise<{ success: boolean; message: string }> {
  return fetchApi(`/articles/${articleId}/summarize`, { method: 'POST' })
}

// Search
export async function searchArticles(query: string): Promise<Article[]> {
  return fetchApi(`/search?q=${encodeURIComponent(query)}`)
}

// Library (Standalone Items)
export async function getLibraryItems(params?: {
  content_type?: string
  bookmarked_only?: boolean
}): Promise<StandaloneItem[]> {
  const searchParams = new URLSearchParams()
  if (params?.content_type) searchParams.append('content_type', params.content_type)
  if (params?.bookmarked_only) searchParams.append('bookmarked_only', 'true')

  const query = searchParams.toString()
  return fetchApi(`/standalone${query ? `?${query}` : ''}`)
}

export async function getLibraryItem(itemId: number): Promise<StandaloneItemDetail> {
  return fetchApi(`/standalone/${itemId}`)
}

export async function addLibraryUrl(url: string): Promise<StandaloneItem> {
  return fetchApi(`/standalone/url?url=${encodeURIComponent(url)}`, {
    method: 'POST',
  })
}

export async function uploadLibraryFile(file: File): Promise<StandaloneItem> {
  const formData = new FormData()
  formData.append('file', file)

  const config = getApiConfig()
  const response = await fetch(`${config.backendUrl}/standalone/upload`, {
    method: 'POST',
    body: formData,
  })

  if (!response.ok) {
    throw new Error('Failed to upload file')
  }

  return response.json()
}

export async function deleteLibraryItem(itemId: number): Promise<void> {
  await fetchApi(`/standalone/${itemId}`, { method: 'DELETE' })
}

export async function toggleLibraryItemRead(
  itemId: number
): Promise<{ success: boolean; is_read: boolean }> {
  return fetchApi(`/standalone/${itemId}/read`, { method: 'POST' })
}

export async function toggleLibraryItemBookmark(
  itemId: number
): Promise<{ success: boolean; is_bookmarked: boolean }> {
  return fetchApi(`/standalone/${itemId}/bookmark`, { method: 'POST' })
}

export async function summarizeLibraryItem(
  itemId: number
): Promise<{ success: boolean; message: string }> {
  return fetchApi(`/standalone/${itemId}/summarize`, { method: 'POST' })
}

// Batch Summarization
export async function batchSummarize(
  urls: string[]
): Promise<{ results: Array<{ url: string; success: boolean; error?: string }> }> {
  return fetchApi('/summarize/batch', {
    method: 'POST',
    body: JSON.stringify({ urls }),
  })
}
