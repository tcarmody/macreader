"""
Story Groups - detects articles from different feeds covering the same news event.

Distinct from broad topic clustering: story groups identify exact-event duplicates
("GPT-5 launches" covered by 5 newsletters) rather than general topic buckets.

Features:
- LLM-powered event-level deduplication with counter-example prompt
- Representative selection (highest word_count, oldest for ties)
- TieredCache (1h TTL) + DB persistence
- Pure detect_groups() for Draft Assembler; get_or_detect_for_window() for the API
"""

import asyncio
import hashlib
import json
import logging
from dataclasses import dataclass, field
from datetime import datetime, timedelta
from typing import TYPE_CHECKING

from ..providers import LLMProvider
from ..providers.base import ModelTier

if TYPE_CHECKING:
    from ..cache import TieredCache
    from ..database import Database
    from ..database.models import DBArticle

logger = logging.getLogger(__name__)

# Max characters of article text to include in the detection prompt
_MAX_PROMPT_CHARS = 8000
# Max description chars per article in the prompt
_MAX_DESC_CHARS = 200
# Cache TTL in seconds (1 hour)
_CACHE_TTL = 3600


@dataclass
class StoryGroup:
    """A group of articles covering the exact same news event."""
    id: int | None          # None before DB persist
    label: str
    representative_id: int  # article_id of best source (highest word_count)
    member_ids: list[int]
    period_start: datetime
    period_end: datetime


# ─── System prompt (static) ───────────────────────────────────────────────────

_SYSTEM_PROMPT = (
    "You are a news editor identifying duplicate story coverage across publications."
)

# ─── Instruction prompt (static, cacheable with Anthropic) ───────────────────

_INSTRUCTION_PROMPT = """Group ONLY articles that cover THE EXACT SAME specific news event — the same announcement, product launch, incident, study release, or development.

General topic similarity is NOT enough. Two articles on the same broad subject are not a group unless they are reporting on the identical event.

Counter-examples (do NOT group these):
- "OpenAI publishes reasoning research" + "Anthropic releases Claude 4" — different companies, different products
- "UK passes AI regulation bill" + "EU AI Act implementation timeline" — different jurisdictions, different legislative stages
- "Apple Q1 earnings beat estimates" + "Microsoft reports record revenue" — different companies

DO group these:
- "OpenAI launches GPT-5 with 2M token context" + "GPT-5 arrives: OpenAI's most powerful model yet" — same product launch
- "FTX founder Sam Bankman-Fried convicted" + "SBF found guilty on all counts" — same verdict

Return JSON only — no explanation, no markdown:
{"groups": [{"label": "5-8 word event description", "article_ids": [id, ...]}]}

Only include groups with 2 or more articles. If no same-event duplicates exist, return:
{"groups": []}"""


