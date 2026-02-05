import { describe, it, expect, beforeEach, vi } from 'vitest'
import { useAppStore } from './app-store'

describe('useAppStore', () => {
  beforeEach(() => {
    // Clear the store state before each test
    useAppStore.setState({
      sidebarCollapsed: false,
      theme: 'system',
      designStyle: 'default',
      hasCompletedInitialSetup: false,
      selectedFilter: 'unread',
      selectedArticleId: null,
      selectedLibraryItemId: null,
      currentView: 'feeds',
      groupBy: 'none',
      sortBy: 'newest',
      hideRead: false,
      searchQuery: '',
      isSearching: false,
      featureUsage: {
        hasUsedGroupBy: false,
        hasUsedSummarize: false,
        hasUsedLibrary: false,
        hasUsedFeedManager: false,
      },
      shownToasts: new Set<string>(),
      apiConfig: {
        backendUrl: '/api',
      },
    })
    // Clear localStorage
    localStorage.clear()
  })

  describe('basic state operations', () => {
    it('should have correct initial state', () => {
      const state = useAppStore.getState()
      expect(state.groupBy).toBe('none')
      expect(state.theme).toBe('system')
      expect(state.shownToasts).toBeInstanceOf(Set)
      expect(state.shownToasts.size).toBe(0)
    })

    it('should update groupBy', () => {
      useAppStore.getState().setGroupBy('topic')
      expect(useAppStore.getState().groupBy).toBe('topic')
    })

    it('should update theme', () => {
      useAppStore.getState().setTheme('dark')
      expect(useAppStore.getState().theme).toBe('dark')
    })

    it('should toggle hideRead', () => {
      expect(useAppStore.getState().hideRead).toBe(false)
      useAppStore.getState().toggleHideRead()
      expect(useAppStore.getState().hideRead).toBe(true)
      useAppStore.getState().toggleHideRead()
      expect(useAppStore.getState().hideRead).toBe(false)
    })
  })

  describe('toast tracking', () => {
    it('should track shown toasts', () => {
      const state = useAppStore.getState()

      expect(state.hasShownToast('test-toast')).toBe(false)

      state.markToastShown('test-toast')

      expect(useAppStore.getState().hasShownToast('test-toast')).toBe(true)
      expect(useAppStore.getState().hasShownToast('other-toast')).toBe(false)
    })

    it('should track multiple toasts', () => {
      const state = useAppStore.getState()

      state.markToastShown('toast-1')
      state.markToastShown('toast-2')
      state.markToastShown('toast-3')

      expect(useAppStore.getState().hasShownToast('toast-1')).toBe(true)
      expect(useAppStore.getState().hasShownToast('toast-2')).toBe(true)
      expect(useAppStore.getState().hasShownToast('toast-3')).toBe(true)
      expect(useAppStore.getState().hasShownToast('toast-4')).toBe(false)
    })

    it('shownToasts should always be a Set', () => {
      const state = useAppStore.getState()
      state.markToastShown('test')

      const shownToasts = useAppStore.getState().shownToasts
      expect(shownToasts).toBeInstanceOf(Set)
      expect(shownToasts.has('test')).toBe(true)
    })
  })

  describe('persistence and rehydration', () => {
    it('should serialize shownToasts as array for localStorage', () => {
      // Mark some toasts as shown
      useAppStore.getState().markToastShown('first-group-by-topic')
      useAppStore.getState().markToastShown('another-toast')

      // Check that localStorage received an array, not a Set
      const stored = localStorage.getItem('datapoints-app-storage')
      expect(stored).toBeTruthy()

      const parsed = JSON.parse(stored!)
      expect(parsed.state.shownToasts).toBeInstanceOf(Array)
      expect(parsed.state.shownToasts).toContain('first-group-by-topic')
      expect(parsed.state.shownToasts).toContain('another-toast')
    })

    it('should deserialize shownToasts back to Set on rehydration', async () => {
      // Simulate stored data with array format (what we persist)
      const storedData = {
        state: {
          groupBy: 'topic',
          shownToasts: ['toast-1', 'toast-2'],
        },
        version: 0,
      }
      localStorage.setItem('datapoints-app-storage', JSON.stringify(storedData))

      // Trigger rehydration by calling persist rehydrate
      await useAppStore.persist.rehydrate()

      const state = useAppStore.getState()
      expect(state.shownToasts).toBeInstanceOf(Set)
      expect(state.shownToasts.has('toast-1')).toBe(true)
      expect(state.shownToasts.has('toast-2')).toBe(true)
    })

    it('should handle corrupted shownToasts data (empty object) gracefully', async () => {
      // Simulate old corrupted data where Set was serialized as {}
      const corruptedData = {
        state: {
          groupBy: 'none',
          shownToasts: {}, // This is what happens when Set is JSON.stringify'd
        },
        version: 0,
      }
      localStorage.setItem('datapoints-app-storage', JSON.stringify(corruptedData))

      // Trigger rehydration
      await useAppStore.persist.rehydrate()

      const state = useAppStore.getState()
      // Should gracefully handle and create empty Set
      expect(state.shownToasts).toBeInstanceOf(Set)
      expect(state.shownToasts.size).toBe(0)
      // hasShownToast should work without crashing
      expect(() => state.hasShownToast('test')).not.toThrow()
      expect(state.hasShownToast('test')).toBe(false)
    })

    it('should handle missing shownToasts data gracefully', async () => {
      // Simulate old data without shownToasts field
      const oldData = {
        state: {
          groupBy: 'date',
          theme: 'dark',
        },
        version: 0,
      }
      localStorage.setItem('datapoints-app-storage', JSON.stringify(oldData))

      // Trigger rehydration
      await useAppStore.persist.rehydrate()

      const state = useAppStore.getState()
      expect(state.shownToasts).toBeInstanceOf(Set)
      expect(() => state.hasShownToast('test')).not.toThrow()
    })
  })

  describe('feature usage tracking', () => {
    it('should mark features as used', () => {
      const state = useAppStore.getState()

      expect(state.featureUsage.hasUsedGroupBy).toBe(false)

      state.markFeatureUsed('hasUsedGroupBy')

      expect(useAppStore.getState().featureUsage.hasUsedGroupBy).toBe(true)
    })

    it('should mark hasUsedGroupBy when changing groupBy', () => {
      const state = useAppStore.getState()

      expect(state.featureUsage.hasUsedGroupBy).toBe(false)

      state.setGroupBy('topic')

      expect(useAppStore.getState().featureUsage.hasUsedGroupBy).toBe(true)
    })
  })
})
