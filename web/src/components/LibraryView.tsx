import { useState, useEffect } from 'react'
import {
  Library,
  BookMarked,
  FileText,
  Link,
  Upload,
  Plus,
  Sparkles,
  Loader2,
  ExternalLink,
  Trash2,
} from 'lucide-react'
import { cn } from '@/lib/utils'
import { formatDate, getDomain } from '@/lib/utils'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Badge } from '@/components/ui/badge'
import { ScrollArea } from '@/components/ui/scroll-area'
import { Skeleton } from '@/components/ui/skeleton'
import { Separator } from '@/components/ui/separator'
import { useToast } from '@/components/ui/toast'
import { useAppStore } from '@/store/app-store'
import {
  useLibrary,
  useLibraryItem,
  useAddLibraryUrl,
  useUploadLibraryFile,
  useDeleteLibraryItem,
  useSummarizeLibraryItem,
} from '@/hooks/use-queries'
// StandaloneItem type imported for documentation but used via inference
import type {} from '@/types'

export function LibraryList() {
  const { selectedFilter, selectedLibraryItemId, setSelectedLibraryItemId, hasShownToast, markToastShown } = useAppStore()
  const { showToast } = useToast()

  const { data: items = [], isLoading } = useLibrary({
    bookmarked_only: selectedFilter === 'bookmarked',
  })

  const [showAddUrl, setShowAddUrl] = useState(false)

  // Show first-time toast when Library is opened
  useEffect(() => {
    if (!hasShownToast('first-library')) {
      showToast('Library lets you save web pages, PDFs, and documents for later.', 'info')
      markToastShown('first-library')
    }
  }, [hasShownToast, markToastShown, showToast])
  const [newUrl, setNewUrl] = useState('')
  const addUrl = useAddLibraryUrl()
  const uploadFile = useUploadLibraryFile()

  const handleAddUrl = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!newUrl.trim()) return

    try {
      await addUrl.mutateAsync(newUrl.trim())
      setNewUrl('')
      setShowAddUrl(false)
    } catch (error) {
      console.error('Failed to add URL:', error)
    }
  }

  const handleFileUpload = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0]
    if (!file) return

    try {
      await uploadFile.mutateAsync(file)
    } catch (error) {
      console.error('Failed to upload file:', error)
    }

    // Reset input
    e.target.value = ''
  }

  const getContentTypeIcon = (type: string) => {
    switch (type) {
      case 'url':
        return Link
      case 'pdf':
      case 'docx':
      case 'txt':
      case 'md':
      case 'html':
        return FileText
      default:
        return FileText
    }
  }

  if (isLoading) {
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
            </div>
          ))}
        </div>
      </div>
    )
  }

  return (
    <div className="w-80 border-r border-border flex flex-col bg-background">
      {/* Header */}
      <div className="p-4 border-b border-border">
        <div className="flex items-center justify-between">
          <h2 className="font-semibold flex items-center gap-2">
            <Library className="h-4 w-4" />
            Library
          </h2>
          <Badge variant="secondary">{items.length}</Badge>
        </div>

        {/* Add buttons */}
        <div className="flex gap-2 mt-3">
          <Button
            variant="outline"
            size="sm"
            className="flex-1"
            onClick={() => setShowAddUrl(true)}
          >
            <Plus className="h-3 w-3 mr-1" />
            Add URL
          </Button>
          <Button variant="outline" size="sm" className="flex-1" asChild>
            <label>
              <Upload className="h-3 w-3 mr-1" />
              Upload
              <input
                type="file"
                className="hidden"
                accept=".pdf,.docx,.txt,.md,.html"
                onChange={handleFileUpload}
              />
            </label>
          </Button>
        </div>

        {/* Add URL form */}
        {showAddUrl && (
          <form onSubmit={handleAddUrl} className="mt-3 space-y-2">
            <Input
              value={newUrl}
              onChange={(e) => setNewUrl(e.target.value)}
              placeholder="https://..."
              autoFocus
            />
            <div className="flex gap-2">
              <Button
                type="button"
                variant="ghost"
                size="sm"
                onClick={() => setShowAddUrl(false)}
              >
                Cancel
              </Button>
              <Button type="submit" size="sm" disabled={addUrl.isPending}>
                {addUrl.isPending ? <Loader2 className="h-4 w-4 animate-spin" /> : 'Add'}
              </Button>
            </div>
          </form>
        )}
      </div>

      {/* Item List */}
      <ScrollArea className="flex-1">
        {items.length === 0 ? (
          <div className="p-8 text-center text-muted-foreground">
            <Library className="h-12 w-12 mx-auto mb-4 opacity-20" />
            <p className="font-medium mb-1">No items in library</p>
            <p className="text-sm mb-4">Save web pages, PDFs, and documents for later</p>
            <div className="flex gap-2 justify-center">
              <Button
                variant="outline"
                size="sm"
                onClick={() => setShowAddUrl(true)}
              >
                <Plus className="h-3 w-3 mr-1" />
                Add URL
              </Button>
              <Button variant="outline" size="sm" asChild>
                <label className="cursor-pointer">
                  <Upload className="h-3 w-3 mr-1" />
                  Upload File
                  <input
                    type="file"
                    className="hidden"
                    accept=".pdf,.docx,.txt,.md,.html"
                    onChange={handleFileUpload}
                  />
                </label>
              </Button>
            </div>
          </div>
        ) : (
          <div className="p-2 space-y-1">
            {items.map((item) => {
              const Icon = getContentTypeIcon(item.content_type)
              const isSelected = selectedLibraryItemId === item.id

              return (
                <button
                  key={item.id}
                  onClick={() => setSelectedLibraryItemId(item.id)}
                  className={cn(
                    "w-full text-left p-3 rounded-lg transition-colors",
                    isSelected
                      ? "bg-primary/10 border border-primary/20"
                      : "hover:bg-muted"
                  )}
                >
                  <div className="flex items-start gap-2">
                    <Icon className="h-4 w-4 mt-0.5 text-muted-foreground flex-shrink-0" />
                    <div className="flex-1 min-w-0">
                      <h3 className="text-sm font-medium line-clamp-2">
                        {item.title}
                      </h3>
                      <div className="flex items-center gap-2 mt-1 text-xs text-muted-foreground">
                        <Badge variant="outline" className="text-[10px]">
                          {item.content_type.toUpperCase()}
                        </Badge>
                        <span>{formatDate(item.created_at)}</span>
                        {item.is_bookmarked && (
                          <BookMarked className="h-3 w-3 text-amber-500 ml-auto" />
                        )}
                        {item.summary_short && (
                          <Sparkles className="h-3 w-3 text-purple-500" />
                        )}
                      </div>
                    </div>
                  </div>
                </button>
              )
            })}
          </div>
        )}
      </ScrollArea>
    </div>
  )
}

