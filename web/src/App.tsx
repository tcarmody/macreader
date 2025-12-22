import { useState, useEffect } from 'react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { Sidebar } from '@/components/Sidebar'
import { ArticleList } from '@/components/ArticleList'
import { ArticleDetail } from '@/components/ArticleDetail'
import { LibraryList, LibraryItemDetail } from '@/components/LibraryView'
import { SettingsDialog } from '@/components/SettingsDialog'
import { AddFeedDialog } from '@/components/AddFeedDialog'
import { useAppStore, applyTheme } from '@/store/app-store'
import { useKeyboardShortcuts } from '@/hooks/use-keyboard-shortcuts'

// Create a client
const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      retry: 1,
      staleTime: 30000,
      refetchOnWindowFocus: false,
    },
  },
})

function AppContent() {
  const { currentView, theme, apiConfig } = useAppStore()
  const [settingsOpen, setSettingsOpen] = useState(false)
  const [addFeedOpen, setAddFeedOpen] = useState(false)

  // Apply theme on mount and changes
  useEffect(() => {
    applyTheme(theme)
  }, [theme])

  // Listen for system theme changes
  useEffect(() => {
    if (theme === 'system') {
      const mediaQuery = window.matchMedia('(prefers-color-scheme: dark)')
      const handleChange = () => applyTheme('system')
      mediaQuery.addEventListener('change', handleChange)
      return () => mediaQuery.removeEventListener('change', handleChange)
    }
  }, [theme])

  // Show setup if no backend URL configured
  const needsSetup = !apiConfig.backendUrl

  // Keyboard shortcuts
  useKeyboardShortcuts({
    onOpenSettings: () => setSettingsOpen(true),
    onOpenAddFeed: () => setAddFeedOpen(true),
  })

  if (needsSetup) {
    return (
      <div className="h-screen flex items-center justify-center bg-background">
        <div className="max-w-md mx-auto text-center p-8">
          <h1 className="text-2xl font-bold mb-4">Welcome to DataPoints</h1>
          <p className="text-muted-foreground mb-6">
            To get started, you need to configure your backend server URL.
          </p>
          <button
            onClick={() => setSettingsOpen(true)}
            className="px-4 py-2 bg-primary text-primary-foreground rounded-md hover:bg-primary/90"
          >
            Open Settings
          </button>
          <SettingsDialog isOpen={settingsOpen} onClose={() => setSettingsOpen(false)} />
        </div>
      </div>
    )
  }

  return (
    <div className="h-screen flex overflow-hidden bg-background">
      {/* Sidebar */}
      <Sidebar
        onOpenSettings={() => setSettingsOpen(true)}
        onAddFeed={() => setAddFeedOpen(true)}
      />

      {/* Main Content */}
      {currentView === 'feeds' ? (
        <>
          <ArticleList />
          <ArticleDetail />
        </>
      ) : (
        <>
          <LibraryList />
          <LibraryItemDetail />
        </>
      )}

      {/* Dialogs */}
      <SettingsDialog isOpen={settingsOpen} onClose={() => setSettingsOpen(false)} />
      <AddFeedDialog isOpen={addFeedOpen} onClose={() => setAddFeedOpen(false)} />
    </div>
  )
}

export default function App() {
  return (
    <QueryClientProvider client={queryClient}>
      <AppContent />
    </QueryClientProvider>
  )
}
