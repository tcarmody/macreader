import { useState } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import {
  RefreshCw,
  ExternalLink,
  Newspaper,
  ChevronDown,
  ChevronUp,
  Loader2,
  AlertCircle,
  Copy,
  Check,
} from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { ScrollArea } from '@/components/ui/scroll-area'
import { Separator } from '@/components/ui/separator'
import { Skeleton } from '@/components/ui/skeleton'
import { cn, formatDate } from '@/lib/utils'
import * as api from '@/api/client'
import type { AutoDigestResponse, DigestSection, DigestArticle } from '@/types'

type Period = 'today' | 'week'

// ─── Section component ────────────────────────────────────────────────────────

function DigestArticleRow({ article }: { article: DigestArticle }) {
  return (
    <div className="py-3">
      <div className="flex items-start gap-2">
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2 flex-wrap mb-1">
            <a
              href={article.url}
              target="_blank"
              rel="noopener noreferrer"
              className="font-medium text-sm hover:underline leading-tight"
            >
              {article.title}
            </a>
            {article.story_group_size > 1 && (
              <Badge variant="secondary" className="text-xs shrink-0">
                {article.story_group_size} sources
              </Badge>
            )}
          </div>
          {article.brief && (
            <p className="text-sm text-muted-foreground leading-relaxed">
              {article.brief}
            </p>
          )}
          <div className="flex items-center gap-2 mt-1.5">
            {article.source && (
              <span className="text-xs text-muted-foreground">{article.source}</span>
            )}
            {article.source && article.published_at && (
              <span className="text-xs text-muted-foreground">·</span>
            )}
            {article.published_at && (
              <span className="text-xs text-muted-foreground">
                {formatDate(article.published_at)}
              </span>
            )}
            <a
              href={article.url}
              target="_blank"
              rel="noopener noreferrer"
              className="text-xs text-muted-foreground hover:text-foreground ml-auto flex items-center gap-1"
            >
              Read
              <ExternalLink className="h-3 w-3" />
            </a>
          </div>
        </div>
      </div>
    </div>
  )
}

function DigestSectionBlock({ section }: { section: DigestSection }) {
  const [collapsed, setCollapsed] = useState(false)

  return (
    <div>
      <button
        onClick={() => setCollapsed(!collapsed)}
        className="w-full flex items-center gap-2 py-2 text-left group"
      >
        <h2 className="text-sm font-semibold uppercase tracking-wide text-muted-foreground group-hover:text-foreground transition-colors">
          {section.label}
        </h2>
        <Badge variant="outline" className="text-xs">
          {section.articles.length}
        </Badge>
        <span className="ml-auto text-muted-foreground">
          {collapsed
            ? <ChevronDown className="h-3.5 w-3.5" />
            : <ChevronUp className="h-3.5 w-3.5" />
          }
        </span>
      </button>
      {!collapsed && (
        <div className="divide-y divide-border">
          {section.articles.map((article) => (
            <DigestArticleRow key={article.id} article={article} />
          ))}
        </div>
      )}
    </div>
  )
}

// ─── Digest controls ─────────────────────────────────────────────────────────

function DigestControls({
  period,
  onPeriodChange,
  onRefresh,
  isRefreshing,
  digest,
}: {
  period: Period
  onPeriodChange: (p: Period) => void
  onRefresh: () => void
  isRefreshing: boolean
  digest: AutoDigestResponse | undefined
}) {
  const [copied, setCopied] = useState(false)

  const handleCopy = async () => {
    if (!digest?.raw) return
    await navigator.clipboard.writeText(digest.raw)
    setCopied(true)
    setTimeout(() => setCopied(false), 2000)
  }

  return (
    <div className="flex items-center gap-2 px-4 py-3 border-b border-border bg-card">
      {/* Period toggle */}
      <div className="flex rounded-md border border-border overflow-hidden text-xs">
        <button
          className={cn(
            "px-3 py-1.5 transition-colors",
            period === 'today'
              ? "bg-secondary text-secondary-foreground"
              : "text-muted-foreground hover:text-foreground hover:bg-muted"
          )}
          onClick={() => onPeriodChange('today')}
        >
          Today
        </button>
        <button
          className={cn(
            "px-3 py-1.5 border-l border-border transition-colors",
            period === 'week'
              ? "bg-secondary text-secondary-foreground"
              : "text-muted-foreground hover:text-foreground hover:bg-muted"
          )}
          onClick={() => onPeriodChange('week')}
        >
          This Week
        </button>
      </div>

      <div className="ml-auto flex items-center gap-2">
        {digest && (
          <>
            <span className="text-xs text-muted-foreground">
              {digest.story_count} {digest.story_count === 1 ? 'story' : 'stories'}
              {digest.cached && ' · cached'}
            </span>
            <Button
              variant="ghost"
              size="icon"
              className="h-7 w-7"
              onClick={handleCopy}
              title="Copy as markdown"
            >
              {copied ? <Check className="h-3.5 w-3.5" /> : <Copy className="h-3.5 w-3.5" />}
            </Button>
          </>
        )}
        <Button
          variant="ghost"
          size="icon"
          className="h-7 w-7"
          onClick={onRefresh}
          disabled={isRefreshing}
          title="Regenerate digest"
        >
          <RefreshCw className={cn("h-3.5 w-3.5", isRefreshing && "animate-spin")} />
        </Button>
      </div>
    </div>
  )
}

