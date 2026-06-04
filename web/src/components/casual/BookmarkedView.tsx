import { BookMarked, Loader2 } from 'lucide-react'
import { EmptyState } from '@/components/ui/empty-state'
import { useArticles, useLibrary } from '@/hooks/use-queries'
import { ArticleCard, LibraryCard } from './ArticleCard'
import { useOpenReader } from './use-open-reader'

// Saved = the reader's own bookmarked stories (articles + library items).
export function BookmarkedView() {
  const { openArticle, openLibraryItem } = useOpenReader()

  const { data: articleData, isLoading: articlesLoading } = useArticles('bookmarked', 'newest')
  const articles = articleData?.pages.flat() ?? []

  const { data: items = [], isLoading: libraryLoading } = useLibrary({ bookmarked_only: true })

  const isLoading = articlesLoading || libraryLoading
  const isEmpty = articles.length === 0 && items.length === 0

  return (
    <div className="mx-auto w-full max-w-2xl px-4 py-6 sm:py-8">
      <div className="mb-4 flex items-center gap-2">
        <BookMarked className="h-4 w-4 text-amber-500" />
        <h2 className="text-sm font-semibold uppercase tracking-wide text-muted-foreground">Saved</h2>
      </div>

      {isLoading && isEmpty ? (
        <div className="flex justify-center py-12">
          <Loader2 className="h-6 w-6 animate-spin text-muted-foreground" />
        </div>
      ) : isEmpty ? (
        <EmptyState
          icon={BookMarked}
          title="No saved stories yet"
          description="Tap the bookmark on any story to keep it here for later."
          className="py-12"
        />
      ) : (
        <div className="space-y-3">
          {articles.map((article) => (
            <ArticleCard key={`a-${article.id}`} article={article} onOpen={openArticle} />
          ))}
          {items.map((item) => (
            <LibraryCard key={`l-${item.id}`} item={item} onOpen={openLibraryItem} />
          ))}
        </div>
      )}
    </div>
  )
}
