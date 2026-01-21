# Scaling DataPoints to 1000+ Users

This document outlines strategies for scaling the DataPoints RSS reader from a single-user SQLite setup to support thousands of concurrent users.

## Current Architecture

**Database**: Single SQLite file (`data/articles.db`) with:
- `articles` - shared RSS content + per-user library items
- `user_article_state` - per-user read/bookmark state (UNIQUE user_id, article_id)
- `feeds` - RSS subscriptions (shared)
- `users` - OAuth/API key accounts
- `articles_fts` - FTS5 full-text search index

**Multi-tenancy Model**:
- Shared articles: `WHERE user_id IS NULL`
- Per-user state: LEFT JOIN to `user_article_state`
- Library items: `user_id` column for ownership

**Current Bottlenecks**:
1. No connection pooling (fresh SQLite connection per operation)
2. N+1 query patterns in bulk operations (loop-based INSERTs)
3. Expensive triple JOINs for feed unread counts
4. Unbounded `user_article_state` growth (users × articles)
5. Synchronous FTS5 triggers on every write

---

## Option 1: SQLite Optimization

**Target**: Up to ~500 concurrent users
**Complexity**: Low (2-3 weeks)
**Cost**: $10-50/month

### Changes Required

#### 1.1 Enable WAL Mode
Add to `backend/database/connection.py`:
```python
connection.execute("PRAGMA journal_mode=WAL")
connection.execute("PRAGMA synchronous=NORMAL")
connection.execute("PRAGMA cache_size=-64000")  # 64MB cache
```

WAL (Write-Ahead Logging) allows concurrent reads during writes.

#### 1.2 Fix N+1 Query Patterns
Replace loop-based INSERTs in `backend/database/user_article_state_repository.py`:

**Before** (current code, lines 115-126):
```python
for article_id in article_ids:
    cursor.execute("INSERT OR REPLACE INTO user_article_state ...")
```

**After**:
```python
cursor.executemany("""
    INSERT INTO user_article_state (user_id, article_id, is_read, read_at)
    VALUES (?, ?, ?, ?)
    ON CONFLICT(user_id, article_id) DO UPDATE SET is_read=excluded.is_read, read_at=excluded.read_at
""", [(user_id, aid, is_read, read_at) for aid in article_ids])
```

#### 1.3 Cache Feed Unread Counts
Add a `user_feed_state` table to store pre-computed counts:
```sql
CREATE TABLE user_feed_state (
    user_id INTEGER NOT NULL,
    feed_id INTEGER NOT NULL,
    unread_count INTEGER DEFAULT 0,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id, feed_id)
);
```

Update incrementally on `mark_read` operations instead of computing via JOIN.

#### 1.4 Defer FTS5 Updates
Remove synchronous triggers, batch index updates via background task every 5 minutes.

### Trade-offs

| Pros | Cons |
|------|------|
| Minimal infrastructure changes | Single-node limited |
| Simple deployment (single file) | ~500 user soft ceiling |
| Good for self-hosted scenarios | Write throughput ~50-100/sec |
| No new dependencies | No horizontal scaling |

### When to Choose
- Self-hosted/on-premise requirements
- Budget constraints
- Small team deployment
- Proof of concept phase

---

## Option 2: PostgreSQL Migration

**Target**: 1,000-10,000 concurrent users
**Complexity**: Medium (4-6 weeks)
**Cost**: $50-200/month (managed PostgreSQL)

### Changes Required

#### 2.1 Database Connection Layer
Replace SQLite with asyncpg in `backend/database/connection.py`:

```python
import asyncpg

class PostgresConnection:
    def __init__(self, dsn: str, pool_size: int = 20):
        self.dsn = dsn
        self._pool: asyncpg.Pool | None = None

    async def init_pool(self):
        self._pool = await asyncpg.create_pool(
            self.dsn,
            min_size=5,
            max_size=self.pool_size
        )

    async def conn(self):
        return self._pool.acquire()
```

#### 2.2 Schema Migration
The existing schema is PostgreSQL-compatible. Use Alembic for migrations:

```bash
pip install alembic asyncpg
alembic init migrations
```

#### 2.3 Optimized Indexes
```sql
-- Covering index for article listing
CREATE INDEX idx_articles_feed_published
ON articles(feed_id, published_at DESC)
INCLUDE (title, author, summary_short);

-- Partial index for unread articles only
CREATE INDEX idx_user_state_unread
ON user_article_state(user_id, article_id)
WHERE is_read = false;

-- Composite index for feed unread counts
CREATE INDEX idx_user_state_feed_unread
ON user_article_state(user_id, is_read)
INCLUDE (article_id);
```

