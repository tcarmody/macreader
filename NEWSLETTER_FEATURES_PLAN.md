# Newsletter Assembly — Feature Implementation Plan

Five features that turn DataPoints into a newsletter production pipeline.
Backlog items (Issue Board, Story Basket, etc.) live in `FEATURETODOs.md`.

---

## Overview

| Feature | New backend files | New DB | New routes | Depends on |
|---|---|---|---|---|
| Duplicate Story Detection | `services/story_groups.py` | `story_groups`, `story_group_members` | `GET /articles/story-groups` | clustering.py |
| Brief Generator | `services/brief_generator.py` | `article_briefs` | `POST /articles/{id}/brief`, `POST /briefs/batch` | summarizer.py |
| Draft Assembler | `services/draft_assembler.py` | `drafts` | `POST /digest/draft` | brief generator, clustering |
| Coverage Gap Analysis | `services/gap_analysis.py` | — | `POST /digest/gap-analysis` | clustering, related_links |
| Auto-Digest | `services/auto_digest.py` | `digests` | `GET /digest/auto` | all of the above |

---

## 1. Duplicate Story Detection

### What it does
Groups articles from different feeds that cover the same underlying news event —
not just exact-duplicate content (which `content_hash` already handles), but
semantically-equivalent coverage ("same story, five newsletters").

### Approach
Reuse the existing `clustering.py` LLM pipeline. A cluster where multiple
articles share a tight semantic label *and* arrived within a configurable time
window (default: 48 h) is a story group. We materialise this as a lightweight
table so the UI and other features can query it cheaply.

```
story_groups
  id               INTEGER PRIMARY KEY
  label            TEXT          -- e.g. "OpenAI o3 Release"
  representative_id INTEGER FK   -- best-sourced article (oldest or highest word count)
  period_start     TIMESTAMP
  period_end       TIMESTAMP
  created_at       TIMESTAMP

story_group_members
  story_group_id   INTEGER FK
  article_id       INTEGER FK
  PRIMARY KEY (story_group_id, article_id)
```

### Service: `backend/services/story_groups.py`
```python
class StoryGroupService:
    async def detect_groups(article_ids: list[int], window_hours: int = 48) -> list[StoryGroup]
    async def get_or_create_groups(feed_id: int | None, since: datetime) -> list[StoryGroup]
    async def get_group_for_article(article_id: int) -> StoryGroup | None
```

**Algorithm:**
1. Fetch articles in window, each with their `title` + `one_liner` (or title only if not yet summarised).
2. Call `clustering.cluster_articles()` — already caches by article-ID set, so repeated calls are free.
3. For each cluster with ≥ 2 articles: create/upsert a `story_group` row.
4. Pick `representative_id`: highest `word_count`, or oldest `published_at` if equal.
5. Write `story_group_members` rows.

### New routes (`backend/routes/articles.py` extension)
```
GET /articles/story-groups
  ?since=ISO8601          (default: 48 h ago)
  ?feed_ids=1,2,3         (optional filter)
  ?min_size=2             (default 2, i.e. only real duplicates)

Response:
[
  {
    "id": 1,
    "label": "OpenAI o3 Release",
    "representative_article": { ...ArticleResponse },
    "members": [ ...ArticleResponse[] ],
    "period_start": "...",
    "period_end": "..."
  }
]
```

### Integration points
- `GET /articles?hide_duplicates=true` already exists — extend it to hide
  non-representative story-group members (not just hash duplicates).
- Draft Assembler uses `story_group.representative_id` to auto-pick the best
  source when building a digest section.
- Coverage Gap Analysis uses story groups to understand what events ARE covered.

### Cost
One LLM call per detection run (same as clustering). Results cached 1 h by
`clustering.py`. Story groups written to DB are cheap to re-read.

---

## 2. Brief Generator

### What it does
Produces newsletter-ready blurbs from a single article at three lengths and
three tones. Unlike the existing `summary_short` (a plain one-liner), briefs
are styled for direct insertion into a newsletter draft.

### Lengths
| Key | Description | Target |
|---|---|---|
| `sentence` | One punchy sentence | 20–30 words |
| `short` | Three-sentence paragraph | 60–80 words |
| `paragraph` | Full contextual paragraph | 120–160 words |

### Tones
| Key | Description |
|---|---|
| `neutral` | Objective, factual |
| `opinionated` | Takes a clear perspective |
| `analytical` | Breaks down significance and implications |

### Database
```
article_briefs
  id           INTEGER PRIMARY KEY
  article_id   INTEGER FK
  length       TEXT  CHECK(length IN ('sentence','short','paragraph'))
  tone         TEXT  CHECK(tone IN ('neutral','opinionated','analytical'))
  content      TEXT
  model_used   TEXT
  created_at   TIMESTAMP
  UNIQUE(article_id, length, tone)
```

