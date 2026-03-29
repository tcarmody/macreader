"""
Digest routes: newsletter assembly endpoints.
"""

from datetime import datetime, timedelta
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query

from ..auth import verify_api_key, get_current_user
from ..config import state, get_db
from ..database import Database
from ..schemas import (
    AutoDigestResponse,
    BatchBriefRequest,
    BatchBriefResponse,
    BatchBriefResult,
    DigestArticleResponse,
    DigestSectionResponse,
    StoryGroupResponse,
    StoryGroupMemberResponse,
)
from ..schemas import serialize_datetime

router = APIRouter(
    prefix="/digest",
    tags=["digest"],
    dependencies=[Depends(verify_api_key)]
)


@router.post("/briefs/batch")
async def generate_briefs_batch(
    request: BatchBriefRequest,
    db: Annotated[Database, Depends(get_db)],
    user_id: Annotated[int, Depends(get_current_user)],
) -> BatchBriefResponse:
    """Batch-generate newsletter briefs for up to 20 articles.

    Articles that already have a cached brief for the requested length/tone are
    returned immediately. New briefs are generated concurrently via LLM.
    """
    if not state.brief_generator:
        raise HTTPException(status_code=503, detail="Brief generator not configured")

    from ..services.brief_generator import BriefLength, BriefTone

    length = BriefLength(request.length.value)
    tone = BriefTone(request.tone.value)

    # Split into cached vs. needs-generation
    items_to_generate: list[dict] = []
    cached_results: dict[int, BatchBriefResult] = {}

    for article_id in request.article_ids:
        cached = db.briefs.get(article_id, length.value, tone.value)
        if cached:
            cached_results[article_id] = BatchBriefResult(
                article_id=article_id,
                success=True,
                content=cached.content,
                model_used=cached.model_used,
                cached=True,
            )
            continue

        article = db.get_article(article_id)
        if article is None:
            cached_results[article_id] = BatchBriefResult(
                article_id=article_id,
                success=False,
                error="Article not found",
            )
            continue

        source_text = article.summary_full or article.content
        if not source_text or len(source_text.strip()) < 50:
            cached_results[article_id] = BatchBriefResult(
                article_id=article_id,
                success=False,
                error="Article has insufficient content",
            )
            continue

        items_to_generate.append({
            "article_id": article_id,
            "title": article.title or "",
            "content": source_text,
        })

    # Generate all missing briefs concurrently
    generated_results: dict[int, BatchBriefResult] = {}
    if items_to_generate:
        briefs = await state.brief_generator.generate_batch(items_to_generate, length, tone)
        for brief in briefs:
            db.briefs.upsert(
                article_id=brief.article_id,
                length=brief.length.value,
                tone=brief.tone.value,
                content=brief.content,
                model_used=brief.model_used,
            )
            generated_results[brief.article_id] = BatchBriefResult(
                article_id=brief.article_id,
                success=True,
                content=brief.content,
                model_used=brief.model_used,
                cached=False,
            )

    # Assemble results in original order
    all_results: list[BatchBriefResult] = []
    for article_id in request.article_ids:
        if article_id in cached_results:
            all_results.append(cached_results[article_id])
        elif article_id in generated_results:
            all_results.append(generated_results[article_id])
        else:
            all_results.append(BatchBriefResult(
                article_id=article_id,
                success=False,
                error="Brief generation failed",
            ))

    successful = sum(1 for r in all_results if r.success)
    return BatchBriefResponse(
        total=len(all_results),
        successful=successful,
        failed=len(all_results) - successful,
        results=all_results,
    )


@router.get("/story-groups")
async def get_story_groups(
    db: Annotated[Database, Depends(get_db)],
    since: str | None = Query(default=None, description="ISO8601 start time (default: 48h ago)"),
    feed_ids: str | None = Query(default=None, description="Comma-separated feed IDs to filter"),
    min_size: int = Query(default=2, ge=2, le=20),
    refresh: bool = Query(default=False),
) -> list[StoryGroupResponse]:
    """Detect and return story groups for a time window.

    Articles from different feeds that cover the same specific news event are
    grouped together. Results are cached for 1 hour and persisted to the DB.
    Use ?refresh=true to force re-detection.
    """
    if not state.story_group_service:
        raise HTTPException(status_code=503, detail="Story group detection not configured")

    # Parse since (default: 48h ago)
    if since:
        try:
            period_start = datetime.fromisoformat(since.replace("Z", "+00:00"))
            # Normalise to naive UTC for consistency with DB storage
            if period_start.tzinfo is not None:
                from datetime import timezone
                period_start = period_start.astimezone(timezone.utc).replace(tzinfo=None)
        except ValueError:
            raise HTTPException(status_code=422, detail="Invalid 'since' datetime format")
    else:
        period_start = datetime.now() - timedelta(hours=48)

    # Parse feed_ids
    parsed_feed_ids: list[int] | None = None
    if feed_ids:
        try:
            parsed_feed_ids = [int(fid.strip()) for fid in feed_ids.split(",") if fid.strip()]
        except ValueError:
            raise HTTPException(status_code=422, detail="Invalid feed_ids format")

    groups = await state.story_group_service.get_or_detect_for_window(
        since=period_start,
        feed_ids=parsed_feed_ids,
        min_size=min_size,
        force_refresh=refresh,
    )

    # Enrich with article details
    return _build_response(groups, db)


