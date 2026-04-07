# UI Improvement Plan

Remaining items from the UI review session. The tab strip (item 0) is already done.

---

## 1. Article list: show first key point instead of raw snippet when summarized

**What**: When an article has been summarized, replace the subtitle/snippet text in the article list row with the first key point from the AI summary.

**Why**: The purple sparkle badge already signals "summarized" — the subtitle should match that signal. This makes AI output feel integrated rather than hidden two scrolls (now two tabs) away.

**Where**:
- Web: `web/src/components/` — the article list item component (wherever `summary_short` or snippet is rendered in the row)
- macOS: `app/DataPointsAI/DataPointsAI/Views/Components/ArticleRow.swift`

**Notes**: Fall back to the normal snippet if no key points exist. The first key point is usually one sentence, which fits the row height budget.

---

## ~~2. Consolidate AI toolbar actions into a single "AI" button~~ ✓ Done

**What**: Group "Summarize", "Find Related" (Context), and "Chat" behind a single **AI** button (sparkles icon) that opens a popover showing all three actions and their current status.

**Why**: The toolbar currently has 6–8 icon-buttons in a row. New users have to hover-discover what each one does. Grouping them as "AI stuff" reduces clutter and frames the features as a coherent system. The popover can show live status: "Summary ready · 3 related links · 5 messages."

**Where**:
- Web: `web/src/components/ArticleDetail.tsx` — the toolbar section
- macOS: `ArticleDetailView.swift` — `articleToolbar` method; window toolbar in `toolbarContent`

**Notes**: The individual action buttons (Summarize, Context) can remain as redundant shortcuts in the Article tab body, but the toolbar entry point becomes unified. Chat tab navigation replaces the Chat button.

---

## 3. Search: dedicated mode with richer results

**What**: When the search bar is active, switch the middle pane into a distinct **search mode** — different header treatment, matched terms highlighted in the result rows, and optionally a toggle to "search within AI summaries."

**Why**: Search currently produces a filtered article list indistinguishable from any other filter (Unread, Today, Bookmarked). It deserves its own visual mode to signal that different rules apply and to surface more useful context per result.

**Sub-tasks**:
- Add match highlighting to article list rows when a search query is active
- Add a "Search in summaries" toggle that hits the backend FTS index including summary text
- Consider showing which field matched (title vs. body vs. summary)

**Where**:
- Web: `web/src/components/ArticleList.tsx`, sidebar search input, `web/src/api/client.ts`
- macOS: `ArticleListView.swift`, search binding in `AppState`
- Backend: `backend/routes/articles.py` — the search endpoint may need a `search_summaries` param

---

## 4. Sidebar: Topics section as a first-class entry point

**What**: Add a collapsible "Topics" section in the sidebar (below the filter list) showing the last N AI-discovered topic clusters as clickable items. Clicking a topic filters the article list to that cluster.

**Why**: Topic clustering exists and is exposed via the Group By picker in the middle pane, but there's no way to *navigate by topic* from the sidebar. Users have to know to look at the Group By control. A sidebar entry makes discovery natural.

**Where**:
- Web: `web/src/components/Sidebar.tsx`
- macOS: `FeedListView.swift`
- The topic data comes from the `topic_history` table, already fetched for grouping

**Notes**: Only show this section when topic data exists (i.e., at least one clustering run has completed). Show the top 5–8 topic labels with article counts.

---

## 5. Reading progress → "Jump to AI Summary" floating chip

**What**: After scrolling past ~30% of the Article tab content, show a small floating chip in the bottom-right of the article pane:

```
[ ↑ AI Summary  ·  sparkles ]
```

Clicking it switches to the AI tab (or scrolls to it if we revert to inline layout). Dismiss automatically when the user switches tabs or closes the article.

**Why**: The Article tab now contains only the raw content with no AI features visible. For long articles the user has read, this gives a clear "next step" — especially useful for new users who may not notice the tab strip.

**Where**:
- Web: `web/src/components/ArticleDetail.tsx` — positioned absolutely inside the ScrollArea container, shown only when `hasSummary && activeTab === 'article'`
- macOS: `ArticleDetailView.swift` — overlay on the scroll view

**Notes**: Only show when `hasSummary` is true and the Article tab is active. Animate in/out with a spring. Keep it dismissible.

---

## 6. Article list rows: richer AI state indicators

**What**: Beyond the current "summarized" sparkle badge, show:
- A chat bubble count badge when a conversation exists for that article
- A "N related" micro-badge when related links have been found

**Why**: Users can't see at a glance which articles have been fully "worked" (summarized, chat, related). These badges make the list scannable for AI-enriched content.

**Where**:
- Web: article list item component
- macOS: `ArticleRow.swift`
- Data: `related_links` and chat counts are available in the article list API response (verify `chat_message_count` is included, add if not)

**Notes**: Keep badges small and low-contrast — they're secondary information. The existing purple sparkle is the primary AI indicator.
