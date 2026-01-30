"""
Background tasks for feed fetching and article summarization.
"""

import asyncio
import re
from bs4 import BeautifulSoup

from .config import state
from .source_extractor import SourceExtractor
from .notification_service import NotificationService, NotificationMatch


def _is_usable_content(content: str) -> bool:
    """
    Check if content is usable for summarization.

    Returns False if content is just aggregator redirect links or
    other non-article content.
    """
    if not content or len(content.strip()) < 50:
        return False

    # Parse HTML to extract text
    soup = BeautifulSoup(content, "html.parser")
    text = soup.get_text(separator=" ", strip=True)

    # Check if mostly just links (common with Google News aggregator content)
    links = soup.find_all("a")
    if links:
        # Calculate ratio of link text to total text
        link_text = " ".join(a.get_text(strip=True) for a in links)
        if len(link_text) > len(text) * 0.8:
            return False

    # Check for very short text content after stripping HTML
    if len(text) < 100:
        return False

    # Check if content looks like a news aggregator list (numbered headlines)
    # Pattern: lots of short lines that look like headlines
    lines = [line.strip() for line in text.split("\n") if line.strip()]
    if len(lines) > 3:
        short_lines = sum(1 for line in lines if len(line) < 100)
        if short_lines > len(lines) * 0.8:
            # Most lines are short, check if they're numbered/bulleted
            numbered = sum(1 for line in lines if re.match(r"^\d+[\.\)]\s", line))
            if numbered > len(lines) * 0.5:
                return False

    return True


def _fetch_content_sync(url: str) -> str | None:
    """Synchronously fetch content from a URL using the configured fetcher."""
    if not state.fetcher:
        return None

    try:
        # Run async fetch in a new event loop
        loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)
        try:
            result = loop.run_until_complete(state.fetcher.fetch(url))
            return result.content if result.content else None
        finally:
            loop.close()
    except Exception as e:
        print(f"Failed to fetch content from {url}: {e}")
        return None


def _extract_source_sync(url: str, content: str) -> str | None:
    """Synchronously extract source URL from aggregator content."""
    extractor = SourceExtractor()
    if not extractor.is_aggregator(url):
        return None

    try:
        loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)
        try:
            result = loop.run_until_complete(extractor.extract(url, content))
            return result.source_url
        finally:
            loop.close()
    except Exception as e:
        print(f"Failed to extract source URL from {url}: {e}")
        return None


def summarize_article(article_id: int, content: str, url: str, title: str):
    """Background task to summarize an article (sync version for BackgroundTasks)."""
    if not state.summarizer or not state.db:
        print(f"Summarizer not configured for article {article_id}")
        return

    # First check: basic content existence
    if not content or len(content.strip()) < 50:
        print(f"Article {article_id} has insufficient content for summarization")
        return

    # Second check: is the content actually usable (not just aggregator links)?
    working_content = content
    if not _is_usable_content(content):
        print(f"Article {article_id} content appears to be aggregator links, trying to fetch real content")

        # Try to get source URL and fetch real content
        source_url = _extract_source_sync(url, content)
        if source_url:
            print(f"Article {article_id}: Found source URL {source_url}")
            fetched = _fetch_content_sync(source_url)
            if fetched and _is_usable_content(fetched):
                working_content = fetched
                # Update the article with fetched content
                state.db.update_article_content(article_id, fetched)
                state.db.update_article_source_url(article_id, source_url)
                print(f"Article {article_id}: Fetched content from source URL")
            else:
                print(f"Article {article_id}: Could not fetch usable content from source URL")
                return
        else:
            # Try fetching directly from the original URL
            fetched = _fetch_content_sync(url)
            if fetched and _is_usable_content(fetched):
                working_content = fetched
                state.db.update_article_content(article_id, fetched)
                print(f"Article {article_id}: Fetched content from original URL")
            else:
                print(f"Article {article_id}: Content is not suitable for summarization (aggregator links only)")
                return

    try:
        print(f"Starting summarization for article {article_id}")
        summary = state.summarizer.summarize(working_content, url, title)
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


