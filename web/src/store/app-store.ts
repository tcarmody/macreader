import { create } from 'zustand'
import { persist } from 'zustand/middleware'
import type { FilterType, GroupBy, ApiKeyConfig } from '@/types'

interface AppState {
  // UI State
  sidebarCollapsed: boolean
  theme: 'light' | 'dark' | 'system'

  // Selection State
  selectedFilter: FilterType
  selectedArticleId: number | null
  selectedLibraryItemId: number | null

  // View State
  currentView: 'feeds' | 'library'
  groupBy: GroupBy
  searchQuery: string
  isSearching: boolean

  // Unread view snapshot - keeps articles visible until navigating away
  unreadViewArticleIds: Set<number> | null

  // API Configuration
  apiConfig: ApiKeyConfig

  // Actions
  setSidebarCollapsed: (collapsed: boolean) => void
  setTheme: (theme: 'light' | 'dark' | 'system') => void
  setSelectedFilter: (filter: FilterType) => void
  setSelectedArticleId: (id: number | null) => void
  setSelectedLibraryItemId: (id: number | null) => void
  setCurrentView: (view: 'feeds' | 'library') => void
  setGroupBy: (groupBy: GroupBy) => void
  setSearchQuery: (query: string) => void
  setIsSearching: (isSearching: boolean) => void
  setApiConfig: (config: ApiKeyConfig) => void
  clearApiKeys: () => void
  captureUnreadSnapshot: (articleIds: number[]) => void
  clearUnreadSnapshot: () => void
}

export const useAppStore = create<AppState>()(
  persist(
    (set) => ({
      // Initial UI State
      sidebarCollapsed: false,
      theme: 'system',

      // Initial Selection State
      selectedFilter: 'all',
      selectedArticleId: null,
      selectedLibraryItemId: null,

      // Initial View State
      currentView: 'feeds',
      groupBy: 'none',
      searchQuery: '',
      isSearching: false,

      // Unread view snapshot (not persisted)
      unreadViewArticleIds: null,

      // Initial API Configuration
      apiConfig: {
        backendUrl: import.meta.env.DEV ? '/api' : (import.meta.env.VITE_API_URL || ''),
      },

      // Actions
      setSidebarCollapsed: (collapsed) => set({ sidebarCollapsed: collapsed }),
      setTheme: (theme) => set({ theme }),
      setSelectedFilter: (filter) => set((state) => {
        // Clear snapshot when leaving unread view
        const clearSnapshot = state.selectedFilter === 'unread' && filter !== 'unread'
        return {
          selectedFilter: filter,
          selectedArticleId: null,
          unreadViewArticleIds: clearSnapshot ? null : state.unreadViewArticleIds,
        }
      }),
      setSelectedArticleId: (id) => set({ selectedArticleId: id }),
      setSelectedLibraryItemId: (id) => set({ selectedLibraryItemId: id }),
      setCurrentView: (view) => set({
        currentView: view,
        selectedArticleId: null,
        selectedLibraryItemId: null,
        unreadViewArticleIds: null, // Clear snapshot when switching views
      }),
      setGroupBy: (groupBy) => set({ groupBy }),
      setSearchQuery: (query) => set({ searchQuery: query }),
      setIsSearching: (isSearching) => set({ isSearching }),
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
      captureUnreadSnapshot: (articleIds) => set({ unreadViewArticleIds: new Set(articleIds) }),
      clearUnreadSnapshot: () => set({ unreadViewArticleIds: null }),
    }),
    {
      name: 'datapoints-app-storage',
      partialize: (state) => ({
        sidebarCollapsed: state.sidebarCollapsed,
        theme: state.theme,
        selectedFilter: state.selectedFilter,
        currentView: state.currentView,
        groupBy: state.groupBy,
        apiConfig: state.apiConfig,
      }),
    }
  )
)

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