// ─── Loading skeleton ─────────────────────────────────────────────────────────

function DigestSkeleton() {
  return (
    <div className="p-6 space-y-6">
      <div className="space-y-2">
        <Skeleton className="h-5 w-48" />
        <Skeleton className="h-4 w-full" />
        <Skeleton className="h-4 w-3/4" />
      </div>
      {[1, 2, 3].map((i) => (
        <div key={i} className="space-y-3">
          <Skeleton className="h-4 w-24" />
          {[1, 2].map((j) => (
            <div key={j} className="space-y-1.5 pl-0">
              <Skeleton className="h-4 w-3/4" />
              <Skeleton className="h-3.5 w-full" />
              <Skeleton className="h-3.5 w-2/3" />
            </div>
          ))}
        </div>
      ))}
    </div>
  )
}

// ─── Main view ────────────────────────────────────────────────────────────────

export function DigestView() {
  const [period, setPeriod] = useState<Period>('today')
  const queryClient = useQueryClient()

  const { data: digest, isLoading, error } = useQuery({
    queryKey: ['digest', period],
    queryFn: () => api.getAutoDigest({ period }),
    staleTime: 5 * 60 * 1000, // treat as fresh for 5 min
  })

  const refresh = useMutation({
    mutationFn: () => api.getAutoDigest({ period, refresh: true }),
    onSuccess: (data) => {
      queryClient.setQueryData(['digest', period], data)
    },
  })

  const handlePeriodChange = (p: Period) => {
    setPeriod(p)
  }

  return (
    <div className="flex-1 flex flex-col overflow-hidden">
      <DigestControls
        period={period}
        onPeriodChange={handlePeriodChange}
        onRefresh={() => refresh.mutate()}
        isRefreshing={refresh.isPending}
        digest={digest}
      />

      <ScrollArea className="flex-1">
        {isLoading ? (
          <DigestSkeleton />
        ) : error ? (
          <div className="flex flex-col items-center justify-center h-64 text-center p-8 gap-3">
            <AlertCircle className="h-8 w-8 text-muted-foreground" />
            <div>
              <p className="font-medium">Could not load digest</p>
              <p className="text-sm text-muted-foreground mt-1">
                {error instanceof Error ? error.message : 'An error occurred'}
              </p>
            </div>
            <Button variant="outline" size="sm" onClick={() => refresh.mutate()}>
              Try again
            </Button>
          </div>
        ) : !digest || digest.story_count === 0 ? (
          <div className="flex flex-col items-center justify-center h-64 text-center p-8 gap-3">
            <Newspaper className="h-8 w-8 text-muted-foreground" />
            <div>
              <p className="font-medium">No stories yet</p>
              <p className="text-sm text-muted-foreground mt-1">
                Add some feeds and refresh to see your digest.
              </p>
            </div>
          </div>
        ) : (
          <div className="max-w-2xl mx-auto px-6 py-6">
            {/* Title + intro */}
            <div className="mb-6">
              <h1 className="text-xl font-semibold mb-2">{digest.title}</h1>
              <p className="text-sm text-muted-foreground leading-relaxed">{digest.intro}</p>
            </div>

            <Separator className="mb-6" />

            {/* Sections */}
            <div className="space-y-4">
              {digest.sections.map((section, i) => (
                <div key={section.label}>
                  <DigestSectionBlock section={section} />
                  {i < digest.sections.length - 1 && <Separator className="mt-4" />}
                </div>
              ))}
            </div>

            {/* Footer */}
            <div className="mt-8 pt-4 border-t border-border flex items-center justify-between text-xs text-muted-foreground">
              <span>{digest.word_count} words · {digest.story_count} stories</span>
              {digest.cached && <span>Cached · refreshes every 2 hours</span>}
            </div>
          </div>
        )}
      </ScrollArea>

      {/* Loading overlay during refresh */}
      {refresh.isPending && (
        <div className="absolute inset-0 bg-background/50 flex items-center justify-center">
          <div className="flex items-center gap-2 text-sm text-muted-foreground bg-card border border-border rounded-lg px-4 py-2 shadow-sm">
            <Loader2 className="h-4 w-4 animate-spin" />
            Generating digest…
          </div>
        </div>
      )}
    </div>
  )
}
