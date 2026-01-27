# DataPoints Webapp: Onboarding Implementation Plan

## Overview

Making the webapp more accessible to novice users through:
1. **Quick UX Improvements** - Immediate usability enhancements
2. **Contextual Tooltips** - Smart, just-in-time guidance
3. **Help Center** - Searchable reference and documentation

**Total Phase 1 Effort**: 47-63 hours

---

## Week 1: Quick UX Improvements (17-23 hours)

### 1. Better Empty States (2-3 hours)

**Files to modify:**
- `web/src/components/ArticleList.tsx`
- `web/src/components/Sidebar.tsx`
- `web/src/components/LibraryList.tsx`

**Tasks:**
- [ ] Enhance empty feed list with "Add Your First Feed" CTA button
- [ ] Add icon, title, and description to empty states
- [ ] Enhance empty library view with "Add URL or Upload File" buttons
- [ ] Ensure buttons open correct dialogs

**Implementation:**
```tsx
<EmptyState
  icon={Inbox}
  title="No feeds yet"
  description="Add RSS feeds to start reading"
  action={
    <Button onClick={onAddFeed}>
      <Plus /> Add Your First Feed
    </Button>
  }
/>
```

---

### 2. Visual Indicators for Features (2-3 hours)

**Files to modify:**
- `web/src/components/ArticleList.tsx` (Group By section)

**Files to create:**
- `web/src/components/ui/badge-pulse.tsx`

**Tasks:**
- [ ] Create pulsing badge component with CSS animation
- [ ] Add badge to "Group By" buttons when never used
- [ ] Track Group By usage in Zustand store (`hasUsedGroupBy: boolean`)
- [ ] Remove badge after first use

**Implementation:**
```typescript
// In app-store.ts
interface FeatureUsageState {
  hasUsedGroupBy: boolean
  hasUsedSummarize: boolean
  // ... other feature flags
}
```

---

### 3. Improved Backend Setup Screen (2-3 hours)

**Files to modify:**
- `web/src/App.tsx` (needsSetup section)

**Tasks:**
- [ ] Add example backend URL placeholder
- [ ] Include helpful setup instructions
- [ ] Add link to backend deployment documentation
- [ ] Improve error messages with troubleshooting tips
- [ ] Add visual feedback for connection testing

---

### 4. "What's This?" Info Icons (3-4 hours)

**Target locations:**
- Group By Topic button
- Library tab
- Summarize button
- Category dropdowns

**Tasks:**
- [ ] Add info icon component (using existing Tooltip)
- [ ] Add to Group By Topic: "AI analyzes and groups similar topics"
- [ ] Add to Library tab: "Store web pages, PDFs, and documents"
- [ ] Add to Summarize: "AI generates a concise summary"
- [ ] Style consistently across all locations

---

### 5. First-Time Feature Toasts (4-5 hours)

**Files to create/modify:**
- Toast notification system (may already exist in shadcn/ui)
- Track first-time usage in Zustand

**Tasks:**
- [ ] Set up toast notification system
- [ ] Track first-time feature usage in store
- [ ] Add toast on first summarize: "AI is generating a summary..."
- [ ] Add toast on first group by topic: "Analyzing articles with AI..."
- [ ] Add toast on first library add: "Item saved to your library"
- [ ] Ensure toasts are dismissible and don't repeat

**Implementation:**
```typescript
// In app-store.ts
interface FirstTimeState {
  shownToasts: Set<string>
}

// Usage
if (!shownToasts.has('first-summarize')) {
  toast.info("AI is generating a summary. This may take a few seconds.");
  addShownToast('first-summarize');
}
```

---

### 6. Better Feed Manager Discovery (2 hours)

**Files to modify:**
- `web/src/components/Sidebar.tsx`
- `web/src/components/FeedManagerDialog.tsx`

**Tasks:**
- [ ] Make "Manage Feeds" button more prominent (larger/clearer text)
- [ ] Show feed count next to manage button: "Manage Feeds (23)"
- [ ] Consider adding to feed context menu
- [ ] Add tooltip: "Bulk edit, organize, and manage your feeds"

---

