import { create } from 'zustand'
import { persist } from 'zustand/middleware'
import type { FilterType, GroupBy, SortBy, ApiKeyConfig } from '@/types'

export type DesignStyle = 'default' | 'warm' | 'soft' | 'sharp' | 'compact' | 'teal' | 'high-contrast' | 'sepia' | 'mono'

// Casual web experience (non-admin readers). See DOCTRINE.md "Web is casual-first".
export type CasualView = 'home' | 'highlights' | 'bookmarked' | 'digest' | 'search'

interface AppState {
  // UI State
  sidebarCollapsed: boolean
  theme: 'light' | 'dark' | 'system'
  designStyle: DesignStyle

  // Onboarding State
  hasCompletedInitialSetup: boolean

  // Selection State
  selectedFilter: FilterType
  selectedArticleId: number | null
  selectedLibraryItemId: number | null

  // View State
  currentView: 'feeds' | 'library' | 'digest' | 'stats'
  groupBy: GroupBy
  sortBy: SortBy
  hideDuplicates: boolean
  searchQuery: string
  isSearching: boolean
  searchIncludeSummaries: boolean

  // Casual web experience (non-admin readers)
  casualView: CasualView
  // Admins use the full UI by default but can preview the reader experience
  readerPreview: boolean
  // Home stream filter by source feed (null = all sources)
  casualSourceFilter: number | null

  // Feature Usage Tracking
  featureUsage: {
    hasUsedGroupBy: boolean
    hasUsedSummarize: boolean
    hasUsedLibrary: boolean
    hasUsedFeedManager: boolean
    hasUsedRelated: boolean
  }

  // First-Time Toast Tracking
  shownToasts: Set<string>

  // Contextual Hint Tracking (SmartTooltip / CoachMark)
  hintViewCounts: Record<string, number>
  dismissedHints: Set<string>

  // API Configuration
  apiConfig: ApiKeyConfig

  // Actions
  setSidebarCollapsed: (collapsed: boolean) => void
  setTheme: (theme: 'light' | 'dark' | 'system') => void
  setSelectedFilter: (filter: FilterType) => void
  setSelectedArticleId: (id: number | null) => void
  setSelectedLibraryItemId: (id: number | null) => void
  setCurrentView: (view: 'feeds' | 'library' | 'digest' | 'stats') => void
  setGroupBy: (groupBy: GroupBy) => void
  setSortBy: (sortBy: SortBy) => void
  toggleHideDuplicates: () => void
  setSearchQuery: (query: string) => void
  setIsSearching: (isSearching: boolean) => void
  toggleSearchIncludeSummaries: () => void
  setCasualView: (view: CasualView) => void
  toggleReaderPreview: () => void
  setCasualSourceFilter: (feedId: number | null) => void
  setHasCompletedInitialSetup: (value: boolean) => void
  setApiConfig: (config: ApiKeyConfig) => void
  clearApiKeys: () => void
  setDesignStyle: (style: DesignStyle) => void
  markFeatureUsed: (feature: keyof AppState['featureUsage']) => void
  markToastShown: (toastId: string) => void
  hasShownToast: (toastId: string) => boolean
  recordHintView: (hintId: string) => void
  dismissHint: (hintId: string) => void
  isHintActive: (hintId: string, maxViews?: number) => boolean
}

