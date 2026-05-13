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
  brief: string | null
  key_points: string[] | null
  is_read: boolean
  is_bookmarked: boolean
  published_at: string
  created_at: string
  related_link_count: number
  has_chat: boolean
  is_featured: boolean
  featured_at: string | null
  featured_note: string | null
}

export interface RelatedLink {
  url: string
  title: string
  snippet: string
  domain: string
  published_date: string | null
  score: number | null
}

export interface ArticleDetail extends Article {
  content: string | null
  summary_full: string | null
  key_points: string[] | null
  model_used: string | null
  author: string | null
  source_url: string | null
  related_links: RelatedLink[] | null
  related_links_error: string | null
  promoted_to_composer: string | null
}

export interface ArticleGroup {
  key: string
  label: string
  articles: Article[]
}

export interface GroupedArticlesResponse {
  group_by: string
  groups: ArticleGroup[]
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
  related_links: RelatedLink[] | null
  related_links_error: string | null
  promoted_to_composer: string | null
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

// OAuth types
export interface OAuthUser {
  email: string
  name: string | null
  provider: 'google' | 'github'
  created_at: string
}

export interface OAuthStatus {
  enabled: boolean
  google_enabled: boolean
  github_enabled: boolean
  user: OAuthUser | null
  is_admin: boolean
}

export interface StatsResponse {
  total_feeds: number
  total_articles: number
  unread_articles: number
  bookmarked_articles: number
  summarized_articles: number
  featured_articles: number
}

export interface SavedSearch {
  id: number
  name: string
  query: string
  include_summaries: boolean
  last_used_at: string | null
  created_at: string
}

// Filter types for article list
export type FilterType =
  | 'all'
  | 'unread'
  | 'today'
  | 'bookmarked'
  | 'featured'
  | 'summarized'
  | { type: 'feed'; feedId: number }
  | { type: 'category'; category: string }
  | { type: 'topic'; label: string; articleIds: number[] }

export type GroupBy = 'none' | 'date' | 'feed' | 'topic'

// Reading statistics types
export interface ReadingActivityStats {
  articles_read: number
  total_reading_time_minutes: number
  avg_reading_time_minutes: number
  bookmarks_added: number
  read_by_day: Record<string, number>
  read_by_feed: Record<string, number>
}

export interface SummarizationStats {
  total_articles: number
  summarized_articles: number
  summarization_rate: number
  model_breakdown: Record<string, number>
  avg_per_day: number
  avg_per_week: number
  period_start: string | null
  period_end: string
}

export interface TopicInfo {
  label: string
  count: number
  article_ids?: number[] | null
}

export interface TopicTrend {
  topic_hash: string
  label: string
  total_count: number
  cluster_count: number
}

export interface TopicStats {
  current_topics: TopicInfo[]
  topic_trends: TopicTrend[]
  most_common: TopicInfo[]
}

export interface ReadingStatsResponse {
  period: { type: string; value: string }
  period_start: string
  period_end: string
  summarization: SummarizationStats
  topics: TopicStats
  reading: ReadingActivityStats
}

// Auto-digest response types
export interface DigestArticle {
  id: number
  title: string
  url: string
  source: string | null
  published_at: string | null
  brief: string
  story_group_size: number
}

export interface DigestSection {
  label: string
  articles: DigestArticle[]
}

export interface AutoDigestResponse {
  period: string
  period_start: string
  period_end: string
  title: string
  intro: string
  sections: DigestSection[]
  story_count: number
  word_count: number
  format: string
  raw: string
  cached: boolean
}

export type SortBy = 'newest' | 'oldest' | 'unread_first' | 'title_asc' | 'title_desc'

// Story groups (duplicate coverage detection)
export interface StoryGroupMember {
  id: number
  title: string
  url: string
  source: string | null
  published_at: string | null
  summary_short: string | null
  word_count: number | null
}

export interface StoryGroup {
  id: number
  label: string
  representative: StoryGroupMember
  members: StoryGroupMember[]
  member_count: number
  period_start: string
  period_end: string
}

// API key configuration stored in localStorage
export interface ApiKeyConfig {
  apiKey?: string  // Auth API key for backend access
  anthropicKey?: string
  openaiKey?: string
  googleKey?: string
  preferredProvider?: 'anthropic' | 'openai' | 'google'
  backendUrl: string
}