#### 2.4 Materialized View for Feed Stats
```sql
CREATE MATERIALIZED VIEW user_feed_stats AS
SELECT
    uas.user_id,
    a.feed_id,
    COUNT(*) FILTER (WHERE NOT COALESCE(uas.is_read, false)) as unread_count
FROM articles a
LEFT JOIN user_article_state uas ON a.id = uas.article_id
WHERE a.user_id IS NULL
GROUP BY uas.user_id, a.feed_id;

-- Refresh periodically (every 5 minutes via cron or pg_cron)
REFRESH MATERIALIZED VIEW CONCURRENTLY user_feed_stats;
```

#### 2.5 Read Replicas (Optional)
For higher read throughput, add read replicas and route read queries:

```python
class DatabaseRouter:
    def __init__(self, primary_pool, replica_pool):
        self.primary = primary_pool
        self.replica = replica_pool

    def get_read_conn(self):
        return self.replica.acquire()

    def get_write_conn(self):
        return self.primary.acquire()
```

### Trade-offs

| Pros | Cons |
|------|------|
| True concurrent writes | Operational complexity |
| Horizontal read scaling | Data migration required |
| Proven at massive scale | Higher hosting costs |
| Managed options (Neon, RDS, Cloud SQL) | Requires migration tooling |
| Better query planner | Team needs PostgreSQL knowledge |

### When to Choose
- Growing beyond 500 users
- Need concurrent write support
- Team has PostgreSQL experience
- Using cloud infrastructure

### Managed PostgreSQL Options
- **Neon**: Serverless, scales to zero, branching for dev/test
- **AWS RDS**: Reliable, read replicas, automated backups
- **Google Cloud SQL**: Good GCP integration
- **Supabase**: PostgreSQL + auth + realtime built-in

---

## Option 3: Hybrid Architecture (PostgreSQL + Redis)

**Target**: 5,000-50,000 concurrent users
**Complexity**: High (8-12 weeks)
**Cost**: $200-500/month

### Architecture Overview

```
                    ┌─────────────────┐
                    │  Load Balancer  │
                    └────────┬────────┘
                             │
            ┌────────────────┼────────────────┐
            │                │                │
      ┌─────▼─────┐    ┌─────▼─────┐    ┌─────▼─────┐
      │  API Pod  │    │  API Pod  │    │  API Pod  │
      └─────┬─────┘    └─────┬─────┘    └─────┬─────┘
            │                │                │
            └────────────────┼────────────────┘
                             │
           ┌─────────────────┼─────────────────┐
           │                 │                 │
     ┌─────▼─────┐     ┌─────▼─────┐     ┌─────▼─────┐
     │ PostgreSQL│     │   Redis   │     │  Workers  │
     │ (Primary) │     │  Cluster  │     │   Queue   │
     └─────┬─────┘     └───────────┘     └───────────┘
           │
     ┌─────▼─────┐
     │  Replica  │
     └───────────┘
```

### Changes Required

#### 3.1 Redis Cache Layer
Extend `backend/cache.py` with Redis backend:

```python
import aioredis
import json
from typing import Any

class RedisCache:
    def __init__(self, redis_url: str):
        self.redis = aioredis.from_url(redis_url)

    async def get(self, key: str) -> Any | None:
        data = await self.redis.get(key)
        return json.loads(data) if data else None

    async def set(self, key: str, value: Any, ttl: int = 3600):
        await self.redis.setex(key, ttl, json.dumps(value))

    async def delete(self, key: str):
        await self.redis.delete(key)

    async def incr(self, key: str, amount: int = 1) -> int:
        return await self.redis.incrby(key, amount)
```

#### 3.2 Cache Key Patterns

**Feed unread counts** (highest impact):
```python
# Key: f"unread:{user_id}:{feed_id}"
# Value: integer count
# TTL: 5 minutes
# Invalidate: on mark_read, mark_all_read, new article

async def get_unread_count(user_id: int, feed_id: int) -> int:
    key = f"unread:{user_id}:{feed_id}"
    cached = await cache.get(key)
    if cached is not None:
        return cached

    count = await db.calculate_unread_count(user_id, feed_id)
    await cache.set(key, count, ttl=300)
    return count
```

**Recent article lists**:
```python
# Key: f"articles:{user_id}:{feed_id}:page:{page}"
# Value: list of article IDs
# TTL: 2 minutes
# Use Redis Sorted Sets for efficient pagination
```

**User sessions**:
```python
# Key: f"session:{token}"
# Value: {user_id, email, expires_at}
# TTL: session duration (e.g., 7 days)
```

#### 3.3 Cache Invalidation Strategy

**Write-through pattern**:
```python
async def mark_article_read(user_id: int, article_id: int):
    # Update database
    await db.mark_read(user_id, article_id)

    # Invalidate relevant caches
    feed_id = await db.get_article_feed_id(article_id)
    await cache.delete(f"unread:{user_id}:{feed_id}")
    await cache.delete(f"articles:{user_id}:{feed_id}:*")  # Pattern delete
```

**Pub/Sub for multi-instance**:
```python
# When cache is invalidated, publish to channel
await redis.publish("cache:invalidate", json.dumps({
    "pattern": f"unread:{user_id}:*"
}))

# All API instances subscribe and clear local caches
```

