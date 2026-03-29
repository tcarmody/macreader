"""
Auto-Digest — assembles a scored, deduplicated, topic-grouped daily or weekly
briefing from recent feed articles.

Pipeline:
  1. Fetch articles in the requested time window.
  2. Detect story groups (same-event deduplication).
  3. Cluster deduplicated articles into topic sections (min 5 clusters).
  4. Score every article; take top-1 per cluster, then fill to 5 stories minimum.
  5. Generate briefs for selected articles (batch, DB-cached).
  6. Generate a 2-sentence intro via LLM.
  7. Render to markdown or html.
  8. Persist to `digests` table (2-hour cache).
"""

import asyncio
import logging
from dataclasses import dataclass, field
from datetime import datetime, timedelta
from typing import TYPE_CHECKING

from ..providers import LLMProvider
from ..providers.base import ModelTier

if TYPE_CHECKING:
    from ..cache import TieredCache
    from ..clustering import Clusterer
    from ..database import Database
    from ..database.models import DBArticle
    from .brief_generator import BriefGenerator, BriefLength, BriefTone
    from .story_groups import StoryGroupService

logger = logging.getLogger(__name__)

# Minimum number of topic clusters to request from the Clusterer
_MIN_CLUSTERS = 5
# Minimum stories in the output (fill across clusters if needed)
_MIN_STORIES = 5
# Cache TTL for digests (seconds)
_CACHE_MAX_AGE_HOURS = 2


# ─── Domain objects ──────────────────────────────────────────────────────────

@dataclass
class DigestArticle:
    id: int
    title: str
    url: str
    source: str | None
    published_at: datetime | None
    brief: str
    story_group_size: int = 1   # >1 means duplicate coverage was collapsed


@dataclass
class DigestSection:
    label: str
    articles: list[DigestArticle] = field(default_factory=list)


@dataclass
class Digest:
    period: str
    period_start: datetime
    period_end: datetime
    title: str
    intro: str
    sections: list[DigestSection]
    story_count: int
    word_count: int
    format: str
    raw: str
    cached: bool = False
    digest_id: int | None = None


# ─── Service ─────────────────────────────────────────────────────────────────

