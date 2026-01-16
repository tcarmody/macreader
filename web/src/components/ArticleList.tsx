import { useMemo } from 'react'
import {
  BookMarked,
  Circle,
  Sparkles,
  ExternalLink,
  Eye,
  EyeOff,
  ArrowUpDown,
  LayoutList,
  Calendar,
  Rss,
  Tags,
} from 'lucide-react'
import { cn } from '@/lib/utils'
import { formatDate, stripHtml } from '@/lib/utils'
import { ScrollArea } from '@/components/ui/scroll-area'
import { Skeleton } from '@/components/ui/skeleton'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { useAppStore } from '@/store/app-store'
import { useArticles, useArticlesGrouped, useSearch, useMarkArticleRead } from '@/hooks/use-queries'
import type { Article, SortBy, GroupBy } from '@/types'

const SORT_OPTIONS: { value: SortBy; label: string }[] = [
  { value: 'newest', label: 'Newest First' },
  { value: 'oldest', label: 'Oldest First' },
  { value: 'unread_first', label: 'Unread First' },
  { value: 'title_asc', label: 'Title A-Z' },
  { value: 'title_desc', label: 'Title Z-A' },
]

const GROUP_OPTIONS: { value: GroupBy; label: string; icon: typeof LayoutList }[] = [
  { value: 'none', label: 'List', icon: LayoutList },
  { value: 'date', label: 'Date', icon: Calendar },
  { value: 'feed', label: 'Feed', icon: Rss },
  { value: 'topic', label: 'Topic', icon: Tags },
]

