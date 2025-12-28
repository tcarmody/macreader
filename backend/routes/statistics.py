"""
Statistics routes: reading stats, topic history, trends.
"""

from datetime import datetime, timedelta
from typing import Annotated

from fastapi import APIRouter, Depends, Query, HTTPException

from ..auth import verify_api_key
from ..config import state, get_db
from ..database import Database
from ..schemas import (
    ReadingStatsResponse,
    TimePeriod,
    SummarizationStatsResponse,
    TopicStatsResponse,
    TopicInfo,
    TopicTrend,
    ReadingActivityStats,
    TopicClusteringResponse,
    TopicTrendsResponse,
)

router = APIRouter(
    prefix="/statistics",
    tags=["statistics"],
    dependencies=[Depends(verify_api_key)]
)


@router.get("/reading-stats")
async def get_reading_stats(
    db: Annotated[Database, Depends(get_db)],
    period_type: str = Query(default="rolling", pattern="^(rolling|calendar)$"),
    period_value: str = Query(default="30d", pattern="^(7d|30d|90d|week|month|year)$"),
) -> ReadingStatsResponse:
    """
    Get comprehensive reading statistics.

    Period types:
    - rolling: 7d, 30d, 90d (rolling windows from now)
    - calendar: week, month, year (current calendar period)
    """
    # Calculate date range based on period
    now = datetime.now()

    if period_type == "rolling":
        days = int(period_value.rstrip("d"))
        start_date = now - timedelta(days=days)
        end_date = now
    else:  # calendar
        if period_value == "week":
            # Start of current week (Monday)
            start_date = now - timedelta(days=now.weekday())
            start_date = start_date.replace(hour=0, minute=0, second=0, microsecond=0)
        elif period_value == "month":
            # Start of current month
            start_date = now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
        else:  # year
            # Start of current year
            start_date = now.replace(month=1, day=1, hour=0, minute=0, second=0, microsecond=0)
        end_date = now

    # Gather all statistics
    summarization_data = db.statistics.get_summarization_stats(
        start_date=start_date, end_date=end_date
    )
    reading_data = db.statistics.get_reading_stats(
        start_date=start_date, end_date=end_date
    )

    # Get topic data
    topic_history = db.statistics.get_topic_history(
        start_date=start_date, end_date=end_date, limit=50
    )
    topic_trends = db.statistics.get_topic_trends(
        days=(end_date - start_date).days or 30, top_n=10
    )
    most_common = db.statistics.get_most_common_topics(limit=10)

    # Convert topic history to current topics (most recent clustering)
    current_topics: list[TopicInfo] = []
    if topic_history:
        # Get topics from the most recent clustering run
        latest_clustered_at = topic_history[0].clustered_at
        for th in topic_history:
            if th.clustered_at == latest_clustered_at:
                current_topics.append(TopicInfo(
                    label=th.topic_label,
                    count=th.article_count,
                    article_ids=th.article_ids
                ))

    # Build response
    return ReadingStatsResponse(
        period=TimePeriod(type=period_type, value=period_value),
        period_start=start_date.isoformat(),
        period_end=end_date.isoformat(),
        summarization=SummarizationStatsResponse(
            total_articles=summarization_data["total_articles"],
            summarized_articles=summarization_data["summarized_articles"],
            summarization_rate=summarization_data["summarization_rate"],
            model_breakdown=summarization_data["model_breakdown"],
            avg_per_day=summarization_data["avg_per_day"],
            avg_per_week=summarization_data["avg_per_week"],
            period_start=summarization_data["period_start"],
            period_end=summarization_data["period_end"],
        ),
        topics=TopicStatsResponse(
            current_topics=current_topics,
            topic_trends=[
                TopicTrend(
                    topic_hash=t["topic_hash"],
                    label=t["label"],
                    total_count=t["total_count"],
                    cluster_count=t["cluster_count"]
                )
                for t in topic_trends
            ],
            most_common=[
                TopicInfo(label=t["label"], count=t["count"])
                for t in most_common
            ]
        ),
        reading=ReadingActivityStats(
            articles_read=reading_data["articles_read"],
            total_reading_time_minutes=reading_data["total_reading_time_minutes"],
            avg_reading_time_minutes=reading_data["avg_reading_time_minutes"],
            bookmarks_added=reading_data["bookmarks_added"],
            read_by_day=reading_data["read_by_day"],
            read_by_feed=reading_data["read_by_feed"],
        )
    )


@router.post("/topics/cluster")
async def trigger_topic_clustering(
    db: Annotated[Database, Depends(get_db)],
    days: int = Query(default=7, ge=1, le=90),
    persist: bool = Query(default=True),
) -> TopicClusteringResponse:
    """
    Trigger topic clustering for recent articles and optionally persist results.
    """
    if not state.clusterer:
        raise HTTPException(
            status_code=503,
            detail="Topic clustering unavailable: LLM API key not configured"
        )

    # Get articles from the specified period
    cutoff = datetime.now() - timedelta(days=days)
    articles = db.articles.get_many(limit=500)  # Get recent articles

    # Filter to articles within the period
    articles = [
        a for a in articles
        if (a.published_at and a.published_at >= cutoff) or
           (not a.published_at and a.created_at >= cutoff)
    ]

    if not articles:
        return TopicClusteringResponse(
            topics=[],
            total_articles=0,
            persisted=False
        )

    # Cluster articles
    result = await state.clusterer.cluster_async(articles)

    # Persist if requested
    if persist:
        db.statistics.save_topic_clustering(
            topics=[
                {"label": t.label, "article_ids": t.article_ids}
                for t in result.topics
            ],
            period_start=cutoff,
            period_end=datetime.now()
        )

    return TopicClusteringResponse(
        topics=[
            TopicInfo(
                label=t.label,
                count=len(t.article_ids),
                article_ids=t.article_ids
            )
            for t in result.topics
        ],
        total_articles=len(articles),
        persisted=persist
    )


@router.get("/topics/trends")
async def get_topic_trends(
    db: Annotated[Database, Depends(get_db)],
    days: int = Query(default=30, ge=7, le=365),
    top_n: int = Query(default=10, ge=1, le=50),
) -> TopicTrendsResponse:
    """Get topic frequency trends over time."""
    trends = db.statistics.get_topic_trends(days=days, top_n=top_n)
    return TopicTrendsResponse(
        trends=[
            TopicTrend(
                topic_hash=t["topic_hash"],
                label=t["label"],
                total_count=t["total_count"],
                cluster_count=t["cluster_count"]
            )
            for t in trends
        ],
        days=days
    )
