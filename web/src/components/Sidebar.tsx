import { useState, useMemo, useEffect } from 'react'
import {
  Newspaper,
  BookMarked,
  Clock,
  Inbox,
  Sparkles,
  Library,
  Settings,
  Plus,
  RefreshCw,
  ChevronDown,
  ChevronRight,
  Rss,
  FolderOpen,
  Search,
  Menu,
  Mail,
  ListFilter,
  Info,
  LayoutList,
  BarChart2,
  Tags,
  Pin,
  X,
  Keyboard,
} from 'lucide-react'
import { cn } from '@/lib/utils'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { ScrollArea } from '@/components/ui/scroll-area'
import { Separator } from '@/components/ui/separator'
import { Badge } from '@/components/ui/badge'
import { Tooltip } from '@/components/ui/tooltip'
import { BadgePulse } from '@/components/ui/badge-pulse'
import { SmartTooltip } from '@/components/ui/smart-tooltip'
import { CoachMark } from '@/components/ui/coach-mark'
import { Dialog } from '@/components/ui/dialog'
import { useAppStore } from '@/store/app-store'
import {
  useFeeds, useRefreshFeeds, useStats, useAuthStatus, useTopics,
  useSavedSearches, useCreateSavedSearch, useDeleteSavedSearch, useTouchSavedSearch,
} from '@/hooks/use-queries'
import type { Feed, FilterType } from '@/types'

interface SidebarProps {
  onOpenSettings: () => void
  onAddFeed: () => void
  onManageFeeds: () => void
}