class StoryGroupService:
    """LLM-powered story group detection with cache and DB persistence."""

    def __init__(
        self,
        db: "Database",
        provider: LLMProvider,
        cache: "TieredCache | None" = None,
    ):
        self._db = db
        self._provider = provider
        self._cache = cache

    # ─── Public API ──────────────────────────────────────────────────────────

    async def detect_groups(
        self,
        articles: "list[DBArticle]",
        window_hours: int = 48,
    ) -> list[StoryGroup]:
        """Pure event-deduplication — no DB read/write.

        Returns StoryGroup objects with id=None (not yet persisted).
        Used directly by Draft Assembler when it has an explicit article list.
        """
        if len(articles) < 2:
            return []

        period_end = datetime.now()
        period_start = period_end - timedelta(hours=window_hours)

        raw_groups = await self._call_llm(articles)

        result: list[StoryGroup] = []
        all_ids = {a.id for a in articles}
        article_map = {a.id: a for a in articles}

        for raw in raw_groups:
            label = (raw.get("label") or "").strip()
            member_ids = [aid for aid in raw.get("article_ids", []) if aid in all_ids]
            if len(member_ids) < 2 or not label:
                continue

            member_articles = [article_map[mid] for mid in member_ids]
            rep_id = self._pick_representative(member_articles)

            result.append(StoryGroup(
                id=None,
                label=label,
                representative_id=rep_id,
                member_ids=member_ids,
                period_start=period_start,
                period_end=period_end,
            ))

        return result

    async def get_or_detect_for_window(
        self,
        since: datetime,
        feed_ids: list[int] | None = None,
        min_size: int = 2,
        window_hours: int = 48,
        force_refresh: bool = False,
    ) -> list[StoryGroup]:
        """Return story groups for a time window, using cache when fresh.

        Flow:
        1. Fetch articles in the window from DB.
        2. Check TieredCache keyed on article-id set + window_hours.
        3. On cache miss (or force_refresh): call LLM, persist to DB, update cache.
        4. Return groups with min_size >= min_size members.
        """
        period_end = datetime.now()
        period_start = since

        articles = self._db.get_articles_since(since=since, feed_ids=feed_ids, limit=300)
        if len(articles) < 2:
            return []

        cache_key = self._cache_key(articles, window_hours)

        if not force_refresh and self._cache:
            cached = self._cache.get(cache_key)
            if cached:
                groups = self._deserialise_cached(cached, period_start, period_end)
                return [g for g in groups if len(g.member_ids) >= min_size]

        # Detect fresh groups
        groups = await self.detect_groups(articles, window_hours=window_hours)
        filtered = [g for g in groups if len(g.member_ids) >= min_size]

        # Persist to DB (replaces any existing groups for this date window)
        if filtered:
            group_dicts = [
                {
                    "label": g.label,
                    "representative_id": g.representative_id,
                    "member_ids": g.member_ids,
                }
                for g in filtered
            ]
            new_ids = self._db.story_groups.save_groups(group_dicts, period_start, period_end)
            for group, gid in zip(filtered, new_ids):
                group.id = gid

        # Write to cache
        if self._cache and filtered:
            self._cache.set(
                cache_key,
                self._serialise_groups(filtered),
                ttl=_CACHE_TTL,
            )

        return filtered

    async def get_group_for_article(self, article_id: int) -> StoryGroup | None:
        """Return the most recent story group containing this article, or None."""
        db_group = self._db.story_groups.get_group_for_article(article_id)
        if db_group is None:
            return None
        return StoryGroup(
            id=db_group.id,
            label=db_group.label,
            representative_id=db_group.representative_id or article_id,
            member_ids=db_group.member_ids,
            period_start=db_group.period_start,
            period_end=db_group.period_end,
        )

    # ─── LLM call ────────────────────────────────────────────────────────────

    async def _call_llm(self, articles: "list[DBArticle]") -> list[dict]:
        """Call LLM and parse story groups from response. Returns [] on any failure."""
        from ..providers import AnthropicProvider

        dynamic = self._build_dynamic(articles)
        model = self._provider.get_model_for_tier(ModelTier.FAST)
        loop = asyncio.get_event_loop()

        try:
            if isinstance(self._provider, AnthropicProvider):
                response = await loop.run_in_executor(
                    None,
                    lambda: self._provider.complete_with_cacheable_prefix(
                        system_prompt=_SYSTEM_PROMPT,
                        instruction_prompt=_INSTRUCTION_PROMPT,
                        dynamic_content=dynamic,
                        model=model,
                        max_tokens=2048,
                        temperature=0.0,
                    ),
                )
            else:
                full_prompt = f"{_INSTRUCTION_PROMPT}\n\nArticles:\n{dynamic}"
                response = await loop.run_in_executor(
                    None,
                    lambda: self._provider.complete(
                        user_prompt=full_prompt,
                        system_prompt=_SYSTEM_PROMPT,
                        model=model,
                        max_tokens=2048,
                        temperature=0.0,
                        json_mode=self._provider.capabilities.supports_json_mode,
                    ),
                )
        except Exception as exc:
            logger.warning("Story group LLM call failed: %s", exc)
            return []

        return self._parse_response(response.text)

    @staticmethod
    def _parse_response(text: str) -> list[dict]:
        """Parse JSON response, return [] on any error."""
        text = text.strip()
        # Strip markdown code fences
        if text.startswith("```"):
            lines = text.split("\n", 1)
            text = lines[1] if len(lines) > 1 else text[3:]
            if text.rstrip().endswith("```"):
                text = text.rstrip()[:-3]
            text = text.strip()

        try:
            data = json.loads(text)
            return data.get("groups", [])
        except (json.JSONDecodeError, AttributeError):
            logger.debug("Could not parse story group response: %r", text[:200])
            return []

    # ─── Prompt building ──────────────────────────────────────────────────────

    @staticmethod
    def _build_dynamic(articles: "list[DBArticle]") -> str:
        """Build the per-request article list for the prompt."""
        lines: list[str] = []
        total = 0

        for article in articles:
            desc = article.summary_short or ""
            if not desc and article.content:
                desc = article.content[:_MAX_DESC_CHARS]
            desc = desc[:_MAX_DESC_CHARS]

            source = article.site_name or article.feed_name or ""
            date_str = ""
            if article.published_at:
                date_str = article.published_at.strftime("%Y-%m-%d")

            line = f"[id={article.id}]"
            if source:
                line += f" [{source}]"
            if date_str:
                line += f" [{date_str}]"
            line += f' "{article.title}"'
            if desc:
                line += f" – {desc}"

            total += len(line)
            if total > _MAX_PROMPT_CHARS:
                break
            lines.append(line)

        return "\n".join(lines)

    # ─── Representative selection ─────────────────────────────────────────────

    @staticmethod
    def _pick_representative(articles: "list[DBArticle]") -> int:
        """Select the best article to represent a story group.

        Prefer highest word_count (most complete coverage).
        Tie-break: oldest published_at (first to break the story).
        """
        def sort_key(a: "DBArticle"):
            words = a.word_count or 0
            # Negate published_at timestamp so older = lower = better (max picks older)
            ts = -(a.published_at.timestamp() if a.published_at else 0)
            return (words, ts)

        best = max(articles, key=sort_key)
        return best.id

    # ─── Cache helpers ────────────────────────────────────────────────────────

    @staticmethod
    def _cache_key(articles: "list[DBArticle]", window_hours: int) -> str:
        ids = sorted(a.id for a in articles)
        payload = ",".join(str(i) for i in ids) + f":{window_hours}"
        h = hashlib.sha256(payload.encode()).hexdigest()[:16]
        return f"story_groups:{h}"

    @staticmethod
    def _serialise_groups(groups: list[StoryGroup]) -> dict:
        return {
            "groups": [
                {
                    "id": g.id,
                    "label": g.label,
                    "representative_id": g.representative_id,
                    "member_ids": g.member_ids,
                    "period_start": g.period_start.isoformat(),
                    "period_end": g.period_end.isoformat(),
                }
                for g in groups
            ]
        }

    @staticmethod
    def _deserialise_cached(data: dict, period_start: datetime, period_end: datetime) -> list[StoryGroup]:
        result = []
        for g in data.get("groups", []):
            try:
                result.append(StoryGroup(
                    id=g.get("id"),
                    label=g["label"],
                    representative_id=g["representative_id"],
                    member_ids=g["member_ids"],
                    period_start=datetime.fromisoformat(g["period_start"]),
                    period_end=datetime.fromisoformat(g["period_end"]),
                ))
            except (KeyError, ValueError):
                continue
        return result
