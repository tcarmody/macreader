"""
JavaScript Renderer - Render dynamic content using Playwright.

Handles:
- JavaScript-heavy sites (SPAs, infinite scroll)
- Lazy-loaded content
- Content behind client-side rendering

Requires: playwright package and browser binaries
Install with: pip install playwright && playwright install chromium
"""

import asyncio
import logging
from dataclasses import dataclass
from typing import Optional

logger = logging.getLogger(__name__)

# Playwright is optional - only import if available
try:
    from playwright.async_api import async_playwright, Browser, Page, TimeoutError as PlaywrightTimeout
    PLAYWRIGHT_AVAILABLE = True
except ImportError:
    PLAYWRIGHT_AVAILABLE = False
    logger.info("Playwright not installed - JS rendering disabled")


@dataclass
class RenderResult:
    """Result of rendering a page with JavaScript."""
    url: str
    html: str
    final_url: str
    success: bool
    error: str | None = None


class JSRenderer:
    """
    Renders JavaScript-heavy pages using a headless browser.

    Uses Playwright with Chromium for reliable rendering.
    Implements connection pooling to avoid browser startup overhead.
    """

    def __init__(
        self,
        timeout: int = 45000,  # milliseconds - increased for slow sites
        scroll_to_load: bool = True,
        max_scrolls: int = 3,
    ):
        """
        Initialize the JS renderer.

        Args:
            timeout: Page load timeout in milliseconds
            scroll_to_load: Scroll page to trigger lazy loading
            max_scrolls: Maximum number of scroll iterations
        """
        self.timeout = timeout
        self.scroll_to_load = scroll_to_load
        self.max_scrolls = max_scrolls

        self._playwright = None
        self._browser: Optional["Browser"] = None
        self._lock = asyncio.Lock()

    @property
    def is_available(self) -> bool:
        """Check if Playwright is installed and available."""
        return PLAYWRIGHT_AVAILABLE

    async def start(self) -> None:
        """Start the browser instance."""
        if not PLAYWRIGHT_AVAILABLE:
            raise RuntimeError("Playwright is not installed. Run: pip install playwright && playwright install chromium")

        async with self._lock:
            if self._browser is None:
                self._playwright = await async_playwright().start()
                self._browser = await self._playwright.chromium.launch(
                    headless=True,
                    args=[
                        "--disable-gpu",
                        "--disable-dev-shm-usage",
                        "--disable-setuid-sandbox",
                        "--no-sandbox",
                        # Stealth args to avoid detection
                        "--disable-blink-features=AutomationControlled",
                        "--disable-infobars",
                        "--window-size=1920,1080",
                        "--start-maximized",
                    ]
                )
                logger.info("Started Playwright browser")

    async def stop(self) -> None:
        """Stop the browser instance."""
        async with self._lock:
            if self._browser:
                await self._browser.close()
                self._browser = None
            if self._playwright:
                await self._playwright.stop()
                self._playwright = None
                logger.info("Stopped Playwright browser")

    async def render(self, url: str) -> RenderResult:
        """
        Render a page and return the resulting HTML.

        Args:
            url: URL to render

        Returns:
            RenderResult with rendered HTML content
        """
        if not PLAYWRIGHT_AVAILABLE:
            return RenderResult(
                url=url,
                html="",
                final_url=url,
                success=False,
                error="Playwright not installed"
            )

        # Ensure browser is started
        if self._browser is None:
            await self.start()

        page: Optional["Page"] = None
        try:
            # Create a new page/context for this request with stealth settings
            context = await self._browser.new_context(
                user_agent=(
                    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                    "AppleWebKit/537.36 (KHTML, like Gecko) "
                    "Chrome/122.0.0.0 Safari/537.36"
                ),
                viewport={"width": 1920, "height": 1080},
                java_script_enabled=True,
                locale="en-US",
                timezone_id="America/New_York",
                # Add realistic browser properties
                extra_http_headers={
                    "Accept-Language": "en-US,en;q=0.9",
                    "Accept-Encoding": "gzip, deflate, br",
                    "Sec-Ch-Ua": '"Chromium";v="122", "Not(A:Brand";v="24", "Google Chrome";v="122"',
                    "Sec-Ch-Ua-Mobile": "?0",
                    "Sec-Ch-Ua-Platform": '"macOS"',
                },
            )

            page = await context.new_page()

            # Inject stealth scripts to hide automation indicators
            await page.add_init_script("""
                // Override navigator.webdriver
                Object.defineProperty(navigator, 'webdriver', {
                    get: () => undefined
                });

                // Override navigator.plugins to look like a real browser
                Object.defineProperty(navigator, 'plugins', {
                    get: () => [
                        { name: 'Chrome PDF Plugin', filename: 'internal-pdf-viewer' },
                        { name: 'Chrome PDF Viewer', filename: 'mhjfbmdgcfjbbpaeojofohoefgiehjai' },
                        { name: 'Native Client', filename: 'internal-nacl-plugin' }
                    ]
                });

                // Override navigator.languages
                Object.defineProperty(navigator, 'languages', {
                    get: () => ['en-US', 'en']
                });

                // Override permissions query
                const originalQuery = window.navigator.permissions.query;
                window.navigator.permissions.query = (parameters) => (
                    parameters.name === 'notifications' ?
                        Promise.resolve({ state: Notification.permission }) :
                        originalQuery(parameters)
                );

                // Hide automation-related Chrome properties
                window.chrome = {
                    runtime: {},
                    loadTimes: function() {},
                    csi: function() {},
                    app: {}
                };

                // Override console.debug to prevent detection via console
                const originalDebug = console.debug;
                console.debug = function(...args) {
                    if (args[0] && typeof args[0] === 'string' && args[0].includes('puppeteer')) {
                        return;
                    }
                    return originalDebug.apply(console, args);
                };
            """)

            # Block unnecessary resources to speed up loading
            await page.route("**/*.{png,jpg,jpeg,gif,webp,svg,ico}", lambda route: route.abort())
            await page.route("**/*", self._filter_requests)

            # Navigate to the page - use domcontentloaded for faster initial load
            # then wait for content to appear
            response = await page.goto(url, timeout=self.timeout, wait_until="domcontentloaded")

            if not response:
                return RenderResult(
                    url=url,
                    html="",
                    final_url=url,
                    success=False,
                    error="No response received"
                )

            # Wait for article content to load (try common selectors)
            try:
                await page.wait_for_selector(
                    "article, [role='main'], .article-content, .story-body, .post-content, main",
                    timeout=10000  # 10 seconds for content to appear
                )
            except Exception:
                # If no article selector found, just wait a bit
                await page.wait_for_timeout(2000)

            # Scroll to trigger lazy loading
            if self.scroll_to_load:
                await self._scroll_page(page)

            # Wait a bit for any final rendering
            await page.wait_for_timeout(1000)

            # Get the final HTML
            html = await page.content()
            final_url = page.url

            await context.close()

            return RenderResult(
                url=url,
                html=html,
                final_url=final_url,
                success=True
            )

        except PlaywrightTimeout:
            logger.warning(f"Timeout rendering {url}")
            return RenderResult(
                url=url,
                html="",
                final_url=url,
                success=False,
                error="Page load timeout"
            )
        except Exception as e:
            logger.error(f"Error rendering {url}: {e}")
            return RenderResult(
                url=url,
                html="",
                final_url=url,
                success=False,
                error=str(e)
            )
        finally:
            if page:
                try:
                    await page.close()
                except Exception:
                    pass

    async def _filter_requests(self, route) -> None:
        """Filter out unnecessary requests to speed up rendering."""
        url = route.request.url

        # Block known tracking/analytics domains
        blocked_domains = [
            "google-analytics.com",
            "googletagmanager.com",
            "facebook.net",
            "facebook.com/tr",
            "doubleclick.net",
            "googlesyndication.com",
            "adservice.google.com",
            "amazon-adsystem.com",
            "quantserve.com",
            "scorecardresearch.com",
        ]

        for domain in blocked_domains:
            if domain in url:
                await route.abort()
                return

        # Block font files (not needed for content extraction)
        if any(ext in url for ext in [".woff", ".woff2", ".ttf", ".otf"]):
            await route.abort()
            return

        await route.continue_()

    async def _scroll_page(self, page: "Page") -> None:
        """Scroll the page to trigger lazy loading."""
        for i in range(self.max_scrolls):
            # Scroll down
            await page.evaluate("window.scrollBy(0, window.innerHeight)")
            await page.wait_for_timeout(300)

        # Scroll back to top
        await page.evaluate("window.scrollTo(0, 0)")
        await page.wait_for_timeout(200)


# Global renderer instance
_renderer: Optional[JSRenderer] = None


async def get_renderer() -> JSRenderer:
    """Get or create the global JS renderer instance."""
    global _renderer
    if _renderer is None:
        _renderer = JSRenderer()
    return _renderer


async def render_url(url: str) -> RenderResult:
    """
    Convenience function to render a single URL.

    Args:
        url: URL to render with JavaScript

    Returns:
        RenderResult with the rendered HTML
    """
    renderer = await get_renderer()
    return await renderer.render(url)


async def shutdown_renderer() -> None:
    """Shutdown the global renderer instance."""
    global _renderer
    if _renderer:
        await _renderer.stop()
        _renderer = None
