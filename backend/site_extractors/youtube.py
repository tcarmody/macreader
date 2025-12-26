"""
YouTube video content extractor.
"""

import re
from urllib.parse import parse_qs, urlparse

from bs4 import BeautifulSoup

from .base import ExtractedContent, SiteExtractor


class YouTubeExtractor(SiteExtractor):
    """Extractor for YouTube video pages."""

    DOMAINS = ['youtube.com', 'youtu.be']

    def extract(self, url: str, html: str) -> ExtractedContent:
        soup = BeautifulSoup(html, 'html.parser')

        # Extract video ID
        video_id = None
        parsed = urlparse(url)
        if 'youtu.be' in parsed.netloc:
            video_id = parsed.path.strip('/')
        elif 'youtube.com' in parsed.netloc:
            if parsed.path == '/watch':
                params = parse_qs(parsed.query)
                video_id = params.get('v', [None])[0]
            elif '/shorts/' in parsed.path:
                video_id = parsed.path.split('/shorts/')[-1].split('/')[0]

        # Title
        title = ""
        if title_meta := soup.find('meta', {'name': 'title'}):
            title = title_meta.get('content', '')
        elif title_tag := soup.find('title'):
            title = title_tag.get_text(strip=True)
            title = re.sub(r'\s*-\s*YouTube$', '', title)

        # Author/Channel
        author = None
        if channel_name := soup.find('link', {'itemprop': 'name'}):
            author = channel_name.get('content')
        elif author_meta := soup.find('meta', {'itemprop': 'author'}):
            author = author_meta.get('content')

        # Published date
        published = None
        if date_meta := soup.find('meta', {'itemprop': 'datePublished'}):
            published = date_meta.get('content')

        # Description
        content = ""
        if desc_meta := soup.find('meta', {'name': 'description'}):
            desc = desc_meta.get('content', '')
            content = f"<p>{desc}</p>"

        # Featured image (thumbnail)
        featured_image = None
        if og_image := soup.find('meta', property='og:image'):
            featured_image = og_image.get('content')
        elif video_id:
            featured_image = f"https://img.youtube.com/vi/{video_id}/maxresdefault.jpg"

        # Video embed URL
        video_embed_url = None
        if video_id:
            video_embed_url = f"https://www.youtube.com/embed/{video_id}"

        # Categories/tags from keywords
        categories = []
        if keywords_meta := soup.find('meta', {'name': 'keywords'}):
            keywords = keywords_meta.get('content', '')
            categories = [k.strip() for k in keywords.split(',')[:5]]  # First 5

        return ExtractedContent(
            title=title,
            content=content,
            author=author,
            published=published,
            categories=categories,
            featured_image=featured_image,
            has_video=True,
            video_embed_url=video_embed_url,
            site_name="YouTube",
            extractor_used="youtube",
        )
