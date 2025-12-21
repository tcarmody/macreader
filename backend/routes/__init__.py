"""
API route modules.
"""

from .articles import router as articles_router
from .feeds import router as feeds_router
from .summarization import router as summarization_router
from .misc import router as misc_router
from .standalone import router as standalone_router

__all__ = [
    "articles_router",
    "feeds_router",
    "summarization_router",
    "misc_router",
    "standalone_router",
]
