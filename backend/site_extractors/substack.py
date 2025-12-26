"""
Substack newsletter content extractor.
"""

from bs4 import BeautifulSoup

from .base import ExtractedContent, SiteExtractor


class SubstackExtractor(SiteExtractor):
    """Extractor for Substack newsletters."""

    DOMAINS = ['substack.com']

    def extract(self, url: str, html: str) -> ExtractedContent:
        soup = BeautifulSoup(html, 'html.parser')

        # Title
        title = ""
        if h1 := soup.select_one('h1.post-title'):
            title = h1.get_text(strip=True)
        elif h1 := soup.find('h1'):
            title = h1.get_text(strip=True)
        elif title_tag := soup.find('title'):
            title = title_tag.get_text(strip=True)

        # Author - Substack shows newsletter name and author
        author = None
        site_name = None
        if pub_name := soup.select_one('.publication-name'):
            site_name = pub_name.get_text(strip=True)
        if author_link := soup.select_one('.author-name'):
            author = author_link.get_text(strip=True)
        elif author_meta := soup.find('meta', {'name': 'author'}):
            author = author_meta.get('content')

        # Published date
        published = None
        if time_elem := soup.find('time', datetime=True):
            published = time_elem.get('datetime')
        elif date_meta := soup.find('meta', property='article:published_time'):
            published = date_meta.get('content')

        # Main content - Substack uses .body class
        content = ""
        if article_body := soup.select_one('.body, .post-content, article'):
            # Remove Substack UI elements
            for selector in ['.subscribe-widget', '.post-ufi', '.share-dialog',
                           '.subscription-widget', '.footer']:
                for elem in article_body.select(selector):
                    elem.decompose()
            content = str(article_body)

        # Check for paywall
        is_paywalled = 'paywall' in html.lower() or 'subscriber-only' in html.lower()

        # Featured image
        featured_image = None
        if og_image := soup.find('meta', property='og:image'):
            featured_image = og_image.get('content')

        # Extract all images
        images = []
        for img in soup.select('.body img, .post-content img'):
            src = img.get('src')
            if src and not src.startswith('data:'):
                images.append(src)

        # Word count and reading time
        text_content = BeautifulSoup(content, 'html.parser').get_text()
        word_count = len(text_content.split())
        reading_time = self._estimate_reading_time(text_content)

        # Code blocks
        code_languages = self._extract_code_languages(soup)
        has_code = bool(soup.find('pre'))

        return ExtractedContent(
            title=title,
            content=content,
            author=author,
            published=published,
            reading_time_minutes=reading_time,
            word_count=word_count,
            featured_image=featured_image,
            images=images,
            is_paywalled=is_paywalled,
            has_code_blocks=has_code,
            code_languages=code_languages,
            site_name=site_name or "Substack",
            extractor_used="substack",
        )