class AutoDigestService:
    """Assembles a scored, deduplicated daily or weekly digest."""

    def __init__(
        self,
        db: "Database",
        provider: LLMProvider,
        clusterer: "Clusterer",
        brief_generator: "BriefGenerator",
        story_group_service: "StoryGroupService",
        cache: "TieredCache | None" = None,
    ):
        self._db = db
        self._provider = provider
        self._clusterer = clusterer
        self._brief_generator = brief_generator
        self._story_group_service = story_group_service
        self._cache = cache

    async def generate(
        self,
        period: str = "today",
        feed_ids: list[int] | None = None,
        max_stories: int = 10,
        tone: str = "neutral",
        brief_length: str = "short",
        format: str = "markdown",
        force_refresh: bool = False,
    ) -> Digest:
        """Generate (or return cached) a digest for the requested period.

        Args:
            period:        "today" (last 24 h) or "week" (last 7 days).
            feed_ids:      Optional feed filter. If set, cache is bypassed.
            max_stories:   Hard cap on total stories (default 10).
            tone:          Brief tone — neutral | opinionated | analytical.
            brief_length:  Brief length — sentence | short | paragraph.
            format:        Output format — markdown | html.
            force_refresh: Ignore cached digest and re-generate.
        """
        period_end = datetime.now()
        period_start = self._period_start(period, period_end)

        # Return cached digest when possible
        if not force_refresh and feed_ids is None:
            cached = self._db.digests.get_latest(period, max_age_hours=_CACHE_MAX_AGE_HOURS)
            if cached and cached.tone == tone and cached.brief_length == brief_length and cached.format == format:
                return self._from_db_digest(cached)

        articles = self._db.get_articles_since(since=period_start, feed_ids=feed_ids, limit=500)
        if not articles:
            return self._empty_digest(period, period_start, period_end, format)

        # ── 1. Dedup via story groups ─────────────────────────────────────────
        story_groups = await self._story_group_service.detect_groups(articles)
        # Map: representative_id → group size (number of sources)
        group_size_by_rep: dict[int, int] = {g.representative_id: len(g.member_ids) for g in story_groups}
        # IDs that are non-representative members (should be excluded from selection)
        non_rep_ids: set[int] = set()
        for g in story_groups:
            for mid in g.member_ids:
                if mid != g.representative_id:
                    non_rep_ids.add(mid)

        deduped = [a for a in articles if a.id not in non_rep_ids]
        if not deduped:
            deduped = articles  # fallback: no groups found

        # ── 2. Cluster into topic sections ───────────────────────────────────
        clustering = await self._clusterer.cluster_async(deduped, min_clusters=_MIN_CLUSTERS)
        article_map = {a.id: a for a in deduped}

        # ── 3. Score and select ───────────────────────────────────────────────
        selected_ids = self._select_articles(
            clustering.topics, article_map, group_size_by_rep, max_stories
        )

        # ── 4. Generate briefs ────────────────────────────────────────────────
        from .brief_generator import BriefLength, BriefTone
        bl = BriefLength(brief_length)
        bt = BriefTone(tone)

        items = [
            {"article_id": a.id, "title": a.title or "", "content": a.summary_full or a.content or ""}
            for aid in selected_ids
            if (a := article_map.get(aid)) and (a.summary_full or a.content or "")
        ]
        briefs_list = await self._brief_generator.generate_batch(items, bl, bt)
        brief_by_id = {b.article_id: b.content for b in briefs_list}

        # ── 5. Build sections (preserve cluster order) ────────────────────────
        selected_set = set(selected_ids)
        sections: list[DigestSection] = []
        for topic in clustering.topics:
            topic_selected = [aid for aid in topic.article_ids if aid in selected_set]
            if not topic_selected:
                continue
            section = DigestSection(label=topic.label)
            for aid in topic_selected:
                a = article_map.get(aid)
                if a is None:
                    continue
                section.articles.append(DigestArticle(
                    id=a.id,
                    title=a.title or "",
                    url=a.url,
                    source=a.site_name or a.feed_name,
                    published_at=a.published_at,
                    brief=brief_by_id.get(a.id, a.summary_short or ""),
                    story_group_size=group_size_by_rep.get(a.id, 1),
                ))
            if section.articles:
                sections.append(section)

        story_count = sum(len(s.articles) for s in sections)

        # ── 6. Generate intro ─────────────────────────────────────────────────
        intro = await self._generate_intro(sections, story_count, tone)

        # ── 7. Render ─────────────────────────────────────────────────────────
        title = self._make_title(period, period_end)
        raw = self._render(title, intro, sections, format)
        word_count = len(raw.split())

        # ── 8. Persist ────────────────────────────────────────────────────────
        digest_id = None
        if feed_ids is None:  # only cache unfilitered digests
            digest_id = self._db.digests.save(
                period=period,
                period_start=period_start,
                period_end=period_end,
                article_ids=selected_ids,
                title=title,
                intro=intro,
                content=raw,
                format=format,
                tone=tone,
                brief_length=brief_length,
                story_count=story_count,
                word_count=word_count,
            )

        return Digest(
            period=period,
            period_start=period_start,
            period_end=period_end,
            title=title,
            intro=intro,
            sections=sections,
            story_count=story_count,
            word_count=word_count,
            format=format,
            raw=raw,
            cached=False,
            digest_id=digest_id,
        )

    # ─── Selection ───────────────────────────────────────────────────────────

    def _select_articles(
        self,
        topics,
        article_map: "dict[int, DBArticle]",
        group_size_by_rep: dict[int, int],
        max_stories: int,
    ) -> list[int]:
        """Score articles, take top-1 per cluster, fill to _MIN_STORIES."""
        now = datetime.now()

        def score(article: "DBArticle") -> float:
            s = 0.0
            if article.summary_short or article.summary_full:
                s += 2.0
            s += group_size_by_rep.get(article.id, 1) - 1  # extra sources bonus
            if article.published_at:
                age_days = max(0, (now - article.published_at).total_seconds() / 86400)
                s -= 0.5 * age_days
            return s

        selected: list[int] = []
        runner_up_pool: list[tuple[float, int]] = []  # (score, id) for fill

        for topic in topics:
            scored = sorted(
                [(score(a), a.id) for aid in topic.article_ids if (a := article_map.get(aid))],
                reverse=True,
            )
            if not scored:
                continue
            best_score, best_id = scored[0]
            selected.append(best_id)
            # Remaining in this cluster go into the fill pool
            for sc, aid in scored[1:]:
                runner_up_pool.append((sc, aid))

        # Fill to _MIN_STORIES if needed, respecting max_stories cap
        if len(selected) < _MIN_STORIES:
            runner_up_pool.sort(reverse=True)
            selected_set = set(selected)
            for sc, aid in runner_up_pool:
                if len(selected) >= max(max_stories, _MIN_STORIES):
                    break
                if aid not in selected_set:
                    selected.append(aid)
                    selected_set.add(aid)

        return selected[:max_stories]

    # ─── Intro generation ────────────────────────────────────────────────────

    async def _generate_intro(
        self, sections: list[DigestSection], story_count: int, tone: str
    ) -> str:
        labels = ", ".join(s.label for s in sections[:6])
        prompt = (
            f"Write a 2-sentence newsletter intro for a digest containing {story_count} stories "
            f"across these topics: {labels}. "
            f"Tone: {tone}. Be specific and engaging. No filler phrases."
        )
        model = self._provider.get_model_for_tier(ModelTier.FAST)
        loop = asyncio.get_event_loop()
        try:
            response = await loop.run_in_executor(
                None,
                lambda: self._provider.complete(
                    user_prompt=prompt,
                    system_prompt="You are writing a brief newsletter intro paragraph.",
                    model=model,
                    max_tokens=150,
                    temperature=0.3,
                ),
            )
            return response.text.strip()
        except Exception as exc:
            logger.warning("Intro generation failed: %s", exc)
            return f"{story_count} stories across {labels}."

    # ─── Rendering ───────────────────────────────────────────────────────────

    def _render(
        self,
        title: str,
        intro: str,
        sections: list[DigestSection],
        format: str,
    ) -> str:
        if format == "html":
            return self._render_html(title, intro, sections)
        return self._render_markdown(title, intro, sections)

    @staticmethod
    def _render_markdown(title: str, intro: str, sections: list[DigestSection]) -> str:
        lines: list[str] = [f"# {title}", "", intro, "", "---"]
        for section in sections:
            lines.append(f"\n## {section.label}\n")
            for a in section.articles:
                source = f" · {a.source}" if a.source else ""
                lines.append(f"**{a.title}**{source}")
                if a.brief:
                    lines.append(a.brief)
                lines.append(f"→ {a.url}")
                if a.story_group_size > 1:
                    lines.append(f"*({a.story_group_size} sources covered this story)*")
                lines.append("")
        return "\n".join(lines).strip()

    @staticmethod
    def _render_html(title: str, intro: str, sections: list[DigestSection]) -> str:
        parts = [
            "<article>",
            f'<h1 style="font-size:1.5em;margin-bottom:0.25em">{_he(title)}</h1>',
            f'<p style="color:#555;margin-bottom:1.5em">{_he(intro)}</p>',
            '<hr style="border:none;border-top:1px solid #eee;margin:1.5em 0">',
        ]
        for section in sections:
            parts.append(f'<h2 style="font-size:1.1em;margin:1.5em 0 0.5em">{_he(section.label)}</h2>')
            for a in section.articles:
                source_html = f' <span style="color:#888">· {_he(a.source)}</span>' if a.source else ""
                parts.append(
                    f'<p style="margin:0.75em 0">'
                    f'<strong>{_he(a.title)}</strong>{source_html}<br>'
                    f'{_he(a.brief)}<br>'
                    f'<a href="{a.url}" style="color:#0066cc">Read more →</a>'
                )
                if a.story_group_size > 1:
                    parts.append(
                        f'<em style="font-size:0.85em;color:#888">'
                        f'({a.story_group_size} sources covered this story)</em>'
                    )
                parts.append("</p>")
        parts.append("</article>")
        return "\n".join(parts)

    # ─── Helpers ─────────────────────────────────────────────────────────────

    @staticmethod
    def _period_start(period: str, period_end: datetime) -> datetime:
        if period == "week":
            return period_end - timedelta(days=7)
        return period_end - timedelta(hours=24)  # "today"

    @staticmethod
    def _make_title(period: str, period_end: datetime) -> str:
        date_str = period_end.strftime("%B %-d, %Y")
        label = "Weekly Digest" if period == "week" else "Daily Digest"
        return f"DataPoints {label} · {date_str}"

    def _empty_digest(
        self, period: str, period_start: datetime, period_end: datetime, format: str
    ) -> Digest:
        title = self._make_title(period, period_end)
        raw = f"# {title}\n\nNo stories available for this period."
        return Digest(
            period=period,
            period_start=period_start,
            period_end=period_end,
            title=title,
            intro="No stories available for this period.",
            sections=[],
            story_count=0,
            word_count=len(raw.split()),
            format=format,
            raw=raw,
            cached=False,
        )

    @staticmethod
    def _from_db_digest(db_digest) -> Digest:
        """Reconstruct a minimal Digest from a cached DB row (no section detail)."""
        return Digest(
            period=db_digest.period,
            period_start=db_digest.period_start,
            period_end=db_digest.period_end,
            title=db_digest.title,
            intro=db_digest.intro or "",
            sections=[],      # not stored at section level — caller gets raw
            story_count=db_digest.story_count,
            word_count=db_digest.word_count,
            format=db_digest.format,
            raw=db_digest.content,
            cached=True,
            digest_id=db_digest.id,
        )


def _he(text: str | None) -> str:
    """Minimal HTML entity escaping."""
    if not text:
        return ""
    return text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace('"', "&quot;")
