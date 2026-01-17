"""
HTTP exception utilities for common error patterns.

Provides helper functions to reduce boilerplate for common 404 and validation errors.
"""

from typing import TypeVar

from fastapi import HTTPException

T = TypeVar("T")


def require_resource(resource: T | None, detail: str = "Resource not found") -> T:
    """
    Raise 404 if resource is None, otherwise return the resource.

    Usage:
        article = require_resource(db.get_article(id), "Article not found")
    """
    if resource is None:
        raise HTTPException(status_code=404, detail=detail)
    return resource


def require_article(article: T | None) -> T:
    """Raise 404 if article is None."""
    return require_resource(article, "Article not found")


def require_feed(feed: T | None) -> T:
    """Raise 404 if feed is None."""
    return require_resource(feed, "Feed not found")


def require_item(item: T | None) -> T:
    """Raise 404 if library item is None."""
    return require_resource(item, "Item not found in library")


def require_rule(rule: T | None) -> T:
    """Raise 404 if notification rule is None."""
    return require_resource(rule, "Rule not found")
