import { useState, useMemo, useRef } from 'react'
import {
  Rss,
  Trash2,
  RefreshCw,
  Download,
  Upload,
  Search,
  Pencil,
  Copy,
  Check,
  AlertCircle,
  Clock,
  CheckCircle2,
  Circle,
} from 'lucide-react'
import { cn } from '@/lib/utils'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Dialog, DialogFooter } from '@/components/ui/dialog'
import { ScrollArea } from '@/components/ui/scroll-area'
import { Badge } from '@/components/ui/badge'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu'
import {
  useFeeds,
  useUpdateFeed,
  useBulkDeleteFeeds,
  useRefreshSingleFeed,
  useImportOpml,
  useExportOpml,
  useAuthStatus,
} from '@/hooks/use-queries'
import type { Feed } from '@/types'

interface FeedManagerDialogProps {
  isOpen: boolean
  onClose: () => void
  onAddFeed: () => void
}

type SortOrder = 'name' | 'category' | 'status' | 'lastFetched'

type FeedHealthStatus = 'healthy' | 'stale' | 'error' | 'neverFetched'

function getFeedHealthStatus(feed: Feed): FeedHealthStatus {
  if (feed.fetch_error) return 'error'
  if (!feed.last_fetched) return 'neverFetched'

  const lastFetched = new Date(feed.last_fetched)
  const hoursSinceUpdate = (Date.now() - lastFetched.getTime()) / (1000 * 60 * 60)

  if (hoursSinceUpdate > 48) return 'stale'
  return 'healthy'
}

function FeedHealthBadge({ status }: { status: FeedHealthStatus }) {
  const config = {
    healthy: { color: 'bg-green-500', label: 'OK', icon: CheckCircle2 },
    stale: { color: 'bg-yellow-500', label: 'Stale', icon: Clock },
    error: { color: 'bg-red-500', label: 'Error', icon: AlertCircle },
    neverFetched: { color: 'bg-gray-400', label: 'New', icon: Circle },
  }[status]

  const Icon = config.icon

  return (
    <div className="flex items-center gap-1.5">
      <Icon className={cn('h-3 w-3', {
        'text-green-500': status === 'healthy',
        'text-yellow-500': status === 'stale',
        'text-red-500': status === 'error',
        'text-gray-400': status === 'neverFetched',
      })} />
      <span className="text-xs text-muted-foreground">{config.label}</span>
    </div>
  )
}

