"""
Twitter/X content extractor.
"""

from urllib.parse import urlparse

from bs4 import BeautifulSoup

from .base import ExtractedContent, SiteExtractor


class TwitterExtractor(SiteExtractor):
    """Extractor for Twitter/X posts."""

    DOMAINS = ['twitter.com', 'x.com']

    def extract(self, url: str, html: str) -> ExtractedContent:
        soup = BeautifulSoup(html, 'html.parser')

        # Twitter heavily relies on JS, so we get what we can from meta tags

        # Title (usually "Author on Twitter: tweet text")
        title = ""
        if og_title := soup.find('meta', property='og:title'):
            title = og_title.get('content', '')
        elif title_tag := soup.find('title'):
            title = title_tag.get_text(strip=True)

        # Description contains the tweet text
        content = ""
        if og_desc := soup.find('meta', property='og:description'):
            desc = og_desc.get('content', '')
            content = f"<p>{desc}</p>"

        # Author from URL
        author = None
        parsed = urlparse(url)
        path_parts = parsed.path.strip('/').split('/')
        if path_parts:
            author = path_parts[0]

        # Published date - often not available without JS
        published = None

        # Featured image
        featured_image = None
        if og_image := soup.find('meta', property='og:image'):
            img = og_image.get('content', '')
            # Skip profile images
            if 'profile_images' not in img:
                featured_image = img

        return ExtractedContent(
            title=title,
            content=content,
            author=author,
            published=published,
            featured_image=featured_image,
            site_name="X (Twitter)",
            extractor_used="twitter",
        )
