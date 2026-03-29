"""
Digest routes: newsletter assembly endpoints.
"""

from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException

from ..auth import verify_api_key, get_current_user
from ..config import state, get_db
from ..database import Database
from ..schemas import (
    BatchBriefRequest,
    BatchBriefResponse,
    BatchBriefResult,
)

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
