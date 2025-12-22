import { useMemo } from 'react'
import {
  BookMarked,
  Circle,
  Sparkles,
  ExternalLink,
} from 'lucide-react'
import { cn } from '@/lib/utils'
import { formatDate, stripHtml } from '@/lib/utils'
import { ScrollArea } from '@/components/ui/scroll-area'
import { Skeleton } from '@/components/ui/skeleton'
import { Badge } from '@/components/ui/badge'
import { useAppStore } from '@/store/app-store'
import { useArticles, useSearch, useMarkArticleRead } from '@/hooks/use-queries'
import type { Article } from '@/types'

export function ArticleList() {
  const {
    selectedFilter,
    selectedArticleId,
    setSelectedArticleId,
    searchQuery,
    isSearching,
  } = useAppStore()

  const { data: articles = [], isLoading } = useArticles(selectedFilter)
  const { data: searchResults = [], isLoading: searchLoading } = useSearch(
    isSearching ? searchQuery : ''
  )
  const markRead = useMarkArticleRead()

  const displayArticles = isSearching ? searchResults : articles

  // Group articles by date
  const groupedArticles = useMemo(() => {
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

  const handleSelectArticle = (article: Article) => {
    setSelectedArticleId(article.id)
    if (!article.is_read) {
      markRead.mutate({ articleId: article.id, isRead: true })
    }
  }

  if (isLoading || searchLoading) {
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
      <div className="p-4 border-b border-border flex items-center justify-between">
        <h2 className="font-semibold">{getFilterTitle()}</h2>
        <Badge variant="secondary">{displayArticles.length}</Badge>
      </div>

      {/* Article List */}
      <ScrollArea className="flex-1">
        {displayArticles.length === 0 ? (
          <div className="p-8 text-center text-muted-foreground">
            <p>No articles found</p>
          </div>
        ) : (
          <div className="p-2">
            {Object.entries(groupedArticles).map(([group, groupArticles]) => (
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