def fetch_related_links_task(article_id: int):
    """Background task to fetch related links for an article (sync version for BackgroundTasks)."""
    if not state.exa_service or not state.db:
        print(f"Exa service not configured for article {article_id}")
        return

    try:
        print(f"Fetching related links for article {article_id}")

        # Get article from database
        article = state.db.get_article(article_id)
        if not article:
            print(f"Article {article_id} not found")
            return

        # Fetch related links using Exa service
        links = state.exa_service.fetch_related_links(article, num_results=5)

        # Store results as JSON
        import json
        from datetime import datetime

        related_links_json = json.dumps({
            "links": links,
            "fetched_at": datetime.now().isoformat(),
            "source": "exa"
        })

        # Also store extracted keywords if they were generated during query construction
        # The extract_keywords_llm function caches keywords in the article object
        from .services.related_links import extract_keywords_llm
        keywords = None
        if article.content and not article.key_points:
            # Keywords may have been extracted during query construction
            keywords = extract_keywords_llm(article, state.provider)

        # Update database
        with state.db._connection.conn() as conn:
            if keywords:
                keywords_json = json.dumps(keywords)
                conn.execute(
                    "UPDATE articles SET related_links = ?, extracted_keywords = ? WHERE id = ?",
                    (related_links_json, keywords_json, article_id)
                )
            else:
                conn.execute(
                    "UPDATE articles SET related_links = ? WHERE id = ?",
                    (related_links_json, article_id)
                )

        print(f"Successfully fetched {len(links)} related links for article {article_id}")

    except Exception as e:
        print(f"Error fetching related links for article {article_id}: {e}")
        import traceback
        traceback.print_exc()


async def refresh_all_feeds():
    """Background task to refresh all feeds."""
    if not state.db or not state.feed_parser:
        return

    state.refresh_in_progress = True
    state.last_refresh_notifications = []  # Clear previous notifications
    try:
        feeds = state.db.get_feeds()
        for feed in feeds:
            matches = await refresh_single_feed(feed.id, feed.url)
            state.last_refresh_notifications.extend(matches)
    finally:
        state.refresh_in_progress = False


async def refresh_single_feed(feed_id: int, feed_url: str) -> list[NotificationMatch]:
    """Refresh a single feed. Returns notification matches."""
    if not state.db or not state.feed_parser:
        return []

    # Skip newsletter feeds - they're fetched via Gmail, not RSS
    if feed_url.startswith("newsletter://"):
        print(f"Skipping newsletter feed {feed_id}: {feed_url}")
        return []

    try:
        feed = await state.feed_parser.fetch(feed_url)
        matches = await fetch_feed_articles(feed_id, feed)
        state.db.update_feed_fetched(feed_id)
        return matches
    except Exception as e:
        state.db.update_feed_fetched(feed_id, error=str(e))
        print(f"Error refreshing feed {feed_id}: {e}")
        return []


async def fetch_feed_articles(feed_id: int, feed) -> list[NotificationMatch]:
    """
    Add articles from a parsed feed to the database.

    Returns a list of NotificationMatch objects for articles that matched
    notification rules (for the caller to handle, e.g., send to client).
    """
    if not state.db or not state.fetcher:
        return []

    notification_matches: list[NotificationMatch] = []
    notification_service = NotificationService(state.db)

    for item in feed.items:
        if not item.url:
            continue

        # Check if article already exists
        existing = state.db.get_article_by_url(item.url)
        if existing:
            continue

        # Fetch full content if feed only has summary
        content = item.content
        reading_time = None
        word_count = None
        featured_image = None
        has_code_blocks = False
        site_name = None

        if len(content) < 500 and state.fetcher:
            try:
                result = await state.fetcher.fetch(item.url)
                content = result.content
                # Extract enhanced metadata from fetcher result
                reading_time = result.reading_time_minutes
                word_count = result.word_count
                featured_image = result.featured_image
                has_code_blocks = result.has_code_blocks
                site_name = result.site_name
            except Exception:
                pass  # Use feed content as fallback

        # Add article (with source_url if available from aggregator)
        article_id = state.db.add_article(
            feed_id=feed_id,
            url=item.url,
            title=item.title,
            content=content,
            author=item.author,
            published_at=item.published,
            source_url=item.source_url,
            reading_time_minutes=reading_time,
            word_count=word_count,
            featured_image=featured_image,
            has_code_blocks=has_code_blocks,
            site_name=site_name,
        )

        if article_id:
            # Check for notification rules match
            article = state.db.get_article(article_id)
            if article:
                match = notification_service.evaluate_and_record(article)
                if match:
                    notification_matches.append(match)
                    print(f"Notification match for article {article_id}: {match.match_reason}")

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

    return notification_matches
