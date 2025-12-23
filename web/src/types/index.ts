// API Response Types - matching backend schemas

export interface Feed {
  id: number
  url: string
  name: string
  category: string | null
  last_fetched: string | null
  unread_count: number
  fetch_error: string | null
}

export interface Article {
  id: number
  feed_id: number
  feed_name: string
  url: string
  title: string
  summary_short: string | null
  is_read: boolean
  is_bookmarked: boolean
  published_at: string
  created_at: string
}

export interface ArticleDetail extends Article {
  content: string | null
  summary_full: string | null
  key_points: string[] | null
  model_used: string | null
  author: string | null
  source_url: string | null
}

export interface ArticleGroup {
  name: string
  articles: Article[]
}

export interface StandaloneItem {
  id: number
  url: string | null
  title: string
  summary_short: string | null
  is_read: boolean
  is_bookmarked: boolean
  content_type: 'url' | 'pdf' | 'docx' | 'txt' | 'md' | 'html'
  file_name: string | null
  created_at: string
}

export interface StandaloneItemDetail extends StandaloneItem {
  content: string | null
  summary_full: string | null
  key_points: string[] | null
  model_used: string | null
}

export interface AppSettings {
  auto_summarize: boolean
  summary_model: 'fast' | 'smart'
  refresh_interval: number
  notifications_enabled: boolean
  items_per_page: number
}

export interface StatusResponse {
  status: string
  summarization_enabled: boolean
  provider: string | null
  model: string | null
  auth_enabled: boolean
}

export interface StatsResponse {
  total_feeds: number
  total_articles: number
  unread_articles: number
  bookmarked_articles: number
  summarized_articles: number
}

// Filter types for article list
export type FilterType =
  | 'all'
  | 'unread'
  | 'today'
  | 'bookmarked'
  | 'summarized'
  | { type: 'feed'; feedId: number }
  | { type: 'category'; category: string }

export type GroupBy = 'none' | 'date' | 'feed' | 'topic'

export type SortBy = 'date' | 'title' | 'feed'

// API key configuration stored in localStorage
export interface ApiKeyConfig {
  apiKey?: string  // Auth API key for backend access
  anthropicKey?: string
  openaiKey?: string
  googleKey?: string
  preferredProvider?: 'anthropic' | 'openai' | 'google'
  backendUrl: string
}
