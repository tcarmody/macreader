"""
Notification service - Rules engine for smart notifications.

Evaluates articles against notification rules and determines which articles
should trigger notifications.
"""

import re
from dataclasses import dataclass
from datetime import datetime

from backend.database.models import DBArticle, DBNotificationRule


@dataclass
class NotificationMatch:
    """Result of matching an article against notification rules."""
    article_id: int
    article_title: str
    feed_id: int
    rule_id: int
    rule_name: str
    priority: str
    match_reason: str


class NotificationService:
    """
    Evaluates articles against notification rules.

    Rules can match based on:
    - Feed: Only articles from specific feeds
    - Keyword: Title or content contains specific terms
    - Author: Articles by specific authors
    """

    def __init__(self, db):
        self._db = db

    def evaluate_article(
        self,
        article: DBArticle,
    ) -> list[NotificationMatch]:
        """
        Evaluate an article against all enabled notification rules.

        Returns a list of matching rules, sorted by priority (high first).
        """
        # Skip if already notified
        if self._db.was_article_notified(article.id):
            return []

        # Get applicable rules (global + feed-specific)
        rules = self._db.get_notification_rules_for_feed(article.feed_id)

        matches = []
        for rule in rules:
            match_reason = self._check_rule(article, rule)
            if match_reason:
                matches.append(NotificationMatch(
                    article_id=article.id,
                    article_title=article.title,
                    feed_id=article.feed_id,
                    rule_id=rule.id,
                    rule_name=rule.name,
                    priority=rule.priority,
                    match_reason=match_reason,
                ))

        # Sort by priority: high > normal > low
        priority_order = {"high": 0, "normal": 1, "low": 2}
        matches.sort(key=lambda m: priority_order.get(m.priority, 1))

        return matches

    def _check_rule(
        self,
        article: DBArticle,
        rule: DBNotificationRule,
    ) -> str | None:
        """
        Check if an article matches a rule.

        Returns a match reason string if matched, None otherwise.
        """
        # Feed filter: if rule has a specific feed, article must be from that feed
        if rule.feed_id is not None and rule.feed_id != article.feed_id:
            return None

        # If no keyword and no author specified, it's a feed-wide rule
        if rule.keyword is None and rule.author is None:
            if rule.feed_id is not None:
                return "Feed notification"
            # Global rule with no filters - shouldn't match everything
            return None

        # Check keyword match
        if rule.keyword:
            keyword_match = self._match_keyword(
                article.title,
                article.content,
                article.summary_short,
                rule.keyword
            )
            if keyword_match:
                return f"Keyword match: '{rule.keyword}'"

        # Check author match
        if rule.author:
            author_match = self._match_author(article.author, rule.author)
            if author_match:
                return f"Author match: '{rule.author}'"

        return None

    def _match_keyword(
        self,
        title: str | None,
        content: str | None,
        summary: str | None,
        keyword: str,
    ) -> bool:
        """Check if keyword appears in article text (case-insensitive)."""
        keyword_lower = keyword.lower()

        # Check title first (most relevant)
        if title and keyword_lower in title.lower():
            return True

        # Check summary
        if summary and keyword_lower in summary.lower():
            return True

        # Check full content
        if content and keyword_lower in content.lower():
            return True

        return False

    def _match_author(
        self,
        article_author: str | None,
        rule_author: str,
    ) -> bool:
        """Check if article author matches rule author (case-insensitive)."""
        if not article_author:
            return False

        # Exact match or partial match
        return rule_author.lower() in article_author.lower()

    def record_notification(
        self,
        article_id: int,
        rule_id: int | None = None,
    ) -> int:
        """Record that a notification was sent for an article."""
        return self._db.add_notification_history(article_id, rule_id)

    def get_pending_notifications(
        self,
        articles: list[DBArticle],
    ) -> list[NotificationMatch]:
        """
        Evaluate multiple articles and return all matches.

        Useful for batch processing after feed refresh.
        """
        all_matches = []
        for article in articles:
            matches = self.evaluate_article(article)
            all_matches.extend(matches)
        return all_matches

    def evaluate_and_record(
        self,
        article: DBArticle,
    ) -> NotificationMatch | None:
        """
        Evaluate an article and record notification if matched.

        Returns the highest priority match, or None if no match.
        Records the match in notification history.
        """
        matches = self.evaluate_article(article)
        if not matches:
            return None

        # Use highest priority match
        best_match = matches[0]

        # Record in history
        self.record_notification(best_match.article_id, best_match.rule_id)

        return best_match
