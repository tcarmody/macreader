"""
Service layer for business logic.

Services encapsulate business logic, keeping routes as thin HTTP adapters.
Each service receives its dependencies via constructor injection.

Usage in routes:
    from ..services import get_article_service, ArticleService

    @router.get("/articles")
    async def list_articles(
        service: Annotated[ArticleService, Depends(get_article_service)],
        user_id: Annotated[int, Depends(get_current_user)]
    ):
        return service.list_articles(user_id=user_id)
"""

from typing import Annotated

from fastapi import Depends

from ..config import state, get_db
from ..database import Database

from .article_service import ArticleService
from .feed_service import FeedService
from .library_service import LibraryService

__all__ = [
    # Services
    "ArticleService",
    "FeedService",
    "LibraryService",
    # Dependency factories
    "get_article_service",
    "get_feed_service",
    "get_library_service",
    # Type aliases for dependency injection
    "ArticleServiceDep",
    "FeedServiceDep",
    "LibraryServiceDep",
]


def get_article_service(db: Annotated[Database, Depends(get_db)]) -> ArticleService:
    """Dependency to get ArticleService instance."""
    return ArticleService(
        db=db,
        fetcher=state.fetcher,
        enhanced_fetcher=state.enhanced_fetcher,
        summarizer=state.summarizer,
        clusterer=state.clusterer,
    )


def get_feed_service(db: Annotated[Database, Depends(get_db)]) -> FeedService:
    """Dependency to get FeedService instance."""
    return FeedService(
        db=db,
        feed_parser=state.feed_parser,
    )


def get_library_service(db: Annotated[Database, Depends(get_db)]) -> LibraryService:
    """Dependency to get LibraryService instance."""
    return LibraryService(
        db=db,
        fetcher=state.fetcher,
        enhanced_fetcher=state.enhanced_fetcher,
        summarizer=state.summarizer,
    )


# Re-export the service factories for convenience
ArticleServiceDep = Annotated[ArticleService, Depends(get_article_service)]
FeedServiceDep = Annotated[FeedService, Depends(get_feed_service)]
LibraryServiceDep = Annotated[LibraryService, Depends(get_library_service)]