def _build_response(groups, db: Database) -> list[StoryGroupResponse]:
    """Fetch article details and build StoryGroupResponse list."""
    # Collect all article IDs we need
    all_ids: set[int] = set()
    for g in groups:
        all_ids.update(g.member_ids)
        if g.representative_id:
            all_ids.add(g.representative_id)

    # Fetch articles in bulk
    article_map = {}
    for aid in all_ids:
        article = db.get_article(aid)
        if article:
            article_map[aid] = article

    def to_member(article_id: int) -> StoryGroupMemberResponse | None:
        a = article_map.get(article_id)
        if a is None:
            return None
        return StoryGroupMemberResponse(
            id=a.id,
            title=a.title,
            url=a.url,
            source=a.site_name or a.feed_name,
            published_at=serialize_datetime(a.published_at),
            summary_short=a.summary_short,
            word_count=a.word_count,
        )

    result: list[StoryGroupResponse] = []
    for g in groups:
        representative = to_member(g.representative_id)
        if representative is None:
            continue

        members = [m for mid in g.member_ids if (m := to_member(mid)) is not None]

        result.append(StoryGroupResponse(
            id=g.id or 0,
            label=g.label,
            representative=representative,
            members=members,
            member_count=len(members),
            period_start=g.period_start.isoformat() + "Z",
            period_end=g.period_end.isoformat() + "Z",
        ))

    return result


# ─── Auto-Digest ─────────────────────────────────────────────────────────────

@router.get("/auto")
async def get_auto_digest(
    db: Annotated[Database, Depends(get_db)],
    period: str = Query(default="today", description="'today' (24 h) or 'week' (7 days)"),
    feed_ids: str | None = Query(default=None, description="Comma-separated feed IDs to filter"),
    max_stories: int = Query(default=10, ge=1, le=50),
    tone: str = Query(default="neutral", description="neutral | opinionated | analytical"),
    brief_length: str = Query(default="short", description="sentence | short | paragraph"),
    format: str = Query(default="markdown", description="markdown | html"),
    refresh: bool = Query(default=False),
) -> AutoDigestResponse:
    """Generate (or return cached) a scored, deduplicated daily or weekly digest.

    Selects the most noteworthy stories from your feeds, collapses same-event
    duplicate coverage, groups by topic, and renders a ready-to-read briefing.
    Results are cached for 2 hours. Use ?refresh=true to force regeneration.
    """
    if not state.auto_digest_service:
        raise HTTPException(status_code=503, detail="Auto-digest not configured")

    # Validate period
    if period not in ("today", "week"):
        raise HTTPException(status_code=422, detail="period must be 'today' or 'week'")

    # Validate tone and brief_length
    from ..services.brief_generator import BriefLength, BriefTone
    try:
        BriefLength(brief_length)
    except ValueError:
        raise HTTPException(status_code=422, detail=f"Invalid brief_length: {brief_length}")
    try:
        BriefTone(tone)
    except ValueError:
        raise HTTPException(status_code=422, detail=f"Invalid tone: {tone}")

    if format not in ("markdown", "html"):
        raise HTTPException(status_code=422, detail="format must be 'markdown' or 'html'")

    # Parse feed_ids
    parsed_feed_ids: list[int] | None = None
    if feed_ids:
        try:
            parsed_feed_ids = [int(fid.strip()) for fid in feed_ids.split(",") if fid.strip()]
        except ValueError:
            raise HTTPException(status_code=422, detail="Invalid feed_ids format")

    digest = await state.auto_digest_service.generate(
        period=period,
        feed_ids=parsed_feed_ids,
        max_stories=max_stories,
        tone=tone,
        brief_length=brief_length,
        format=format,
        force_refresh=refresh,
    )

    return AutoDigestResponse(
        period=digest.period,
        period_start=digest.period_start.isoformat() + "Z",
        period_end=digest.period_end.isoformat() + "Z",
        title=digest.title,
        intro=digest.intro,
        sections=[
            DigestSectionResponse(
                label=s.label,
                articles=[
                    DigestArticleResponse(
                        id=a.id,
                        title=a.title,
                        url=a.url,
                        source=a.source,
                        published_at=serialize_datetime(a.published_at),
                        brief=a.brief,
                        story_group_size=a.story_group_size,
                    )
                    for a in s.articles
                ],
            )
            for s in digest.sections
        ],
        story_count=digest.story_count,
        word_count=digest.word_count,
        format=digest.format,
        raw=digest.raw,
        cached=digest.cached,
    )