export const useAppStore = create<AppState>()(
  persist(
    (set, get) => ({
      // Initial UI State
      sidebarCollapsed: false,
      theme: 'system',
      designStyle: 'default',

      // Initial Onboarding State
      hasCompletedInitialSetup: false,

      // Initial Selection State - use 'unread' for new users
      selectedFilter: 'unread',
      selectedArticleId: null,
      selectedLibraryItemId: null,

      // Initial View State
      currentView: 'feeds',
      groupBy: 'none',
      sortBy: 'newest',
      hideDuplicates: false,
      searchQuery: '',
      isSearching: false,
      searchIncludeSummaries: true,

      // Initial Casual State
      casualView: 'home',
      readerPreview: false,
      casualSourceFilter: null,

      // Initial Feature Usage
      featureUsage: {
        hasUsedGroupBy: false,
        hasUsedSummarize: false,
        hasUsedLibrary: false,
        hasUsedFeedManager: false,
        hasUsedRelated: false,
      },

      // Initial Toast Tracking
      shownToasts: new Set<string>(),

      // Initial Hint Tracking
      hintViewCounts: {},
      dismissedHints: new Set<string>(),

      // Initial API Configuration
      apiConfig: {
        backendUrl: import.meta.env.DEV ? '/api' : (import.meta.env.VITE_API_URL || ''),
      },

      // Actions
      setSidebarCollapsed: (collapsed) => set({ sidebarCollapsed: collapsed }),
      setTheme: (theme) => set({ theme }),
      setSelectedFilter: (filter) => set({ selectedFilter: filter, selectedArticleId: null }),
      setSelectedArticleId: (id) => set({ selectedArticleId: id }),
      setSelectedLibraryItemId: (id) => set({ selectedLibraryItemId: id }),
      setCurrentView: (view: 'feeds' | 'library' | 'digest' | 'stats') => set((state) => ({
        currentView: view,
        selectedArticleId: null,
        selectedLibraryItemId: null,
        featureUsage: {
          ...state.featureUsage,
          hasUsedLibrary: view === 'library' ? true : state.featureUsage.hasUsedLibrary,
        },
      })),
      setGroupBy: (groupBy) => set((state) => ({
        groupBy,
        featureUsage: {
          ...state.featureUsage,
          hasUsedGroupBy: groupBy !== 'none' ? true : state.featureUsage.hasUsedGroupBy,
        },
      })),
      setSortBy: (sortBy) => set({ sortBy }),
      toggleHideDuplicates: () => set((state) => ({ hideDuplicates: !state.hideDuplicates })),
      setSearchQuery: (query) => set({ searchQuery: query }),
      setIsSearching: (isSearching) => set({ isSearching }),
      toggleSearchIncludeSummaries: () => set((state) => ({ searchIncludeSummaries: !state.searchIncludeSummaries })),
      // Switching casual tabs closes any open reader (clears selection)
      setCasualView: (view) => set({ casualView: view, selectedArticleId: null, selectedLibraryItemId: null }),
      toggleReaderPreview: () => set((state) => {
        const next = !state.readerPreview
        // Keep the API client's synchronous flag in sync (see syncReaderPreviewFlag)
        try { localStorage.setItem('dp-reader-preview', next ? '1' : '0') } catch { /* ignore */ }
        return { readerPreview: next, casualView: 'home', selectedArticleId: null, selectedLibraryItemId: null }
      }),
      setCasualSourceFilter: (feedId) => set({ casualSourceFilter: feedId }),
      setHasCompletedInitialSetup: (value) => set({ hasCompletedInitialSetup: value }),
      setApiConfig: (config) => {
        // Also store in localStorage for API client to access
        localStorage.setItem('apiConfig', JSON.stringify(config))
        set({ apiConfig: config })
      },
      clearApiKeys: () => {
        const currentConfig = useAppStore.getState().apiConfig
        const newConfig = { backendUrl: currentConfig.backendUrl }
        localStorage.setItem('apiConfig', JSON.stringify(newConfig))
        set({ apiConfig: newConfig })
      },
      setDesignStyle: (style) => set({ designStyle: style }),
      markFeatureUsed: (feature) => set((state) => ({
        featureUsage: {
          ...state.featureUsage,
          [feature]: true,
        },
      })),
      markToastShown: (toastId) => set((state) => ({
        shownToasts: new Set([...state.shownToasts, toastId]),
      })),
      hasShownToast: (toastId) => get().shownToasts.has(toastId),
      recordHintView: (hintId) => set((state) => ({
        hintViewCounts: {
          ...state.hintViewCounts,
          [hintId]: (state.hintViewCounts[hintId] ?? 0) + 1,
        },
      })),
      dismissHint: (hintId) => set((state) => ({
        dismissedHints: new Set([...state.dismissedHints, hintId]),
      })),
      isHintActive: (hintId, maxViews = 5) => {
        const s = get()
        return !s.dismissedHints.has(hintId) && (s.hintViewCounts[hintId] ?? 0) < maxViews
      },
    }),
    {
      name: 'datapoints-app-storage',
      partialize: (state) => ({
        sidebarCollapsed: state.sidebarCollapsed,
        theme: state.theme,
        designStyle: state.designStyle,
        hasCompletedInitialSetup: state.hasCompletedInitialSetup,
        selectedFilter: state.selectedFilter,
        currentView: state.currentView,
        groupBy: state.groupBy,
        sortBy: state.sortBy,
        hideDuplicates: state.hideDuplicates,
        searchIncludeSummaries: state.searchIncludeSummaries,
        casualView: state.casualView,
        readerPreview: state.readerPreview,
        featureUsage: state.featureUsage,
        // Convert Sets to Arrays for JSON serialization
        shownToasts: [...state.shownToasts],
        hintViewCounts: state.hintViewCounts,
        dismissedHints: [...state.dismissedHints],
        apiConfig: state.apiConfig,
      }),
      // Convert Array back to Set on rehydration
      merge: (persistedState, currentState) => ({
        ...currentState,
        ...(persistedState as object),
        shownToasts: new Set(
          Array.isArray((persistedState as { shownToasts?: string[] })?.shownToasts)
            ? (persistedState as { shownToasts: string[] }).shownToasts
            : []
        ),
        hintViewCounts: (persistedState as { hintViewCounts?: Record<string, number> })?.hintViewCounts ?? {},
        dismissedHints: new Set(
          Array.isArray((persistedState as { dismissedHints?: string[] })?.dismissedHints)
            ? (persistedState as { dismissedHints: string[] }).dismissedHints
            : []
        ),
      }),
    }
  )
)

// The API client reads `dp-reader-preview` from localStorage synchronously to
// decide whether to send the X-Reader-Preview header. Mirror the persisted
// store value into it at startup so the very first request is already correct.
export function syncReaderPreviewFlag() {
  try {
    localStorage.setItem('dp-reader-preview', useAppStore.getState().readerPreview ? '1' : '0')
  } catch {
    /* ignore */
  }
}
syncReaderPreviewFlag()

// Apply theme on load
export function applyTheme(theme: 'light' | 'dark' | 'system') {
  const root = window.document.documentElement
  root.classList.remove('light', 'dark')

  if (theme === 'system') {
    const systemTheme = window.matchMedia('(prefers-color-scheme: dark)').matches
      ? 'dark'
      : 'light'
    root.classList.add(systemTheme)
  } else {
    root.classList.add(theme)
  }
}

// Apply design style
export function applyDesignStyle(style: DesignStyle) {
  const root = window.document.documentElement
  root.classList.remove('design-default', 'design-warm', 'design-soft', 'design-sharp', 'design-compact', 'design-teal', 'design-high-contrast', 'design-sepia', 'design-mono')
  root.classList.add(`design-${style}`)
}
