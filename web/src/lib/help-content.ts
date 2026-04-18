export interface HelpArticle {
  id: string
  category: 'getting-started' | 'features' | 'troubleshooting' | 'faq'
  title: string
  body: string // markdown
}

export const HELP_CATEGORIES: Record<HelpArticle['category'], string> = {
  'getting-started': 'Getting Started',
  'features': 'Features',
  'troubleshooting': 'Troubleshooting',
  'faq': 'FAQ',
}

export const HELP_ARTICLES: HelpArticle[] = [
  // ── Getting Started ──────────────────────────────────────────────────────────

  {
    id: 'gs-setup',
    category: 'getting-started',
    title: 'Connect to your backend',
    body: `Data Points needs a running backend server. Open **Settings → Backend** and paste your server URL.

**Local development:**
\`\`\`
http://localhost:5005
\`\`\`

**Deployed server (Railway, Fly, etc.):**
\`\`\`
https://your-app.railway.app
\`\`\`

If you see a connection error, make sure the backend process is running and the URL includes the correct port.`,
  },
  {
    id: 'gs-add-feed',
    category: 'getting-started',
    title: 'Add your first feed',
    body: `Click the **+** button in the Feeds section (or press **⌘N**) and paste either:

- A direct RSS/Atom feed URL: \`https://example.com/feed.xml\`
- Any website URL — we'll auto-detect the feed

You can also import an **OPML file** from another reader via **Settings → Import OPML**.`,
  },
  {
    id: 'gs-reading',
    category: 'getting-started',
    title: 'Reading articles',
    body: `Click any article in the list to open it. Keyboard shortcuts:

| Key | Action |
|-----|--------|
| j / k | Next / previous article |
| m | Toggle read/unread |
| s | Bookmark (save for later) |
| o | Open in browser |
| / | Focus search |

Articles marked **unread** have a blue left border and a filled dot. They are automatically marked read when you open them.`,
  },
  {
    id: 'gs-filters',
    category: 'getting-started',
    title: 'Filters and views',
    body: `The sidebar shows several built-in filters:

- **Unread** — articles you haven't opened yet (default view)
- **Today** — published in the last 24 hours
- **Bookmarked** — articles you've saved
- **Summarized** — articles with an AI summary

You can also click any **feed name** or **topic** in the sidebar to filter to just those articles.`,
  },
  {
    id: 'gs-search',
    category: 'getting-started',
    title: 'Searching your feeds',
    body: `Press **/** to focus the search bar. Data Points searches article titles, full content, and AI summaries simultaneously.

- **Pin a search** — click the 📌 pin icon while a query is active to save it. Saved searches appear in the sidebar.
- **Toggle summary search** — use the page icon in the article list header to include or exclude AI summaries from results.`,
  },

  // ── Features ─────────────────────────────────────────────────────────────────

  {
    id: 'feat-summarize',
    category: 'features',
    title: 'AI Summarization',
    body: `Click the **AI** tab on any article, then click **Generate Summary**. Data Points calls your configured AI provider (Anthropic Claude, OpenAI GPT, or Google Gemini) and returns:

- **Key points** — bullet points of the most important facts
- **Brief** — one sentence distillation
- **Full summary** — 2–4 paragraph deep read

Requires an API key in **Settings → AI**. Anthropic Claude is recommended — it supports prompt caching which reduces cost ~90% on repeated summaries.`,
  },
  {
    id: 'feat-group-by-topic',
    category: 'features',
    title: 'Group articles by topic',
    body: `In the article list toolbar, click the **Topic** grouping button (tags icon). The AI will cluster your current articles into topic groups (e.g. "AI Research", "Climate Policy").

**Tips:**
- Works best with 10+ articles loaded
- Topics are regenerated fresh each time
- Use the **Topics** section in the sidebar to filter by a topic cluster`,
  },
  {
    id: 'feat-library',
    category: 'features',
    title: 'Library: save anything',
    body: `The **Library** tab (sidebar) lets you save content that isn't in an RSS feed:

- **Web pages** — paste any URL
- **PDFs** — upload and read inline
- **Documents** — DOCX, TXT, Markdown, HTML files

Once saved, Library items can be summarized and searched the same as feed articles.`,
  },
  {
    id: 'feat-digest',
    category: 'features',
    title: 'Auto-Digest',
    body: `The **Digest** tab shows an AI-assembled daily or weekly summary of your top stories. It:

1. Deduplicates articles covering the same event
2. Clusters them into topics
3. Selects the most important story per cluster
4. Generates a formatted digest

Refresh the digest anytime with the refresh button. Digests are cached for a few hours.`,
  },
  {
    id: 'feat-newsletters',
    category: 'features',
    title: 'Newsletter import via Gmail',
    body: `Connect your Gmail account in **Settings → Newsletters** to import email newsletters as articles.

Data Points uses read-only Gmail IMAP access and respects the label filters you configure. Newsletters appear in the **Newsletters** section of the sidebar and are fully searchable and summarizable.`,
  },
  {
    id: 'feat-notifications',
    category: 'features',
    title: 'Smart Notifications',
    body: `In **Settings → Notifications**, create rules that trigger an alert when new articles match:

- A **keyword** in title or content
- A specific **author**
- A specific **feed**
- A **priority level** (high / normal / low)

Notifications fire after each feed refresh.`,
  },

  // ── Troubleshooting ───────────────────────────────────────────────────────────

  {
    id: 'ts-connection',
    category: 'troubleshooting',
    title: 'Cannot connect to backend',
    body: `**Check these first:**

1. Is the backend process running? Open a terminal and run:
   \`\`\`
   source rss_venv/bin/activate && python -m uvicorn backend.server:app --port 5005
   \`\`\`
2. Is the URL correct, including the port? (default: \`http://localhost:5005\`)
3. Did you set an API key in \`.env\`? The app requires \`AUTH_API_KEY\`.
4. **CORS errors** — if the frontend origin isn't listed in \`CORS_ORIGINS\`, the browser will block the request.`,
  },
  {
    id: 'ts-no-articles',
    category: 'troubleshooting',
    title: 'Feed added but no articles appear',
    body: `After adding a feed, click **Refresh** (the circular arrow in the sidebar header) or press **r**.

If articles still don't appear:
- Check the feed URL is valid and publicly accessible
- Some feeds require JavaScript rendering — enable **Settings → Advanced → JS Rendering** (requires Playwright)
- Try the **All Articles** filter (you may be on **Unread** and have already read everything)`,
  },
  {
    id: 'ts-ai-errors',
    category: 'troubleshooting',
    title: 'AI summarization fails',
    body: `If summarization returns an error:

1. Go to **Settings → AI** and verify your API key is entered correctly
2. Check that your chosen provider (Anthropic / OpenAI / Google) is selected
3. Ensure you have credits remaining on your API account
4. For very long articles, the request may timeout — try again; the server retries automatically`,
  },
  {
    id: 'ts-search',
    category: 'troubleshooting',
    title: 'Search returns no results',
    body: `Data Points uses a Tantivy full-text index that is rebuilt at startup. If search seems broken:

1. Restart the backend — the index rebuilds automatically
2. Make sure articles have been fetched (refresh feeds)
3. Try searching with a simpler term first
4. The **include summaries** toggle (page icon in article list header) expands search to AI-generated text`,
  },

  // ── FAQ ───────────────────────────────────────────────────────────────────────

  {
    id: 'faq-cost',
    category: 'faq',
    title: 'How much does AI summarization cost?',
    body: `With **Anthropic Claude** and prompt caching enabled (the default), a typical article summary costs roughly **$0.001–0.003**. If you summarize 100 articles per month, that's under $0.30.

OpenAI and Google models are comparable in cost. You control which provider is used in **Settings → AI**.`,
  },
  {
    id: 'faq-privacy',
    category: 'faq',
    title: 'Is my reading data private?',
    body: `Yes. Data Points is **self-hosted** — your articles, reading history, and summaries never leave your own server. The only external calls made are:

- Your RSS feed URLs (to fetch articles)
- Your AI provider (only when you trigger summarization)
- Exa neural search (only when you click "Find Related")`,
  },
  {
    id: 'faq-opml',
    category: 'faq',
    title: 'Can I import/export my feeds?',
    body: `Yes! Go to **Settings → Feeds**:

- **Import OPML** — paste or upload an OPML file from any RSS reader
- **Export OPML** — download your current subscriptions as a standard OPML file, compatible with Feedly, NetNewsWire, etc.`,
  },
  {
    id: 'faq-shortcuts',
    category: 'faq',
    title: 'What are all the keyboard shortcuts?',
    body: `| Shortcut | Action |
|----------|--------|
| j | Next article |
| k | Previous article |
| m | Toggle read/unread |
| s | Toggle bookmark |
| o | Open in browser |
| r | Refresh feeds |
| / | Focus search |
| Esc | Clear search |
| ⌘ , | Open Settings |
| ⌘ N | Add new feed |
| ? | Open this help panel |`,
  },
  {
    id: 'faq-themes',
    category: 'faq',
    title: 'Can I change the appearance?',
    body: `Yes — open **Settings → Appearance**:

- **Theme** — Light, Dark, or System
- **Design Style** — 9 options including Warm, Teal, High Contrast, Sepia, and Mono

Changes apply instantly and are saved for your next visit.`,
  },
]
