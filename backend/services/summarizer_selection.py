"""
Pick the summarizer for the provider the user chose.

The provider is chosen per request, in this order:
1. the `X-Preferred-Provider` header (the web app sends it),
2. the `llm_provider` setting (the Mac app saves it through PUT /settings),
3. the provider the server started with (`state.summarizer`).

A preferred provider with no API key on the server falls back to the default,
so a bad choice degrades to the provider that works instead of failing.
"""

import hashlib
import logging

from dpcommon.llm import create_provider

from ..config import config, state
from ..summarizer import Summarizer

logger = logging.getLogger(__name__)

PROVIDER_KEYS = {
    "anthropic": lambda: config.ANTHROPIC_API_KEY,
    "openai": lambda: config.OPENAI_API_KEY,
    "google": lambda: config.GOOGLE_API_KEY,
}

# (provider name, key fingerprint) -> Summarizer. Keyed by key so a rotated
# key or a client-supplied key gets its own provider rather than a stale one.
_cache: dict[tuple[str, str], Summarizer] = {}
_MAX_CACHED = 8


def clear_cache() -> None:
    _cache.clear()


def preferred_provider_name(header_value: str | None = None) -> str | None:
    """The provider the user asked for, lower-cased, or None for the default."""
    name = (header_value or "").strip().lower()
    if not name and state.db:
        name = (state.db.get_setting("llm_provider", "") or "").strip().lower()
    return name or None


def select_summarizer(header_value: str | None = None) -> Summarizer | None:
    """Summarizer for the preferred provider, else the server default."""
    default = state.summarizer
    name = preferred_provider_name(header_value)
    if not name or name not in PROVIDER_KEYS:
        return default
    if state.provider is not None and state.provider.name == name:
        return default

    key = PROVIDER_KEYS[name]()
    if not key:
        logger.warning(
            "Preferred provider %r has no API key on the server; using %s",
            name, state.provider.name if state.provider else "none",
        )
        return default

    cache_key = (name, hashlib.sha256(key.encode()).hexdigest()[:16])
    summarizer = _cache.get(cache_key)
    if summarizer is None:
        try:
            provider = create_provider(name, key, workspace_id=config.ANTHROPIC_WORKSPACE_ID)
        except Exception as e:
            logger.warning("Could not create %s provider (%s); using the default", name, e)
            return default
        if len(_cache) >= _MAX_CACHED:
            _cache.pop(next(iter(_cache)))
        summarizer = Summarizer(provider=provider, cache=state.cache)
        _cache[cache_key] = summarizer
    return summarizer


def selected_provider_name(header_value: str | None = None) -> str | None:
    """Name of the provider select_summarizer() would use."""
    summarizer = select_summarizer(header_value)
    return summarizer.provider.name if summarizer else None
