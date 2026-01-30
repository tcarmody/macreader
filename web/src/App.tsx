import { useState, useEffect } from 'react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { Server, Sparkles, Rss, ExternalLink } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { ToastProvider } from '@/components/ui/toast'
import { Sidebar } from '@/components/Sidebar'
import { ArticleList } from '@/components/ArticleList'
import { ArticleDetail } from '@/components/ArticleDetail'
import { LibraryList, LibraryItemDetail } from '@/components/LibraryView'
import { SettingsDialog } from '@/components/SettingsDialog'
import { AddFeedDialog } from '@/components/AddFeedDialog'
import { FeedManagerDialog } from '@/components/FeedManagerDialog'
import { LoginScreen } from '@/components/LoginScreen'
import { useAppStore, applyTheme, applyDesignStyle } from '@/store/app-store'
import { useKeyboardShortcuts } from '@/hooks/use-keyboard-shortcuts'
import { useAuthStatus } from '@/hooks/use-queries'

// Create a client with global error handling
const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      retry: (failureCount, error) => {
        // Don't retry on auth errors
        if ((error as Error & { status?: number }).status === 401) {
          return false
        }
        return failureCount < 1
      },
      staleTime: 30000,
      refetchOnWindowFocus: false,
    },
    mutations: {
      onError: (error) => {
        // On 401, invalidate auth status to trigger login screen
        if ((error as Error & { status?: number }).status === 401) {
          queryClient.invalidateQueries({ queryKey: ['authStatus'] })
        }
      },
    },
  },
})

function AppContent() {
  const { currentView, theme, designStyle, apiConfig } = useAppStore()
  const [settingsOpen, setSettingsOpen] = useState(false)
  const [addFeedOpen, setAddFeedOpen] = useState(false)
  const [feedManagerOpen, setFeedManagerOpen] = useState(false)

  // Handle OAuth token from URL (workaround for third-party cookie blocking)
  useEffect(() => {
    const params = new URLSearchParams(window.location.search)
    const authToken = params.get('auth_token')
    if (authToken) {
      // Store token in localStorage
      localStorage.setItem('authToken', authToken)
      // Remove token from URL
      window.history.replaceState({}, '', window.location.pathname)
      // Refresh auth status
      queryClient.invalidateQueries({ queryKey: ['authStatus'] })
    }
  }, [])

  // Check auth status
  const { data: authStatus, isLoading: authLoading, error: authError } = useAuthStatus()

  // Apply theme on mount and changes
  useEffect(() => {
    applyTheme(theme)
  }, [theme])

  // Apply design style on mount and changes
  useEffect(() => {
    applyDesignStyle(designStyle)
  }, [designStyle])

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

  // Check if login is required: OAuth is enabled but user is not logged in
  const needsLogin = authStatus?.enabled && !authStatus?.user

  // Keyboard shortcuts
  useKeyboardShortcuts({
    onOpenSettings: () => setSettingsOpen(true),
    onOpenAddFeed: () => setAddFeedOpen(true),
    onOpenFeedManager: () => setFeedManagerOpen(true),
  })

  if (needsSetup) {
    return (
      <div className="h-screen flex items-center justify-center bg-background p-4">
        <div className="max-w-2xl w-full">
          <div className="text-center mb-8">
            <div className="inline-flex items-center justify-center w-16 h-16 rounded-full bg-primary/10 mb-4">
              <Server className="h-8 w-8 text-primary" />
            </div>
            <h1 className="text-3xl font-bold mb-2">Welcome to Data Points</h1>
            <p className="text-lg text-muted-foreground">
              Your AI-powered RSS reader with intelligent summarization
            </p>
          </div>

          <div className="bg-card border border-border rounded-lg p-6 mb-6">
            <h2 className="text-lg font-semibold mb-4">Getting Started</h2>
            <div className="space-y-4">
              <div className="flex gap-3">
                <div className="flex-shrink-0 w-6 h-6 rounded-full bg-primary/10 flex items-center justify-center text-sm font-semibold text-primary">
                  1
                </div>
                <div>
                  <h3 className="font-medium mb-1">Configure your backend</h3>
                  <p className="text-sm text-muted-foreground">
                    Set your backend server URL in settings
                  </p>
                  <div className="mt-2 p-2 bg-muted rounded text-xs font-mono">
                    Example: https://your-backend.railway.app
                  </div>
                </div>
              </div>

              <div className="flex gap-3 opacity-60">
                <div className="flex-shrink-0 w-6 h-6 rounded-full bg-muted flex items-center justify-center text-sm font-semibold">
                  2
                </div>
                <div>
                  <h3 className="font-medium mb-1 flex items-center gap-2">
                    <Rss className="h-4 w-4" />
                    Add your feeds
                  </h3>
                  <p className="text-sm text-muted-foreground">
                    Subscribe to RSS feeds and newsletters
                  </p>
                </div>
              </div>

              <div className="flex gap-3 opacity-60">
                <div className="flex-shrink-0 w-6 h-6 rounded-full bg-muted flex items-center justify-center text-sm font-semibold">
                  3
                </div>
                <div>
                  <h3 className="font-medium mb-1 flex items-center gap-2">
                    <Sparkles className="h-4 w-4" />
                    Enable AI features
                  </h3>
                  <p className="text-sm text-muted-foreground">
                    Configure your API keys for summarization
                  </p>
                </div>
              </div>
            </div>
          </div>

          <div className="flex flex-col sm:flex-row gap-3">
            <Button
              onClick={() => setSettingsOpen(true)}
              size="lg"
              className="flex-1"
            >
              <Server className="h-4 w-4 mr-2" />
              Configure Backend
            </Button>
            <Button
              variant="outline"
              size="lg"
              asChild
              className="sm:w-auto"
            >
              <a
                href="https://github.com/yourusername/datapoints#deployment"
                target="_blank"
                rel="noopener noreferrer"
                className="flex items-center"
              >
                <ExternalLink className="h-4 w-4 mr-2" />
                Deployment Guide
              </a>
            </Button>
          </div>

          <SettingsDialog isOpen={settingsOpen} onClose={() => setSettingsOpen(false)} />
        </div>
      </div>
    )
  }

  // Show login screen if:
  // - Still loading auth status
  // - OAuth is enabled but user not authenticated
  // - Auth request failed (likely CORS or network issue)
  if (authLoading || authError || needsLogin) {
    return (
      <>
        <LoginScreen
          authStatus={authStatus}
          isLoading={authLoading}
          error={authError}
          onOpenSettings={() => setSettingsOpen(true)}
        />
        <SettingsDialog isOpen={settingsOpen} onClose={() => setSettingsOpen(false)} />
      </>
    )
  }

  return (
    <div className="h-screen flex overflow-hidden bg-background">
      {/* Sidebar */}
      <Sidebar
        onOpenSettings={() => setSettingsOpen(true)}
        onAddFeed={() => setAddFeedOpen(true)}
        onManageFeeds={() => setFeedManagerOpen(true)}
      />

      {/* Main Content */}
      {currentView === 'feeds' ? (
        <>
          <ArticleList onAddFeed={() => setAddFeedOpen(true)} />
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
      <FeedManagerDialog
        isOpen={feedManagerOpen}
        onClose={() => setFeedManagerOpen(false)}
        onAddFeed={() => {
          setFeedManagerOpen(false)
          setAddFeedOpen(true)
        }}
      />
    </div>
  )
}

export default function App() {
  return (
    <QueryClientProvider client={queryClient}>
      <ToastProvider>
        <AppContent />
      </ToastProvider>
    </QueryClientProvider>
  )
}
