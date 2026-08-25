import { useState } from 'react'
import { Sparkles, User, Eye } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { useAppStore } from '@/store/app-store'
import { useAuthStatus } from '@/hooks/use-queries'
import { SettingsDialog } from '@/components/SettingsDialog'
import { SideNav, BottomNav } from './CasualNav'
import { HomeView } from './HomeView'
import { HighlightsView } from './HighlightsView'
import { BookmarkedView } from './BookmarkedView'
import { CasualSearchView } from './CasualSearchView'
import { CasualReader } from './CasualReader'

// The casual-first web shell for non-admin readers (and admins who opt into
// the reader preview). Adaptive: left rail on desktop, bottom tabs on mobile.
export function CasualApp() {
  const { casualView, readerPreview, toggleReaderPreview } = useAppStore()
  const { data: authStatus } = useAuthStatus()
  const [settingsOpen, setSettingsOpen] = useState(false)

  const userLabel = authStatus?.user?.name || authStatus?.user?.email || 'Account'
  const initial = userLabel.charAt(0).toUpperCase()

  const accountButton = (
    <button
      onClick={() => setSettingsOpen(true)}
      title={userLabel}
      className="flex h-8 w-8 items-center justify-center rounded-full bg-primary/10 text-sm font-semibold text-primary hover:bg-primary/20"
    >
      {authStatus?.user ? initial : <User className="h-4 w-4" />}
    </button>
  )

  const brand = (
    <div className="flex items-center gap-2 font-semibold">
      <Sparkles className="h-5 w-5 text-primary" />
      <span>Data Points</span>
    </div>
  )

  return (
    <div className="flex h-dvh flex-col overflow-hidden bg-background md:flex-row">
      {/* Desktop left rail */}
      <aside className="hidden shrink-0 flex-col border-r border-border md:flex md:w-60">
        <div className="px-4 py-4">{brand}</div>
        <SideNav />
        <div className="mt-auto flex items-center gap-2 border-t border-border p-3">
          {accountButton}
          <div className="min-w-0 flex-1">
            <p className="truncate text-xs font-medium">{userLabel}</p>
            {readerPreview && (
              <button onClick={toggleReaderPreview} className="text-[11px] text-primary hover:underline">
                Exit reader preview
              </button>
            )}
          </div>
        </div>
      </aside>

      {/* Mobile top bar */}
      <header className="flex h-12 shrink-0 items-center gap-2 border-b border-border px-4 md:hidden">
        {brand}
        <div className="ml-auto flex items-center gap-2">
          {readerPreview && (
            <Button variant="ghost" size="sm" onClick={toggleReaderPreview} className="text-xs">
              <Eye className="h-3.5 w-3.5 mr-1" />
              Exit preview
            </Button>
          )}
          {accountButton}
        </div>
      </header>

      {/* Main content (Home is the fallback for any unknown/retired view) */}
      <main className="relative flex min-h-0 flex-1 flex-col overflow-hidden">
        <div className="flex-1 overflow-y-auto">
          {casualView === 'highlights' ? (
            <HighlightsView />
          ) : casualView === 'bookmarked' ? (
            <BookmarkedView />
          ) : casualView === 'search' ? (
            <CasualSearchView />
          ) : (
            <HomeView />
          )}
        </div>
        <CasualReader />
      </main>

      {/* Mobile bottom nav */}
      <div className="shrink-0 md:hidden">
        <BottomNav />
      </div>

      <SettingsDialog isOpen={settingsOpen} onClose={() => setSettingsOpen(false)} restricted />
    </div>
  )
}
