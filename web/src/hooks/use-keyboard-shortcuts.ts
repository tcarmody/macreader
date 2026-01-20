import { useHotkeys } from 'react-hotkeys-hook'
import { useAppStore } from '@/store/app-store'
import { useArticles, useMarkArticleRead, useToggleBookmark, useRefreshFeeds } from '@/hooks/use-queries'

interface UseKeyboardShortcutsOptions {
  onOpenSettings?: () => void
  onOpenAddFeed?: () => void
}

export function useKeyboardShortcuts(options: UseKeyboardShortcutsOptions = {}) {
  const {
    selectedFilter,
    selectedArticleId,
    setSelectedArticleId,
    setIsSearching,
    setSearchQuery,
  } = useAppStore()

  const { data: articles = [] } = useArticles(selectedFilter)
  const markRead = useMarkArticleRead()
  const toggleBookmark = useToggleBookmark()
  const refreshFeeds = useRefreshFeeds()

  // Get current article index
  const currentIndex = selectedArticleId
    ? articles.findIndex((a) => a.id === selectedArticleId)
    : -1

  // Navigation - j (next article)
  useHotkeys('j', () => {
    if (articles.length > 0) {
      const nextIndex = Math.min(currentIndex + 1, articles.length - 1)
      if (nextIndex >= 0) {
        const article = articles[nextIndex]
        setSelectedArticleId(article.id)
        if (!article.is_read) {
          markRead.mutate({ articleId: article.id, isRead: true })
        }
      }
    }
  }, { preventDefault: true }, [articles, currentIndex, setSelectedArticleId, markRead])

  // Navigation - k (previous article)
  useHotkeys('k', () => {
    if (articles.length > 0) {
      const prevIndex = Math.max(currentIndex - 1, 0)
      const article = articles[prevIndex]
      setSelectedArticleId(article.id)
      if (!article.is_read) {
        markRead.mutate({ articleId: article.id, isRead: true })
      }
    }
  }, { preventDefault: true }, [articles, currentIndex, setSelectedArticleId, markRead])

  // Navigation - g (go to first article)
  useHotkeys('g', () => {
    if (articles.length > 0) {
      setSelectedArticleId(articles[0].id)
    }
  }, [articles, setSelectedArticleId])

  // Action - m (toggle read)
  useHotkeys('m', () => {
    if (selectedArticleId) {
      const article = articles.find((a) => a.id === selectedArticleId)
      if (article) {
        markRead.mutate({ articleId: article.id, isRead: !article.is_read })
      }
    }
  }, { preventDefault: true }, [selectedArticleId, articles, markRead])

  // Action - s (toggle bookmark/save)
  useHotkeys('s', () => {
    if (selectedArticleId) {
      toggleBookmark.mutate(selectedArticleId)
    }
  }, { preventDefault: true }, [selectedArticleId, toggleBookmark])

  // Action - o (open in browser)
  useHotkeys('o', () => {
    if (selectedArticleId) {
      const article = articles.find((a) => a.id === selectedArticleId)
      if (article) {
        window.open(article.url, '_blank', 'noopener,noreferrer')
      }
    }
  }, { preventDefault: true }, [selectedArticleId, articles])

  // Action - r (refresh feeds)
  useHotkeys('r', () => {
    refreshFeeds.mutate()
  }, { preventDefault: true }, [refreshFeeds])

  // Search - / (focus search)
  useHotkeys('/', () => {
    setIsSearching(true)
    const searchInput = document.querySelector('input[placeholder*="Search"]') as HTMLInputElement
    if (searchInput) {
      searchInput.focus()
    }
  }, { preventDefault: true }, [setIsSearching])

  // Escape - clear search
  useHotkeys('escape', () => {
    setIsSearching(false)
    setSearchQuery('')
  }, [setIsSearching, setSearchQuery])

  // Mod+, (Cmd/Ctrl + comma) - open settings
  useHotkeys('mod+,', () => {
    options.onOpenSettings?.()
  }, { preventDefault: true }, [options.onOpenSettings])

  // Mod+n (Cmd/Ctrl + n) - new feed
  useHotkeys('mod+n', () => {
    options.onOpenAddFeed?.()
  }, { preventDefault: true }, [options.onOpenAddFeed])
}
