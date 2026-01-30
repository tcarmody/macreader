# Related Links Feature - Search API Research & Implementation Plan

## Executive Summary

This document outlines a comprehensive plan for adding related links to article summaries in DataPoints RSS reader. After evaluating 8+ search and AI research APIs, **Exa** is recommended for this use case based on requirements prioritizing quality for technical/research content at <1,000 articles/month volume.

**Key Decision Factors:**
- Priority: Quality over cost
- Volume: <1,000 articles/month
- Content Type: Technical/Research articles
- Focus: External web search only

**Recommendation:** Exa neural search API with piggyback integration during summarization flow.

---

## Table of Contents

1. [API Options Comparison](#api-options-comparison)
2. [Cost-Latency-Quality Tradeoffs](#cost-latency-quality-tradeoffs)
3. [Recommended Solution: Exa](#recommended-solution-exa)
4. [Implementation Architecture](#implementation-architecture)
5. [Integration Approach](#integration-approach)
6. [Database Design](#database-design)
7. [Frontend Design](#frontend-design)
8. [Cost Analysis](#cost-analysis)
9. [Alternative Approaches](#alternative-approaches)
10. [Future Enhancements](#future-enhancements)
11. [Testing & Verification](#testing--verification)

---

## API Options Comparison

### 1. Traditional Search APIs

#### Brave Search API
**Overview:** Independent search engine with 30B+ page index, official API with clear pricing.

| Metric | Value |
|--------|-------|
| **Cost** | $3-5 per 1,000 searches |
| **Free Tier** | 2,000 queries/month (1 QPS limit) |
| **Latency** | 1-2 seconds |
| **Quality** | High - comparable to Google/Bing |
| **Index Size** | 30+ billion pages |

**Pros:**
- Most viable official search API in 2026 (Bing retired August 2025, Google has no public API)
- Clear, predictable pricing model
- Generous free tier for testing/low volume
- Simple REST API integration
- Independent index (not scraped)

**Cons:**
- Traditional keyword-based search (not semantic)
- Requires careful query construction
- May miss conceptually related content that doesn't share keywords
- Limited to web content only

**Best For:** General news articles, budget-conscious implementations, keyword-focused search needs

---

#### Budget SERP APIs (Serper, Scrapingdog, DataForSEO)
**Overview:** Third-party services that scrape Google search results.

| API | Cost/1k | Latency | Quality |
|-----|---------|---------|---------|
| **Serper** | $0.30-1.00 | 2-3s | Medium |
| **Scrapingdog** | $0.29 | 1.8s | Medium |
| **DataForSEO** | $0.60 | 2-5s | Medium |

**Pros:**
- Cheapest option available
- Access to Google's search quality
- Easy integration

**Cons:**
- Legally gray area (scraping Google violates ToS)
- Variable reliability
- Risk of IP blocking
- Slower response times
- No official support or SLAs
- Could break without notice

**Best For:** High-volume price-sensitive applications, prototyping, non-critical features

---

### 2. AI-Powered Deep Research APIs

#### Exa (formerly Metaphor) ⭐ RECOMMENDED
**Overview:** Neural search API using embeddings for semantic understanding, designed specifically for AI applications.

| Metric | Value |
|--------|-------|
| **Cost** | $5 per 1,000 neural searches |
| **Free Tier** | $10 in credits (~2,000 searches) |
| **Latency** | 350ms-1.2s (sub-second fast endpoint available) |
| **Quality** | 94.9% SimpleQA benchmark (industry-leading) |
| **Index Type** | Neural embeddings + web crawl |

**Key Features:**
- Neural embeddings understand semantic meaning, not just keyword matches
- Fast response times (sub-second option available)
- Designed for LLM/AI integration workflows
- Rich result metadata (title, URL, snippet, published date)
- Category filtering (research papers, news, forums, etc.)
- Highlights feature shows relevant excerpts

**Pros:**
- Highest accuracy for research and technical queries
- Understands conceptual relationships between topics
- Faster than competitors (0.35s vs 1.6-2.9s)
- Built specifically for AI applications
- Good documentation and developer experience
- Finds semantically related content that keyword search would miss

**Cons:**
- More expensive than Brave ($5/1k vs $3/1k)
- Smaller index than traditional search engines
- Relatively new company (less established)
- Requires API key management

**Example Use Cases:**
- Finding related research papers for ML article
- Discovering similar technical blog posts
- Connecting concepts across different terminology
- Research-heavy content discovery

**Why Best for Technical Content:**
```
Query: "Transformer architecture in large language models"

Brave (keyword): Returns articles containing those exact words
Exa (semantic): Returns articles about:
  - Attention mechanisms
  - BERT and GPT architectures
  - Self-attention in neural networks
  - Positional encoding techniques
```

**Best For:** Technical/research articles, semantic search needs, AI/ML applications, content where quality matters more than cost

---

#### Tavily
**Overview:** AI search API optimized for feeding results into LLMs, includes content extraction and crawling.

| Metric | Value |
|--------|-------|
| **Cost** | $0.008 per credit (~$10 per 1,000 searches) |
| **Free Tier** | 1,000 credits/month |
| **Latency** | 1.6-2.9 seconds (avg 1.88s) |
| **Quality** | 93.3% SimpleQA accuracy |

**Key Features:**
- Extracts and processes full content (not just links)
- Returns cleaned text ready for LLM consumption
- Built-in relevance scoring
- Domain filtering
- News vs general search modes

**Pros:**
- Optimized for LLM workflows
- Includes content extraction (saves separate fetch step)
- Good balance of speed and quality
- Strong documentation

**Cons:**
- Higher cost than Exa ($10/1k vs $5/1k)
- Slower than Exa (1.88s vs 0.35-1.2s)
- Overkill if you only need links (not full content)
- Lower accuracy than Exa (93.3% vs 94.9%)

**Best For:** Applications that need full content extraction, LLM-powered research assistants, comprehensive content analysis

---

#### You.com Search API
**Overview:** Search engine integrated with OpenAI, fastest response times.

| Metric | Value |
|--------|-------|
| **Cost** | Contact sales (unclear pricing) |
| **Free Tier** | 1,000 API calls |
| **Latency** | <445ms (fastest in category) |
| **Quality** | High (OpenAI integration) |

**Pros:**
- Fastest latency by far (<0.5s)
- Integrated with OpenAI ecosystem
- Good for speed-critical applications

**Cons:**
- Unclear pricing (requires sales contact)
- Less established than competitors
- Fewer public case studies
- May require enterprise commitment

**Best For:** Speed-critical applications, existing OpenAI customers, low-latency requirements

---

### 3. LLM Native Solutions

#### Anthropic Web Search Tool
**Overview:** Built-in web search capability in Claude API, powered by Brave Search with Claude's reasoning.

| Metric | Value |
|--------|-------|
| **Cost** | $10 per 1,000 searches + standard token costs |
| **Latency** | 3-5 seconds (LLM inference + search) |
| **Quality** | High (Claude reasoning + Brave search) |
| **Requires** | Claude 3.7/3.5 Sonnet or 3.5 Haiku |

**Key Features:**
- Claude intelligently decides when to search
- Can make multiple searches per query
- Supports prompt caching (reduces token costs)
- Domain allow/block lists
- Location-aware results
- Integrates seamlessly with existing Claude workflows

**How It Works:**
```json
{
  "model": "claude-sonnet-4-5",
  "messages": [{
    "role": "user",
    "content": "Find articles related to: {title}"
  }],
  "tools": [{
    "type": "web_search_20250305",
    "name": "web_search",
    "max_uses": 5
  }]
}
```

**Pros:**
- Zero additional integration (already using Anthropic)
- Claude's reasoning improves query quality
- Prompt caching reduces costs
- Consistent tech stack
- Good for complex multi-step searches

**Cons:**
- Higher total cost ($10/1k + tokens vs $5/1k for Exa)
- Slower due to LLM inference overhead (3-5s vs <1s)
- Less control over search parameters
- Requires Claude 3.5+ models
- Uses Brave backend (not neural search)

**Best For:** Existing heavy Claude users, complex query construction needs, when LLM reasoning adds value

---

### 4. Internal Corpus Search

#### OpenAI Embeddings + Vector Search
**Overview:** Generate embeddings for your article database, find similar content via cosine similarity.

| Metric | Value |
|--------|-------|
| **Cost** | $0.13 per 1M tokens (<$0.01 per 1,000 articles) |
| **Latency** | <1 second (local database query) |
| **Quality** | Medium (depends on corpus size) |
| **Index** | Your own article database only |

**Model Options:**
- `text-embedding-3-small`: 62k tokens per request, $0.02/1M tokens
- `text-embedding-3-large`: 62k tokens per request, $0.13/1M tokens (higher quality)
- `text-embedding-ada-002`: Legacy model, $0.10/1M tokens

**How It Works:**
1. Generate embeddings for all articles in database (one-time setup)
2. Store embeddings in vector column or separate table
3. For new article, compute embedding
4. Find top-K similar articles via cosine similarity
5. Return related articles from your own corpus

**Implementation:**
```python
# One-time: Generate embeddings for existing articles
for article in articles:
    embedding = openai.embeddings.create(
        model="text-embedding-3-large",
        input=article.title + " " + article.summary_short
    )
    store_embedding(article.id, embedding.data[0].embedding)

# Real-time: Find similar articles
query_embedding = openai.embeddings.create(...)
similar = find_cosine_similarity(query_embedding, threshold=0.7)
```

**Pros:**
- Extremely cheap (<$0.01 per 1,000 articles)
- Very fast (local database query, no API calls)
- Privacy-friendly (no external calls after embedding generation)
- Great for "More from Your Library" or "Related Feeds"
- Works offline after initial embedding
- No rate limits

**Cons:**
- Only searches your own database (no external content discovery)
- Requires vector database infrastructure (pgvector, SQLite-vec, or separate vector DB)
- Cold start problem (needs article corpus to be useful)
- Quality depends on corpus size and diversity
- Requires re-embedding when article content changes
- Doesn't discover new external resources

**Use Cases:**
- "Related articles in your library"
- "More from this feed"
- "Similar bookmarked articles"
- Complement to external search (show both)

**Best For:** Complementary feature to external search, internal content discovery, privacy-focused implementations

---

## Cost-Latency-Quality Tradeoffs

### Comprehensive Comparison Matrix

| Solution | Cost/1k | Latency | Quality Score | Index Type | Integration | Best Use Case |
|----------|---------|---------|---------------|------------|-------------|---------------|
| **Exa** ⭐ | $5 | 0.35-1.2s | 94.9% | Neural | Medium | Research/Technical |
| **Brave Search** | $3-5 | 1-2s | High | Keyword | Low | General News |
| **Tavily** | $10 | 1.6-2.9s | 93.3% | Hybrid | Medium | LLM-Optimized |
| **You.com** | TBD | <0.5s | High | Hybrid | Low-Med | Speed-Critical |
| **Anthropic Web** | $10-20 | 3-5s | High | Keyword+LLM | Low | Claude Users |
| **Serper** | $0.30-1 | 2-5s | Medium | Scraped | Low | Budget/High-Volume |
| **OpenAI Embeddings** | <$0.01 | <1s | Medium | Semantic | High | Internal Only |

### Quality Score Methodology
- Based on SimpleQA benchmark (Exa: 94.9%, Tavily: 93.3%)
- Measures accuracy of search results for question-answering tasks
- Higher scores indicate better relevance and factual accuracy

---

### Tradeoff Analysis by Priority

#### If You Prioritize: QUALITY ⭐
**Winner:** Exa ($5/1k, 0.35-1.2s, 94.9% accuracy)

**Rationale:**
- Highest SimpleQA benchmark score (94.9%)
- Neural embeddings understand semantic relationships
- Best for technical/research content
- Fast enough for real-time use
- Worth the premium vs Brave ($2 more per 1k)

**Runner-up:** Tavily ($10/1k, 1.88s, 93.3% accuracy)
- Good for comprehensive content extraction
- Better if you need full article text, not just links

---

#### If You Prioritize: COST
**Winner:** Serper ($0.30-1/1k, 2-5s, Medium quality)

**Rationale:**
- 10x cheaper than premium options
- Access to Google's index
- Good enough for non-critical features

**Runner-up:** OpenAI Embeddings (<$0.01/1k, <1s)
- Cheapest option but internal-only
- Perfect for "Related in Library" complement

**Legitimate Alternative:** Brave ($3-5/1k, 1-2s, High quality)
- Best price/quality ratio for legitimate APIs
- Free tier covers low-volume testing

---

#### If You Prioritize: SPEED
**Winner:** OpenAI Embeddings (<1s, <$0.01/1k)

**Rationale:**
- Local database query (no API call)
- Sub-second response
- Nearly free

**External Winner:** You.com (<0.5s, TBD pricing)
- Fastest external API
- Good if internal search isn't sufficient

**Runner-up:** Exa (0.35s fast endpoint, $5/1k)
- Sub-second with fast endpoint
- Best quality/speed ratio

---

#### If You Prioritize: STACK CONSISTENCY
**Winner:** Anthropic Web Search ($10-20/1k, 3-5s)

**Rationale:**
- Already using Anthropic for summarization
- Single vendor for AI features
- Prompt caching integration
- Claude's reasoning improves queries

**Tradeoff:** 2x cost and slower vs Exa, but simpler tech stack

---

### Monthly Cost Projections

#### Low Volume: <1,000 articles/month

| API | Monthly Cost | Notes |
|-----|--------------|-------|
| Exa | **$5** | Or FREE with $10 credits initially |
| Brave | $3-5 | Or FREE with 2k free tier |
| Anthropic Web | $10-20 | Includes token costs |
| Serper | $0.30-1 | Cheapest option |
| OpenAI Embeddings | <$1 | One-time embedding cost |
| Tavily | $10 | Free tier covers 1k/month |

**Recommendation:** At low volume, cost differences are negligible ($5-10/month). **Choose based on quality**, not cost.

---

#### Medium Volume: 1,000-10,000 articles/month

| API | Monthly Cost | Notes |
|-----|--------------|-------|
| Exa | **$5-50** | Linear scaling |
| Brave | $3-50 | Best cost/quality |
| Anthropic Web | $10-200 | Token costs add up |
| Serper | $0.30-10 | Cheapest at scale |
| OpenAI Embeddings | <$10 | Still negligible |
| Tavily | $10-100 | Good middle ground |

**Recommendation:** At 5k+ articles/month, consider **Brave for cost efficiency** or **Exa for quality** depending on content type.

---

#### High Volume: 10,000+ articles/month

| API | Monthly Cost | Notes |
|-----|--------------|-------|
| Exa | **$50+** | Quality premium |
| Brave | $30-150 | Best cost/quality |
| Anthropic Web | $100-500+ | Gets expensive |
| Serper | $3-30 | Cheapest option |
| OpenAI Embeddings | <$20 | Still cheap |
| Tavily | $100-300 | Mid-tier cost |

**Recommendation:** Consider **hybrid approach**:
- Use Exa for technical articles (filter by `has_code_blocks`)
- Use Brave for general news
- Cost: ~$80-100/month vs $150+ for Exa-only

---

## Recommended Solution: Exa

### Why Exa for This Use Case

**Requirements Match:**
1. ✅ **Priority: Quality** → Exa has 94.9% SimpleQA (highest in category)
2. ✅ **Volume: <1,000/month** → $5/month is negligible, can use free credits
3. ✅ **Content: Technical/Research** → Neural embeddings excel at complex topics
4. ✅ **Focus: External search** → Exa's strength (vs internal corpus)

**Key Advantages:**
- **Semantic Understanding:** Finds conceptually related content, not just keyword matches
- **Speed:** Sub-second latency available (0.35s fast endpoint)
- **Quality:** Industry-leading accuracy for research queries
- **Developer Experience:** Built for AI apps, excellent docs, simple API
- **Cost-Effective at Scale:** $5/1k is reasonable for quality received

---

### How Exa Works

**Neural Search Process:**
1. User submits article for summarization
2. Query constructed: `f"{title} {key_points[0]} {key_points[1]}"`
3. Exa converts query to neural embedding (semantic representation)
4. Searches web index for similar embeddings (cosine similarity)
5. Ranks results by relevance score
6. Returns top 5 with titles, URLs, snippets, metadata

**vs Traditional Keyword Search:**
```
Article: "Attention Is All You Need - Transformer Architecture"

Traditional (Brave):
- Searches for pages containing "attention", "transformer", "architecture"
- Misses related concepts using different terminology
- Results: Papers explicitly mentioning transformers

Neural (Exa):
- Understands semantic meaning of transformer concepts
- Finds related work even with different terminology
- Results:
  ✓ Papers about attention mechanisms (core concept)
  ✓ BERT/GPT implementations (transformer applications)
  ✓ Self-attention in computer vision (related application)
  ✓ Positional encoding techniques (transformer components)
```

---

### Exa API Details

**Endpoint:** `https://api.exa.ai/search`

**Request:**
```python
import requests

response = requests.post(
    "https://api.exa.ai/search",
    headers={"x-api-key": EXA_API_KEY},
    json={
        "query": "transformer architecture in language models",
        "num_results": 5,
        "use_autoprompt": True,  # Let Exa optimize query
        "category": "research paper",  # Optional: research, news, forum, etc.
        "start_published_date": "2023-01-01",  # Optional: filter by date
    }
)
```

**Response:**
```json
{
  "results": [
    {
      "url": "https://arxiv.org/abs/2108.12409",
      "title": "Attention Mechanisms in Neural Networks: A Survey",
      "snippet": "This paper provides a comprehensive survey of attention mechanisms...",
      "published_date": "2023-08-15",
      "author": "Smith et al.",
      "score": 0.89
    },
    // ... 4 more results
  ],
  "autoprompt_string": "Here is a research paper about transformer architecture..."
}
```

**Key Parameters:**
- `use_autoprompt`: Let Exa optimize your query (recommended)
- `category`: Filter by content type (research, news, forum, company, etc.)
- `num_results`: How many results to return (default: 10)
- `start_published_date` / `end_published_date`: Date range filtering
- `exclude_domains`: Block specific domains
- `include_domains`: Whitelist specific domains

---

### Cost Breakdown

**Pricing Tiers:**
- Free: $10 in credits (~2,000 searches)
- Starter: $30/month (10k searches)
- Pro: $150/month (75k searches)
- Enterprise: Custom pricing

**Your Use Case (<1,000 articles/month):**
- Monthly cost: **$5**
- Or FREE for first 2,000 using credits
- Negligible cost relative to feature value

**Cost per article:**
- $5 / 1,000 = **$0.005 per article**
- Less than half a cent per related links fetch

---

## Implementation Architecture

### System Overview

```
User clicks "Summarize" button
         ↓
FastAPI endpoint: POST /articles/{id}/summarize
         ↓
Background task: summarize_article()
         ↓
    ┌────────────┴────────────┐
    ↓                         ↓
Generate Summary         Fetch Related Links
(Anthropic Claude)          (Exa API)
    ↓                         ↓
    └────────────┬────────────┘
         ↓
Store in database (single transaction)
  - summary_short
  - summary_full
  - key_points
  - related_links (JSON)
         ↓
Return to frontend
         ↓
Display in ArticleDetail component
  - Summary section
  - Related Links section
```

---

### Component Architecture

#### Backend Components

**1. Exa Service** (`backend/services/related_links.py`)
```python
class ExaSearchService:
    """Handles related links fetching via Exa API."""

    def __init__(self, api_key: str, cache: Cache):
        self.api_key = api_key
        self.cache = cache
        self.client = requests.Session()

    async def fetch_related_links(
        self,
        title: str,
        key_points: list[str] = None,
        summary: str = None,
        num_results: int = 5
    ) -> list[RelatedLink]:
        """
        Fetch related links for an article.

        Args:
            title: Article title
            key_points: List of key points from summary
            summary: Article summary (fallback if no key points)
            num_results: Number of links to return (default: 5)

        Returns:
            List of RelatedLink objects
        """
        # Build query from title + key points
        query = self._construct_query(title, key_points, summary)

        # Check cache first
        cache_key = f"related_links:{query}"
        cached = await self.cache.get(cache_key)
        if cached:
            return cached

        # Call Exa API
        response = await self._call_exa_api(query, num_results)

        # Parse and format results
        links = self._parse_results(response)

        # Cache results (24 hour TTL)
        await self.cache.set(cache_key, links, ttl=86400)

        return links

    def _construct_query(
        self,
        title: str,
        key_points: list[str] = None,
        summary: str = None
    ) -> str:
        """Build optimal query for technical content."""
        if key_points and len(key_points) >= 2:
            # Use title + top 2 key points for rich context
            return f"{title} {key_points[0]} {key_points[1]}"
        elif key_points:
            return f"{title} {key_points[0]}"
        elif summary:
            return f"{title} {summary[:200]}"  # Truncate summary
        else:
            return title

    async def _call_exa_api(self, query: str, num_results: int):
        """Call Exa search API."""
        response = await self.client.post(
            "https://api.exa.ai/search",
            headers={"x-api-key": self.api_key},
            json={
                "query": query,
                "num_results": num_results,
                "use_autoprompt": True,
                "category": "research paper",  # Optimize for technical content
            }
        )
        response.raise_for_status()
        return response.json()

    def _parse_results(self, response: dict) -> list[RelatedLink]:
        """Parse Exa response into RelatedLink objects."""
        results = []
        for item in response.get("results", []):
            results.append(RelatedLink(
                url=item["url"],
                title=item["title"],
                snippet=item.get("snippet", ""),
                domain=self._extract_domain(item["url"]),
                published_date=item.get("published_date"),
                score=item.get("score")
            ))
        return results

    def _extract_domain(self, url: str) -> str:
        """Extract domain from URL."""
        from urllib.parse import urlparse
        return urlparse(url).netloc
```

**2. Data Models** (`backend/schemas.py`)
```python
from pydantic import BaseModel

class RelatedLink(BaseModel):
    """A related article link."""
    url: str
    title: str
    snippet: str = ""
    domain: str = ""
    published_date: str = None
    score: float = None

class ArticleDetailResponse(BaseModel):
    """Extended response with related links."""
    # ... existing fields ...
    summary_short: str = None
    summary_full: str = None
    key_points: list[str] = None

    # NEW: Related links
    related_links: list[RelatedLink] = None
```

**3. Task Integration** (`backend/tasks.py`)
```python
async def summarize_article(
    article_id: int,
    content: str,
    url: str,
    title: str,
    state: AppState
):
    """Generate summary and fetch related links in parallel."""

    # Generate summary (existing code)
    summary = await state.summarizer.summarize_async(content, url, title)

    # NEW: Fetch related links in parallel
    related_links = None
    if state.exa_service and state.config.ENABLE_RELATED_LINKS:
        try:
            related_links = await state.exa_service.fetch_related_links(
                title=title,
                key_points=summary.key_points,
                summary=summary.one_liner
            )
        except Exception as e:
            # Don't fail summarization if related links fail
            logger.error(f"Failed to fetch related links: {e}")
            related_links = None

    # Store both in single transaction
    await state.db.update_article_summary(
        article_id=article_id,
        summary=summary,
        related_links=related_links
    )
```

**4. Database Repository** (`backend/database/article_repository.py`)
```python
def update_article_summary(
    self,
    article_id: int,
    summary: Summary,
    related_links: list[RelatedLink] = None
):
    """Update article with summary and related links."""

    # Serialize related links to JSON
    links_json = None
    if related_links:
        links_json = json.dumps({
            "links": [link.dict() for link in related_links],
            "fetched_at": datetime.now().isoformat(),
            "source": "exa"
        })

    self.cursor.execute("""
        UPDATE articles
        SET summary_short = ?,
            summary_full = ?,
            key_points = ?,
            model_used = ?,
            summarized_at = ?,
            related_links = ?
        WHERE id = ?
    """, (
        summary.one_liner,
        summary.full_summary,
        json.dumps(summary.key_points),
        summary.model_used,
        datetime.now().isoformat(),
        links_json,
        article_id
    ))
    self.conn.commit()
```

---

#### Frontend Components

**ArticleDetail Component** (`web/src/components/ArticleDetail.tsx`)

**Insert after summary section (line 268):**

```tsx
{/* Related Links Section */}
{article.related_links && article.related_links.length > 0 && (
  <section className="mb-8 p-4 bg-blue-500/5 border border-blue-500/20 rounded-lg">
    <div className="flex items-center gap-2 mb-4">
      <Link2 className="h-4 w-4 text-blue-500" />
      <h3 className="font-semibold text-blue-700 dark:text-blue-300">
        Related Articles
      </h3>
    </div>

    <div className="space-y-3">
      {article.related_links.map((link, index) => (
        <a
          key={index}
          href={link.url}
          target="_blank"
          rel="noopener noreferrer"
          className="block p-3 rounded hover:bg-blue-500/10 transition-colors group"
        >
          <div className="flex items-start justify-between gap-3">
            <div className="flex-1 min-w-0">
              {/* Title */}
              <h4 className="font-medium text-sm mb-1 line-clamp-2 group-hover:text-blue-600 dark:group-hover:text-blue-400 transition-colors">
                {link.title}
              </h4>

              {/* Snippet */}
              {link.snippet && (
                <p className="text-xs text-muted-foreground mb-2 line-clamp-2">
                  {link.snippet}
                </p>
              )}

              {/* Domain + Date */}
              <div className="flex items-center gap-2 text-xs">
                <span className="text-blue-500 font-medium">
                  {link.domain}
                </span>
                {link.published_date && (
                  <>
                    <span className="text-muted-foreground">•</span>
                    <span className="text-muted-foreground">
                      {new Date(link.published_date).toLocaleDateString()}
                    </span>
                  </>
                )}
              </div>
            </div>

            {/* External link icon */}
            <ExternalLink className="h-3.5 w-3.5 text-muted-foreground flex-shrink-0 mt-0.5 group-hover:text-blue-500 transition-colors" />
          </div>
        </a>
      ))}
    </div>

    {/* Powered by badge */}
    <div className="mt-3 pt-3 border-t border-blue-500/10">
      <p className="text-xs text-muted-foreground text-center">
        Powered by Exa neural search
      </p>
    </div>
  </section>
)}
```

**TypeScript Types** (`web/src/types/index.ts`)
```typescript
export interface RelatedLink {
  url: string;
  title: string;
  snippet?: string;
  domain?: string;
  published_date?: string;
  score?: number;
}

export interface Article {
  // ... existing fields ...
  summary_short?: string;
  summary_full?: string;
  key_points?: string[];

  // NEW
  related_links?: RelatedLink[];
}
```

---

## Integration Approach

### Option 1: Piggyback on Summarization ⭐ RECOMMENDED

**When:** Fetch related links during existing summarization task
**Perceived Latency:** Zero (user already waiting for summary)
**Implementation:** Modify `summarize_article()` task

**Pros:**
- No additional perceived latency
- Single database write transaction
- Efficient batch operation
- Users expect to wait for AI processing
- Related links available immediately after summary

**Cons:**
- Couples two features (summary + links)
- Can't fetch links without summary
- If Exa fails, still succeeds with summary

**Flow:**
```
User clicks "Summarize" button
  ↓
FastAPI returns {"success": true, "message": "Summarization started"}
  ↓
Background task runs:
  1. Fetch article content (if needed)
  2. Generate summary via Claude (3-5s)
  3. Fetch related links via Exa (0.5-1s) ← In parallel
  4. Store both in database
  ↓
Frontend polls or receives SSE update
  ↓
Display summary + related links together
```

**Why This is Best:**
- Summary generation takes 3-5 seconds
- Adding 0.5-1s for Exa is negligible (still 3-6s total)
- User already committed to waiting for AI
- No additional UI complexity
- Clean single-transaction update

---

### Option 2: On-Demand (Separate Button)

**When:** User clicks "Find Related" button
**Perceived Latency:** 0.5-1 second visible wait
**Implementation:** New endpoint `/articles/{id}/related`

**Pros:**
- Decoupled from summarization
- User controls when to fetch
- Can work without summary existing
- Optional feature (doesn't affect all users)

**Cons:**
- Additional UI button needed
- Visible wait time for user
- Extra user action required
- More API calls (not batched with summary)

**Flow:**
```
User clicks "Find Related" button
  ↓
Show loading spinner
  ↓
POST /articles/{id}/related
  ↓
Fetch from Exa (0.5-1s)
  ↓
Store in database
  ↓
Return and display links
```

**When to Use:**
- If you want links without requiring summary
- If you want to give users control over the feature
- If you plan to charge for this feature separately

---

### Option 3: Background Job (Async)

**When:** Async task after summarization completes
**Perceived Latency:** Links appear 30s-5min later
**Implementation:** Job queue (Celery, RQ, etc.)

**Pros:**
- No blocking at all
- Can retry failures
- Bulk processing optimization
- Handles rate limits gracefully

**Cons:**
- Links not immediately available
- More complex architecture
- Requires job queue infrastructure
- User may leave page before links appear

**Flow:**
```
Summary completes
  ↓
Queue background job
  ↓
Job picks up task (30s-5min later)
  ↓
Fetch related links
  ↓
Store in database
  ↓
User sees links on next page load
```

**When to Use:**
- High volume (10k+ articles/month)
- Strict latency requirements for summary
- Already have job queue infrastructure
- Don't need immediate link availability

---

### Recommendation: Option 1 (Piggyback)

**For this use case, Option 1 is clearly best:**
- Low volume (<1k/month) → No need for complex job queue
- Quality priority → Want links immediately to enhance experience
- Technical content → Users will read carefully, not bounce quickly
- Fast API (0.5-1s) → Negligible addition to 3-5s summary generation

**Implementation is straightforward:**
1. Modify existing `summarize_article()` function
2. Add parallel async call to Exa
3. Store in same database transaction
4. No frontend changes to summary flow
5. Just add display component for links

---

## Database Design

### Option 1: JSON Column ⭐ RECOMMENDED

**Schema:**
```sql
ALTER TABLE articles ADD COLUMN related_links TEXT;
```

**Data Format:**
```json
{
  "links": [
    {
      "url": "https://arxiv.org/abs/2103.14030",
      "title": "The Transformer Family: A Survey",
      "snippet": "We present a comprehensive survey of Transformer architectures...",
      "domain": "arxiv.org",
      "published_date": "2023-08-15",
      "score": 0.89
    },
    {
      "url": "https://jalammar.github.io/illustrated-transformer/",
      "title": "The Illustrated Transformer",
      "snippet": "A visual explanation of the Transformer architecture...",
      "domain": "jalammar.github.io",
      "published_date": "2018-06-27",
      "score": 0.85
    }
  ],
  "query": "transformer architecture attention mechanisms",
  "source": "exa",
  "fetched_at": "2026-01-29T14:30:00Z",
  "num_results": 5
}
```

**Pros:**
- Simplest implementation (follows existing pattern)
- `key_points` already uses JSON format
- No schema migration complexity
- Fast to implement (1-2 hours)
- Good enough for MVP
- Easy to version (add new fields to JSON)

**Cons:**
- Not first-class database support
- Harder to query (can't easily find all articles linking to X)
- No relational integrity
- JSON parsing overhead (minimal)

**When to Use:** MVP, simple use cases, low query complexity

---

### Option 2: Separate Table (Normalized)

**Schema:**
```sql
CREATE TABLE article_related_links (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    article_id INTEGER NOT NULL,
    url TEXT NOT NULL,
    title TEXT NOT NULL,
    snippet TEXT,
    domain TEXT,
    published_date TEXT,
    score REAL,
    position INTEGER,  -- Display order (1-5)
    source TEXT DEFAULT 'exa',
    created_at TEXT DEFAULT (datetime('now')),
    FOREIGN KEY (article_id) REFERENCES articles(id) ON DELETE CASCADE,
    UNIQUE(article_id, url)  -- Prevent duplicates
);

CREATE INDEX idx_article_related_links_article_id
ON article_related_links(article_id);

CREATE INDEX idx_article_related_links_url
ON article_related_links(url);
```

**Query Example:**
```sql
-- Get all links for an article
SELECT * FROM article_related_links
WHERE article_id = 123
ORDER BY position;

-- Find all articles that link to a URL
SELECT DISTINCT article_id FROM article_related_links
WHERE url = 'https://arxiv.org/abs/2103.14030';

-- Most commonly linked domains
SELECT domain, COUNT(*) as count
FROM article_related_links
GROUP BY domain
ORDER BY count DESC
LIMIT 10;
```

**Pros:**
- First-class database support
- Queryable and indexable
- Better for analytics
- Relational integrity
- Scalable for large datasets
- Can track click-through rates per link

**Cons:**
- More complex schema
- Requires joins to fetch
- Slower writes (5 INSERTs vs 1 UPDATE)
- More complex migration

**When to Use:**
- Phase 2 (if analytics needed)
- High volume (10k+ articles/month)
- Want to track link popularity
- Need to query relationships

---

### Recommendation: JSON Column (Option 1)

**For MVP:**
- Matches existing pattern (`key_points` is JSON)
- Fast to implement
- Good enough for <10k articles
- Can migrate to separate table later if needed

**Migration Path:**
```sql
-- Phase 1: JSON column (MVP)
ALTER TABLE articles ADD COLUMN related_links TEXT;

-- Phase 2: Migrate to table (if needed)
CREATE TABLE article_related_links AS
SELECT
    article_id,
    json_extract(value, '$.url') as url,
    json_extract(value, '$.title') as title,
    json_extract(value, '$.snippet') as snippet,
    json_extract(value, '$.domain') as domain
FROM articles,
     json_each(articles.related_links, '$.links');
```

---

## Frontend Design

### UI Placement

**Location:** Between summary section and main content in `ArticleDetail.tsx`

**Rationale:**
- Summary provides context for what links are related to
- Links act as supplementary material before diving into full article
- Natural reading flow: Summary → Related → Full Content

**Visual Hierarchy:**
```
┌─────────────────────────────────────┐
│ Article Title                       │
│ Feed • Author • Date                │
├─────────────────────────────────────┤
│ [Fetch Content] [Summarize] Buttons │
├─────────────────────────────────────┤
│ AI SUMMARY SECTION                  │
│ • Full summary text                 │
│ • Key points (bullets)              │
│ • Model used badge                  │
├─────────────────────────────────────┤
│ RELATED ARTICLES SECTION ← NEW      │
│ • Link 1                            │
│ • Link 2                            │
│ • Link 3                            │
│ • Link 4                            │
│ • Link 5                            │
├─────────────────────────────────────┤
│ MAIN ARTICLE CONTENT                │
│ • Full HTML content                 │
└─────────────────────────────────────┘
```

---

### Design Mockup

**Section Header:**
```
┌─────────────────────────────────────┐
│ 🔗 Related Articles                 │
└─────────────────────────────────────┘
```

**Individual Link Card:**
```
┌─────────────────────────────────────┐
│ The Transformer Family: A Survey ↗  │
│ ─────────────────────────────────   │
│ We present a comprehensive survey   │
│ of Transformer architectures...     │
│ ─────────────────────────────────   │
│ arxiv.org • Aug 15, 2023            │
└─────────────────────────────────────┘
```

**Hover State:**
```
┌─────────────────────────────────────┐
│ 🔗 The Transformer Family: A Survey │ ← Blue underline
│ ─────────────────────────────────   │
│ We present a comprehensive survey   │
│ of Transformer architectures...     │
│ ─────────────────────────────────   │
│ arxiv.org • Aug 15, 2023            │
└─────────────────────────────────────┘
    ← Blue background tint
```

---

### Styling Guidelines

**Color Scheme:**
- Primary: Blue (`text-blue-500`, `border-blue-500/20`)
- Background: `bg-blue-500/5` (subtle blue tint)
- Hover: `hover:bg-blue-500/10` (slightly darker)
- Text: `text-blue-700` (dark mode: `text-blue-300`)

**Typography:**
- Title: `font-medium text-sm` (readable but not overpowering)
- Snippet: `text-xs text-muted-foreground` (supporting detail)
- Domain: `text-xs text-blue-500 font-medium` (clear source indicator)

**Spacing:**
- Section padding: `p-4`
- Between links: `space-y-3`
- Link internal padding: `p-3`

**Accessibility:**
- All links open in new tab (`target="_blank"`)
- Security: `rel="noopener noreferrer"`
- Keyboard navigation: Focusable links with visible focus states
- Screen readers: Descriptive link text, external link indicator

---

### Responsive Design

**Desktop (≥768px):**
- Single column list layout
- Full snippets visible (2 lines)
- Hover effects

**Mobile (<768px):**
- Same single column (stacks naturally)
- Slightly reduced padding (`p-2` instead of `p-3`)
- Tap targets ≥44px for accessibility
- Truncated snippets (1-2 lines)

---

### Empty State

**If no related links found:**
```tsx
{article.related_links && article.related_links.length === 0 && (
  <section className="mb-8 p-4 bg-muted/50 border border-muted rounded-lg">
    <div className="flex items-center gap-2 text-muted-foreground">
      <Link2 className="h-4 w-4" />
      <span className="text-sm">No related articles found</span>
    </div>
  </section>
)}
```

**If related links not fetched yet:**
- Don't show section at all (only show when `related_links` exists)

---

### Loading State

**During summarization (when links are being fetched):**
```tsx
{isSummarizing && (
  <section className="mb-8 p-4 bg-blue-500/5 border border-blue-500/20 rounded-lg">
    <div className="flex items-center gap-2 mb-4">
      <Link2 className="h-4 w-4 text-blue-500 animate-pulse" />
      <span className="font-semibold text-blue-700 dark:text-blue-300">
        Finding related articles...
      </span>
    </div>
    <div className="space-y-3">
      {[1, 2, 3, 4, 5].map(i => (
        <div key={i} className="p-3 rounded animate-pulse">
          <div className="h-4 bg-muted rounded w-3/4 mb-2"></div>
          <div className="h-3 bg-muted rounded w-full mb-1"></div>
          <div className="h-3 bg-muted rounded w-5/6"></div>
        </div>
      ))}
    </div>
  </section>
)}
```

---

## Cost Analysis

### Monthly Costs by Volume

| Volume | Exa Cost | Brave Alternative | Anthropic Alternative | Serper Budget |
|--------|----------|-------------------|----------------------|---------------|
| 100 | $0.50 | $0.30-0.50 | $1-2 | $0.03-0.10 |
| 500 | $2.50 | $1.50-2.50 | $5-10 | $0.15-0.50 |
| 1,000 | **$5** | $3-5 | $10-20 | $0.30-1 |
| 5,000 | $25 | $15-25 | $50-100 | $1.50-5 |
| 10,000 | $50 | $30-50 | $100-200 | $3-10 |

### Cost per User Interaction

**Assumptions:**
- Average session: User reads 5 articles
- Summary rate: 80% of articles get summarized
- Click-through rate: 15% of users click related links

**Cost Breakdown:**
```
Articles viewed: 5
Articles summarized: 4 (80% of 5)
Related links fetched: 4

Cost:
- Exa: 4 × $0.005 = $0.02 per session
- Summary (Claude): 4 × $0.015 = $0.06 per session
- Total AI cost per session: $0.08

Revenue from engagement:
- Increased session time: +2 minutes avg
- Increased page views: +1.5 pages per session
- Increased return rate: +8% (users find more relevant content)
```

**ROI:**
- Cost: $0.02 per session for related links
- Value: Better content discovery, increased engagement, improved retention
- **Positive ROI** if user engagement value > $0.02/session

---

### Annual Cost Projection

**Scenario: 1,000 articles/month average**

| Service | Monthly | Annual | Notes |
|---------|---------|--------|-------|
| **Exa** | $5 | **$60** | Recommended choice |
| Brave | $3-5 | $36-60 | Alternative if cost-sensitive |
| Anthropic Web | $10-20 | $120-240 | If already heavy Claude user |
| Serper | $0.30-1 | $3.60-12 | Budget option (legally gray) |

**Total AI Stack (with Exa):**
- Summarization (Claude): ~$50-100/month
- Related Links (Exa): ~$5/month
- **Total: $55-105/month** or **$660-1,260/year**

---

### Cost Optimization Strategies

**1. Smart Caching**
```python
# Cache popular queries for 24 hours
cache_key = f"related_links:{normalized_query}"
ttl = 86400  # 24 hours

# Saves repeated searches for trending topics
# Example: 100 articles about "GPT-5 release" → 1 API call instead of 100
```

**2. Conditional Fetching**
```python
# Only fetch for articles with summaries
if article.summary_full:
    related_links = await exa.fetch_related_links(...)

# Or only for bookmarked articles
if article.is_bookmarked:
    related_links = await exa.fetch_related_links(...)
```

**3. Batch Processing**
```python
# If using background jobs, batch process during off-peak
# Process 100 articles at once with rate limiting
# Spreads cost over longer time period
```

**4. Hybrid Approach (Phase 2)**
```python
# Use expensive Exa only for technical articles
if article.has_code_blocks or article.word_count > 2000:
    related_links = await exa.fetch_related_links(...)
else:
    # Use cheaper Brave for general news
    related_links = await brave.search(...)

# Estimated savings: 40-60% (if 60% of articles are non-technical)
```

---

## Alternative Approaches

### Alternative 1: Hybrid Search Strategy

**Concept:** Use different APIs based on article type

**Implementation:**
```python
async def fetch_related_links(article: Article):
    """Smart routing based on article characteristics."""

    if article.has_code_blocks or article.word_count > 2000:
        # Technical/Research → Use Exa (quality)
        return await exa_service.search(article)

    elif article.published_at > (datetime.now() - timedelta(days=7)):
        # Recent news → Use Brave (freshness)
        return await brave_service.search(article)

    else:
        # General content → Use Brave (cost)
        return await brave_service.search(article)
```

**Cost Analysis:**
- 40% technical articles → Exa ($5/1k)
- 60% general articles → Brave ($3/1k)
- Blended cost: (0.4 × $5) + (0.6 × $3) = **$3.80/1k**
- Savings: 24% vs Exa-only, with 40% getting premium quality

**Pros:**
- Best of both worlds (quality where it matters, cost savings elsewhere)
- Optimizes for content type
- Flexible and extensible

**Cons:**
- More complex implementation
- Two API integrations to maintain
- More potential failure points
- Harder to predict costs

---

### Alternative 2: Internal Corpus + External Search

**Concept:** Show both internal related articles and external links

**Implementation:**
```python
async def fetch_all_related(article: Article):
    """Get both internal and external related content."""

    # Internal: Fast, cheap, private
    internal = await embeddings_service.find_similar(
        article.id,
        limit=3
    )

    # External: Slower, more expensive, broader
    external = await exa_service.search(
        article.title,
        limit=5
    )

    return {
        "internal": internal,  # "Related in Your Library"
        "external": external   # "Related Articles"
    }
```

**UI Layout:**
```
┌─────────────────────────────────────┐
│ 📚 Related in Your Library (3)      │
│ • Article from your bookmarks       │
│ • Article from same feed            │
│ • Article you read last week        │
├─────────────────────────────────────┤
│ 🌐 Related Articles (5)             │
│ • External article 1                │
│ • External article 2                │
│ • External article 3                │
│ • External article 4                │
│ • External article 5                │
└─────────────────────────────────────┘
```

**Cost Analysis:**
- Internal: <$0.01/1k (negligible)
- External (Exa): $5/1k
- Total: ~$5/1k (same as Exa-only)

**Pros:**
- Richer user experience (two types of recommendations)
- Internal links keep users in your app longer
- Leverages existing article corpus
- Privacy-friendly internal search
- No additional cost (embeddings are cheap)

**Cons:**
- More complex UI
- More API calls (internal + external)
- Internal links only work after building corpus
- Requires vector database setup

---

### Alternative 3: LLM-Generated Links

**Concept:** Have Claude suggest related links during summarization

**Implementation:**
```python
system_prompt = """
After generating the summary, suggest 5 related articles
or resources the reader should explore. Provide specific URLs
or search queries for each recommendation.
"""

# Claude generates suggestions like:
# - Search for "transformer architecture explained"
# - Read the original paper at arxiv.org/abs/1706.03762
# - Explore the Hugging Face transformers documentation
```

**Then execute search queries:**
```python
suggestions = parse_claude_suggestions(response)
links = []
for suggestion in suggestions:
    if suggestion.type == "search":
        # Execute search via Brave/Exa
        results = await search_api.search(suggestion.query, limit=1)
        links.extend(results)
    elif suggestion.type == "url":
        # Validate and add direct URL
        links.append(suggestion.url)
```

**Cost Analysis:**
- Claude suggestions: +500 tokens output (~$0.003)
- Search execution: 3 queries × $0.005 = $0.015
- Total: ~$0.018 per article (vs $0.005 for direct Exa)
- **3.6x more expensive**

**Pros:**
- Claude's reasoning improves suggestion quality
- Can suggest non-web resources (books, courses, docs)
- More contextual recommendations
- Works with existing summarization flow

**Cons:**
- Much more expensive (3-4x cost)
- Slower (extra LLM inference)
- Search queries may not match exact URLs
- Requires parsing Claude's freeform suggestions
- Less reliable (depends on Claude's knowledge)

---

### Alternative 4: Citation Extraction

**Concept:** Extract citations and references from article content

**Implementation:**
```python
def extract_citations(content: str):
    """Extract URLs and references from article HTML."""

    soup = BeautifulSoup(content, 'html.parser')

    # Find all links in content
    links = []
    for a in soup.find_all('a', href=True):
        url = a['href']
        text = a.get_text()

        # Filter for meaningful citations
        if is_relevant_citation(url, text):
            links.append({
                "url": url,
                "title": text or "Referenced Article",
                "snippet": get_surrounding_context(a)
            })

    return links[:5]  # Top 5 citations
```

**Cost Analysis:**
- Zero API calls (local parsing)
- Compute: negligible
- **Free**

**Pros:**
- Completely free
- Instant (no API latency)
- Shows actual article citations
- Privacy-friendly (no external calls)
- Always relevant (author chose these links)

**Cons:**
- Only works if article has citations
- Many articles don't link externally
- Quality varies by article
- Misses related content not cited
- Doesn't discover new connections

**Use Case:** Complement to external search (show "Article Citations" + "Related Articles")

---

## Future Enhancements

### Phase 2: Enhanced Features

**1. Internal Corpus Search (OpenAI Embeddings)**
- Add "Related in Your Library" section
- Show similar bookmarked articles
- Cost: <$1/month
- Timeline: 2-3 days

**2. Smart Routing (Hybrid API)**
- Use Exa for technical articles
- Use Brave for general news
- Cost savings: 20-40%
- Timeline: 1 day

**3. User Feedback**
- "Was this helpful?" thumbs up/down
- Track click-through rates
- Learn which topics need better suggestions
- Timeline: 1 day

**4. Caching Optimization**
- Cache popular queries (24hr TTL)
- Deduplicate similar searches
- Cost savings: 10-30% depending on overlap
- Timeline: 2-4 hours

---

### Phase 3: Advanced Intelligence

**1. Personalized Recommendations**
- Learn from user's reading history
- Boost domains/topics user prefers
- Weight by user's expertise level
- Requires user profiling system

**2. Topic Clustering**
- Group related articles into topics
- Show "More in this topic" clusters
- Leverage existing `topic_history` table
- Integration with existing clustering feature

**3. Temporal Awareness**
- Prioritize recent articles for news
- Show historical context for older articles
- "Original paper" vs "Recent developments" sections

**4. Multi-Language Support**
- Detect article language
- Find related content in same language
- Or translate queries for broader results

**5. Citation Graph**
- Track which articles link to each other
- Build citation network
- Show "Most cited in your library"
- Requires separate `article_related_links` table

---

### Phase 4: Analytics

**1. Link Performance Tracking**
```sql
-- Track clicks on related links
CREATE TABLE related_link_clicks (
    id INTEGER PRIMARY KEY,
    article_id INTEGER,
    related_url TEXT,
    clicked_at TEXT,
    user_id INTEGER
);

-- Analytics queries
SELECT related_url, COUNT(*) as clicks
FROM related_link_clicks
GROUP BY related_url
ORDER BY clicks DESC;
```

**2. Quality Metrics**
- Click-through rate per link
- Time spent on related articles
- Bookmark rate for suggested articles
- A/B test different query strategies

**3. Cost Monitoring**
- Track API usage per day/week/month
- Alert if approaching budget limits
- Visualize cost trends
- ROI calculation (engagement vs cost)

---

## Testing & Verification

### Functional Testing

**1. Happy Path**
```python
# Test: Summarize article → verify related links
async def test_summarize_with_related_links():
    # Create test article
    article_id = create_test_article(
        title="Attention Is All You Need",
        content="<p>Transformer architecture...</p>"
    )

    # Trigger summarization
    response = await client.post(f"/articles/{article_id}/summarize")
    assert response.status_code == 200

    # Wait for background task
    await wait_for_summary(article_id)

    # Verify related links stored
    article = await db.get_article(article_id)
    assert article.related_links is not None
    assert len(article.related_links) == 5

    # Verify link structure
    link = article.related_links[0]
    assert link.url.startswith("http")
    assert len(link.title) > 0
    assert len(link.snippet) > 0
    assert len(link.domain) > 0
```

**2. Edge Cases**
```python
# Test: Article with no key points
async def test_fallback_query_construction():
    article_id = create_test_article(
        title="Test Article",
        content="<p>Short content</p>",
        has_summary=False
    )

    # Should use title-only query
    related_links = await exa_service.fetch_related_links(
        title="Test Article",
        key_points=None
    )
    assert len(related_links) > 0

# Test: Exa API timeout
async def test_graceful_failure():
    with mock_exa_timeout():
        article_id = create_test_article()
        await summarize_article(article_id)

        article = await db.get_article(article_id)
        assert article.summary_full is not None  # Summary still works
        assert article.related_links is None  # Links gracefully failed

# Test: No results found
async def test_empty_results():
    related_links = await exa_service.fetch_related_links(
        title="asdfghjklzxcvbnmqwerty12345",  # Gibberish
        key_points=[]
    )
    assert len(related_links) == 0
```

**3. Frontend Display**
```typescript
// Test: Links render correctly
test('renders related links section', () => {
  const article = {
    ...mockArticle,
    related_links: [
      {
        url: 'https://example.com',
        title: 'Test Article',
        snippet: 'Test snippet',
        domain: 'example.com'
      }
    ]
  };

  render(<ArticleDetail article={article} />);

  expect(screen.getByText('Related Articles')).toBeInTheDocument();
  expect(screen.getByText('Test Article')).toBeInTheDocument();
  expect(screen.getByText('example.com')).toBeInTheDocument();
});

// Test: Links open in new tab
test('related links have correct attributes', () => {
  const { container } = render(<ArticleDetail article={mockArticle} />);
  const link = container.querySelector('a[href="https://example.com"]');

  expect(link).toHaveAttribute('target', '_blank');
  expect(link).toHaveAttribute('rel', 'noopener noreferrer');
});
```

---

### Quality Testing

**1. Relevance Assessment**
```python
# Manual test cases for research articles
test_cases = [
    {
        "title": "Attention Is All You Need",
        "key_points": ["Transformer architecture", "Self-attention mechanisms"],
        "expected_domains": ["arxiv.org", "distill.pub", "jalammar.github.io"],
        "expected_topics": ["transformers", "attention", "NLP", "BERT", "GPT"]
    },
    {
        "title": "AlphaFold: Protein Structure Prediction",
        "key_points": ["Protein folding", "Deep learning for biology"],
        "expected_domains": ["nature.com", "deepmind.com", "biorxiv.org"],
        "expected_topics": ["protein", "folding", "biology", "structure"]
    }
]

for case in test_cases:
    links = await exa_service.fetch_related_links(
        title=case["title"],
        key_points=case["key_points"]
    )

    # Check domain diversity
    domains = [link.domain for link in links]
    assert any(expected in domains for expected in case["expected_domains"])

    # Check topic relevance
    all_text = " ".join([link.title + " " + link.snippet for link in links])
    assert any(topic in all_text.lower() for topic in case["expected_topics"])
```

**2. Compare to Manual Search**
```python
# For 10 test articles, compare Exa results to Google search
# Measure:
# - Overlap in top 5 results (should be >30%)
# - Unique value-added links from Exa (semantic connections)
# - False positives (irrelevant links)

for article in test_articles:
    exa_links = await exa_service.fetch_related_links(article)
    google_links = manual_google_search(article.title)

    overlap = calculate_overlap(exa_links, google_links)
    unique = [link for link in exa_links if link not in google_links]

    print(f"Article: {article.title}")
    print(f"Overlap: {overlap}%")
    print(f"Unique Exa links: {len(unique)}")

    # Review unique links manually for value assessment
```

---

### Performance Testing

**1. Latency**
```python
# Measure end-to-end summarization + links time
import time

async def test_total_latency():
    start = time.time()

    # Trigger summarization (includes links)
    await client.post(f"/articles/{article_id}/summarize")
    await wait_for_completion(article_id)

    end = time.time()
    total_time = end - start

    # Should complete in 5-8 seconds
    assert total_time < 10, f"Too slow: {total_time}s"
    print(f"Total time: {total_time:.2f}s")

# Breakdown:
# - Summary generation: 3-5s (Claude)
# - Related links: 0.5-1s (Exa)
# - Database writes: <0.1s
# - Total: 4-6.5s (acceptable)
```

**2. Caching**
```python
# Test cache hit rate
async def test_caching():
    title = "Popular Article About AI"

    # First call: Cache miss
    start = time.time()
    links1 = await exa_service.fetch_related_links(title)
    time1 = time.time() - start

    # Second call: Cache hit
    start = time.time()
    links2 = await exa_service.fetch_related_links(title)
    time2 = time.time() - start

    # Cache hit should be much faster
    assert time2 < time1 * 0.1, "Cache not working"
    assert links1 == links2, "Cache returned different results"
```

**3. Rate Limiting**
```python
# Test handling of rate limits
async def test_rate_limit_handling():
    # Trigger 100 summarizations rapidly
    tasks = [
        summarize_article(article_id)
        for article_id in range(1, 101)
    ]

    results = await asyncio.gather(*tasks, return_exceptions=True)

    # Should gracefully handle rate limits
    # Some might fail, but shouldn't crash
    successes = [r for r in results if not isinstance(r, Exception)]
    assert len(successes) > 50, "Too many failures"
```

---

### Cost Tracking

**1. Monitor API Usage**
```python
# Track API calls in application
class ExaServiceWithTracking(ExaService):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.call_count = 0
        self.total_cost = 0.0

    async def fetch_related_links(self, *args, **kwargs):
        result = await super().fetch_related_links(*args, **kwargs)
        self.call_count += 1
        self.total_cost += 0.005  # $5 per 1,000 = $0.005 per call
        return result

    def get_stats(self):
        return {
            "calls": self.call_count,
            "cost": f"${self.total_cost:.2f}",
            "avg_per_day": self.call_count / 30
        }
```

**2. Cost Alerts**
```python
# Set up billing alerts
async def check_monthly_budget():
    stats = exa_service.get_stats()
    monthly_cost = stats["total_cost"]

    if monthly_cost > 10:  # $10 threshold
        send_alert(f"Exa costs: ${monthly_cost:.2f}/month")
```

**3. ROI Calculation**
```python
# Track engagement metrics
engagement_before = {
    "avg_session_time": 3.5,  # minutes
    "pages_per_session": 2.8,
    "return_rate": 0.42
}

engagement_after = {
    "avg_session_time": 5.2,  # +48%
    "pages_per_session": 4.1,  # +46%
    "return_rate": 0.51  # +21%
}

cost_per_month = 5  # $5 for Exa
value_per_engaged_user = 0.50  # Estimated

roi = ((value_per_engaged_user * num_users) - cost_per_month) / cost_per_month
print(f"ROI: {roi*100:.1f}%")
```

---

### Acceptance Criteria

**MVP is ready when:**

✅ **Functionality**
- [ ] Summarization triggers related links fetch
- [ ] Links stored in database `related_links` column
- [ ] Frontend displays related links section
- [ ] Links open in new tab
- [ ] Handles edge cases (no results, timeouts, no key points)

✅ **Quality**
- [ ] >80% relevance rate (manual review of 20 test cases)
- [ ] Links are semantically related, not just keyword matches
- [ ] Diverse sources (not all from same domain)
- [ ] At least 3-5 results per article (on average)

✅ **Performance**
- [ ] Total latency <8 seconds (summary + links)
- [ ] Cache hit rate >30% for popular topics
- [ ] Graceful degradation (summary works even if links fail)

✅ **Cost**
- [ ] Actual monthly cost matches projection ($5 for <1k articles)
- [ ] Billing alerts configured
- [ ] Usage tracking in place

✅ **UX**
- [ ] Clear visual design (matches summary section style)
- [ ] Responsive on mobile
- [ ] Accessible (keyboard nav, screen readers)
- [ ] Loading states and error handling

---

## Implementation Checklist

### Backend Tasks

- [ ] **Set up Exa account**
  - Sign up at exa.ai
  - Get API key
  - Add $10 credits for testing

- [ ] **Environment configuration**
  - Add `EXA_API_KEY` to `.env`
  - Add `ENABLE_RELATED_LINKS=true` flag
  - Document in `.env.example`

- [ ] **Create service layer** (`backend/services/related_links.py`)
  - Implement `ExaSearchService` class
  - Query construction logic
  - API call with retry logic
  - Result parsing and formatting
  - Caching integration

- [ ] **Update schemas** (`backend/schemas.py`)
  - Add `RelatedLink` model
  - Update `ArticleDetailResponse` with `related_links` field

- [ ] **Database migration** (`backend/database/connection.py`)
  - Add `related_links TEXT` column to `articles` table
  - Run migration on local database

- [ ] **Update repository** (`backend/database/article_repository.py`)
  - Add `related_links` to article converter
  - Update `update_article_summary()` method

- [ ] **Integrate into tasks** (`backend/tasks.py`)
  - Modify `summarize_article()` function
  - Add parallel call to Exa service
  - Handle errors gracefully
  - Log API calls for monitoring

- [ ] **Add to app state** (`backend/server.py`)
  - Initialize `ExaSearchService` on startup
  - Wire up config and cache dependencies

---

### Frontend Tasks

- [ ] **Update TypeScript types** (`web/src/types/index.ts`)
  - Add `RelatedLink` interface
  - Update `Article` interface

- [ ] **Create UI component** (`web/src/components/ArticleDetail.tsx`)
  - Add Related Links section after summary (line 268)
  - Style with blue accent (match summary)
  - Add loading skeleton
  - Handle empty state
  - Make responsive

- [ ] **Add icons** (if not already available)
  - `Link2` icon from lucide-react
  - `ExternalLink` icon from lucide-react

---

### Testing Tasks

- [ ] **Unit tests**
  - Test query construction logic
  - Test API response parsing
  - Test error handling
  - Test caching behavior

- [ ] **Integration tests**
  - Test full summarization + links flow
  - Test database storage and retrieval
  - Test API endpoint responses

- [ ] **Manual testing**
  - Test with 10 diverse articles
  - Verify link relevance
  - Check performance (latency)
  - Test edge cases (no key points, timeouts)

- [ ] **Quality assessment**
  - Compare Exa results to manual search
  - Measure relevance rate
  - Check domain diversity

---

### Deployment Tasks

- [ ] **Update documentation**
  - Add to README.md
  - Document Exa API key requirement
  - Add troubleshooting guide

- [ ] **Set up monitoring**
  - Track API call counts
  - Monitor costs
  - Set up billing alerts
  - Log errors and timeouts

- [ ] **Deploy to production**
  - Add `EXA_API_KEY` to production environment
  - Run database migration
  - Deploy backend changes
  - Deploy frontend changes
  - Monitor for errors

---

## Conclusion

**Summary:**
- **Recommended API:** Exa neural search ($5/1k, 0.35-1.2s, 94.9% accuracy)
- **Integration:** Piggyback on summarization (zero perceived latency)
- **Cost:** $5/month for <1,000 articles (negligible)
- **Timeline:** 1-2 days for MVP implementation
- **ROI:** Expected 10-15% CTR, improved engagement and retention

**Why Exa:**
- Best quality for technical/research content (neural embeddings)
- Fast latency (sub-second option)
- Affordable at low volume
- Simple integration
- Built for AI applications

**Next Steps:**
1. Sign up for Exa account and get $10 free credits
2. Implement backend service and integration
3. Add frontend UI component
4. Test with 10 diverse articles
5. Monitor performance and costs
6. Iterate based on user engagement

This feature will significantly enhance content discovery for DataPoints users, especially for technical and research-focused articles where semantic understanding provides the most value.
