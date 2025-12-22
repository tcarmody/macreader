import { useEffect, useCallback } from 'react'
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
    currentView,
    setIsSearching,
    setSearchQuery,
  } = useAppStore()

  const { data: articles = [] } = useArticles(selectedFilter)
  const markRead = useMarkArticleRead()
  const toggleBookmark = useToggleBookmark()
  const refreshFeeds = useRefreshFeeds()

  const handleKeyDown = useCallback((e: KeyboardEvent) => {
    // Don't handle shortcuts when typing in input fields
    if (
      e.target instanceof HTMLInputElement ||
      e.target instanceof HTMLTextAreaElement ||
      (e.target as HTMLElement).isContentEditable
    ) {
      return
    }

    // Get current article index
    const currentIndex = selectedArticleId
      ? articles.findIndex((a) => a.id === selectedArticleId)
      : -1

    switch (e.key.toLowerCase()) {
      // Navigation
      case 'j': // Next article
        e.preventDefault()
        if (currentView === 'feeds' && articles.length > 0) {
          const nextIndex = Math.min(currentIndex + 1, articles.length - 1)
          if (nextIndex >= 0) {
            const article = articles[nextIndex]
            setSelectedArticleId(article.id)
            if (!article.is_read) {
              markRead.mutate({ articleId: article.id, isRead: true })
            }
          }
        }
        break

      case 'k': // Previous article
        e.preventDefault()
        if (currentView === 'feeds' && articles.length > 0) {
          const prevIndex = Math.max(currentIndex - 1, 0)
          const article = articles[prevIndex]
          setSelectedArticleId(article.id)
          if (!article.is_read) {
            markRead.mutate({ articleId: article.id, isRead: true })
          }
        }
        break

      case 'g': // Go to top (gg sequence handled separately)
        // For now, just go to first article
        if (currentView === 'feeds' && articles.length > 0) {
          setSelectedArticleId(articles[0].id)
        }
        break

      // Actions
      case 'm': // Toggle read
        e.preventDefault()
        if (selectedArticleId) {
          const article = articles.find((a) => a.id === selectedArticleId)
          if (article) {
            markRead.mutate({ articleId: article.id, isRead: !article.is_read })
          }
        }
        break

      case 's': // Toggle bookmark (save)
        e.preventDefault()
        if (selectedArticleId) {
          toggleBookmark.mutate(selectedArticleId)
        }
        break

      case 'o': // Open in browser
        e.preventDefault()
        if (selectedArticleId) {
          const article = articles.find((a) => a.id === selectedArticleId)
          if (article) {
            window.open(article.url, '_blank', 'noopener,noreferrer')
          }
        }
        break

      case 'r': // Refresh feeds
        if (!e.metaKey && !e.ctrlKey) {
          e.preventDefault()
          refreshFeeds.mutate()
        }
        break

      case '/': // Focus search
        e.preventDefault()
        setIsSearching(true)
        // Focus the search input
        const searchInput = document.querySelector('input[placeholder*="Search"]') as HTMLInputElement
        if (searchInput) {
          searchInput.focus()
        }
        break

      case 'escape': // Clear search, close dialogs
        setIsSearching(false)
        setSearchQuery('')
        break

      case ',': // Open settings (like macOS)
        if (e.metaKey || e.ctrlKey) {
          e.preventDefault()
          options.onOpenSettings?.()
        }
        break

      case 'n': // New feed
        if (e.metaKey || e.ctrlKey) {
          e.preventDefault()
          options.onOpenAddFeed?.()
        }
        break
    }
  }, [
    selectedArticleId,
    articles,
    currentView,
    setSelectedArticleId,
    markRead,
    toggleBookmark,
    refreshFeeds,
    setIsSearching,
    setSearchQuery,
    options,
  ])

  useEffect(() => {
    window.addEventListener('keydown', handleKeyDown)
    return () => window.removeEventListener('keydown', handleKeyDown)
  }, [handleKeyDown])
}
