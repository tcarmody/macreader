import { useState, useEffect, useRef } from 'react'
import {
  BookMarked,
  ExternalLink,
  Sparkles,
  Check,
  Circle,
  Share2,
  Loader2,
  Link2,
  Download,
  ClipboardPaste,
  X,
  Plus,
} from 'lucide-react'
import { cn, formatFullDate, getDomain, smartQuotes } from '@/lib/utils'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { ScrollArea } from '@/components/ui/scroll-area'
import { Skeleton } from '@/components/ui/skeleton'
import { Separator } from '@/components/ui/separator'
import { Tooltip } from '@/components/ui/tooltip'
import { SmartTooltip } from '@/components/ui/smart-tooltip'
import { useToast } from '@/components/ui/toast'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu'
import { useAppStore } from '@/store/app-store'
import {
  useArticle,
  useMarkArticleRead,
  useToggleBookmark,
  useFetchContent,
  useExtractFromHtml,
  useSummarizeArticle,
  useFindRelatedLinks,
  useChatHistory,
} from '@/hooks/use-queries'
import { ArticleChat } from './ArticleChat'
import { RelatedLinks } from './RelatedLinks'

type DetailTab = 'article' | 'ai' | 'related' | 'chat'

export function ArticleDetail() {
  const { selectedArticleId, hasShownToast, markToastShown, markFeatureUsed } = useAppStore()
  const { data: article, isLoading } = useArticle(selectedArticleId)
  const markRead = useMarkArticleRead()
  const toggleBookmark = useToggleBookmark()
  const fetchContent = useFetchContent()
  const extractFromHtml = useExtractFromHtml()
  const summarize = useSummarizeArticle()
  const findRelated = useFindRelatedLinks()
  const { data: chatHistory } = useChatHistory(selectedArticleId)
  const { showToast } = useToast()

  const [activeTab, setActiveTab] = useState<DetailTab>('article')
  const [hasTriggeredRelated, setHasTriggeredRelated] = useState(false)
  const [autoSwitchAfterSummarize, setAutoSwitchAfterSummarize] = useState(false)
  const [autoSwitchAfterRelated, setAutoSwitchAfterRelated] = useState(false)
  const [showPasteDialog, setShowPasteDialog] = useState(false)
  const [pastedHtml, setPastedHtml] = useState('')
  const [showSummaryChip, setShowSummaryChip] = useState(false)
  const scrollAreaRef = useRef<HTMLDivElement>(null)

  // Show first-time toast when summarization starts
  useEffect(() => {
    if (summarize.isPending && !hasShownToast('first-summarize')) {
      showToast('AI is generating a summary. This may take a few seconds.', 'info')
      markToastShown('first-summarize')
      markFeatureUsed('hasUsedSummarize')
    }
  }, [summarize.isPending, hasShownToast, markToastShown, showToast, markFeatureUsed])

  // Show first-time toast when finding related links starts
  useEffect(() => {
    if (findRelated.isPending && !hasShownToast('first-related')) {
      showToast('Finding related articles using neural search...', 'info')
      markToastShown('first-related')
      markFeatureUsed('hasUsedRelated')
    }
  }, [findRelated.isPending, hasShownToast, markToastShown, showToast, markFeatureUsed])

  // Auto-switch to AI tab when summary arrives after user triggered it
  useEffect(() => {
    const hasSummary = article?.summary_full || article?.summary_short
    if (hasSummary && autoSwitchAfterSummarize && !summarize.isPending) {
      setActiveTab('ai')
      setAutoSwitchAfterSummarize(false)
    }
  }, [article?.summary_full, article?.summary_short, autoSwitchAfterSummarize, summarize.isPending])

  // Auto-switch to Related tab when related links arrive after user triggered it
  useEffect(() => {
    if (article?.related_links?.length && autoSwitchAfterRelated && !findRelated.isPending) {
      setActiveTab('related')
      setAutoSwitchAfterRelated(false)
    }
  }, [article?.related_links, autoSwitchAfterRelated, findRelated.isPending])

  // Reset state when article changes
  useEffect(() => {
    setActiveTab('article')
    setHasTriggeredRelated(false)
    setAutoSwitchAfterSummarize(false)
    setAutoSwitchAfterRelated(false)
    setShowSummaryChip(false)
  }, [selectedArticleId])

  // Hide chip when switching away from article tab
  useEffect(() => {
    if (activeTab !== 'article') setShowSummaryChip(false)
  }, [activeTab])

  // Attach scroll listener to the radix scroll area viewport
  useEffect(() => {
    const container = scrollAreaRef.current
    if (!container) return
    const viewport = container.querySelector('[data-radix-scroll-area-viewport]') as HTMLElement | null
    if (!viewport) return

    const handleScroll = () => {
      if (activeTab !== 'article') return
      const { scrollTop, scrollHeight, clientHeight } = viewport
      const scrollable = scrollHeight - clientHeight
      if (scrollable <= 0) return
      const pct = scrollTop / scrollable
      setShowSummaryChip(pct >= 0.3)
    }

    viewport.addEventListener('scroll', handleScroll, { passive: true })
    return () => viewport.removeEventListener('scroll', handleScroll)
  }, [activeTab, selectedArticleId])

  if (!selectedArticleId) {
    return (
      <div className="flex-1 flex items-center justify-center text-muted-foreground bg-muted/30">
        <div className="text-center">
          <ExternalLink className="h-16 w-16 mx-auto mb-4 opacity-20" />
          <p className="text-lg">Select an article to read</p>
          <p className="text-sm mt-1">Or use keyboard shortcuts: j/k to navigate</p>
        </div>
      </div>
    )
  }

  if (isLoading || !article) {
    return (
      <div className="flex-1 p-8 space-y-4">
        <Skeleton className="h-8 w-3/4" />
        <Skeleton className="h-4 w-1/2" />
        <Skeleton className="h-32 w-full" />
        <Skeleton className="h-64 w-full" />
      </div>
    )
  }

  const hasSummary = article.summary_full || article.summary_short
  const hasContent = article.content && article.content.length > 100
  const relatedCount = article.related_links?.length ?? 0

  const handleToggleRead = () => {
    markRead.mutate({ articleId: article.id, isRead: !article.is_read })
  }

  const handleToggleBookmark = () => {
    toggleBookmark.mutate(article.id)
  }

  const handleFetchContent = () => {
    fetchContent.mutate(article.id)
  }

  const handleExtractFromHtml = () => {
    if (!pastedHtml.trim()) return
    extractFromHtml.mutate(
      { articleId: article.id, html: pastedHtml, url: article.url },
      {
        onSuccess: () => {
          setShowPasteDialog(false)
          setPastedHtml('')
          showToast('Content extracted successfully', 'success')
        },
        onError: (error) => {
          showToast(`Failed to extract content: ${error.message}`, 'warning')
        },
      }
    )
  }

  const handleSummarize = () => {
    setAutoSwitchAfterSummarize(true)
    summarize.mutate(article.id)
  }

  const handleFindRelated = () => {
    setHasTriggeredRelated(true)
    setAutoSwitchAfterRelated(true)
    findRelated.mutate(article.id)
  }

  const handleShare = async () => {
    if (navigator.share) {
      await navigator.share({
        title: article.title,
        url: article.url,
      })
    } else {
      await navigator.clipboard.writeText(article.url)
    }
  }

  const handleOpenExternal = () => {
    window.open(article.url, '_blank', 'noopener,noreferrer')
  }

  const handleTabClick = (id: DetailTab) => {
    if (id === 'ai' && !hasSummary && !summarize.isPending) {
      handleSummarize()
    } else if (id === 'related' && relatedCount === 0 && !findRelated.isPending && !hasTriggeredRelated) {
      handleFindRelated()
    }
    setActiveTab(id)
  }

  const tabs: {
    id: DetailTab
    label: string
    dot?: 'purple' | 'blue'
    count?: number
    pending?: boolean
    disabled?: boolean
  }[] = [
    { id: 'article', label: 'Article' },
    {
      id: 'ai',
      label: 'AI Summary',
      dot: hasSummary ? 'purple' : undefined,
      pending: summarize.isPending,
    },
    {
      id: 'related',
      label: 'Related',
      dot: relatedCount > 0 ? 'blue' : undefined,
      count: relatedCount > 0 ? relatedCount : undefined,
      pending: findRelated.isPending,
    },
    {
      id: 'chat',
      label: 'Chat',
      dot: chatHistory?.has_chat ? 'blue' : undefined,
      disabled: !hasSummary,
    },
  ]

  return (
    <div className="flex-1 flex flex-col bg-background">
      {/* Toolbar */}
      <div className="flex items-center gap-2 p-4 border-b border-border">
        <Button
          variant="ghost"
          size="sm"
          onClick={handleToggleRead}
          className={cn(article.is_read && "text-muted-foreground")}
        >
          {article.is_read ? (
            <>
              <Check className="h-4 w-4 mr-1" />
              Read
            </>
          ) : (
            <>
              <Circle className="h-4 w-4 mr-1" />
              Unread
            </>
          )}
        </Button>

        <SmartTooltip
          hintId="bookmark-tip"
          title="Save for later"
          body="Bookmarked articles appear under the Bookmarked filter and in your Library."
          side="bottom"
        >
          <Button
            variant="ghost"
            size="sm"
            onClick={handleToggleBookmark}
            className={cn(article.is_bookmarked && "text-amber-500")}
          >
            <BookMarked className={cn("h-4 w-4 mr-1", article.is_bookmarked && "fill-amber-500")} />
            {article.is_bookmarked ? 'Saved' : 'Save'}
          </Button>
        </SmartTooltip>

        <Separator orientation="vertical" className="h-6" />

        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <Tooltip content={hasContent ? 'Refetch full content' : 'Fetch full content'}>
              <Button
                variant="ghost"
                size="icon"
                className="h-7 w-7 text-muted-foreground hover:text-foreground"
                disabled={fetchContent.isPending || extractFromHtml.isPending}
              >
                {fetchContent.isPending || extractFromHtml.isPending ? (
                  <Loader2 className="h-4 w-4 animate-spin" />
                ) : (
                  <Download className="h-4 w-4" />
                )}
              </Button>
            </Tooltip>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="start">
            <DropdownMenuItem onClick={handleFetchContent}>
              <Download className="h-4 w-4 mr-2" />
              Fetch Content
            </DropdownMenuItem>
            <DropdownMenuItem onClick={() => setShowPasteDialog(true)}>
              <ClipboardPaste className="h-4 w-4 mr-2" />
              Paste from Browser
            </DropdownMenuItem>
          </DropdownMenuContent>
        </DropdownMenu>

        <div className="ml-auto flex items-center gap-0.5">
          <Tooltip content="Share">
            <Button variant="ghost" size="icon" className="h-7 w-7 text-muted-foreground hover:text-foreground" onClick={handleShare}>
              <Share2 className="h-4 w-4" />
            </Button>
          </Tooltip>
          <Tooltip content="Open in browser">
            <Button variant="ghost" size="icon" className="h-7 w-7 text-muted-foreground hover:text-foreground" onClick={handleOpenExternal}>
              <ExternalLink className="h-4 w-4" />
            </Button>
          </Tooltip>
        </div>
      </div>

      {/* Tab Strip */}
      <div className="flex items-stretch border-b border-border bg-background shrink-0">
        {tabs.map(({ id, label, dot, count, pending, disabled }) => (
          <button
            key={id}
            onClick={() => !disabled && handleTabClick(id)}
            disabled={disabled}
            className={cn(
              'flex items-center gap-1.5 px-4 py-2.5 text-sm font-medium transition-colors',
              'border-b-2 -mb-px relative',
              activeTab === id
                ? 'border-primary text-foreground'
                : 'border-transparent text-muted-foreground hover:text-foreground hover:border-border',
              disabled && 'opacity-40 cursor-not-allowed pointer-events-none'
            )}
          >
            {pending ? (
              <Loader2 className="h-2 w-2 animate-spin text-muted-foreground" />
            ) : dot === 'purple' ? (
              <span className="h-1.5 w-1.5 rounded-full bg-purple-500 shrink-0" />
            ) : dot === 'blue' ? (
              <span className="h-1.5 w-1.5 rounded-full bg-blue-500 shrink-0" />
            ) : (id === 'ai' || id === 'related') ? (
              <Plus className="h-2.5 w-2.5 shrink-0 opacity-40" />
            ) : null}
            {label}
            {count != null && (
              <span className="text-xs text-muted-foreground">({count})</span>
            )}
          </button>
        ))}
      </div>

      {/* Tab Content */}
      <div className="flex-1 relative overflow-hidden" ref={scrollAreaRef}>
      <ScrollArea className="h-full">
        {/* Article Tab */}
        {activeTab === 'article' && (
          <article className="max-w-3xl mx-auto p-8">
            <header className="mb-8">
              <h1 className="text-3xl font-bold mb-4 leading-tight">
                {article.title}
              </h1>

              <div className="flex items-center gap-3 text-sm text-muted-foreground">
                <Badge variant="secondary">{article.feed_name}</Badge>
                {article.author && <span>by {article.author}</span>}
                <span>·</span>
                <time>{formatFullDate(article.published_at)}</time>
              </div>

              {article.source_url && article.source_url !== article.url && (
                <div className="mt-2">
                  <a
                    href={article.source_url}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="text-sm text-primary hover:underline inline-flex items-center gap-1"
                  >
                    Original source: {getDomain(article.source_url)}
                    <ExternalLink className="h-3 w-3" />
                  </a>
                </div>
              )}
            </header>

            {hasContent ? (
              <div
                className="article-content prose prose-slate dark:prose-invert max-w-none"
                dangerouslySetInnerHTML={{ __html: article.content || '' }}
                onClick={(e) => {
                  const target = e.target as HTMLElement
                  const anchor = target.closest('a')
                  if (anchor && anchor.href) {
                    e.preventDefault()
                    window.open(anchor.href, '_blank', 'noopener,noreferrer')
                  }
                }}
              />
            ) : (
              <div className="text-center py-12 text-muted-foreground">
                <p>Content not available</p>
                <div className="mt-4 flex flex-col items-center gap-2">
                  <Button
                    variant="outline"
                    onClick={handleFetchContent}
                    disabled={fetchContent.isPending}
                  >
                    {fetchContent.isPending ? (
                      <>
                        <Loader2 className="h-4 w-4 mr-2 animate-spin" />
                        Fetching...
                      </>
                    ) : (
                      <>
                        <Download className="h-4 w-4 mr-2" />
                        Fetch Full Article
                      </>
                    )}
                  </Button>
                  <Button
                    variant="ghost"
                    size="sm"
                    onClick={() => setShowPasteDialog(true)}
                  >
                    <ClipboardPaste className="h-4 w-4 mr-2" />
                    Paste from Browser
                  </Button>
                </div>
                <p className="mt-4 text-sm">
                  Or{' '}
                  <a
                    href={article.url}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="text-primary hover:underline"
                  >
                    read on {getDomain(article.url)}
                  </a>
                </p>
              </div>
            )}

            <footer className="mt-12 pt-8 border-t border-border">
              <div className="flex items-center justify-between text-sm text-muted-foreground">
                <a
                  href={article.url}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="hover:text-foreground inline-flex items-center gap-1"
                >
                  View original on {getDomain(article.url)}
                  <ExternalLink className="h-3 w-3" />
                </a>
              </div>
            </footer>
          </article>
        )}

        {/* AI Summary Tab */}
        {activeTab === 'ai' && (
          <div className="max-w-3xl mx-auto p-8">
            {hasSummary ? (
              <div className="space-y-6">
                <div className="flex items-center justify-between">
                  <div className="flex items-center gap-2">
                    <Sparkles className="h-5 w-5 text-purple-500" />
                    <h2 className="text-lg font-semibold text-purple-700 dark:text-purple-300">
                      AI Summary
                    </h2>
                    {article.model_used && (
                      <Badge variant="outline" className="text-xs">
                        {article.model_used}
                      </Badge>
                    )}
                  </div>
                  <Button
                    variant="ghost"
                    size="sm"
                    onClick={() => {
                      const text = [
                        article.summary_full,
                        article.key_points?.length
                          ? '\nKey Points:\n' + article.key_points.map(p => `• ${p}`).join('\n')
                          : '',
                        `\n${getDomain(article.url)}\n${article.url}`,
                      ].filter(Boolean).join('\n')
                      navigator.clipboard.writeText(text)
                      showToast('Summary copied', 'success')
                    }}
                  >
                    Copy
                  </Button>
                </div>

                {article.summary_full && (
                  <p className="text-base leading-relaxed">
                    {smartQuotes(article.summary_full)}
                  </p>
                )}

                {article.key_points && article.key_points.length > 0 && (
                  <div>
                    <h3 className="text-sm font-semibold mb-3">Key Points</h3>
                    <ul className="space-y-2">
                      {article.key_points.map((point, i) => (
                        <li key={i} className="flex gap-2 text-sm">
                          <span className="text-purple-500 shrink-0 mt-0.5">•</span>
                          {smartQuotes(point)}
                        </li>
                      ))}
                    </ul>
                  </div>
                )}

                <div className="pt-4 border-t border-border">
                  <a
                    href={article.url}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="text-xs text-muted-foreground hover:text-purple-600 dark:hover:text-purple-400 inline-flex items-center gap-1"
                  >
                    Source: {getDomain(article.url)}
                    <ExternalLink className="h-3 w-3" />
                  </a>
                </div>
              </div>
            ) : (
              <div className="text-center py-16 text-muted-foreground">
                {summarize.isPending ? (
                  <div className="flex flex-col items-center gap-3">
                    <Loader2 className="h-10 w-10 animate-spin text-purple-500" />
                    <p className="font-medium">Generating summary…</p>
                    <p className="text-sm">This may take a few seconds</p>
                  </div>
                ) : (
                  <div className="flex flex-col items-center gap-4">
                    <Sparkles className="h-12 w-12 opacity-20" />
                    <div>
                      <p className="text-lg font-medium mb-1">No summary yet</p>
                      <p className="text-sm">Generate an AI summary to see key insights and highlights</p>
                    </div>
                    <SmartTooltip
                      hintId="summarize-tip"
                      title="AI Summarization"
                      body="Generates key points, a one-sentence brief, and a full summary using Claude or GPT."
                      side="top"
                    >
                      <Button onClick={handleSummarize} disabled={!!article.summary_full}>
                        <Sparkles className="h-4 w-4 mr-2" />
                        Generate Summary
                      </Button>
                    </SmartTooltip>
                  </div>
                )}
              </div>
            )}
          </div>
        )}

        {/* Related Tab */}
        {activeTab === 'related' && (
          <div className="max-w-3xl mx-auto p-8">
            {hasTriggeredRelated || relatedCount > 0 || findRelated.isPending ? (
              <RelatedLinks
                relatedLinks={article.related_links}
                isLoading={findRelated.isPending}
                error={article.related_links_error || findRelated.error?.message || null}
                hasTriggered={hasTriggeredRelated}
              />
            ) : (
              <div className="text-center py-16 text-muted-foreground">
                <Link2 className="h-12 w-12 mx-auto mb-4 opacity-20" />
                <p className="text-lg font-medium mb-2">Find related articles</p>
                <p className="text-sm mb-6">
                  Discover semantically similar content using neural search
                </p>
                <Button onClick={handleFindRelated}>
                  <Link2 className="h-4 w-4 mr-2" />
                  Find Related Articles
                </Button>
              </div>
            )}
          </div>
        )}

        {/* Chat Tab */}
        {activeTab === 'chat' && hasSummary && (
          <div className="max-w-3xl mx-auto p-8">
            <ArticleChat
              articleId={article.id}
              isExpanded={true}
            />
          </div>
        )}
      </ScrollArea>

      {/* Floating "Jump to AI Summary" chip */}
      {hasSummary && activeTab === 'article' && showSummaryChip && (
        <div className="absolute bottom-6 right-6 z-10 pointer-events-none">
          <button
            className="pointer-events-auto flex items-center gap-2 px-4 py-2 rounded-full bg-purple-600 text-white text-sm font-medium shadow-lg hover:bg-purple-700 active:scale-95 transition-all animate-in slide-in-from-bottom-2 duration-200"
            onClick={() => setActiveTab('ai')}
          >
            <Sparkles className="h-3.5 w-3.5" />
            AI Summary
          </button>
        </div>
      )}
      </div>

      {/* Paste HTML Dialog */}
      {showPasteDialog && (
        <div className="fixed inset-0 z-50 flex items-center justify-center">
          <div
            className="absolute inset-0 bg-black/50"
            onClick={() => {
              setShowPasteDialog(false)
              setPastedHtml('')
            }}
          />
          <div className="relative bg-background border border-border rounded-lg shadow-lg w-full max-w-2xl mx-4 max-h-[80vh] flex flex-col">
            <div className="flex items-center justify-between p-4 border-b border-border">
              <div>
                <h2 className="text-lg font-semibold">Paste from Browser</h2>
                <p className="text-sm text-muted-foreground mt-1">
                  Select the article content in your browser, copy it (Ctrl/Cmd+C), then click below and paste (Ctrl/Cmd+V).
                </p>
              </div>
              <Button
                variant="ghost"
                size="icon"
                onClick={() => {
                  setShowPasteDialog(false)
                  setPastedHtml('')
                }}
              >
                <X className="h-4 w-4" />
              </Button>
            </div>
            <div className="flex-1 p-4 overflow-hidden">
              <div
                className={cn(
                  "w-full h-64 p-3 text-sm border border-input rounded-md bg-background overflow-auto focus:outline-none focus:ring-2 focus:ring-ring cursor-text",
                  !pastedHtml && "flex items-center justify-center"
                )}
                tabIndex={0}
                onPaste={(e) => {
                  e.preventDefault()
                  const html = e.clipboardData.getData('text/html')
                  const text = e.clipboardData.getData('text/plain')
                  if (html) {
                    setPastedHtml(html)
                  } else if (text) {
                    setPastedHtml(`<div>${text.split('\n').map(line => `<p>${line}</p>`).join('')}</div>`)
                  }
                }}
              >
                {pastedHtml ? (
                  <div className="space-y-2">
                    <div className="flex items-center gap-2 text-xs text-muted-foreground pb-2 border-b border-border">
                      <Check className="h-3 w-3 text-green-500" />
                      <span>Content captured ({Math.round(pastedHtml.length / 1024)}KB)</span>
                      <Button
                        variant="ghost"
                        size="sm"
                        className="h-6 px-2 ml-auto text-xs"
                        onClick={() => setPastedHtml('')}
                      >
                        Clear
                      </Button>
                    </div>
                    <div
                      className="prose prose-sm dark:prose-invert max-w-none max-h-48 overflow-auto"
                      dangerouslySetInnerHTML={{ __html: pastedHtml }}
                    />
                  </div>
                ) : (
                  <div className="text-muted-foreground text-center">
                    <ClipboardPaste className="h-8 w-8 mx-auto mb-2 opacity-50" />
                    <p>Click here and paste (Ctrl/Cmd+V)</p>
                    <p className="text-xs mt-1 opacity-70">The HTML formatting will be preserved</p>
                  </div>
                )}
              </div>
            </div>
            <div className="flex items-center justify-end gap-2 p-4 border-t border-border">
              <Button
                variant="outline"
                onClick={() => {
                  setShowPasteDialog(false)
                  setPastedHtml('')
                }}
              >
                Cancel
              </Button>
              <Button
                onClick={handleExtractFromHtml}
                disabled={!pastedHtml.trim() || extractFromHtml.isPending}
              >
                {extractFromHtml.isPending ? (
                  <>
                    <Loader2 className="h-4 w-4 mr-2 animate-spin" />
                    Extracting...
                  </>
                ) : (
                  'Extract Content'
                )}
              </Button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
