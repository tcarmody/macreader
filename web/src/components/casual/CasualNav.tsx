import { Home, Star, BookMarked, Search } from 'lucide-react'
import { cn } from '@/lib/utils'
import { useAppStore } from '@/store/app-store'
import type { CasualView } from '@/store/app-store'

interface NavItem {
  view: CasualView
  label: string
  icon: typeof Home
}

// NOTE: "Digest" is temporarily removed from the reader (it fails). See PLANS.md.
const NAV_ITEMS: NavItem[] = [
  { view: 'home', label: 'Home', icon: Home },
  { view: 'highlights', label: 'Highlights', icon: Star },
  { view: 'bookmarked', label: 'Saved', icon: BookMarked },
  { view: 'search', label: 'Search', icon: Search },
]

// Desktop / tablet: slim left rail
export function SideNav() {
  const { casualView, setCasualView } = useAppStore()

  return (
    <nav className="flex flex-col gap-1 py-4 px-2">
      {NAV_ITEMS.map(({ view, label, icon: Icon }) => (
        <button
          key={view}
          onClick={() => setCasualView(view)}
          className={cn(
            'flex items-center gap-3 rounded-lg px-3 py-2 text-sm font-medium transition-colors',
            casualView === view
              ? 'bg-primary/10 text-primary'
              : 'text-muted-foreground hover:bg-muted hover:text-foreground'
          )}
        >
          <Icon className="h-5 w-5 shrink-0" />
          <span>{label}</span>
        </button>
      ))}
    </nav>
  )
}

// Mobile: sticky bottom tab bar
export function BottomNav() {
  const { casualView, setCasualView } = useAppStore()

  return (
    <nav className="flex items-stretch border-t border-border bg-background/95 backdrop-blur supports-[backdrop-filter]:bg-background/80 pb-[env(safe-area-inset-bottom)]">
      {NAV_ITEMS.map(({ view, label, icon: Icon }) => (
        <button
          key={view}
          onClick={() => setCasualView(view)}
          className={cn(
            'flex-1 flex flex-col items-center justify-center gap-0.5 py-2 text-[10px] font-medium transition-colors',
            casualView === view ? 'text-primary' : 'text-muted-foreground'
          )}
        >
          <Icon className={cn('h-5 w-5', casualView === view && 'fill-primary/10')} />
          <span>{label}</span>
        </button>
      ))}
    </nav>
  )
}
