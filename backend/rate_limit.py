"""
Rate limiting middleware for API protection.

Uses slowapi to limit requests per IP address, preventing:
- DoS attacks
- API abuse
- Excessive LLM API costs from summarization spam
"""

from slowapi import Limiter
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded
from slowapi.middleware import SlowAPIMiddleware

from fastapi import Request
from fastapi.responses import JSONResponse

from .config import config


def get_rate_limit() -> str:
    """Get rate limit from config, defaulting to 60/minute."""
    limit = config.RATE_LIMIT_PER_MINUTE
    if limit <= 0:
        # Rate limiting disabled
        return "1000000/minute"  # Effectively unlimited
    return f"{limit}/minute"


# Create limiter with IP-based key
limiter = Limiter(
    key_func=get_remote_address,
    default_limits=[get_rate_limit()],
    storage_uri="memory://",  # In-memory storage (resets on restart)
)


def rate_limit_exceeded_handler(request: Request, exc: RateLimitExceeded) -> JSONResponse:
    """Custom handler for rate limit exceeded errors."""
    return JSONResponse(
        status_code=429,
        content={
            "detail": f"Rate limit exceeded: {exc.detail}",
            "retry_after": getattr(exc, "retry_after", 60),
        },
        headers={"Retry-After": str(getattr(exc, "retry_after", 60))},
    )


def setup_rate_limiting(app):
    """
    Configure rate limiting for a FastAPI app.

    Call this during app startup to enable rate limiting.
    """
    # Add rate limiter state to app
    app.state.limiter = limiter

    # Add middleware
    app.add_middleware(SlowAPIMiddleware)

    # Add exception handler
    app.add_exception_handler(RateLimitExceeded, rate_limit_exceeded_handler)