export function Sidebar({ onOpenSettings, onAddFeed, onManageFeeds }: SidebarProps) {
  const {
    selectedFilter,
    setSelectedFilter,
    currentView,
    setCurrentView,
    sidebarCollapsed,
    setSidebarCollapsed,
    searchQuery,
    setSearchQuery,
    setIsSearching,
    searchIncludeSummaries,
    hasCompletedInitialSetup,
    setHasCompletedInitialSetup,
    featureUsage,
  } = useAppStore()

  const { data: feeds = [], isLoading: feedsLoading } = useFeeds()
  const { data: stats } = useStats()
  const { data: topics = [] } = useTopics()
  const { data: authStatus } = useAuthStatus()
  const { data: savedSearches = [] } = useSavedSearches()
  const createSavedSearch = useCreateSavedSearch()
  const deleteSavedSearch = useDeleteSavedSearch()
  const touchSavedSearch = useTouchSavedSearch()
  const refreshFeeds = useRefreshFeeds()
  const isAdmin = authStatus?.is_admin ?? true // default true for backwards compat

  // Mark initial setup complete once the user has feeds
  useEffect(() => {
    if (!hasCompletedInitialSetup && feeds.length > 0) {
      setHasCompletedInitialSetup(true)
    }
  }, [feeds.length, hasCompletedInitialSetup, setHasCompletedInitialSetup])

  // Separate newsletter feeds from RSS feeds
  const { rssFeeds, newsletterFeeds } = useMemo(() => {
    const rss: Feed[] = []
    const newsletters: Feed[] = []

    for (const feed of feeds) {
      if (feed.url.startsWith('newsletter://')) {
        newsletters.push(feed)
      } else {
        rss.push(feed)
      }
    }

    return { rssFeeds: rss, newsletterFeeds: newsletters.sort((a, b) => a.name.localeCompare(b.name)) }
  }, [feeds])

  // Group RSS feeds by category (excluding newsletter feeds)
  const feedsByCategory = useMemo(() => {
    return rssFeeds.reduce((acc, feed) => {
      const category = feed.category || 'Uncategorized'
      if (!acc[category]) acc[category] = []
      acc[category].push(feed)
      return acc
    }, {} as Record<string, Feed[]>)
  }, [rssFeeds])

  const categories = Object.keys(feedsByCategory).sort()

  // For new users, collapse all categories by default. For returning users, expand all.
  const [collapsedCategories, setCollapsedCategories] = useState<Set<string>>(() =>
    !hasCompletedInitialSetup ? new Set(categories) : new Set()
  )
  const [collapsedNewsletters, setCollapsedNewsletters] = useState(false)
  const [collapsedTopics, setCollapsedTopics] = useState(true)
  const [collapsedSavedSearches, setCollapsedSavedSearches] = useState(true)
  const [shortcutsOpen, setShortcutsOpen] = useState(false)

  const isSearchAlreadySaved = savedSearches.some(
    (s) => s.query === searchQuery.trim() && s.include_summaries === searchIncludeSummaries
  )

  // Rotating search placeholders for discoverability
  const searchPlaceholders = [
    "Search articles... (Press '/' to focus)",
    "Try searching by author, title, or content",
    "Search across all your feeds",
    "Find articles by keyword",
  ]
  const [searchPlaceholder, setSearchPlaceholder] = useState(searchPlaceholders[0])

  useEffect(() => {
    let index = 0
    const interval = setInterval(() => {
      index = (index + 1) % searchPlaceholders.length
      setSearchPlaceholder(searchPlaceholders[index])
    }, 5000) // Change every 5 seconds

    return () => clearInterval(interval)
  }, [])

  // Calculate newsletter unread count
  const newsletterUnreadCount = useMemo(() => {
    return newsletterFeeds.reduce((sum, f) => sum + f.unread_count, 0)
  }, [newsletterFeeds])

  const toggleCategory = (category: string) => {
    const newCollapsed = new Set(collapsedCategories)
    if (newCollapsed.has(category)) {
      newCollapsed.delete(category)
    } else {
      newCollapsed.add(category)
    }
    setCollapsedCategories(newCollapsed)
  }

  const filterItems: Array<{ filter: FilterType; label: string; icon: React.ElementType; count?: number }> = [
    { filter: 'all', label: 'All Articles', icon: Inbox, count: stats?.total_articles },
    { filter: 'unread', label: 'Unread', icon: Newspaper, count: stats?.unread_articles },
    { filter: 'today', label: 'Today', icon: Clock },
    { filter: 'bookmarked', label: 'Bookmarked', icon: BookMarked, count: stats?.bookmarked_articles },
    { filter: 'summarized', label: 'Summarized', icon: Sparkles, count: stats?.summarized_articles },
  ]

  const isFilterSelected = (filter: FilterType) => {
    if (typeof selectedFilter === 'string' && typeof filter === 'string') {
      return selectedFilter === filter
    }
    return false
  }

  const isTopicSelected = (label: string) =>
    typeof selectedFilter === 'object' &&
    selectedFilter.type === 'topic' &&
    selectedFilter.label === label

  const handleSearch = (e: React.FormEvent) => {
    e.preventDefault()
    if (searchQuery.trim()) {
      setIsSearching(true)
    }
  }

  if (sidebarCollapsed) {
    return (
      <div className="w-12 border-r border-border flex flex-col items-center py-2 bg-card">
        <Button
          variant="ghost"
          size="icon"
          onClick={() => setSidebarCollapsed(false)}
          className="mb-4"
        >
          <Menu className="h-4 w-4" />
        </Button>
        <div className="flex flex-col gap-1">
          {filterItems.slice(0, 3).map(({ filter, icon: Icon }) => (
            <Button
              key={typeof filter === 'string' ? filter : filter.type}
              variant={isFilterSelected(filter) ? 'secondary' : 'ghost'}
              size="icon"
              onClick={() => {
                setCurrentView('feeds')
                setSelectedFilter(filter)
              }}
            >
              <Icon className="h-4 w-4" />
            </Button>
          ))}
        </div>
      </div>
    )
  }

  return (
    <div className="w-64 border-r border-border flex flex-col bg-card">
      {/* Header */}
      <div className="p-4 flex items-center justify-between">
        <h1 className="font-semibold text-lg">Data Points</h1>
        <div className="flex gap-1">
          <Button
            variant="ghost"
            size="icon"
            onClick={() => refreshFeeds.mutate()}
            disabled={refreshFeeds.isPending}
            title="Refresh all feeds"
          >
            <RefreshCw className={cn("h-4 w-4", refreshFeeds.isPending && "animate-spin")} />
          </Button>
          <Button
            variant="ghost"
            size="icon"
            onClick={() => setSidebarCollapsed(true)}
          >
            <Menu className="h-4 w-4" />
          </Button>
        </div>
      </div>

      {/* Search */}
      <div className="px-4 pb-2">
        <form onSubmit={handleSearch}>
          <SmartTooltip
            hintId="search-tip"
            title="Full-text search"
            body="Search across article titles, content, and AI summaries. Press '/' to focus instantly."
            side="bottom"
          >
          <div className="relative">
            <Search className="absolute left-2 top-2.5 h-4 w-4 text-muted-foreground" />
            <Input
              placeholder={searchPlaceholder}
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              className={cn("pl-8 h-9", searchQuery.length >= 2 && "pr-8")}
            />
            {searchQuery.length >= 2 && (
              <button
                type="button"
                title={isSearchAlreadySaved ? "Already pinned" : "Pin this search"}
                disabled={isSearchAlreadySaved || createSavedSearch.isPending}
                onClick={() => createSavedSearch.mutate({
                  name: searchQuery.trim(),
                  query: searchQuery.trim(),
                  includeSummaries: searchIncludeSummaries,
                })}
                className={cn(
                  "absolute right-2 top-2.5 h-4 w-4 transition-colors",
                  isSearchAlreadySaved
                    ? "text-primary"
                    : "text-muted-foreground hover:text-foreground"
                )}
              >
                <Pin className="h-4 w-4" />
              </button>
            )}
          </div>
          </SmartTooltip>
        </form>
      </div>

      <ScrollArea className="flex-1">
        {/* View Toggle */}
        <div className="px-2 py-2 flex gap-1">
          <Button
            variant={currentView === 'feeds' ? 'secondary' : 'ghost'}
            size="sm"
            className="flex-1"
            onClick={() => setCurrentView('feeds')}
          >
            <Rss className="h-4 w-4 mr-1" />
            Feeds
          </Button>
          <Tooltip
            content="Save web pages, PDFs, and documents for later reading"
            side="bottom"
          >
            <Button
              variant={currentView === 'library' ? 'secondary' : 'ghost'}
              size="sm"
              className="flex-1 relative"
              onClick={() => setCurrentView('library')}
            >
              <Library className="h-4 w-4 mr-1" />
              Library
              <Info className="h-2.5 w-2.5 ml-1 opacity-50" />
              {!featureUsage.hasUsedLibrary && (
                <span className="absolute -top-0.5 -right-0.5">
                  <BadgePulse />
                </span>
              )}
            </Button>
          </Tooltip>
          <Tooltip
            content="AI-assembled daily or weekly digest of top stories"
            side="bottom"
          >
            <Button
              variant={currentView === 'digest' ? 'secondary' : 'ghost'}
              size="sm"
              className="flex-1"
              onClick={() => setCurrentView('digest')}
            >
              <LayoutList className="h-4 w-4 mr-1" />
              Digest
            </Button>
          </Tooltip>
          <Tooltip
            content="Reading statistics and topic trends"
            side="bottom"
          >
            <Button
              variant={currentView === 'stats' ? 'secondary' : 'ghost'}
              size="sm"
              className="flex-1"
              onClick={() => setCurrentView('stats')}
            >
              <BarChart2 className="h-4 w-4 mr-1" />
              Stats
            </Button>
          </Tooltip>
        </div>

        <Separator className="my-2" />

        {/* Newsletters Section - always visible, just below Library */}
        {newsletterFeeds.length > 0 && (
          <div className="px-2 mb-2">
            <button
              onClick={() => setCollapsedNewsletters(!collapsedNewsletters)}
              className="w-full flex items-center gap-1 px-2 py-1 text-sm text-muted-foreground hover:text-foreground"
            >
              {collapsedNewsletters ? (
                <ChevronRight className="h-3 w-3" />
              ) : (
                <ChevronDown className="h-3 w-3" />
              )}
              <Mail className="h-3 w-3 text-orange-500" />
              <span className="flex-1 text-left truncate font-medium">Newsletters</span>
              {newsletterUnreadCount > 0 && (
                <Badge variant="secondary" className="text-xs">
                  {newsletterUnreadCount}
                </Badge>
              )}
            </button>

            {!collapsedNewsletters && (
              <div className="ml-4 space-y-0.5">
                {newsletterFeeds.map((feed) => {
                  const isSelected =
                    typeof selectedFilter === 'object' &&
                    selectedFilter.type === 'feed' &&
                    selectedFilter.feedId === feed.id

                  return (
                    <button
                      key={feed.id}
                      onClick={() => {
                        setCurrentView('feeds')
                        setSelectedFilter({ type: 'feed', feedId: feed.id })
                        setIsSearching(false)
                      }}
                      className={cn(
                        "w-full flex items-center gap-2 px-2 py-1 rounded-md text-sm transition-colors",
                        isSelected
                          ? "bg-secondary text-secondary-foreground"
                          : "hover:bg-muted text-muted-foreground hover:text-foreground"
                      )}
                    >
                      <Mail className="h-3 w-3 flex-shrink-0 text-orange-500" />
                      <span className="flex-1 text-left truncate">{feed.name}</span>
                      {feed.unread_count > 0 && (
                        <Badge variant="secondary" className="text-xs">
                          {feed.unread_count}
                        </Badge>
                      )}
                    </button>
                  )
                })}
              </div>
            )}
          </div>
        )}

        {currentView === 'feeds' ? (
          <>
            {/* Filters */}
            <div className="px-2 space-y-1">
              {filterItems.map(({ filter, label, icon: Icon, count }) => (
                <button
                  key={typeof filter === 'string' ? filter : filter.type}
                  onClick={() => {
                    setSelectedFilter(filter)
                    setIsSearching(false)
                  }}
                  className={cn(
                    "w-full flex items-center gap-2 px-2 py-1.5 rounded-md text-sm transition-colors",
                    isFilterSelected(filter)
                      ? "bg-secondary text-secondary-foreground"
                      : "hover:bg-muted text-muted-foreground hover:text-foreground"
                  )}
                >
                  <Icon className="h-4 w-4" />
                  <span className="flex-1 text-left">{label}</span>
                  {count !== undefined && count > 0 && (
                    <Badge variant="secondary" className="text-xs">
                      {count}
                    </Badge>
                  )}
                </button>
              ))}
            </div>

            {/* Saved Searches Section */}
            {savedSearches.length > 0 && (
              <>
                <Separator className="my-2" />
                <div className="px-2 mb-2">
                  <button
                    onClick={() => setCollapsedSavedSearches(!collapsedSavedSearches)}
                    className="w-full flex items-center gap-1 px-2 py-1 text-sm text-muted-foreground hover:text-foreground"
                  >
                    {collapsedSavedSearches ? (
                      <ChevronRight className="h-3 w-3" />
                    ) : (
                      <ChevronDown className="h-3 w-3" />
                    )}
                    <Pin className="h-3 w-3 text-blue-500" />
                    <span className="flex-1 text-left truncate font-medium">Pinned Searches</span>
                    <span className="text-xs text-muted-foreground tabular-nums">{savedSearches.length}</span>
                  </button>

                  {!collapsedSavedSearches && (
                    <div className="ml-4 space-y-0.5">
                      {savedSearches.map((saved) => (
                        <div key={saved.id} className="group flex items-center">
                          <button
                            onClick={() => {
                              setSearchQuery(saved.query)
                              setIsSearching(true)
                              touchSavedSearch.mutate(saved.id)
                            }}
                            className="flex-1 flex items-center gap-2 px-2 py-1 rounded-md text-sm transition-colors hover:bg-muted text-muted-foreground hover:text-foreground min-w-0"
                          >
                            <Search className="h-3 w-3 flex-shrink-0" />
                            <span className="flex-1 text-left truncate">{saved.name}</span>
                          </button>
                          <button
                            onClick={() => deleteSavedSearch.mutate(saved.id)}
                            className="opacity-0 group-hover:opacity-100 p-1 rounded hover:bg-muted text-muted-foreground hover:text-foreground transition-opacity flex-shrink-0"
                            title="Unpin"
                          >
                            <X className="h-3 w-3" />
                          </button>
                        </div>
                      ))}
                    </div>
                  )}
                </div>
              </>
            )}

            {/* Topics Section */}
            {topics.length > 0 && (
              <>
                <Separator className="my-2" />
                <div className="px-2 mb-2">
                  <button
                    onClick={() => setCollapsedTopics(!collapsedTopics)}
                    className="w-full flex items-center gap-1 px-2 py-1 text-sm text-muted-foreground hover:text-foreground"
                  >
                    {collapsedTopics ? (
                      <ChevronRight className="h-3 w-3" />
                    ) : (
                      <ChevronDown className="h-3 w-3" />
                    )}
                    <Tags className="h-3 w-3 text-purple-500" />
                    <span className="flex-1 text-left truncate font-medium">Topics</span>
                    <span className="text-xs text-muted-foreground tabular-nums">{topics.length}</span>
                  </button>

                  {!collapsedTopics && (
                    <div className="ml-4 space-y-0.5">
                      {topics.map((topic) => (
                        <button
                          key={topic.label}
                          onClick={() => {
                            setCurrentView('feeds')
                            setSelectedFilter({
                              type: 'topic',
                              label: topic.label,
                              articleIds: topic.article_ids ?? [],
                            })
                            setIsSearching(false)
                          }}
                          className={cn(
                            "w-full flex items-center gap-2 px-2 py-1 rounded-md text-sm transition-colors",
                            isTopicSelected(topic.label)
                              ? "bg-secondary text-secondary-foreground"
                              : "hover:bg-muted text-muted-foreground hover:text-foreground"
                          )}
                        >
                          <Tags className="h-3 w-3 flex-shrink-0 text-purple-400" />
                          <span className="flex-1 text-left truncate">{topic.label}</span>
                          <Badge variant="secondary" className="text-xs">
                            {topic.count}
                          </Badge>
                        </button>
                      ))}
                    </div>
                  )}
                </div>
              </>
            )}

            <Separator className="my-2" />

            {/* RSS Feeds by Category */}
            <div className="px-2 space-y-1">
              <div className="flex items-center justify-between px-2 py-1">
                <span className="text-xs font-semibold text-muted-foreground uppercase">
                  Feeds {rssFeeds.length > 0 && `(${rssFeeds.length})`}
                </span>
                <div className="flex gap-0.5">
                  {rssFeeds.length > 0 && (
                    <SmartTooltip
                      hintId="feed-manager-tip"
                      title="Feed Manager"
                      body="Bulk-edit categories, delete feeds, and organize your subscriptions."
                      side="bottom"
                    >
                      <Button
                        variant="ghost"
                        size="sm"
                        className="h-6 px-2 text-xs"
                        onClick={onManageFeeds}
                      >
                        <ListFilter className="h-3 w-3 mr-1" />
                        Manage ({rssFeeds.length})
                      </Button>
                    </SmartTooltip>
                  )}
                  {isAdmin && (
                    <span className="relative inline-flex items-center">
                      <Button variant="ghost" size="icon" className="h-6 w-6" onClick={onAddFeed} title="Add feed">
                        <Plus className="h-3 w-3" />
                      </Button>
                      {rssFeeds.length === 0 && (
                        <CoachMark
                          hintId="add-feed-coach"
                          title="Add your first feed"
                          body="Paste any RSS/Atom URL or website URL — we'll auto-detect the feed."
                          side="bottom"
                          className="absolute -top-0.5 -right-0.5"
                        />
                      )}
                    </span>
                  )}
                </div>
              </div>

              {feedsLoading ? (
                <div className="px-2 py-2 text-sm text-muted-foreground">Loading feeds...</div>
              ) : categories.length === 0 ? (
                <div className="px-2 py-8 text-center">
                  <Inbox className="h-8 w-8 mx-auto mb-2 opacity-20 text-muted-foreground" />
                  <p className="text-xs text-muted-foreground mb-3">No feeds yet</p>
                  {isAdmin && (
                    <Button size="sm" variant="outline" onClick={onAddFeed} className="w-full">
                      <Plus className="h-3 w-3 mr-1" />
                      Add Your First Feed
                    </Button>
                  )}
                </div>
              ) : (
                categories.map((category) => (
                  <div key={category}>
                    <button
                      onClick={() => toggleCategory(category)}
                      className="w-full flex items-center gap-1 px-2 py-1 text-sm text-muted-foreground hover:text-foreground"
                    >
                      {collapsedCategories.has(category) ? (
                        <ChevronRight className="h-3 w-3" />
                      ) : (
                        <ChevronDown className="h-3 w-3" />
                      )}
                      <FolderOpen className="h-3 w-3" />
                      <span className="flex-1 text-left truncate">{category}</span>
                      <span className="text-xs">
                        {feedsByCategory[category].reduce((sum, f) => sum + f.unread_count, 0)}
                      </span>
                    </button>

                    {!collapsedCategories.has(category) && (
                      <div className="ml-4 space-y-0.5">
                        {feedsByCategory[category].map((feed) => {
                          const isSelected =
                            typeof selectedFilter === 'object' &&
                            selectedFilter.type === 'feed' &&
                            selectedFilter.feedId === feed.id

                          return (
                            <button
                              key={feed.id}
                              onClick={() => {
                                setSelectedFilter({ type: 'feed', feedId: feed.id })
                                setIsSearching(false)
                              }}
                              className={cn(
                                "w-full flex items-center gap-2 px-2 py-1 rounded-md text-sm transition-colors",
                                isSelected
                                  ? "bg-secondary text-secondary-foreground"
                                  : "hover:bg-muted text-muted-foreground hover:text-foreground"
                              )}
                            >
                              <Rss className="h-3 w-3 flex-shrink-0" />
                              <span className="flex-1 text-left truncate">{feed.name}</span>
                              {feed.unread_count > 0 && (
                                <Badge variant="secondary" className="text-xs">
                                  {feed.unread_count}
                                </Badge>
                              )}
                            </button>
                          )
                        })}
                      </div>
                    )}
                  </div>
                ))
              )}
            </div>
          </>
        ) : (
          /* Library Filters */
          <div className="px-2 space-y-1">
            <button
              onClick={() => setSelectedFilter('all')}
              className={cn(
                "w-full flex items-center gap-2 px-2 py-1.5 rounded-md text-sm transition-colors",
                selectedFilter === 'all'
                  ? "bg-secondary text-secondary-foreground"
                  : "hover:bg-muted text-muted-foreground hover:text-foreground"
              )}
            >
              <Library className="h-4 w-4" />
              <span>All Items</span>
            </button>
            <button
              onClick={() => setSelectedFilter('bookmarked')}
              className={cn(
                "w-full flex items-center gap-2 px-2 py-1.5 rounded-md text-sm transition-colors",
                selectedFilter === 'bookmarked'
                  ? "bg-secondary text-secondary-foreground"
                  : "hover:bg-muted text-muted-foreground hover:text-foreground"
              )}
            >
              <BookMarked className="h-4 w-4" />
              <span>Saved</span>
            </button>
            <button
              onClick={() => setSelectedFilter('summarized')}
              className={cn(
                "w-full flex items-center gap-2 px-2 py-1.5 rounded-md text-sm transition-colors",
                selectedFilter === 'summarized'
                  ? "bg-secondary text-secondary-foreground"
                  : "hover:bg-muted text-muted-foreground hover:text-foreground"
              )}
            >
              <Sparkles className="h-4 w-4" />
              <span>Summarized</span>
            </button>
          </div>
        )}
      </ScrollArea>

      {/* Footer */}
      <div className="p-2 border-t border-border flex items-center gap-1">
        <SmartTooltip
          hintId="settings-tip"
          title="Settings"
          body="Configure your backend URL, AI provider, theme, and more."
          side="top"
          className="flex-1"
        >
          <Button variant="ghost" className="w-full justify-start" onClick={onOpenSettings}>
            <Settings className="h-4 w-4 mr-2" />
            Settings
          </Button>
        </SmartTooltip>
        <Tooltip content="Keyboard shortcuts">
          <Button variant="ghost" size="icon" className="h-9 w-9 shrink-0" onClick={() => setShortcutsOpen(true)}>
            <Keyboard className="h-4 w-4" />
          </Button>
        </Tooltip>
      </div>

      <Dialog isOpen={shortcutsOpen} onClose={() => setShortcutsOpen(false)} title="Keyboard Shortcuts">
        <div className="space-y-2 text-sm">
          {[
            ['Next article', 'j'],
            ['Previous article', 'k'],
            ['Toggle read', 'm'],
            ['Toggle bookmark', 's'],
            ['Open in browser', 'o'],
            ['Refresh feeds', 'r'],
            ['Search', '/'],
            ['Clear search', 'Esc'],
            ['Settings', '⌘ ,'],
            ['Add new feed', '⌘ N'],
          ].map(([label, key]) => (
            <div key={label} className="flex justify-between items-center">
              <span className="text-muted-foreground">{label}</span>
              <kbd className="px-2 py-1 bg-muted rounded text-xs font-mono">{key}</kbd>
            </div>
          ))}
        </div>
      </Dialog>
    </div>
  )
}