### 7. Smarter Default Behavior (1-2 hours)

**Files to modify:**
- `web/src/store/app-store.ts`

**Tasks:**
- [ ] Auto-collapse all feed categories on first load
- [ ] Default to "Unread" filter instead of "All" for new users
- [ ] Consider enabling "Hide Read" by default
- [ ] Track user's first visit to apply defaults only once

**Implementation:**
```typescript
// Check if first visit
const isFirstVisit = !localStorage.getItem('hasVisitedBefore');

if (isFirstVisit) {
  // Apply smart defaults
  set({ selectedFilter: 'unread', categoriesCollapsed: true });
  localStorage.setItem('hasVisitedBefore', 'true');
}
```

---

### 8. Search Placeholder Improvements (1 hour)

**Files to modify:**
- `web/src/components/Sidebar.tsx` (search input)

**Tasks:**
- [ ] Rotate helpful tips in search placeholder
- [ ] Examples:
  - "Search articles... (Press '/' to focus)"
  - "Try searching by author, title, or content"
  - "Search across all your feeds"
- [ ] Change placeholder every few seconds or on focus

---

## Week 2: Contextual Tooltips System (11-15 hours)

### Core Tooltip Infrastructure (5-6 hours)

**Files to create:**
- `web/src/components/ui/smart-tooltip.tsx`
- `web/src/components/CoachMarks/CoachMark.tsx`
- `web/src/components/CoachMarks/FirstTimeHint.tsx`
- `web/src/hooks/use-hint-tracking.ts`
- `web/src/lib/hints.ts`

**Tasks:**
- [ ] Create SmartTooltip component with view tracking
- [ ] Create CoachMark component with pulsing indicator
- [ ] Create FirstTimeHint wrapper component
- [ ] Implement useHintTracking hook
- [ ] Add hint state to Zustand store
- [ ] Create centralized hints configuration

**State Structure:**
```typescript
// In app-store.ts
interface HintState {
  seenHints: Record<string, number>  // hintId -> view count
  dismissedHints: Set<string>
  hintingEnabled: boolean
}
```

**SmartTooltip Interface:**
```typescript
interface SmartTooltipProps {
  id: string
  content: string
  showOnce?: boolean
  maxShows?: number  // Default: 3
  children: React.ReactNode
}
```

---

### Strategic Tooltip Placement (6-9 hours)

**Files to modify:**
- `web/src/components/Sidebar.tsx`
- `web/src/components/ArticleList.tsx`
- `web/src/components/ArticleDetail.tsx`
- `web/src/components/FeedManagerDialog.tsx`

**Tooltips to add:**
- [ ] Add Feed button: "Subscribe to RSS feeds and newsletters"
- [ ] Group By Date: "See what's new today"
- [ ] Group By Feed: "Organize by publication"
- [ ] Group By Topic: "AI groups similar articles (requires 10+ articles)"
- [ ] Summarize: "AI generates a concise summary"
- [ ] Library tab: "Save web pages, PDFs, and documents"
- [ ] Settings: "Configure backend, API keys, and preferences"
- [ ] Search: "Search across all articles and content"
- [ ] Feed Manager: "Bulk edit, organize, and manage your feeds"
- [ ] Bookmark: "Save articles for later reading"

---

## Week 3-4: Help Center (19-25 hours)

### Help Panel Components (8-10 hours)

**Files to create:**
- `web/src/components/HelpCenter/HelpPanel.tsx`
- `web/src/components/HelpCenter/HelpArticle.tsx`
- `web/src/components/HelpCenter/HelpSearch.tsx`
- `web/src/components/HelpCenter/HelpNavigation.tsx`
- `web/src/components/HelpCenter/KeyboardShortcuts.tsx`

**Tasks:**
- [ ] Create HelpPanel container (slides in from right)
- [ ] Create HelpArticle renderer (supports markdown)
- [ ] Create HelpSearch with fuzzy search
- [ ] Create HelpNavigation for categories
- [ ] Create KeyboardShortcuts reference view
- [ ] Add help state to Zustand store

**State Structure:**
```typescript
interface HelpState {
  helpOpen: boolean
  currentArticleId: string | null
  searchQuery: string
}
```

