import { create } from 'zustand'
import { persist } from 'zustand/middleware'
import type { FilterType, GroupBy, SortBy, ApiKeyConfig } from '@/types'

export type DesignStyle = 'default' | 'warm' | 'soft' | 'rounded' | 'compact' | 'teal' | 'high-contrast' | 'sepia' | 'mono'

interface AppState {
  // UI State
  sidebarCollapsed: boolean
  theme: 'light' | 'dark' | 'system'
  designStyle: DesignStyle

  // Selection State
  selectedFilter: FilterType
  selectedArticleId: number | null
  selectedLibraryItemId: number | null

  // View State
  currentView: 'feeds' | 'library'
  groupBy: GroupBy
  sortBy: SortBy
  hideRead: boolean
  searchQuery: string
  isSearching: boolean

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
  setSortBy: (sortBy: SortBy) => void
  setHideRead: (hideRead: boolean) => void
  toggleHideRead: () => void
  setSearchQuery: (query: string) => void
  setIsSearching: (isSearching: boolean) => void
  setApiConfig: (config: ApiKeyConfig) => void
  clearApiKeys: () => void
  setDesignStyle: (style: DesignStyle) => void
}

export const useAppStore = create<AppState>()(
  persist(
    (set) => ({
      // Initial UI State
      sidebarCollapsed: false,
      theme: 'system',
      designStyle: 'default',

      // Initial Selection State
      selectedFilter: 'all',
      selectedArticleId: null,
      selectedLibraryItemId: null,

      // Initial View State
      currentView: 'feeds',
      groupBy: 'none',
      sortBy: 'newest',
      hideRead: false,
      searchQuery: '',
      isSearching: false,

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
      setCurrentView: (view) => set({
        currentView: view,
        selectedArticleId: null,
        selectedLibraryItemId: null,
      }),
      setGroupBy: (groupBy) => set({ groupBy }),
      setSortBy: (sortBy) => set({ sortBy }),
      setHideRead: (hideRead) => set({ hideRead }),
      toggleHideRead: () => set((state) => ({ hideRead: !state.hideRead })),
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
      setDesignStyle: (style) => set({ designStyle: style }),
    }),
    {
      name: 'datapoints-app-storage',
      partialize: (state) => ({
        sidebarCollapsed: state.sidebarCollapsed,
        theme: state.theme,
        designStyle: state.designStyle,
        selectedFilter: state.selectedFilter,
        currentView: state.currentView,
        groupBy: state.groupBy,
        sortBy: state.sortBy,
        hideRead: state.hideRead,
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

// Apply design style
export function applyDesignStyle(style: DesignStyle) {
  const root = window.document.documentElement
  root.classList.remove('design-default', 'design-warm', 'design-soft', 'design-rounded', 'design-compact', 'design-teal', 'design-high-contrast', 'design-sepia', 'design-mono')
  root.classList.add(`design-${style}`)
}
