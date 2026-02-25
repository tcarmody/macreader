"""
Notification routes: rules management and history.
"""

from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException

from ..auth import verify_api_key, require_admin
from ..config import get_db, state
from ..database import Database
from ..exceptions import require_feed, require_rule
from ..schemas import (
    NotificationRuleResponse,
    CreateNotificationRuleRequest,
    UpdateNotificationRuleRequest,
    NotificationHistoryResponse,
    NotificationMatchResponse,
    PendingNotificationsResponse,
)

router = APIRouter(
    prefix="/notifications",
    tags=["notifications"],
    dependencies=[Depends(verify_api_key)]
)


# ─────────────────────────────────────────────────────────────
# Notification Rules
# ─────────────────────────────────────────────────────────────

@router.get("/rules")
async def list_rules(
    db: Annotated[Database, Depends(get_db)],
    enabled_only: bool = False
) -> list[NotificationRuleResponse]:
    """List all notification rules."""
    rules = db.get_notification_rules(enabled_only=enabled_only)

    # Build feed name lookup
    feeds = {f.id: f.name for f in db.get_feeds()}

    return [
        NotificationRuleResponse.from_db(
            rule,
            feed_name=feeds.get(rule.feed_id) if rule.feed_id else None
        )
        for rule in rules
    ]


@router.post("/rules")
async def create_rule(
    request: CreateNotificationRuleRequest,
    db: Annotated[Database, Depends(get_db)],
    _admin: Annotated[int, Depends(require_admin)] = 0
) -> NotificationRuleResponse:
    """Create a new notification rule."""
    # Validate feed_id if provided
    feed_name = None
    if request.feed_id:
        feed = require_feed(db.get_feed(request.feed_id))
        feed_name = feed.name

    # Validate priority
    if request.priority not in ("high", "normal", "low"):
        raise HTTPException(
            status_code=400,
            detail="Priority must be 'high', 'normal', or 'low'"
        )

    # At least one filter should be set (keyword, author, or feed)
    if not request.keyword and not request.author and not request.feed_id:
        raise HTTPException(
            status_code=400,
            detail="Rule must have at least one filter (keyword, author, or feed)"
        )

    rule_id = db.add_notification_rule(
        name=request.name,
        feed_id=request.feed_id,
        keyword=request.keyword,
        author=request.author,
        priority=request.priority,
    )

    rule = db.get_notification_rule(rule_id)
    if not rule:
        raise HTTPException(status_code=500, detail="Failed to create rule")

    return NotificationRuleResponse.from_db(rule, feed_name=feed_name)


@router.get("/rules/{rule_id}")
async def get_rule(
    rule_id: int,
    db: Annotated[Database, Depends(get_db)]
) -> NotificationRuleResponse:
    """Get a single notification rule."""
    rule = require_rule(db.get_notification_rule(rule_id))

    feed_name = None
    if rule.feed_id:
        feed = db.get_feed(rule.feed_id)
        feed_name = feed.name if feed else None

    return NotificationRuleResponse.from_db(rule, feed_name=feed_name)


@router.put("/rules/{rule_id}")
async def update_rule(
    rule_id: int,
    request: UpdateNotificationRuleRequest,
    db: Annotated[Database, Depends(get_db)],
    _admin: Annotated[int, Depends(require_admin)] = 0
) -> NotificationRuleResponse:
    """Update a notification rule."""
    require_rule(db.get_notification_rule(rule_id))

    # Validate feed_id if being set
    if request.feed_id:
        require_feed(db.get_feed(request.feed_id))

    # Validate priority if being set
    if request.priority and request.priority not in ("high", "normal", "low"):
        raise HTTPException(
            status_code=400,
            detail="Priority must be 'high', 'normal', or 'low'"
        )

    db.update_notification_rule(
        rule_id=rule_id,
        name=request.name,
        feed_id=request.feed_id,
        clear_feed=request.clear_feed,
        keyword=request.keyword,
        clear_keyword=request.clear_keyword,
        author=request.author,
        clear_author=request.clear_author,
        priority=request.priority,
        enabled=request.enabled,
    )

    updated_rule = db.get_notification_rule(rule_id)
    if not updated_rule:
        raise HTTPException(status_code=500, detail="Failed to retrieve updated rule")

    feed_name = None
    if updated_rule.feed_id:
        feed = db.get_feed(updated_rule.feed_id)
        feed_name = feed.name if feed else None

    return NotificationRuleResponse.from_db(updated_rule, feed_name=feed_name)


