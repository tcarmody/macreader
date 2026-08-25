import { describe, it, expect, beforeEach, vi } from 'vitest'
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { Sidebar } from './Sidebar'
import { useAppStore } from '@/store/app-store'

// The sidebar pulls a lot of server state it doesn't need for these assertions.
vi.mock('@/hooks/use-queries', () => {
  const empty = { data: [], isLoading: false }
  return {
    useFeeds: () => empty,
    useStats: () => ({ data: undefined }),
    useAuthStatus: () => ({ data: { is_admin: true } }),
    useTopics: () => empty,
    useSavedSearches: () => empty,
    useCreateSavedSearch: () => ({ mutate: vi.fn(), isPending: false }),
    useDeleteSavedSearch: () => ({ mutate: vi.fn(), isPending: false }),
    useTouchSavedSearch: () => ({ mutate: vi.fn(), isPending: false }),
    useRefreshFeeds: () => ({ mutate: vi.fn(), isPending: false }),
  }
})

function renderSidebar(overrides: Partial<Parameters<typeof Sidebar>[0]> = {}) {
  const onOpenSettings = vi.fn()
  render(
    <Sidebar
      onOpenSettings={onOpenSettings}
      onAddFeed={vi.fn()}
      onManageFeeds={vi.fn()}
      onOpenHelp={vi.fn()}
      {...overrides}
    />,
  )
  return { onOpenSettings }
}

describe('Sidebar', () => {
  beforeEach(() => {
    useAppStore.setState({ sidebarCollapsed: false })
  })

  describe('Settings reachability', () => {
    it('exposes Settings when expanded', async () => {
      const { onOpenSettings } = renderSidebar()

      await userEvent.click(screen.getByRole('button', { name: /settings/i }))
      expect(onOpenSettings).toHaveBeenCalledOnce()
    })

    it('exposes Settings when collapsed to the icon rail', async () => {
      // Collapsing is the only way to see content on a phone-width screen, so
      // the rail dropping Settings made it unreachable there entirely.
      useAppStore.setState({ sidebarCollapsed: true })
      const { onOpenSettings } = renderSidebar()

      await userEvent.click(screen.getByRole('button', { name: /settings/i }))
      expect(onOpenSettings).toHaveBeenCalledOnce()
    })

    it('exposes Help when collapsed to the icon rail', async () => {
      useAppStore.setState({ sidebarCollapsed: true })
      const onOpenHelp = vi.fn()
      renderSidebar({ onOpenHelp })

      await userEvent.click(screen.getByRole('button', { name: /help center/i }))
      expect(onOpenHelp).toHaveBeenCalledOnce()
    })
  })
})
