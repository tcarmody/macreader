import { BookMarked, Star, Sparkles, FileText, Link as LinkIcon } from 'lucide-react'
import { cn, formatDate, stripHtml, smartQuotes } from '@/lib/utils'
import { SourceTag } from '@/components/ui/source-tag'
import type { Article, StandaloneItem } from '@/types'

// A roomy, casual-friendly reading card. Used across Home / Highlights /
// Bookmarked / Search. Single-column, responsive, no power-user jargon.

function cardSummary(a: Article): string | null {
  if (a.key_points?.[0]) return a.key_points[0]
  if (a.brief) return a.brief
  if (a.summary_short) return stripHtml(a.summary_short)
  return null
}

export function ArticleCard({
  article,
  onOpen,
}: {
  article: Article
  onOpen: (article: Article) => void
}) {
  const summary = cardSummary(article)

  return (
    <button
      onClick={() => onOpen(article)}
      className={cn(
        'w-full text-left rounded-xl border border-border bg-card p-4 sm:p-5 transition-colors',
        'hover:border-primary/40 hover:bg-muted/40',
        !article.is_read && 'border-l-2 border-l-primary'
      )}
    >
      <div className="flex items-center gap-2 text-xs text-muted-foreground mb-2">
        <span className="shrink-0">{formatDate(article.published_at)}</span>
        <div className="ml-auto flex items-center gap-1.5">
          {article.is_featured && <Star className="h-3.5 w-3.5 text-amber-400 fill-amber-400" />}
          {article.is_bookmarked && <BookMarked className="h-3.5 w-3.5 text-amber-500" />}
        </div>
      </div>

      <h3 className={cn('text-base sm:text-lg leading-snug', !article.is_read ? 'font-semibold' : 'font-medium')}>
        {article.title}
        <SourceTag name={article.feed_name} variant="caps" className="ml-2 align-middle" />
      </h3>

      {summary && (
        <p className="mt-1.5 text-sm text-muted-foreground line-clamp-2 leading-relaxed">
          {smartQuotes(summary)}
        </p>
      )}

      {article.summary_short && (
        <div className="mt-2.5 inline-flex items-center gap-1 text-xs text-purple-600/80 dark:text-purple-300/80">
          <Sparkles className="h-3 w-3" />
          AI summary inside
        </div>
      )}
    </button>
  )
}

export function LibraryCard({
  item,
  onOpen,
}: {
  item: StandaloneItem
  onOpen: (item: StandaloneItem) => void
}) {
  const Icon = item.content_type === 'url' ? LinkIcon : FileText

  return (
    <button
      onClick={() => onOpen(item)}
      className={cn(
        'w-full text-left rounded-xl border border-border bg-card p-4 sm:p-5 transition-colors',
        'hover:border-primary/40 hover:bg-muted/40'
      )}
    >
      <div className="flex items-center gap-2 text-xs text-muted-foreground mb-1.5">
        <Icon className="h-3.5 w-3.5" />
        <span className="uppercase tracking-wide">{item.content_type}</span>
        <span>·</span>
        <span>{formatDate(item.created_at)}</span>
        <div className="ml-auto flex items-center gap-1.5">
          {item.is_bookmarked && <BookMarked className="h-3.5 w-3.5 text-amber-500" />}
        </div>
      </div>

      <h3 className="text-base sm:text-lg font-medium leading-snug line-clamp-2">{item.title}</h3>

      {item.summary_short && (
        <p className="mt-1.5 text-sm text-muted-foreground line-clamp-2 leading-relaxed">
          {smartQuotes(stripHtml(item.summary_short))}
        </p>
      )}
    </button>
  )
}
