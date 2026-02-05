import { useState, useEffect } from 'react'
import {
  BookMarked,
  ExternalLink,
  Sparkles,
  Check,
  Circle,
  Share2,
  Loader2,
  ChevronDown,
  ChevronUp,
  Info,
  Link2,
  MessageCircle,
  Download,
  ClipboardPaste,
  X,
} from 'lucide-react'
import { cn, formatFullDate, getDomain, smartQuotes } from '@/lib/utils'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { ScrollArea } from '@/components/ui/scroll-area'
import { Skeleton } from '@/components/ui/skeleton'
import { Separator } from '@/components/ui/separator'
import { Tooltip } from '@/components/ui/tooltip'
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

  const [showSummary, setShowSummary] = useState(true)
  const [hasTriggeredRelated, setHasTriggeredRelated] = useState(false)
  const [isChatExpanded, setIsChatExpanded] = useState(false)
  const [showPasteDialog, setShowPasteDialog] = useState(false)
  const [pastedHtml, setPastedHtml] = useState('')

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

  // Reset hasTriggeredRelated and chat state when article changes
  useEffect(() => {
    setHasTriggeredRelated(false)
    setIsChatExpanded(false)
  }, [selectedArticleId])

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
    summarize.mutate(article.id)
  }

  const handleFindRelated = () => {
    setHasTriggeredRelated(true)
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

        <Button
          variant="ghost"
          size="sm"
          onClick={handleToggleBookmark}
          className={cn(article.is_bookmarked && "text-amber-500")}
        >
          <BookMarked className={cn("h-4 w-4 mr-1", article.is_bookmarked && "fill-amber-500")} />
          {article.is_bookmarked ? 'Saved' : 'Save'}
        </Button>

        <Separator orientation="vertical" className="h-6" />

        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <Button
              variant="ghost"
              size="sm"
              disabled={fetchContent.isPending || extractFromHtml.isPending}
            >
              {fetchContent.isPending || extractFromHtml.isPending ? (
                <Loader2 className="h-4 w-4 mr-1 animate-spin" />
              ) : (
                <Download className="h-4 w-4 mr-1" />
              )}
              {hasContent ? 'Refetch' : 'Fetch'}
              <ChevronDown className="h-3 w-3 ml-1" />
            </Button>
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

        <Tooltip
          content="AI generates a concise summary using your configured provider (Anthropic, OpenAI, or Google)"
          side="bottom"
        >
          <Button
            variant="ghost"
            size="sm"
            onClick={handleSummarize}
            disabled={summarize.isPending || !!article.summary_full}
          >
            {summarize.isPending ? (
              <Loader2 className="h-4 w-4 mr-1 animate-spin" />
            ) : (
              <Sparkles className={cn("h-4 w-4 mr-1", hasSummary && "text-purple-500")} />
            )}
            {hasSummary ? 'Summarized' : 'Summarize'}
            {!hasSummary && <Info className="h-2.5 w-2.5 ml-1 opacity-50" />}
          </Button>
        </Tooltip>

        <Tooltip
          content="Find semantically related articles using neural search"
          side="bottom"
        >
          <Button
            variant="ghost"
            size="sm"
            onClick={handleFindRelated}
            disabled={findRelated.isPending || (!!article.related_links && article.related_links.length > 0)}
          >
            {findRelated.isPending ? (
              <Loader2 className="h-4 w-4 mr-1 animate-spin" />
            ) : (
              <Link2 className={cn(
                "h-4 w-4 mr-1",
                article.related_links && article.related_links.length > 0 && "text-blue-500"
              )} />
            )}
            {article.related_links && article.related_links.length > 0 ? 'Contextualized' : 'Context'}
            {(!article.related_links || article.related_links.length === 0) && (
              <Info className="h-2.5 w-2.5 ml-1 opacity-50" />
            )}
          </Button>
        </Tooltip>

        {hasSummary && (
          <Tooltip content="Ask questions and refine the summary" side="bottom">
            <Button
              variant="ghost"
              size="sm"
              onClick={() => {
                setIsChatExpanded(true)
                // Scroll to chat section
                setTimeout(() => {
                  document.getElementById('article-chat')?.scrollIntoView({
                    behavior: 'smooth',
                    block: 'start',
                  })
                }, 100)
              }}
            >
              <MessageCircle
                className={cn(
                  'h-4 w-4 mr-1',
                  chatHistory?.has_chat && 'text-blue-500'
                )}
              />
              Chat
              {!chatHistory?.has_chat && (
                <Info className="h-2.5 w-2.5 ml-1 opacity-50" />
              )}
            </Button>
          </Tooltip>
        )}

        <div className="ml-auto flex items-center gap-1">
          <Button variant="ghost" size="sm" onClick={handleShare}>
            <Share2 className="h-4 w-4" />
          </Button>
          <Button variant="ghost" size="sm" onClick={handleOpenExternal}>
            <ExternalLink className="h-4 w-4" />
          </Button>
        </div>
      </div>

      {/* Article Content */}
      <ScrollArea className="flex-1">
        <article className="max-w-3xl mx-auto p-8">
          {/* Header */}
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

            {/* Quick Actions */}
            <div className="flex flex-wrap items-center gap-2 mt-4 pt-4 border-t border-border">
              <Button
                variant="outline"
                size="sm"
                onClick={handleFetchContent}
                disabled={fetchContent.isPending}
              >
                {fetchContent.isPending ? (
                  <Loader2 className="h-4 w-4 mr-2 animate-spin" />
                ) : (
                  <Download className="h-4 w-4 mr-2" />
                )}
                {hasContent ? 'Refetch Content' : 'Fetch Full Content'}
              </Button>
              <Button
                variant="outline"
                size="sm"
                onClick={() => setShowPasteDialog(true)}
                disabled={extractFromHtml.isPending}
              >
                <ClipboardPaste className="h-4 w-4 mr-2" />
                Paste from Browser
              </Button>
              <Button
                variant="outline"
                size="sm"
                onClick={handleFindRelated}
                disabled={findRelated.isPending || (!!article.related_links && article.related_links.length > 0)}
              >
                {findRelated.isPending ? (
                  <Loader2 className="h-4 w-4 mr-2 animate-spin" />
                ) : (
                  <Link2 className="h-4 w-4 mr-2" />
                )}
                {article.related_links && article.related_links.length > 0 ? 'Related Found' : 'Find Related Articles'}
              </Button>
            </div>
          </header>

          {/* Summary Section */}
          {hasSummary && (
            <section className="mb-8 p-4 bg-purple-500/5 border border-purple-500/20 rounded-lg">
              <button
                onClick={() => setShowSummary(!showSummary)}
                className="w-full flex items-center justify-between text-left"
              >
                <div className="flex items-center gap-2">
                  <Sparkles className="h-4 w-4 text-purple-500" />
                  <span className="font-semibold text-purple-700 dark:text-purple-300">
                    AI Summary
                  </span>
                  {article.model_used && (
                    <Badge variant="outline" className="text-xs">
                      {article.model_used}
                    </Badge>
                  )}
                </div>
                {showSummary ? (
                  <ChevronUp className="h-4 w-4 text-muted-foreground" />
                ) : (
                  <ChevronDown className="h-4 w-4 text-muted-foreground" />
                )}
              </button>

              {showSummary && (
                <div className="mt-4 space-y-4">
                  {article.summary_full && (
                    <p className="text-sm leading-relaxed">
                      {smartQuotes(article.summary_full)}
                    </p>
                  )}

                  {article.key_points && article.key_points.length > 0 && (
                    <div>
                      <h4 className="text-sm font-semibold mb-2">Key Points</h4>
                      <ul className="list-disc list-inside space-y-1 text-sm">
                        {article.key_points.map((point, i) => (
                          <li key={i}>{smartQuotes(point)}</li>
                        ))}
                      </ul>
                    </div>
                  )}
                </div>
              )}
            </section>
          )}

          {/* Related Links Section */}
          <RelatedLinks
            relatedLinks={article.related_links}
            isLoading={findRelated.isPending}
            error={article.related_links_error || findRelated.error?.message || null}
            hasTriggered={hasTriggeredRelated}
          />

          {/* Chat Section - for Q&A and summary refinement */}
          {hasSummary && (
            <ArticleChat
              articleId={article.id}
              isExpanded={isChatExpanded}
              onExpandedChange={setIsChatExpanded}
            />
          )}

          {/* Main Content */}
          {hasContent ? (
            <div
              className="article-content prose prose-slate dark:prose-invert max-w-none"
              dangerouslySetInnerHTML={{ __html: article.content || '' }}
              onClick={(e) => {
                // Open external links in new tab
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

          {/* Footer */}
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
      </ScrollArea>

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
                  // Try to get HTML content first, fall back to plain text
                  const html = e.clipboardData.getData('text/html')
                  const text = e.clipboardData.getData('text/plain')
                  if (html) {
                    setPastedHtml(html)
                  } else if (text) {
                    // Wrap plain text in basic HTML structure
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
