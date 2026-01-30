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
} from 'lucide-react'
import { cn } from '@/lib/utils'
import { formatFullDate, getDomain } from '@/lib/utils'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { ScrollArea } from '@/components/ui/scroll-area'
import { Skeleton } from '@/components/ui/skeleton'
import { Separator } from '@/components/ui/separator'
import { Tooltip } from '@/components/ui/tooltip'
import { useToast } from '@/components/ui/toast'
import { useAppStore } from '@/store/app-store'
import {
  useArticle,
  useMarkArticleRead,
  useToggleBookmark,
  useFetchContent,
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
  const summarize = useSummarizeArticle()
  const findRelated = useFindRelatedLinks()
  const { data: chatHistory } = useChatHistory(selectedArticleId)
  const { showToast } = useToast()

  const [showSummary, setShowSummary] = useState(true)
  const [hasTriggeredRelated, setHasTriggeredRelated] = useState(false)
  const [isChatExpanded, setIsChatExpanded] = useState(false)

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

        {!hasContent && (
          <Button
            variant="ghost"
            size="sm"
            onClick={handleFetchContent}
            disabled={fetchContent.isPending}
          >
            {fetchContent.isPending ? (
              <Loader2 className="h-4 w-4 mr-1 animate-spin" />
            ) : (
              <ExternalLink className="h-4 w-4 mr-1" />
            )}
            Fetch Content
          </Button>
        )}

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
              onClick={() => setIsChatExpanded(!isChatExpanded)}
            >
              <MessageCircle
                className={cn(
                  'h-4 w-4 mr-1',
                  chatHistory?.has_chat && 'text-blue-500'
                )}
              />
              {chatHistory?.has_chat ? 'Chatted' : 'Chat'}
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
                      {article.summary_full}
                    </p>
                  )}

                  {article.key_points && article.key_points.length > 0 && (
                    <div>
                      <h4 className="text-sm font-semibold mb-2">Key Points</h4>
                      <ul className="list-disc list-inside space-y-1 text-sm">
                        {article.key_points.map((point, i) => (
                          <li key={i}>{point}</li>
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
            onFindRelated={handleFindRelated}
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
            />
          ) : (
            <div className="text-center py-12 text-muted-foreground">
              <p>Content not available</p>
              <Button
                variant="outline"
                className="mt-4"
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
                    <ExternalLink className="h-4 w-4 mr-2" />
                    Fetch Full Content
                  </>
                )}
              </Button>
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
    </div>
  )
}