### Service: `backend/services/brief_generator.py`
```python
class BriefGenerator:
    async def generate(article_id: int, length: BriefLength, tone: BriefTone) -> Brief
    async def generate_batch(article_ids: list[int], length: BriefLength, tone: BriefTone) -> list[Brief]
    async def get_cached(article_id: int, length: BriefLength, tone: BriefTone) -> Brief | None
```

**Implementation:**
- Check `article_briefs` cache first; return if hit.
- Build prompt from article title + content (or `summary_full` if available —
  cheaper tokens).
- Use `ModelTier.FAST` (Haiku) for `sentence` and `short`; `STANDARD` (Sonnet)
  for `paragraph`.
- Use Anthropic's cacheable-prefix pattern for the static instruction block.
- Write result to `article_briefs`.

**Prompt skeleton (sentence, neutral):**
```
You are writing a newsletter brief. Given the article below, write a single
punchy sentence (20-30 words) that tells the reader what happened and why it
matters. No filler, no hedging.

Article: {title}
{summary_full or first 500 chars of content}
```

### Routes
```
POST /articles/{id}/brief
  Body: { "length": "short", "tone": "neutral" }
  Response: { "brief": "...", "length": "short", "tone": "neutral", "cached": false }

POST /briefs/batch
  Body: { "article_ids": [1,2,3], "length": "short", "tone": "neutral" }
  Response: [ { "article_id": 1, "brief": "..." }, ... ]
  (runs concurrently, max 20 articles per call — same pattern as /summarize/batch)
```

---

## 3. Draft Assembler

### What it does
Takes a list of article IDs (a newsletter issue in the making) and produces a
complete formatted newsletter draft: section headers, per-article briefs, intro,
and outro — ready to paste into a publishing platform.