export function ArticleList() {
  const {
    selectedFilter,
    selectedArticleId,
    setSelectedArticleId,
    searchQuery,
    isSearching,
    groupBy,
    setGroupBy,
    sortBy,
    setSortBy,
    hideRead,
    toggleHideRead,
  } = useAppStore()

  // Fetch flat articles with pagination when groupBy is 'none', otherwise fetch grouped
  const {
    data: articlesData,
    isLoading,
    fetchNextPage,
    hasNextPage,
    isFetchingNextPage,
  } = useArticles(selectedFilter, sortBy)
  const { data: groupedData, isLoading: groupedLoading } = useArticlesGrouped(groupBy)
  const { data: searchResults = [], isLoading: searchLoading } = useSearch(
    isSearching ? searchQuery : ''
  )
  const markRead = useMarkArticleRead()

  // Flatten paginated articles
  const articles = articlesData?.pages.flat() ?? []

  // When searching, always use flat search results
  // When groupBy !== 'none', use server-side grouped data
  // Otherwise use flat articles with client-side date grouping
  const allArticles = isSearching ? searchResults : articles

  // Apply hide read filter client-side (separate from the Unread filter)
  const displayArticles = hideRead
    ? allArticles.filter((a) => !a.is_read)
    : allArticles

  // Client-side date grouping for flat view (groupBy === 'none')
  const clientGroupedArticles = useMemo(() => {
    const groups: Record<string, Article[]> = {}

    displayArticles.forEach((article) => {
      const date = new Date(article.published_at)
      const today = new Date()
      const yesterday = new Date(today)
      yesterday.setDate(yesterday.getDate() - 1)

      let groupKey: string
      if (date.toDateString() === today.toDateString()) {
        groupKey = 'Today'
      } else if (date.toDateString() === yesterday.toDateString()) {
        groupKey = 'Yesterday'
      } else if (date > new Date(today.getTime() - 7 * 24 * 60 * 60 * 1000)) {
        groupKey = 'This Week'
      } else {
        groupKey = date.toLocaleDateString('en-US', { month: 'long', year: 'numeric' })
      }

      if (!groups[groupKey]) groups[groupKey] = []
      groups[groupKey].push(article)
    })

    return groups
  }, [displayArticles])

  // Server-side grouped data with hide read filter applied
  const serverGroups = useMemo(() => {
    if (!groupedData?.groups) return []
    if (!hideRead) return groupedData.groups

    // Filter out read articles from each group
    return groupedData.groups
      .map(group => ({
        ...group,
        articles: group.articles.filter(a => !a.is_read)
      }))
      .filter(group => group.articles.length > 0)
  }, [groupedData, hideRead])

  const handleSelectArticle = (article: Article) => {
    setSelectedArticleId(article.id)
    if (!article.is_read) {
      markRead.mutate({ articleId: article.id, isRead: true })
    }
  }

  // Use grouped loading when in grouped mode
  const isLoadingArticles = groupBy !== 'none' && !isSearching ? groupedLoading : isLoading

  if (isLoadingArticles || searchLoading) {
    return (
      <div className="w-80 border-r border-border flex flex-col bg-background">
        <div className="p-4 border-b border-border">
          <Skeleton className="h-6 w-32" />
        </div>
        <div className="flex-1 p-2 space-y-2">
          {Array.from({ length: 5 }).map((_, i) => (
            <div key={i} className="p-3 space-y-2">
              <Skeleton className="h-4 w-full" />
              <Skeleton className="h-3 w-3/4" />
              <Skeleton className="h-3 w-1/2" />
            </div>
          ))}
        </div>
      </div>
    )
  }

  // Calculate total count based on mode
  const totalCount = groupBy !== 'none' && !isSearching
    ? serverGroups.reduce((sum, g) => sum + g.articles.length, 0)
    : displayArticles.length

  const getFilterTitle = () => {
    if (isSearching) return `Search: "${searchQuery}"`
    if (typeof selectedFilter === 'string') {
      return {
        all: 'All Articles',
        unread: 'Unread',
        today: 'Today',
        bookmarked: 'Bookmarked',
        summarized: 'Summarized',
      }[selectedFilter]
    }
    return 'Articles'
  }

  return (
    <div className="w-80 border-r border-border flex flex-col bg-background">
      {/* Header */}
      <div className="p-4 border-b border-border flex flex-col gap-2">
        <div className="flex items-center justify-between">
          <h2 className="font-semibold">{getFilterTitle()}</h2>
          <div className="flex items-center gap-2">
            <Button
              variant="ghost"
              size="icon"
              className="h-7 w-7"
              onClick={toggleHideRead}
              title={hideRead ? 'Show read articles' : 'Hide read articles'}
            >
              {hideRead ? (
                <EyeOff className="h-4 w-4" />
              ) : (
                <Eye className="h-4 w-4" />
              )}
            </Button>
            <Badge variant="secondary">{totalCount}</Badge>
          </div>
        </div>

        {/* Group by picker */}
        <div className="flex gap-0.5 p-0.5 rounded-md border border-input bg-muted/30">
          {GROUP_OPTIONS.map((option) => {
            const Icon = option.icon
            return (
              <button
                key={option.value}
                onClick={() => setGroupBy(option.value)}
                className={cn(
                  "flex-1 flex items-center justify-center gap-1 px-2 py-1 text-xs rounded transition-colors",
                  groupBy === option.value
                    ? "bg-background text-foreground shadow-sm"
                    : "text-muted-foreground hover:text-foreground"
                )}
                title={`Group by ${option.label}`}
              >
                <Icon className="h-3 w-3" />
                <span className="hidden sm:inline">{option.label}</span>
              </button>
            )
          })}
        </div>

        {/* Sort dropdown - only show when not using server-side grouping */}
        {(groupBy === 'none' || isSearching) && (
          <div className="flex items-center gap-2">
            <ArrowUpDown className="h-3 w-3 text-muted-foreground" />
            <select
              value={sortBy}
              onChange={(e) => setSortBy(e.target.value as SortBy)}
              className="flex-1 h-7 px-2 text-xs rounded-md border border-input bg-background"
            >
              {SORT_OPTIONS.map((option) => (
                <option key={option.value} value={option.value}>
                  {option.label}
                </option>
              ))}
            </select>
          </div>
        )}
      </div>

      {/* Article List */}
      <ScrollArea className="flex-1">
        {totalCount === 0 ? (
          <div className="p-8 text-center text-muted-foreground">
            <p>No articles found</p>
          </div>
        ) : groupBy !== 'none' && !isSearching ? (
          // Server-side grouping (date, feed, or topic)
          <div className="p-2">
            {serverGroups.map((group) => (
              <div key={group.key} className="mb-4">
                <div className="px-2 py-1 text-xs font-semibold text-muted-foreground uppercase sticky top-0 bg-background">
                  {group.label}
                </div>
                <div className="space-y-1">
                  {group.articles.map((article) => (
                    <ArticleListItem
                      key={article.id}
                      article={article}
                      isSelected={selectedArticleId === article.id}
                      onSelect={() => handleSelectArticle(article)}
                    />
                  ))}
                </div>
              </div>
            ))}
          </div>
        ) : (
          // Flat view with client-side date grouping
          <div className="p-2">
            {Object.entries(clientGroupedArticles).map(([group, groupArticles]) => (
              <div key={group} className="mb-4">
                <div className="px-2 py-1 text-xs font-semibold text-muted-foreground uppercase sticky top-0 bg-background">
                  {group}
                </div>
                <div className="space-y-1">
                  {groupArticles.map((article) => (
                    <ArticleListItem
                      key={article.id}
                      article={article}
                      isSelected={selectedArticleId === article.id}
                      onSelect={() => handleSelectArticle(article)}
                    />
                  ))}
                </div>
              </div>
            ))}

            {/* Load More button for pagination */}
            {hasNextPage && !isSearching && groupBy === 'none' && (
              <div className="py-4 text-center">
                <Button
                  variant="outline"
                  size="sm"
                  onClick={() => fetchNextPage()}
                  disabled={isFetchingNextPage}
                >
                  {isFetchingNextPage ? 'Loading...' : 'Load More'}
                </Button>
              </div>
            )}
          </div>
        )}
      </ScrollArea>
    </div>
  )
}

