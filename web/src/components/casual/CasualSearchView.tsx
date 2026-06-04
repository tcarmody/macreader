import { useState } from 'react'
import { Search, Loader2, X } from 'lucide-react'
import { Input } from '@/components/ui/input'
import { Button } from '@/components/ui/button'
import { EmptyState } from '@/components/ui/empty-state'
import { useSearch } from '@/hooks/use-queries'
import { ArticleCard } from './ArticleCard'
import { useOpenReader } from './use-open-reader'

export function CasualSearchView() {
  const { openArticle } = useOpenReader()
  const [query, setQuery] = useState('')

  // Always search summaries too — no power-user toggle for casual readers.
  const { data: results = [], isLoading, isFetching } = useSearch(query, true)
  const active = query.trim().length >= 2

  return (
    <div className="mx-auto w-full max-w-2xl px-4 py-6 sm:py-8">
      <div className="relative mb-6">
        <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
        <Input
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder="Search stories…"
          autoFocus
          className="pl-9 pr-9 h-11 text-base"
        />
        {query && (
          <Button
            variant="ghost"
            size="icon"
            className="absolute right-1 top-1/2 h-8 w-8 -translate-y-1/2"
            onClick={() => setQuery('')}
          >
            <X className="h-4 w-4" />
          </Button>
        )}
      </div>

      {!active ? (
        <EmptyState
          icon={Search}
          title="Search your stories"
          description="Find anything by title, content, or AI summary."
          className="py-12"
        />
      ) : isLoading || isFetching ? (
        <div className="flex justify-center py-12">
          <Loader2 className="h-6 w-6 animate-spin text-muted-foreground" />
        </div>
      ) : results.length === 0 ? (
        <EmptyState
          icon={Search}
          title="No results"
          description={`Nothing matched “${query}”.`}
          className="py-12"
        />
      ) : (
        <div className="space-y-3">
          {results.map((article) => (
            <ArticleCard key={article.id} article={article} onOpen={openArticle} />
          ))}
        </div>
      )}
    </div>
  )
}