### Formats
- `markdown` — default, paste anywhere
- `html` — inline styles, safe for email clients
- `substack` — Substack-optimised HTML (no external CSS, heading levels matched
  to Substack's editor)

### Service: `backend/services/draft_assembler.py`
```python
class DraftAssembler:
    async def assemble(
        article_ids: list[int],
        title: str,
        brief_length: BriefLength = "short",
        tone: BriefTone = "neutral",
        format: DraftFormat = "markdown",
    ) -> Draft

@dataclass
class Draft:
    title: str
    intro: str
    sections: list[DraftSection]   # one per topic cluster
    outro: str
    word_count: int
    article_count: int
    format: str
    raw: str                        # full rendered text
```

**Assembly pipeline:**
1. Fetch all articles (with summaries where available).
2. Run `StoryGroupService.detect_groups()` on the set — collapse duplicates to
   their representative.
3. Run `clustering.cluster_articles()` — produces topic sections.
4. For each article, call `BriefGenerator.generate()` (batch, cached).
5. Generate **intro**: LLM call with cluster labels + article count.
   - Model: `FAST`. Prompt: "Write a 2-sentence newsletter intro covering these
     topics: {labels}. Tone: {tone}."
6. Generate **outro**: short sign-off paragraph (optional, can be omitted).
7. Render into requested format.

**Database (optional caching):**
```
drafts
  id           INTEGER PRIMARY KEY
  article_ids  TEXT   -- JSON array, sorted
  title        TEXT
  format       TEXT
  tone         TEXT
  brief_length TEXT
  content      TEXT   -- rendered draft
  word_count   INTEGER
  created_at   TIMESTAMP
```
Cache key: SHA256 of sorted `article_ids + format + tone + brief_length`.
TTL: 2 hours (articles may get summarised in the interim).

### Route
```
POST /digest/draft
  Body:
  {
    "article_ids": [4, 17, 23, 41],
    "title": "The Weekly Brief #47",
    "brief_length": "short",       // optional, default "short"
    "tone": "neutral",             // optional, default "neutral"
    "format": "markdown"           // optional, default "markdown"
  }

  Response:
  {
    "title": "The Weekly Brief #47",
    "intro": "...",
    "sections": [
      {
        "label": "AI & Models",
        "articles": [
          { "id": 4, "title": "...", "brief": "...", "url": "...", "source": "..." }
        ]
      }
    ],
    "outro": "...",
    "word_count": 420,
    "article_count": 4,
    "raw": "# The Weekly Brief #47\n\n..."
  }
```

---

## 4. Coverage Gap Analysis

### What it does
Given a draft's article set, the gap analyser finds what angles or stories your
selected articles miss — based on what related articles *exist* in the world
(via Exa) vs. what you've chosen to cover.

### Service: `backend/services/gap_analysis.py`
```python
class GapAnalysisService:
    async def analyse(article_ids: list[int]) -> GapAnalysisResult

@dataclass
class GapAnalysisResult:
    covered_topics: list[str]           # cluster labels from article set
    gaps: list[Gap]
    suggested_searches: list[str]       # ready-to-use search terms

@dataclass
class Gap:
    description: str                    # "No coverage of the regulatory angle"
    related_articles: list[RelatedLink] # Exa results for this gap
    suggested_query: str
```

**Algorithm:**
1. Cluster the article set → `covered_topics`.
2. For each topic cluster, pull its representative article's `related_links`
   (from Exa, already cached on article). If missing, trigger `related_links`
   fetch for the representative.
3. Collect all Exa-returned articles that are *not* in `article_ids` —
   these are candidates for uncovered angles.
4. Pass to LLM (`STANDARD` tier):
   - Input: covered topic labels + titles, plus the candidate external articles
   - Prompt: "You are a newsletter editor. The following topics are covered:
     {covered}. The following related articles exist but are not covered:
     {external}. What angles or perspectives are missing? List 3-5 gaps with a
     1-sentence description and a suggested search query for each."
5. Return structured gaps + any Exa articles that exemplify each gap.

**No new DB table needed** — results are ephemeral (tied to a specific draft
snapshot). Cache in memory for 30 min keyed on sorted article IDs.

### Route
```
POST /digest/gap-analysis
  Body: { "article_ids": [4, 17, 23, 41] }

  Response:
  {
    "covered_topics": ["AI Models", "Open Source LLMs"],
    "gaps": [
      {
        "description": "No coverage of the regulatory/policy angle",
        "suggested_query": "AI regulation EU Act 2025",
        "related_articles": [
          { "url": "...", "title": "...", "snippet": "...", "score": 0.87 }
        ]
      }
    ],
    "suggested_searches": ["AI regulation EU Act 2025", "...]
  }
```

---

## 5. Auto-Digest

### What it does
Given a time period, automatically selects the most noteworthy stories from your
feeds, deduplicates them, groups them by topic, and assembles a ready-to-read
(or ready-to-publish) digest — without the editor choosing individual articles.

### Selection algorithm
1. Fetch articles in window (`today` = last 24 h, `week` = last 7 days).
2. Detect story groups — collapse duplicates, keep representative.
3. Cluster remaining articles into topics.
4. Score each story group:
   - `+2` if representative has a summary (more content signal)
   - `+1` per additional source that covered the same story (breadth)
   - `-1` per day since `published_at` (freshness decay)
   - `+1` if article is from a bookmarked/high-signal feed (future: Source
     Intelligence score)
5. Take top N per topic cluster (default: 1), overall cap of 10 stories.
6. Run Draft Assembler on selected article IDs.
7. Cache result as a `digests` row.

### Database
```
digests
  id            INTEGER PRIMARY KEY
  user_id       INTEGER FK (NULL = shared/global)
  period        TEXT  CHECK(period IN ('today','week','custom'))
  period_start  TIMESTAMP
  period_end    TIMESTAMP
  article_ids   TEXT   -- JSON array
  title         TEXT
  content       TEXT   -- rendered markdown
  word_count    INTEGER
  created_at    TIMESTAMP
```

### Service: `backend/services/auto_digest.py`
```python
class AutoDigestService:
    async def generate(
        period: DigestPeriod,            # "today" | "week"
        user_id: int | None = None,
        feed_ids: list[int] | None = None,
        max_stories: int = 10,
        format: DraftFormat = "markdown",
        tone: BriefTone = "neutral",
    ) -> Digest

    async def get_latest(period: DigestPeriod, user_id: int | None) -> Digest | None
```

### Route
```
GET /digest/auto
  ?period=today              (default "today"; also "week")
  ?feed_ids=1,2,3            (optional feed filter)
  ?max_stories=10            (optional)
  ?format=markdown           (optional)
  ?tone=neutral              (optional)
  ?refresh=false             (force regeneration even if cached)

  Response: same shape as /digest/draft, plus:
  {
    "period": "today",
    "period_start": "2026-03-29T00:00:00Z",
    "period_end": "2026-03-29T23:59:59Z",
    "cached": true,
    "story_count": 8,
    ...draft fields...
  }
```

Cached for 2 hours unless `?refresh=true`. Regenerating is cheap once briefs
are cached.

---

## Implementation Order

These features have a natural dependency chain:

```
Story Groups  ──►  Brief Generator  ──►  Draft Assembler  ──►  Auto-Digest
                                    └──►  Coverage Gap Analysis
```

**Recommended sequence:**
1. **Brief Generator** — standalone, immediately useful, validates the LLM prompts
2. **Story Groups** — enables smart dedup for everything downstream
3. **Draft Assembler** — first end-to-end output a user can actually use
4. **Coverage Gap Analysis** — enhances Draft Assembler; depends on Exa cache
5. **Auto-Digest** — caps the pipeline; requires all four above

---

## Shared Infrastructure Notes

- **LLM calls:** All use the existing `LLMProvider` interface. Default to
  Anthropic with cacheable-prefix for static instruction blocks.
- **Cost guardrails:** Brief Generator and Assembler batch calls to avoid
  per-article overhead; cache aggressively at every layer.
- **Testing:** Follow existing pattern — mock `LLMProvider` in unit tests
  (`MockProvider` in conftest); integration tests against real SQLite.
- **Auth:** All new routes accept the existing `AUTH_API_KEY` header.

---

*Plan written: March 2026*