export function FeedManagerDialog({ isOpen, onClose, onAddFeed }: FeedManagerDialogProps) {
  const { data: feeds = [] } = useFeeds()
  const { data: authStatus } = useAuthStatus()
  const updateFeed = useUpdateFeed()
  const bulkDeleteFeeds = useBulkDeleteFeeds()
  const refreshSingleFeed = useRefreshSingleFeed()
  const importOpml = useImportOpml()
  const exportOpml = useExportOpml()
  const isAdmin = authStatus?.is_admin ?? true

  const [searchText, setSearchText] = useState('')
  const [selectedFeedIds, setSelectedFeedIds] = useState<Set<number>>(new Set())
  const [sortOrder, setSortOrder] = useState<SortOrder>('name')
  const [editingFeed, setEditingFeed] = useState<Feed | null>(null)
  const [editName, setEditName] = useState('')
  const [editCategory, setEditCategory] = useState('')
  const [showDeleteConfirm, setShowDeleteConfirm] = useState(false)
  const [copiedId, setCopiedId] = useState<number | null>(null)

  const fileInputRef = useRef<HTMLInputElement>(null)

  // Filter out newsletter feeds and apply search
  const filteredFeeds = useMemo(() => {
    let result = feeds.filter(feed => !feed.url.startsWith('newsletter://'))

    if (searchText) {
      const query = searchText.toLowerCase()
      result = result.filter(feed =>
        feed.name.toLowerCase().includes(query) ||
        (feed.category?.toLowerCase().includes(query)) ||
        feed.url.toLowerCase().includes(query)
      )
    }

    // Sort
    result.sort((a, b) => {
      switch (sortOrder) {
        case 'name':
          return a.name.localeCompare(b.name)
        case 'category': {
          const catA = a.category || ''
          const catB = b.category || ''
          if (catA !== catB) return catA.localeCompare(catB)
          return a.name.localeCompare(b.name)
        }
        case 'status': {
          const statusOrder = { error: 0, neverFetched: 1, stale: 2, healthy: 3 }
          const statusA = statusOrder[getFeedHealthStatus(a)]
          const statusB = statusOrder[getFeedHealthStatus(b)]
          if (statusA !== statusB) return statusA - statusB
          return a.name.localeCompare(b.name)
        }
        case 'lastFetched': {
          const dateA = a.last_fetched ? new Date(a.last_fetched).getTime() : 0
          const dateB = b.last_fetched ? new Date(b.last_fetched).getTime() : 0
          return dateB - dateA
        }
        default:
          return 0
      }
    })

    return result
  }, [feeds, searchText, sortOrder])

  // Get unique categories
  const categories = useMemo(() => {
    const cats = new Set<string>()
    feeds.forEach(feed => {
      if (feed.category) cats.add(feed.category)
    })
    return Array.from(cats).sort()
  }, [feeds])

  const toggleFeedSelection = (feedId: number) => {
    const newSelection = new Set(selectedFeedIds)
    if (newSelection.has(feedId)) {
      newSelection.delete(feedId)
    } else {
      newSelection.add(feedId)
    }
    setSelectedFeedIds(newSelection)
  }

  const toggleSelectAll = () => {
    if (selectedFeedIds.size === filteredFeeds.length) {
      setSelectedFeedIds(new Set())
    } else {
      setSelectedFeedIds(new Set(filteredFeeds.map(f => f.id)))
    }
  }

  const handleDeleteSelected = async () => {
    if (selectedFeedIds.size === 0) return
    await bulkDeleteFeeds.mutateAsync(Array.from(selectedFeedIds))
    setSelectedFeedIds(new Set())
    setShowDeleteConfirm(false)
  }

  const handleRefreshSelected = () => {
    selectedFeedIds.forEach(id => {
      refreshSingleFeed.mutate(id)
    })
  }

  const handleCopyUrl = (feed: Feed) => {
    navigator.clipboard.writeText(feed.url)
    setCopiedId(feed.id)
    setTimeout(() => setCopiedId(null), 2000)
  }

  const handleEditFeed = (feed: Feed) => {
    setEditingFeed(feed)
    setEditName(feed.name)
    setEditCategory(feed.category || '')
  }

  const handleSaveEdit = async () => {
    if (!editingFeed) return

    const updates: { name?: string; category?: string } = {}
    if (editName !== editingFeed.name) updates.name = editName
    if (editCategory !== (editingFeed.category || '')) updates.category = editCategory

    if (Object.keys(updates).length > 0) {
      await updateFeed.mutateAsync({ feedId: editingFeed.id, data: updates })
    }
    setEditingFeed(null)
  }

  const handleCategoryChange = async (feed: Feed, category: string | null) => {
    await updateFeed.mutateAsync({
      feedId: feed.id,
      data: { category: category || '' }
    })
  }

  const handleImportClick = () => {
    fileInputRef.current?.click()
  }

  const handleFileChange = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0]
    if (!file) return

    const content = await file.text()
    await importOpml.mutateAsync(content)
    e.target.value = '' // Reset input
  }

  const handleExport = async () => {
    const result = await exportOpml.mutateAsync()
    const blob = new Blob([result.opml], { type: 'text/xml' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = 'Data Points Feeds.opml'
    a.click()
    URL.revokeObjectURL(url)
  }

  const formatRelativeTime = (dateString: string | null) => {
    if (!dateString) return 'Never'
    const date = new Date(dateString)
    const now = new Date()
    const diffMs = now.getTime() - date.getTime()
    const diffMins = Math.floor(diffMs / 60000)
    const diffHours = Math.floor(diffMs / 3600000)
    const diffDays = Math.floor(diffMs / 86400000)

    if (diffMins < 1) return 'Just now'
    if (diffMins < 60) return `${diffMins}m ago`
    if (diffHours < 24) return `${diffHours}h ago`
    if (diffDays < 7) return `${diffDays}d ago`
    return date.toLocaleDateString()
  }

  return (
    <>
      <Dialog
        isOpen={isOpen}
        onClose={onClose}
        title="Feed Manager"
        icon={<Rss className="h-5 w-5" />}
        maxWidth="lg"
        className="max-w-4xl h-[80vh] flex flex-col"
      >
        {/* Toolbar */}
        <div className="flex items-center gap-2 p-4 border-b border-border flex-wrap">
          {isAdmin && (
            <>
              <Button variant="outline" size="sm" onClick={onAddFeed}>
                <Rss className="h-4 w-4 mr-1" />
                Add
              </Button>
              <Button
                variant="outline"
                size="sm"
                onClick={() => setShowDeleteConfirm(true)}
                disabled={selectedFeedIds.size === 0}
              >
                <Trash2 className="h-4 w-4 mr-1" />
                Delete
              </Button>
            </>
          )}
          <Button
            variant="outline"
            size="sm"
            onClick={handleRefreshSelected}
            disabled={selectedFeedIds.size === 0 || refreshSingleFeed.isPending}
          >
            <RefreshCw className={cn("h-4 w-4 mr-1", refreshSingleFeed.isPending && "animate-spin")} />
            Refresh
          </Button>

          <div className="w-px h-6 bg-border mx-1" />

          {isAdmin && (
            <Button variant="outline" size="sm" onClick={handleImportClick}>
              <Upload className="h-4 w-4 mr-1" />
              Import
            </Button>
          )}
          <Button
            variant="outline"
            size="sm"
            onClick={handleExport}
            disabled={exportOpml.isPending}
          >
            <Download className="h-4 w-4 mr-1" />
            Export
          </Button>

          <div className="flex-1" />

          <select
            value={sortOrder}
            onChange={(e) => setSortOrder(e.target.value as SortOrder)}
            className="h-9 px-3 rounded-md border border-input bg-background text-sm"
          >
            <option value="name">Sort by Name</option>
            <option value="category">Sort by Category</option>
            <option value="status">Sort by Status</option>
            <option value="lastFetched">Sort by Last Fetched</option>
          </select>

          <div className="relative">
            <Search className="absolute left-2.5 top-2.5 h-4 w-4 text-muted-foreground" />
            <Input
              placeholder="Search feeds..."
              value={searchText}
              onChange={(e) => setSearchText(e.target.value)}
              className="pl-9 w-48"
            />
          </div>
        </div>

        {/* Feed List */}
        <ScrollArea className="flex-1">
          {filteredFeeds.length === 0 ? (
            <div className="flex flex-col items-center justify-center h-64 text-muted-foreground">
              <Rss className="h-12 w-12 mb-4 opacity-50" />
              {searchText ? (
                <p>No feeds match your search</p>
              ) : (
                <>
                  <p className="mb-2">No feeds yet</p>
                  {isAdmin && (
                    <Button variant="outline" size="sm" onClick={onAddFeed}>
                      Add Feed
                    </Button>
                  )}
                </>
              )}
            </div>
          ) : (
            <div className="divide-y divide-border">
              {/* Header Row */}
              <div className="flex items-center gap-3 px-4 py-2 bg-muted/50 text-xs font-medium text-muted-foreground sticky top-0">
                {isAdmin && (
                  <input
                    type="checkbox"
                    checked={selectedFeedIds.size === filteredFeeds.length && filteredFeeds.length > 0}
                    onChange={toggleSelectAll}
                    className="h-4 w-4 rounded border-input"
                  />
                )}
                <div className="flex-1 min-w-0">Name</div>
                <div className="w-28">Category</div>
                <div className="w-20">Status</div>
                <div className="w-24">Last Fetched</div>
                <div className="w-20">Actions</div>
              </div>

              {/* Feed Rows */}
              {filteredFeeds.map((feed) => (
                <div
                  key={feed.id}
                  className={cn(
                    "flex items-center gap-3 px-4 py-2 hover:bg-muted/50 transition-colors",
                    selectedFeedIds.has(feed.id) && "bg-primary/5"
                  )}
                >
                  {isAdmin && (
                    <input
                      type="checkbox"
                      checked={selectedFeedIds.has(feed.id)}
                      onChange={() => toggleFeedSelection(feed.id)}
                      className="h-4 w-4 rounded border-input"
                    />
                  )}

                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-2">
                      <Rss className="h-4 w-4 flex-shrink-0 text-muted-foreground" />
                      <span className="truncate font-medium">{feed.name}</span>
                      {feed.unread_count > 0 && (
                        <Badge variant="secondary" className="text-xs">
                          {feed.unread_count}
                        </Badge>
                      )}
                    </div>
                    <div className="text-xs text-muted-foreground truncate mt-0.5" title={feed.url}>
                      {feed.url}
                    </div>
                  </div>

                  <div className="w-28">
                    {isAdmin ? (
                      <DropdownMenu>
                        <DropdownMenuTrigger asChild>
                          <button className="text-sm text-left hover:text-foreground transition-colors">
                            {feed.category || <span className="text-muted-foreground">None</span>}
                          </button>
                        </DropdownMenuTrigger>
                        <DropdownMenuContent align="start">
                          <DropdownMenuItem onClick={() => handleCategoryChange(feed, null)}>
                            None
                          </DropdownMenuItem>
                          <DropdownMenuSeparator />
                          {categories.map((cat) => (
                            <DropdownMenuItem key={cat} onClick={() => handleCategoryChange(feed, cat)}>
                              {cat}
                            </DropdownMenuItem>
                          ))}
                        </DropdownMenuContent>
                      </DropdownMenu>
                    ) : (
                      <span className="text-sm">{feed.category || <span className="text-muted-foreground">None</span>}</span>
                    )}
                  </div>

                  <div className="w-20">
                    <FeedHealthBadge status={getFeedHealthStatus(feed)} />
                  </div>

                  <div className="w-24 text-xs text-muted-foreground">
                    {formatRelativeTime(feed.last_fetched)}
                  </div>

                  <div className="w-20 flex items-center gap-1">
                    {isAdmin && (
                      <Button
                        variant="ghost"
                        size="icon"
                        className="h-7 w-7"
                        onClick={() => handleEditFeed(feed)}
                        title="Edit feed"
                      >
                        <Pencil className="h-3.5 w-3.5" />
                      </Button>
                    )}
                    <Button
                      variant="ghost"
                      size="icon"
                      className="h-7 w-7"
                      onClick={() => handleCopyUrl(feed)}
                      title="Copy URL"
                    >
                      {copiedId === feed.id ? (
                        <Check className="h-3.5 w-3.5 text-green-500" />
                      ) : (
                        <Copy className="h-3.5 w-3.5" />
                      )}
                    </Button>
                    <Button
                      variant="ghost"
                      size="icon"
                      className="h-7 w-7"
                      onClick={() => refreshSingleFeed.mutate(feed.id)}
                      title="Refresh feed"
                    >
                      <RefreshCw className="h-3.5 w-3.5" />
                    </Button>
                  </div>
                </div>
              ))}
            </div>
          )}
        </ScrollArea>

        {/* Footer */}
        {selectedFeedIds.size > 0 && (
          <div className="flex items-center justify-between px-4 py-2 border-t border-border bg-muted/30">
            <span className="text-sm text-muted-foreground">
              {selectedFeedIds.size} feed{selectedFeedIds.size === 1 ? '' : 's'} selected
            </span>
            <div className="flex gap-2">
              <Button variant="ghost" size="sm" onClick={toggleSelectAll}>
                Select All
              </Button>
              <Button variant="ghost" size="sm" onClick={() => setSelectedFeedIds(new Set())}>
                Deselect All
              </Button>
            </div>
          </div>
        )}

        <input
          type="file"
          ref={fileInputRef}
          onChange={handleFileChange}
          accept=".opml,.xml"
          className="hidden"
        />
      </Dialog>

      {/* Delete Confirmation Dialog */}
      {showDeleteConfirm && (
        <Dialog
          isOpen={showDeleteConfirm}
          onClose={() => setShowDeleteConfirm(false)}
          title="Delete Feeds"
          icon={<Trash2 className="h-5 w-5 text-destructive" />}
        >
          <div className="p-4">
            <p>
              Are you sure you want to delete {selectedFeedIds.size} feed
              {selectedFeedIds.size === 1 ? '' : 's'}? This action cannot be undone.
            </p>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setShowDeleteConfirm(false)}>
              Cancel
            </Button>
            <Button
              variant="destructive"
              onClick={handleDeleteSelected}
              disabled={bulkDeleteFeeds.isPending}
            >
              {bulkDeleteFeeds.isPending ? 'Deleting...' : 'Delete'}
            </Button>
          </DialogFooter>
        </Dialog>
      )}

      {/* Edit Feed Dialog */}
      {editingFeed && (
        <Dialog
          isOpen={!!editingFeed}
          onClose={() => setEditingFeed(null)}
          title="Edit Feed"
          icon={<Pencil className="h-5 w-5" />}
        >
          <div className="p-4 space-y-4">
            <div>
              <label className="block text-sm font-medium mb-1">URL</label>
              <div className="flex items-center gap-2 p-2 bg-muted rounded-md">
                <span className="text-sm text-muted-foreground truncate flex-1">
                  {editingFeed.url}
                </span>
                <Button
                  variant="ghost"
                  size="icon"
                  className="h-6 w-6 flex-shrink-0"
                  onClick={() => handleCopyUrl(editingFeed)}
                >
                  {copiedId === editingFeed.id ? (
                    <Check className="h-3 w-3 text-green-500" />
                  ) : (
                    <Copy className="h-3 w-3" />
                  )}
                </Button>
              </div>
            </div>

            <div>
              <label className="block text-sm font-medium mb-1">Name</label>
              <Input
                value={editName}
                onChange={(e) => setEditName(e.target.value)}
                placeholder="Feed name"
              />
            </div>

            <div>
              <label className="block text-sm font-medium mb-1">Category</label>
              <Input
                value={editCategory}
                onChange={(e) => setEditCategory(e.target.value)}
                placeholder="Category (optional)"
                list="categories"
              />
              <datalist id="categories">
                {categories.map((cat) => (
                  <option key={cat} value={cat} />
                ))}
              </datalist>
            </div>

            <div className="flex items-center gap-2">
              <span className="text-sm text-muted-foreground">Status:</span>
              <FeedHealthBadge status={getFeedHealthStatus(editingFeed)} />
            </div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setEditingFeed(null)}>
              Cancel
            </Button>
            <Button
              onClick={handleSaveEdit}
              disabled={!editName.trim() || updateFeed.isPending}
            >
              {updateFeed.isPending ? 'Saving...' : 'Save'}
            </Button>
          </DialogFooter>
        </Dialog>
      )}
    </>
  )
}
