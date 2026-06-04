import { Star, Newspaper, ChevronRight, Loader2 } from 'lucide-react'
import { cn } from '@/lib/utils'
import { Button } from '@/components/ui/button'
import { EmptyState } from '@/components/ui/empty-state'
import { useAppStore } from '@/store/app-store'
import { useArticles, useFeeds } from '@/hooks/use-queries'
import type { FilterType } from '@/types'
import { ArticleCard } from './ArticleCard'
import { useOpenReader } from './use-open-reader'

export function HomeView() {
  const { casualSourceFilter, setCasualSourceFilter, setCasualView } = useAppStore()
  const { openArticle } = useOpenReader()

  // Featured highlights (admin-curated) for the top strip
  const { data: featuredData } = useArticles('featured', 'newest')
  const featured = (featuredData?.pages.flat() ?? []).slice(0, 6)

  // Source chips
  const { data: feeds = [] } = useFeeds()
  const topSources = [...feeds]
    .sort((a, b) => b.unread_count - a.unread_count)
    .slice(0, 12)

  // Latest stream, optionally filtered to a single source
  const latestFilter: FilterType =
    casualSourceFilter != null ? { type: 'feed', feedId: casualSourceFilter } : 'all'
  const {
    data: latestData,
    isLoading,
    fetchNextPage,
    hasNextPage,
    isFetchingNextPage,
  } = useArticles(latestFilter, 'newest')
  const latest = latestData?.pages.flat() ?? []

  return (
    <div className="mx-auto w-full max-w-2xl px-4 py-6 sm:py-8">
      {/* Featured highlights */}
      {featured.length > 0 && (
        <section className="mb-8">
          <div className="mb-3 flex items-center gap-2">
            <Star className="h-4 w-4 text-amber-400 fill-amber-400" />
            <h2 className="text-sm font-semibold uppercase tracking-wide text-muted-foreground">
              Highlights
            </h2>
          </div>
          <div className="space-y-3">
            {featured.map((article) => (
              <ArticleCard key={article.id} article={article} onOpen={openArticle} />
            ))}
          </div>
        </section>
      )}

      {/* Digest call-to-action */}
      <button
        onClick={() => setCasualView('digest')}
        className="mb-8 flex w-full items-center gap-3 rounded-xl border border-border bg-muted/30 p-4 text-left transition-colors hover:bg-muted/60"
      >
        <Newspaper className="h-5 w-5 text-primary shrink-0" />
        <div className="flex-1 min-w-0">
          <p className="text-sm font-medium">Today's digest</p>
          <p className="text-xs text-muted-foreground">The day's stories, summarized for you</p>
        </div>
        <ChevronRight className="h-4 w-4 text-muted-foreground" />
      </button>

      {/* Latest */}
      <section>
        <div className="mb-3 flex items-center justify-between">
          <h2 className="text-sm font-semibold uppercase tracking-wide text-muted-foreground">Latest</h2>
        </div>

        {/* Source chips */}
        {topSources.length > 0 && (
          <div className="mb-4 -mx-1 flex gap-1.5 overflow-x-auto pb-1 [scrollbar-width:none] [&::-webkit-scrollbar]:hidden">
            <SourceChip
              label="All"
              active={casualSourceFilter == null}
              onClick={() => setCasualSourceFilter(null)}
            />
            {topSources.map((feed) => (
              <SourceChip
                key={feed.id}
                label={feed.name}
                active={casualSourceFilter === feed.id}
                onClick={() => setCasualSourceFilter(feed.id)}
              />
            ))}
          </div>
        )}

        {isLoading ? (
          <div className="flex justify-center py-12">
            <Loader2 className="h-6 w-6 animate-spin text-muted-foreground" />
          </div>
        ) : latest.length === 0 ? (
          <EmptyState
            icon={Newspaper}
            title="Nothing here yet"
            description="New stories will show up as your sources publish them."
            className="py-12"
          />
        ) : (
          <div className="space-y-3">
            {latest.map((article) => (
              <ArticleCard key={article.id} article={article} onOpen={openArticle} />
            ))}
            {hasNextPage && (
              <div className="py-4 text-center">
                <Button variant="outline" size="sm" onClick={() => fetchNextPage()} disabled={isFetchingNextPage}>
                  {isFetchingNextPage ? 'Loading…' : 'Load more'}
                </Button>
              </div>
            )}
          </div>
        )}
      </section>
    </div>
  )
}

function SourceChip({ label, active, onClick }: { label: string; active: boolean; onClick: () => void }) {
  return (
    <button
      onClick={onClick}
      className={cn(
        'shrink-0 whitespace-nowrap rounded-full border px-3 py-1 text-xs font-medium transition-colors',
        active
          ? 'border-primary bg-primary/10 text-primary'
          : 'border-border text-muted-foreground hover:text-foreground hover:border-primary/40'
      )}
    >
      {label}
    </button>
  )
}
