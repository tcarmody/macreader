"""
Tests for the archive fallback used by "extract article" and "add to library".

Archive services that don't answer (archive.today tarpits non-browser clients)
must not stall the request past the client's 60s timeout, and a stub page from
one service must not shadow real content from another.
"""

import asyncio
import time

import pytest

from backend.advanced.archive import ArchiveResult, ArchiveService
from backend.advanced.enhanced_fetcher import EnhancedFetcher

URL = "https://paywalled.example.com/story"
ARTICLE_HTML = (
    "<html><head><title>Real Story</title></head><body><article>"
    + "".join(f"<p>Paragraph {i} of the real archived article body text.</p>" for i in range(40))
    + "</article></body></html>"
)
STUB_HTML = "<html><body><p>Nothing here.</p></body></html>"


def _ok(source: str, html: str) -> ArchiveResult:
    return ArchiveResult(url=f"https://{source}/x", original_url=URL, html=html,
                         source=source, cached_date=None, success=True)


def _miss(source: str) -> ArchiveResult:
    return ArchiveResult(url=URL, original_url=URL, html="", source=source,
                         cached_date=None, success=False, error="Not found")


async def _hang(url):
    await asyncio.sleep(3600)


def _service(timeout: float, **funcs) -> ArchiveService:
    service = ArchiveService(timeout=timeout)
    for name, func in funcs.items():
        setattr(service, name, func)
    return service


@pytest.mark.asyncio
async def test_hanging_services_do_not_stack_timeouts():
    """Two hung services must cost one timeout in total, not one each."""
    async def wayback(url):
        return _ok("wayback", ARTICLE_HTML)

    service = _service(
        0.5,
        _fetch_archive_today=_hang,
        _fetch_archive_ph=_hang,
        _fetch_ghostarchive=_hang,
        _fetch_wayback=wayback,
    )

    start = time.monotonic()
    result = await service.fetch(URL)
    elapsed = time.monotonic() - start

    assert result.success and result.source == "wayback"
    assert elapsed < 0.5


@pytest.mark.asyncio
async def test_all_services_hanging_is_bounded_by_one_timeout():
    service = _service(
        0.3,
        _fetch_archive_today=_hang,
        _fetch_archive_ph=_hang,
        _fetch_ghostarchive=_hang,
        _fetch_wayback=_hang,
    )

    start = time.monotonic()
    result = await service.fetch(URL)
    elapsed = time.monotonic() - start

    assert not result.success
    assert elapsed < 0.6


@pytest.mark.asyncio
async def test_stub_success_does_not_shadow_real_content():
    """A service that returns 200 with a stub page must not end the search."""
    async def stub(url):
        return _ok("archive.ph", STUB_HTML)

    async def wayback(url):
        await asyncio.sleep(0.05)
        return _ok("wayback", ARTICLE_HTML)

    async def miss(url):
        return _miss("ghostarchive")

    fetcher = EnhancedFetcher(enable_js_render=False, enable_archive=True)
    fetcher._archive_service = _service(
        1,
        _fetch_archive_today=miss,
        _fetch_archive_ph=stub,
        _fetch_ghostarchive=miss,
        _fetch_wayback=wayback,
    )

    result = await fetcher._fetch_from_archive(URL)

    assert result.fallback_used == "archive"
    assert result.archive_source == "wayback"
    assert "real archived article" in result.content


def test_google_cache_is_not_queried():
    """Google Cache was shut down in 2024; it returns a 200 stub for every URL."""
    assert not hasattr(ArchiveService, "_fetch_google_cache")