interface ArticleListItemProps {
  article: Article
  isSelected: boolean
  onSelect: () => void
}

function ArticleListItem({ article, isSelected, onSelect }: ArticleListItemProps) {
  const summary = article.summary_short
    ? stripHtml(article.summary_short)
    : null

  return (
    <button
      onClick={onSelect}
      className={cn(
        "w-full text-left p-3 rounded-lg transition-colors",
        isSelected
          ? "bg-primary/10 border border-primary/20"
          : "hover:bg-muted",
        !article.is_read && "border-l-2 border-l-primary"
      )}
    >
      <div className="flex items-start gap-2">
        {!article.is_read && (
          <Circle className="h-2 w-2 mt-1.5 fill-primary text-primary flex-shrink-0" />
        )}
        <div className="flex-1 min-w-0">
          <h3 className={cn(
            "text-sm line-clamp-2",
            !article.is_read ? "font-semibold" : "font-medium"
          )}>
            {article.title}
          </h3>

          {summary && (
            <p className="text-xs text-muted-foreground mt-1 line-clamp-2">
              {summary}
            </p>
          )}

          <div className="flex items-center gap-2 mt-2 text-xs text-muted-foreground">
            <span className="truncate max-w-[120px]">{article.feed_name}</span>
            <span>·</span>
            <span>{formatDate(article.published_at)}</span>

            <div className="flex items-center gap-1 ml-auto">
              {article.is_bookmarked && (
                <BookMarked className="h-3 w-3 text-amber-500" />
              )}
              {article.summary_short && (
                <Sparkles className="h-3 w-3 text-purple-500" />
              )}
            </div>
          </div>
        </div>
      </div>
    </button>
  )
}

// Empty state for no selection
export function ArticleListEmpty() {
  return (
    <div className="flex-1 flex items-center justify-center text-muted-foreground">
      <div className="text-center">
        <ExternalLink className="h-12 w-12 mx-auto mb-4 opacity-20" />
        <p>Select an article to read</p>
      </div>
    </div>
  )
}