export function LibraryItemDetail() {
  const { selectedLibraryItemId, setSelectedLibraryItemId } = useAppStore()
  const { data: item, isLoading } = useLibraryItem(selectedLibraryItemId)
  const deleteItem = useDeleteLibraryItem()
  const summarize = useSummarizeLibraryItem()

  if (!selectedLibraryItemId) {
    return (
      <div className="flex-1 flex items-center justify-center text-muted-foreground bg-muted/30">
        <div className="text-center">
          <Library className="h-16 w-16 mx-auto mb-4 opacity-20" />
          <p className="text-lg">Select an item to view</p>
        </div>
      </div>
    )
  }

  if (isLoading || !item) {
    return (
      <div className="flex-1 p-8 space-y-4">
        <Skeleton className="h-8 w-3/4" />
        <Skeleton className="h-4 w-1/2" />
        <Skeleton className="h-64 w-full" />
      </div>
    )
  }

  const handleDelete = async () => {
    if (confirm('Are you sure you want to delete this item?')) {
      await deleteItem.mutateAsync(item.id)
      setSelectedLibraryItemId(null)
    }
  }

  const handleSummarize = () => {
    summarize.mutate(item.id)
  }

  return (
    <div className="flex-1 flex flex-col bg-background">
      {/* Toolbar */}
      <div className="flex items-center gap-2 p-4 border-b border-border">
        <Button
          variant="ghost"
          size="sm"
          onClick={handleSummarize}
          disabled={summarize.isPending || !!item.summary_full}
        >
          {summarize.isPending ? (
            <Loader2 className="h-4 w-4 mr-1 animate-spin" />
          ) : (
            <Sparkles className={cn("h-4 w-4 mr-1", item.summary_full && "text-purple-500")} />
          )}
          {item.summary_full ? 'Summarized' : 'Summarize'}
        </Button>

        <Separator orientation="vertical" className="h-6" />

        {item.url && (
          <Button
            variant="ghost"
            size="sm"
            onClick={() => window.open(item.url!, '_blank')}
          >
            <ExternalLink className="h-4 w-4 mr-1" />
            Open
          </Button>
        )}

        <div className="ml-auto">
          <Button
            variant="ghost"
            size="sm"
            onClick={handleDelete}
            className="text-destructive hover:text-destructive"
          >
            <Trash2 className="h-4 w-4" />
          </Button>
        </div>
      </div>

      {/* Content */}
      <ScrollArea className="flex-1">
        <article className="max-w-3xl mx-auto p-8">
          <header className="mb-8">
            <Badge variant="outline" className="mb-2">
              {item.content_type.toUpperCase()}
            </Badge>
            <h1 className="text-3xl font-bold mb-4">{item.title}</h1>
            {item.url && (
              <p className="text-sm text-muted-foreground">
                {getDomain(item.url)}
              </p>
            )}
            {item.file_name && (
              <p className="text-sm text-muted-foreground">
                File: {item.file_name}
              </p>
            )}
          </header>

          {/* Summary */}
          {item.summary_full && (
            <section className="mb-8 p-4 bg-purple-500/5 border border-purple-500/20 rounded-lg">
              <div className="flex items-center gap-2 mb-3">
                <Sparkles className="h-4 w-4 text-purple-500" />
                <span className="font-semibold text-purple-700 dark:text-purple-300">
                  AI Summary
                </span>
              </div>
              <p className="text-sm leading-relaxed">{item.summary_full}</p>
              {item.key_points && item.key_points.length > 0 && (
                <div className="mt-4">
                  <h4 className="text-sm font-semibold mb-2">Key Points</h4>
                  <ul className="list-disc list-inside space-y-1 text-sm">
                    {item.key_points.map((point, i) => (
                      <li key={i}>{point}</li>
                    ))}
                  </ul>
                </div>
              )}
            </section>
          )}

          {/* Content */}
          {item.content ? (
            <div
              className="article-content prose prose-slate dark:prose-invert max-w-none"
              dangerouslySetInnerHTML={{ __html: item.content }}
            />
          ) : (
            <div className="text-center py-12 text-muted-foreground">
              <p>No content available</p>
            </div>
          )}
        </article>
      </ScrollArea>
    </div>
  )
}