---

### Help Content (6-8 hours)

**File to create:**
- `web/src/lib/help-content.ts`

**Content to write:**

**Getting Started (5 articles):**
- [ ] Setting up your backend
- [ ] Adding your first feed
- [ ] Understanding the interface
- [ ] Importing existing subscriptions (OPML)
- [ ] Organizing with categories

**Features (6 articles):**
- [ ] AI Summarization explained
- [ ] Library: Saving web pages and files
- [ ] Grouping options (Date/Feed/Topic)
- [ ] Feed Manager capabilities
- [ ] Search and filters
- [ ] Keyboard shortcuts

**Troubleshooting (4 articles):**
- [ ] Connection issues (CORS, backend URL)
- [ ] Feed not updating
- [ ] Summarization not working
- [ ] Authentication problems

**FAQ (3-5 articles):**
- [ ] What is an RSS feed?
- [ ] How does AI summarization work?
- [ ] Can I use this offline?
- [ ] How do I backup my feeds?

---

### Integration (5-7 hours)

**Files to modify:**
- `web/src/components/Sidebar.tsx` (add help button)
- `web/src/App.tsx` (render HelpPanel)
- `web/src/store/app-store.ts` (add help state)

**Tasks:**
- [ ] Add "?" help button to sidebar footer
- [ ] Integrate HelpPanel into App.tsx
- [ ] Connect help panel to Zustand store
- [ ] Add keyboard shortcut to open help (e.g., `?` or `Shift+/`)
- [ ] Ensure help panel is responsive
- [ ] Polish animations and transitions

---

## Testing Checklist

### Week 1 Verification
- [ ] Empty states show with CTAs and work correctly
- [ ] Backend setup screen shows examples and help
- [ ] Visual indicators pulse on unused features
- [ ] Info icons display helpful tooltips
- [ ] First-time toasts appear once and are dismissible
- [ ] Feed Manager is more discoverable
- [ ] Smart defaults apply on first visit
- [ ] Search placeholder rotates helpful tips

### Week 2 Verification
- [ ] Tooltips appear on hover for first-time features
- [ ] Tooltip view count tracks correctly in localStorage
- [ ] CoachMark pulses are visible and dismissible
- [ ] Tooltips stop appearing after maxShows reached
- [ ] All 10 strategic tooltips are placed correctly

### Week 3-4 Verification
- [ ] Help button opens/closes panel smoothly
- [ ] Help search finds relevant articles
- [ ] All help content renders correctly
- [ ] Keyboard shortcuts reference is complete
- [ ] Help panel state persists across page reloads
- [ ] Responsive design works on all screen sizes

---

## Implementation Notes

### State Management Strategy
All onboarding state will be managed in Zustand store with localStorage persistence:
- Feature usage tracking (Group By, Summarize, etc.)
- First-time toast tracking
- Hint view counts and dismissals
- Help panel state

### Component Patterns
Following existing DataPoints patterns:
- Use shadcn/ui components (Dialog, Tooltip, Button, etc.)
- Extend existing EmptyState component
- Follow existing modal/dialog patterns
- Use existing icons from Lucide React

### Styling
- Match existing design styles (Default, Serif, Dense)
- Respect theme (light/dark mode)
- Use Tailwind CSS classes
- Subtle animations (avoid distracting users)

---

## Success Metrics to Track

After implementation, monitor:
1. **Setup Completion Rate**: % users who add first feed
2. **Feature Discovery**: % users who try summarization, library, categories
3. **Help Center Usage**: Most viewed articles
4. **Tooltip Engagement**: View vs dismiss rates
5. **Time to First Value**: Time until first article read

---

## Phase 2: Future Enhancements

After gathering user feedback from Phase 1, consider:
- **Onboarding Checklist Widget** (12-16 hrs) - if users need explicit progress tracking
- **Interactive Product Tour** (10-15 hrs) - if users are overwhelmed on first use
- **Enhanced First-Run Wizard** (28-37 hrs) - if backend setup remains a barrier

Monitor analytics and user feedback for 2-4 weeks before implementing Phase 2.
