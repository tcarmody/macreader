import { useState } from 'react'
import { Star, Library, Plus, Upload, Loader2 } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { EmptyState } from '@/components/ui/empty-state'
import { useArticles, useLibrary, useAddLibraryUrl, useUploadLibraryFile } from '@/hooks/use-queries'
import { ArticleCard, LibraryCard } from './ArticleCard'
import { useOpenReader } from './use-open-reader'

// Highlights = admin-curated Featured + the reader's own Library, in one place.
export function HighlightsView() {
  const { openArticle, openLibraryItem } = useOpenReader()

  const { data: featuredData, isLoading: featuredLoading } = useArticles('featured', 'newest')
  const featured = featuredData?.pages.flat() ?? []

  const { data: items = [], isLoading: libraryLoading } = useLibrary()

  const [showAddUrl, setShowAddUrl] = useState(false)
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
    } catch (err) {
      console.error('Failed to add URL:', err)
    }
  }

  const handleFileUpload = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0]
    if (!file) return
    try {
      await uploadFile.mutateAsync(file)
    } catch (err) {
      console.error('Failed to upload file:', err)
    }
    e.target.value = ''
  }

  const isLoading = featuredLoading || libraryLoading

  return (
    <div className="mx-auto w-full max-w-2xl px-4 py-6 sm:py-8">
      {/* Editor's picks */}
      <section className="mb-10">
        <div className="mb-3 flex items-center gap-2">
          <Star className="h-4 w-4 text-amber-400 fill-amber-400" />
          <h2 className="text-sm font-semibold uppercase tracking-wide text-muted-foreground">
            Editor's picks
          </h2>
        </div>
        {featuredLoading ? (
          <div className="flex justify-center py-8">
            <Loader2 className="h-6 w-6 animate-spin text-muted-foreground" />
          </div>
        ) : featured.length === 0 ? (
          <p className="text-sm text-muted-foreground">No featured stories right now — check back soon.</p>
        ) : (
          <div className="space-y-3">
            {featured.map((article) => (
              <ArticleCard key={article.id} article={article} onOpen={openArticle} />
            ))}
          </div>
        )}
      </section>

      {/* Your library */}
      <section>
        <div className="mb-3 flex items-center gap-2">
          <Library className="h-4 w-4 text-muted-foreground" />
          <h2 className="text-sm font-semibold uppercase tracking-wide text-muted-foreground">
            Your library
          </h2>
          <div className="ml-auto flex items-center gap-2">
            <Button variant="outline" size="sm" onClick={() => setShowAddUrl((v) => !v)}>
              <Plus className="h-3.5 w-3.5 mr-1" />
              Add link
            </Button>
            <Button variant="outline" size="sm" asChild>
              <label className="inline-flex cursor-pointer items-center">
                <Upload className="h-3.5 w-3.5 mr-1" />
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
        </div>

        {showAddUrl && (
          <form onSubmit={handleAddUrl} className="mb-4 flex gap-2">
            <Input
              value={newUrl}
              onChange={(e) => setNewUrl(e.target.value)}
              placeholder="https://…"
              autoFocus
            />
            <Button type="submit" size="sm" disabled={addUrl.isPending}>
              {addUrl.isPending ? <Loader2 className="h-4 w-4 animate-spin" /> : 'Add'}
            </Button>
          </form>
        )}

        {isLoading && items.length === 0 ? (
          <div className="flex justify-center py-8">
            <Loader2 className="h-6 w-6 animate-spin text-muted-foreground" />
          </div>
        ) : items.length === 0 ? (
          <EmptyState
            icon={Library}
            title="Nothing saved yet"
            description="Add a link or upload a PDF, doc, or article to read later."
            className="py-10"
          />
        ) : (
          <div className="space-y-3">
            {items.map((item) => (
              <LibraryCard key={item.id} item={item} onOpen={openLibraryItem} />
            ))}
          </div>
        )}
      </section>
    </div>
  )
}