#### 3.4 Background Workers
Move heavy operations out of API request cycle:

**Feed refresh worker** (`backend/workers/feed_worker.py`):
```python
from dramatiq import actor

@actor(queue_name="feeds")
async def refresh_feed(feed_id: int):
    articles = await fetch_feed_articles(feed_id)
    await db.insert_articles(articles)

    # Invalidate caches for all users subscribed to this feed
    await publish_cache_invalidation(f"articles:*:{feed_id}:*")
```

**Summarization worker**:
```python
@actor(queue_name="summarization", time_limit=120000)  # 2 min timeout
async def summarize_article(article_id: int):
    article = await db.get_article(article_id)
    summary = await llm.summarize(article.content)
    await db.update_article_summary(article_id, summary)
```

#### 3.5 Configuration
Add to `backend/config.py`:
```python
import os

DATABASE_URL = os.getenv("DATABASE_URL", "sqlite:///data/articles.db")
REDIS_URL = os.getenv("REDIS_URL", None)  # Falls back to memory cache if None
WORKER_BROKER_URL = os.getenv("WORKER_BROKER_URL", "redis://localhost:6379/0")

# Feature flags for gradual rollout
ENABLE_REDIS_CACHE = os.getenv("ENABLE_REDIS_CACHE", "false").lower() == "true"
ENABLE_BACKGROUND_WORKERS = os.getenv("ENABLE_BACKGROUND_WORKERS", "false").lower() == "true"
```

### Trade-offs

| Pros | Cons |
|------|------|
| Horizontal scaling for all components | Architectural complexity |
| Sub-millisecond read latency | Cache consistency challenges |
| Handles traffic spikes gracefully | Multiple services to deploy/monitor |
| Clear separation of concerns | Higher operational costs |
| Battle-tested patterns | Eventual consistency considerations |

### When to Choose
- Rapid user growth anticipated
- Performance SLAs required
- Team comfortable with distributed systems
- Budget for multi-service infrastructure

---

## Option 4: Cloud-Native Microservices

**Target**: 50,000+ concurrent users
**Complexity**: Very High (16-24 weeks)
**Cost**: $500-5000+/month

### Architecture Overview

Split into independent services:
- **Article Service**: CRUD, summaries, content extraction
- **Feed Service**: RSS parsing, refresh scheduling
- **User Service**: Auth, preferences, state management
- **Notification Service**: Rules engine, delivery
- **Search Service**: Full-text search, recommendations

### Key Components

- **Event Bus**: Kafka or AWS EventBridge for inter-service communication
- **Service Mesh**: Istio or Linkerd for observability
- **Container Orchestration**: Kubernetes
- **Serverless**: Lambda/Cloud Functions for feed refresh
- **Managed Services**: Aurora Serverless, ElastiCache, OpenSearch

### When to Choose
- Building commercial SaaS product
- Need multi-region deployment
- Strict compliance requirements (SOC2, HIPAA)
- Dedicated platform/DevOps team

---

## Recommendation Summary

| User Scale | Recommended Option | Timeline | Monthly Cost |
|------------|-------------------|----------|--------------|
| <500 | Option 1 (SQLite) | 2-3 weeks | $10-50 |
| 500-5,000 | Option 2 (PostgreSQL) | 4-6 weeks | $50-200 |
| 5,000-50,000 | Option 3 (Hybrid) | 8-12 weeks | $200-500 |
| 50,000+ | Option 4 (Microservices) | 16-24 weeks | $500+ |

### Recommended Migration Path

1. **Immediate** (Option 1): Fix N+1 queries, enable WAL mode
2. **At 200-300 users**: Migrate to managed PostgreSQL (Neon recommended for serverless)
3. **At 2,000-3,000 users**: Add Redis caching layer
4. **At 10,000+ users**: Evaluate full hybrid architecture

---

## Quick Wins (Do First)

These changes provide immediate benefit with minimal risk:

### 1. Fix Bulk Operations (1-2 days)
File: `backend/database/user_article_state_repository.py`

### 2. Enable WAL Mode (1 hour)
File: `backend/database/connection.py`

### 3. Add Composite Index (1 hour)
```sql
CREATE INDEX IF NOT EXISTS idx_user_state_composite
ON user_article_state(user_id, article_id, is_read);
```

### 4. Cache Unread Counts in Memory (1 day)
Use existing `MemoryCache` class for feed unread counts with 60-second TTL.

---

## Monitoring Recommendations

Regardless of which option you choose, add observability:

1. **Database metrics**: Connection count, query latency, slow query log
2. **API metrics**: Request latency (p50, p95, p99), error rate
3. **Cache metrics**: Hit rate, eviction rate, memory usage
4. **Business metrics**: Active users, articles read/day, feed refresh success rate

Tools: Prometheus + Grafana, or managed options like Datadog, New Relic
