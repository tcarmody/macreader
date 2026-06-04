import { ArrowLeft } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { useAppStore } from '@/store/app-store'
import { ArticleDetail } from '@/components/ArticleDetail'
import { LibraryItemDetail } from '@/components/LibraryView'

// Single-column reader. Reuses the full ArticleDetail / LibraryItemDetail
// (summary, chat, related links) and adds a back affordance. Shown as a
// full-bleed overlay on top of the active list when something is selected.
export function CasualReader() {
  const { selectedArticleId, selectedLibraryItemId, setSelectedArticleId, setSelectedLibraryItemId } =
    useAppStore()

  const isOpen = selectedArticleId != null || selectedLibraryItemId != null
  if (!isOpen) return null

  const close = () => {
    setSelectedArticleId(null)
    setSelectedLibraryItemId(null)
  }

  return (
    <div className="absolute inset-0 z-20 flex flex-col bg-background">
      <div className="flex items-center gap-2 border-b border-border px-2 py-2">
        <Button variant="ghost" size="sm" onClick={close} className="text-muted-foreground">
          <ArrowLeft className="h-4 w-4 mr-1" />
          Back
        </Button>
      </div>
      <div className="relative flex-1 overflow-hidden">
        {selectedArticleId != null ? <ArticleDetail /> : <LibraryItemDetail />}
      </div>
    </div>
  )
}
