import { useAppStore } from '@/store/app-store'
import { useMarkArticleRead } from '@/hooks/use-queries'
import type { Article, StandaloneItem } from '@/types'

// Opening a card in the casual shell = select it (the reader renders off store
// selection) and optimistically mark articles read, mirroring ArticleList.
export function useOpenReader() {
  const { setSelectedArticleId, setSelectedLibraryItemId } = useAppStore()
  const markRead = useMarkArticleRead()

  const openArticle = (article: Article) => {
    setSelectedLibraryItemId(null)
    setSelectedArticleId(article.id)
    if (!article.is_read) {
      markRead.mutate({ articleId: article.id, isRead: true })
    }
  }

  const openLibraryItem = (item: StandaloneItem) => {
    setSelectedArticleId(null)
    setSelectedLibraryItemId(item.id)
  }

  return { openArticle, openLibraryItem }
}
