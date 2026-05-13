import type {
  Feed,
  Article,
  ArticleDetail,
  AutoDigestResponse,
  GroupedArticlesResponse,
  StandaloneItem,
  StandaloneItemDetail,
  AppSettings,
  StatusResponse,
  StatsResponse,
  GroupBy,
  ApiKeyConfig,
  OAuthStatus,
  ReadingStatsResponse,
  StoryGroup,
  SavedSearch,
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

  // OAuth token from localStorage (workaround for third-party cookie blocking)
  const authToken = localStorage.getItem('authToken')
  if (authToken) {
    headers['Authorization'] = `Bearer ${authToken}`
  }

  // Auth API key for backend access
  if (config.apiKey) {
    headers['X-API-Key'] = config.apiKey
  }

  // Pass LLM API keys via headers for the backend to use
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
    credentials: 'include',  // Include cookies for OAuth session
    headers: {
      ...getHeaders(),
      ...options.headers,
    },
  })

  if (!response.ok) {
    const error = await response.json().catch(() => ({ detail: 'Request failed' }))
    // Handle various error response formats
    const message = typeof error.detail === 'string'
      ? error.detail
      : typeof error.message === 'string'
        ? error.message
        : `HTTP ${response.status}`

    // Create error with status code for auth handling
    const err = new Error(message) as Error & { status?: number }
    err.status = response.status
    throw err
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

export async function getCurrentTopics(): Promise<import('@/types').TopicInfo[]> {
  return fetchApi('/statistics/topics/current')
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

export async function addFeed(url: string, name?: string, _category?: string): Promise<Feed> {
  return fetchApi('/feeds', {
    method: 'POST',
    body: JSON.stringify({ url, name }),
  })
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

export interface OPMLImportResult {
  url: string
  name: string | null
  success: boolean
  error?: string
  feed_id?: number
}

export interface OPMLImportResponse {
  total: number
  imported: number
  skipped: number
  failed: number
  results: OPMLImportResult[]
}

export async function importOpml(opmlContent: string): Promise<OPMLImportResponse> {
  return fetchApi('/feeds/import-opml', {
    method: 'POST',
    body: JSON.stringify({ opml_content: opmlContent }),
  })
}

export async function exportOpml(): Promise<{ opml: string; feed_count: number }> {
  return fetchApi('/feeds/export-opml')
}

export async function bulkDeleteFeeds(feedIds: number[]): Promise<{ deleted: number }> {
  return fetchApi('/feeds/bulk/delete', {
    method: 'POST',
    body: JSON.stringify({ feed_ids: feedIds }),
  })
}

export async function refreshSingleFeed(feedId: number): Promise<{ message: string }> {
  return fetchApi(`/feeds/${feedId}/refresh`, { method: 'POST' })
}

// Articles
export async function getArticles(params: {
  feed_id?: number
  unread_only?: boolean
  bookmarked_only?: boolean
  featured_only?: boolean
  summarized_only?: boolean
  hide_duplicates?: boolean
  sort_by?: string
  limit?: number
  offset?: number
}): Promise<Article[]> {
  const searchParams = new URLSearchParams()
  if (params.feed_id) searchParams.append('feed_id', params.feed_id.toString())
  if (params.unread_only) searchParams.append('unread_only', 'true')
  if (params.bookmarked_only) searchParams.append('bookmarked_only', 'true')
  if (params.featured_only) searchParams.append('featured_only', 'true')
  if (params.summarized_only) searchParams.append('summarized_only', 'true')
  if (params.hide_duplicates) searchParams.append('hide_duplicates', 'true')
  if (params.sort_by) searchParams.append('sort_by', params.sort_by)
  if (params.limit) searchParams.append('limit', params.limit.toString())
  if (params.offset) searchParams.append('offset', params.offset.toString())

  return fetchApi(`/articles?${searchParams}`)
}

export async function getArticlesGrouped(groupBy: GroupBy): Promise<GroupedArticlesResponse> {
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

export async function featureArticle(
  articleId: number,
  note: string | null
): Promise<ArticleDetail> {
  return fetchApi(`/articles/${articleId}/feature`, {
    method: 'POST',
    body: JSON.stringify({ note }),
  })
}

export async function unfeatureArticle(
  articleId: number
): Promise<ArticleDetail> {
  return fetchApi(`/articles/${articleId}/feature`, { method: 'DELETE' })
}

export async function markAllRead(): Promise<{ success: boolean; count: number }> {
  return fetchApi('/articles/all/read', { method: 'POST' })
}

export async function archiveOldArticles(
  days: number
): Promise<{ success: boolean; archived_count: number; days: number }> {
  return fetchApi(`/articles/archive?days=${days}`, { method: 'POST' })
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

export async function extractFromHtml(
  articleId: number,
  html: string,
  url?: string
): Promise<ArticleDetail> {
  return fetchApi(`/articles/${articleId}/extract-from-html`, {
    method: 'POST',
    body: JSON.stringify({ html, url }),
  })
}

export async function summarizeArticle(
  articleId: number
): Promise<{ success: boolean; message: string }> {
  return fetchApi(`/articles/${articleId}/summarize`, { method: 'POST' })
}

export async function findRelatedLinks(
  articleId: number
): Promise<{ success: boolean; message: string }> {
  return fetchApi(`/articles/${articleId}/related`, { method: 'POST' })
}

export interface PromoteResponse {
  success: boolean
  composer_id: string
  composer_url: string
  already_existed: boolean
}

export async function promoteArticleToComposer(
  articleId: number
): Promise<PromoteResponse> {
  return fetchApi(`/articles/${articleId}/promote`, { method: 'POST' })
}

// Search
export async function searchArticles(query: string, includeSummaries: boolean = true): Promise<Article[]> {
  const params = new URLSearchParams({ q: query })
  if (!includeSummaries) params.append('include_summaries', 'false')
  return fetchApi(`/search?${params}`)
}

// Saved Searches
export async function getSavedSearches(): Promise<SavedSearch[]> {
  return fetchApi('/searches/saved')
}

export async function createSavedSearch(name: string, query: string, includeSummaries: boolean): Promise<SavedSearch> {
  return fetchApi('/searches/saved', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ name, query, include_summaries: includeSummaries }),
  })
}

export async function deleteSavedSearch(id: number): Promise<void> {
  await fetchApi(`/searches/saved/${id}`, { method: 'DELETE' })
}

export async function touchSavedSearch(id: number): Promise<void> {
  await fetchApi(`/searches/saved/${id}/use`, { method: 'POST' })
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
  const response = await fetchApi<{ items: StandaloneItem[]; total: number }>(
    `/standalone${query ? `?${query}` : ''}`
  )
  return response.items
}

export async function getLibraryItem(itemId: number): Promise<StandaloneItemDetail> {
  return fetchApi(`/standalone/${itemId}`)
}

export async function addLibraryUrl(url: string): Promise<StandaloneItem> {
  return fetchApi('/standalone/url', {
    method: 'POST',
    body: JSON.stringify({ url }),
  })
}

export async function uploadLibraryFile(file: File): Promise<StandaloneItem> {
  const formData = new FormData()
  formData.append('file', file)

  const config = getApiConfig()
  const headers: HeadersInit = {}

  // OAuth token from localStorage (workaround for third-party cookie blocking)
  const authToken = localStorage.getItem('authToken')
  if (authToken) {
    headers['Authorization'] = `Bearer ${authToken}`
  }

  // Include auth API key for file uploads
  if (config.apiKey) {
    headers['X-API-Key'] = config.apiKey
  }

  const response = await fetch(`${config.backendUrl}/standalone/upload`, {
    method: 'POST',
    credentials: 'include',  // Include cookies for OAuth session
    headers,
    body: formData,
  })

  if (!response.ok) {
    const error = await response.json().catch(() => ({ detail: 'Upload failed' }))
    throw new Error(error.detail || 'Failed to upload file')
  }

  return response.json()
}

export async function deleteLibraryItem(itemId: number): Promise<void> {
  await fetchApi(`/standalone/${itemId}`, { method: 'DELETE' })
}

export async function toggleLibraryItemRead(
  itemId: number,
  isRead: boolean = true
): Promise<{ success: boolean; is_read: boolean }> {
  return fetchApi(`/standalone/${itemId}/read?is_read=${isRead}`, { method: 'POST' })
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

export async function findRelatedLinksForLibraryItem(
  itemId: number
): Promise<{ success: boolean; message: string }> {
  return fetchApi(`/standalone/${itemId}/related`, { method: 'POST' })
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

// Chat API
export interface ChatMessage {
  id: number
  role: 'user' | 'assistant'
  content: string
  model_used: string | null
  created_at: string
}

export interface ChatHistoryResponse {
  article_id: number
  messages: ChatMessage[]
  has_chat: boolean
}

export async function getChatHistory(articleId: number): Promise<ChatHistoryResponse> {
  return fetchApi(`/articles/${articleId}/chat`)
}

export async function sendChatMessage(
  articleId: number,
  message: string
): Promise<ChatMessage> {
  return fetchApi(`/articles/${articleId}/chat`, {
    method: 'POST',
    body: JSON.stringify({ message }),
  })
}

export async function clearChatHistory(
  articleId: number
): Promise<{ success: boolean; deleted: boolean; message: string }> {
  return fetchApi(`/articles/${articleId}/chat`, { method: 'DELETE' })
}

// Story Groups
export async function getStoryGroups(params: {
  since?: string
  min_size?: number
  refresh?: boolean
} = {}): Promise<StoryGroup[]> {
  const searchParams = new URLSearchParams()
  if (params.since) searchParams.append('since', params.since)
  if (params.min_size) searchParams.append('min_size', params.min_size.toString())
  if (params.refresh) searchParams.append('refresh', 'true')
  const query = searchParams.toString()
  return fetchApi(`/digest/story-groups${query ? `?${query}` : ''}`)
}

// Reading Statistics
export async function getReadingStats(params: {
  period_type?: string
  period_value?: string
} = {}): Promise<ReadingStatsResponse> {
  const searchParams = new URLSearchParams()
  if (params.period_type) searchParams.append('period_type', params.period_type)
  if (params.period_value) searchParams.append('period_value', params.period_value)
  const query = searchParams.toString()
  return fetchApi(`/statistics/reading-stats${query ? `?${query}` : ''}`)
}

// Auto-Digest
export interface AutoDigestParams {
  period?: 'today' | 'week'
  tone?: 'neutral' | 'opinionated' | 'analytical'
  brief_length?: 'sentence' | 'short' | 'paragraph'
  max_stories?: number
  refresh?: boolean
}

export async function getAutoDigest(params: AutoDigestParams = {}): Promise<AutoDigestResponse> {
  const searchParams = new URLSearchParams()
  if (params.period) searchParams.append('period', params.period)
  if (params.tone) searchParams.append('tone', params.tone)
  if (params.brief_length) searchParams.append('brief_length', params.brief_length)
  if (params.max_stories) searchParams.append('max_stories', params.max_stories.toString())
  if (params.refresh) searchParams.append('refresh', 'true')
  const query = searchParams.toString()
  return fetchApi(`/digest/auto${query ? `?${query}` : ''}`)
}

// OAuth Authentication
export async function getAuthStatus(): Promise<OAuthStatus> {
  const config = getApiConfig()
  const headers: HeadersInit = {}

  // Include auth token if available
  const authToken = localStorage.getItem('authToken')
  if (authToken) {
    headers['Authorization'] = `Bearer ${authToken}`
  }

  const response = await fetch(`${config.backendUrl}/auth/status`, {
    credentials: 'include',  // Include cookies for session
    headers,
  })
  if (!response.ok) {
    throw new Error('Failed to get auth status')
  }
  return response.json()
}

export function getLoginUrl(provider: 'google' | 'github'): string {
  const config = getApiConfig()
  return `${config.backendUrl}/auth/login/${provider}`
}

export async function logout(): Promise<void> {
  const config = getApiConfig()
  // Clear local auth token
  localStorage.removeItem('authToken')
  await fetch(`${config.backendUrl}/auth/logout`, {
    method: 'POST',
    credentials: 'include',
  })
}