@router.delete("/rules/{rule_id}")
async def delete_rule(
    rule_id: int,
    db: Annotated[Database, Depends(get_db)],
    _admin: Annotated[int, Depends(require_admin)] = 0
) -> dict:
    """Delete a notification rule."""
    require_rule(db.get_notification_rule(rule_id))
    db.delete_notification_rule(rule_id)
    return {"success": True}


# ─────────────────────────────────────────────────────────────
# Notification History
# ─────────────────────────────────────────────────────────────

@router.get("/history")
async def get_history(
    db: Annotated[Database, Depends(get_db)],
    limit: int = 50,
    offset: int = 0,
    include_dismissed: bool = False
) -> list[NotificationHistoryResponse]:
    """Get notification history."""
    history = db.get_notification_history(
        limit=limit,
        offset=offset,
        include_dismissed=include_dismissed
    )

    # Build lookups for article titles and rule names
    article_ids = [h.article_id for h in history]
    rule_ids = [h.rule_id for h in history if h.rule_id]

    # Fetch articles
    articles = {}
    for article_id in set(article_ids):
        article = db.get_article(article_id)
        if article:
            articles[article_id] = article.title

    # Fetch rules
    rules = {}
    for rule_id in set(rule_ids):
        rule = db.get_notification_rule(rule_id)
        if rule:
            rules[rule_id] = rule.name

    return [
        NotificationHistoryResponse.from_db(
            h,
            article_title=articles.get(h.article_id),
            rule_name=rules.get(h.rule_id) if h.rule_id else None,
        )
        for h in history
    ]


@router.post("/history/{history_id}/dismiss")
async def dismiss_notification(
    history_id: int,
    db: Annotated[Database, Depends(get_db)]
) -> dict:
    """Dismiss a notification."""
    db.dismiss_notification(history_id)
    return {"success": True}


@router.post("/history/dismiss-all")
async def dismiss_all_notifications(
    db: Annotated[Database, Depends(get_db)]
) -> dict:
    """Dismiss all notifications."""
    db.dismiss_all_notifications()
    return {"success": True}


@router.delete("/history/clear-old")
async def clear_old_history(
    db: Annotated[Database, Depends(get_db)],
    days: int = 30
) -> dict:
    """Clear notification history older than specified days."""
    db.clear_old_notification_history(days=days)
    return {"success": True}


# ─────────────────────────────────────────────────────────────
# Pending Notifications (from last refresh)
# ─────────────────────────────────────────────────────────────

@router.get("/pending")
async def get_pending_notifications() -> PendingNotificationsResponse:
    """
    Get notifications that were triggered during the last feed refresh.

    These are articles that matched notification rules and should be
    displayed to the user. After retrieval, these are cleared from memory
    (but remain in history).
    """
    matches = state.last_refresh_notifications
    notifications = [
        NotificationMatchResponse(
            article_id=m.article_id,
            article_title=m.article_title,
            feed_id=m.feed_id,
            rule_id=m.rule_id,
            rule_name=m.rule_name,
            priority=m.priority,
            match_reason=m.match_reason,
        )
        for m in matches
    ]

    # Clear after retrieval
    state.last_refresh_notifications = []

    return PendingNotificationsResponse(
        count=len(notifications),
        notifications=notifications
    )
