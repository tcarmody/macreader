"""
Summarization routes: single URL and batch summarization.
"""

import asyncio

from typing import Annotated

from fastapi import APIRouter, Depends, Header, HTTPException

from ..auth import verify_api_key
from ..config import state
from ..services.summarizer_selection import select_summarizer
from ..schemas import (
    SummarizeRequest,
    BatchSummarizeRequest,
    BatchSummarizeResult,
    BatchSummarizeResponse,
)

router = APIRouter(tags=["summarization"], dependencies=[Depends(verify_api_key)])


@router.post("/summarize")
async def summarize_url(
    request: SummarizeRequest,
    x_preferred_provider: Annotated[str | None, Header()] = None,
) -> dict:
    """Summarize a single URL (any webpage, not just feeds)."""
    summarizer = select_summarizer(x_preferred_provider)
    if not summarizer or not state.fetcher:
        raise HTTPException(status_code=503, detail="Summarization not configured")

    try:
        # Fetch content
        result = await state.fetcher.fetch(request.url)

        # Generate summary
        summary = await summarizer.summarize_async(
            result.content,
            result.url,
            result.title
        )

        return {
            "url": result.url,
            "title": result.title,
            "one_liner": summary.one_liner,
            "full_summary": summary.full_summary,
            "key_points": summary.key_points,
            "model_used": summary.model_used.value,
            "cached": summary.cached
        }
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post("/summarize/batch")
async def batch_summarize_urls(
    request: BatchSummarizeRequest,
    x_preferred_provider: Annotated[str | None, Header()] = None,
) -> BatchSummarizeResponse:
    """
    Summarize multiple URLs at once.

    Processes URLs concurrently and returns results for each.
    Useful for summarizing multiple articles or webpages in one request.
    """
    summarizer = select_summarizer(x_preferred_provider)
    if not summarizer or not state.fetcher:
        raise HTTPException(status_code=503, detail="Summarization not configured")

    if not request.urls:
        raise HTTPException(status_code=400, detail="No URLs provided")

    if len(request.urls) > 20:
        raise HTTPException(status_code=400, detail="Maximum 20 URLs per batch")

    async def summarize_single(url: str) -> BatchSummarizeResult:
        """Summarize a single URL, catching errors."""
        try:
            result = await state.fetcher.fetch(url)
            summary = await summarizer.summarize_async(
                result.content,
                result.url,
                result.title
            )
            return BatchSummarizeResult(
                url=url,
                success=True,
                title=result.title,
                one_liner=summary.one_liner,
                full_summary=summary.full_summary,
                key_points=summary.key_points,
                model_used=summary.model_used.value,
                cached=summary.cached
            )
        except Exception as e:
            return BatchSummarizeResult(
                url=url,
                success=False,
                error=str(e)
            )

    # Process all URLs concurrently
    tasks = [summarize_single(url) for url in request.urls]
    results = await asyncio.gather(*tasks)

    successful = sum(1 for r in results if r.success)
    failed = len(results) - successful

    return BatchSummarizeResponse(
        total=len(results),
        successful=successful,
        failed=failed,
        results=results
    )
