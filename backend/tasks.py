"""
Background tasks for feed fetching and article summarization.
"""

from .config import state


def summarize_article(article_id: int, content: str, url: str, title: str):
    """Background task to summarize an article (sync version for BackgroundTasks)."""
    if not state.summarizer or not state.db:
        print(f"Summarizer not configured for article {article_id}")
        return

    if not content or len(content.strip()) < 50:
        print(f"Article {article_id} has insufficient content for summarization")
        return

    try:
        print(f"Starting summarization for article {article_id}")
        summary = state.summarizer.summarize(content, url, title)
        state.db.update_summary(
            article_id=article_id,
            summary_short=summary.one_liner,
            summary_full=summary.full_summary,
            key_points=summary.key_points,
            model_used=summary.model_used.value
        )
        print(f"Successfully summarized article {article_id}")
    except Exception as e:
        print(f"Error summarizing article {article_id}: {e}")
        import traceback
        traceback.print_exc()


async def refresh_all_feeds():
    """Background task to refresh all feeds."""
    if not state.db or not state.feed_parser:
        return

    state.refresh_in_progress = True
    try:
        feeds = state.db.get_feeds()
        for feed in feeds:
            await refresh_single_feed(feed.id, feed.url)
    finally:
        state.refresh_in_progress = False


async def refresh_single_feed(feed_id: int, feed_url: str):
    """Refresh a single feed."""
    if not state.db or not state.feed_parser:
        return

    try:
        feed = await state.feed_parser.fetch(feed_url)
        await fetch_feed_articles(feed_id, feed)
        state.db.update_feed_fetched(feed_id)
    except Exception as e:
        state.db.update_feed_fetched(feed_id, error=str(e))
        print(f"Error refreshing feed {feed_id}: {e}")


async def fetch_feed_articles(feed_id: int, feed):
    """Add articles from a parsed feed to the database."""
    if not state.db or not state.fetcher:
        return

    for item in feed.items:
        if not item.url:
            continue

        # Check if article already exists
        existing = state.db.get_article_by_url(item.url)
        if existing:
            continue

        # Fetch full content if feed only has summary
        content = item.content
        if len(content) < 500 and state.fetcher:
            try:
                result = await state.fetcher.fetch(item.url)
                content = result.content
            except Exception:
                pass  # Use feed content as fallback

        # Add article
        article_id = state.db.add_article(
            feed_id=feed_id,
            url=item.url,
            title=item.title,
            content=content,
            author=item.author,
            published_at=item.published
        )

        # Auto-summarize only if setting is enabled and API key configured
        auto_summarize = state.db.get_setting("auto_summarize", "false").lower() == "true"
        if article_id and state.summarizer and content and auto_summarize:
            try:
                summary = await state.summarizer.summarize_async(
                    content, item.url, item.title
                )
                state.db.update_summary(
                    article_id=article_id,
                    summary_short=summary.one_liner,
                    summary_full=summary.full_summary,
                    key_points=summary.key_points,
                    model_used=summary.model_used.value
                )
            except Exception as e:
                print(f"Error summarizing article {item.url}: {e}")
