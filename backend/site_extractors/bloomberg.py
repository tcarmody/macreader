"""
Bloomberg news content extractor.
"""

import json
import re
from copy import copy

from bs4 import BeautifulSoup

from .base import ExtractedContent, SiteExtractor


class BloombergExtractor(SiteExtractor):
    """Extractor for Bloomberg articles."""

    DOMAINS = ['bloomberg.com']

    def extract(self, url: str, html: str) -> ExtractedContent:
        soup = BeautifulSoup(html, 'html.parser')

        # Title
        title = ""
        if h1 := soup.find('h1'):
            title = h1.get_text(strip=True)
        elif og_title := soup.find('meta', property='og:title'):
            title = og_title.get('content', '')
        elif title_tag := soup.find('title'):
            title = title_tag.get_text(strip=True)
            title = re.sub(r'\s*-\s*Bloomberg.*$', '', title)

        # Author
        author = None
        if author_elem := soup.select_one('[class*="author"], .byline, [data-component="byline"]'):
            author = author_elem.get_text(strip=True)
            author = re.sub(r'^By\s+', '', author, flags=re.I)
        elif author_meta := soup.find('meta', {'name': 'author'}):
            author = author_meta.get('content')

        # Published date
        published = None
        if time_elem := soup.find('time', datetime=True):
            published = time_elem.get('datetime')
        elif date_meta := soup.find('meta', property='article:published_time'):
            published = date_meta.get('content')

        # Try to extract content from JSON-LD first
        content = self._extract_from_json_ld(soup)

        # Main content - Bloomberg uses various article body selectors
        if not content or len(content) < 500:
            content = self._extract_from_html(soup)

        # Check for paywall
        is_paywalled = any(x in html.lower() for x in [
            'subscribe to continue', 'subscription required',
            'paywall', 'sign in to read', 'subscriber-only'
        ])

        # Featured image
        featured_image = None
        if og_image := soup.find('meta', property='og:image'):
            featured_image = og_image.get('content')

        # Word count and reading time
        text_content = BeautifulSoup(content, 'html.parser').get_text() if content else ""
        word_count = len(text_content.split())
        reading_time = self._estimate_reading_time(text_content) if text_content else None

        # Categories from meta
        categories = []
        if section := soup.find('meta', property='article:section'):
            categories.append(section.get('content'))

        return ExtractedContent(
            title=title,
            content=content,
            author=author,
            published=published,
            reading_time_minutes=reading_time,
            word_count=word_count,
            categories=categories,
            featured_image=featured_image,
            is_paywalled=is_paywalled,
            site_name="Bloomberg",
            extractor_used="bloomberg",
        )

    def _extract_from_html(self, soup: BeautifulSoup) -> str:
        """Extract article content from HTML."""
        content_selectors = [
            '[data-component="body-content"]',
            '[data-component="article-body"]',
            '[class*="body-content"]',
            '[class*="article-body"]',
            '[class*="story-body"]',
            '[class*="ArticleBody"]',
            '.body-content',
            'article .content',
            '.article-body__content',
        ]

        for selector in content_selectors:
            if article_body := soup.select_one(selector):
                paragraphs = article_body.find_all('p')
                if len(paragraphs) >= 2:
                    body_copy = copy(article_body)
                    self._remove_noise(body_copy)
                    return str(body_copy)

        # Try finding article tag and extracting paragraphs
        if article := soup.find('article'):
            article_paragraphs = []
            for p in article.find_all('p'):
                text = p.get_text(strip=True)
                if len(text) > 100:
                    article_paragraphs.append(str(p))
            if article_paragraphs:
                return '\n'.join(article_paragraphs)

        # Last resort: filter paragraphs aggressively
        return self._extract_paragraphs(soup)

    def _remove_noise(self, body: BeautifulSoup) -> None:
        """Remove noise elements from content."""
        noise_selectors = [
            '[class*="newsletter"]', '[class*="subscribe"]',
            '[class*="related"]', '[class*="recommended"]',
            '[class*="ad-"]', '[class*="promo"]', '[class*="Promo"]',
            '[class*="recirc"]', '[class*="Recirc"]',
            '[class*="terminal"]', '[class*="Terminal"]',
            'aside', 'nav', 'footer', 'script', 'style',
            '[data-component="related"]', '[data-component="newsletter"]',
        ]
        for selector in noise_selectors:
            for elem in body.select(selector):
                elem.decompose()

    def _extract_paragraphs(self, soup: BeautifulSoup) -> str:
        """Extract paragraphs with aggressive noise filtering."""
        noise_phrases = [
            'subscribe', 'sign up', 'newsletter', 'cookie', 'privacy',
            'more from bloomberg', 'top reads', 'related', 'before it\'s here',
            'bloomberg terminal', 'learn more', 'gift this article',
            'add us on', 'contact us', 'send a tip', 'site feedback',
            'take our survey', 'provide news feedback', 'report an error',
            'by bloomberg', 'updated', 'read more', 'see also'
        ]

        all_paragraphs = []
        for p in soup.find_all('p'):
            text = p.get_text(strip=True)
            text_lower = text.lower()

            if len(text) < 80:
                continue

            if any(phrase in text_lower for phrase in noise_phrases):
                continue

            parent_classes = ' '.join(p.parent.get('class', [])).lower() if p.parent else ''
            if any(x in parent_classes for x in ['related', 'sidebar', 'nav', 'footer', 'promo', 'ad-']):
                continue

            all_paragraphs.append(str(p))

        return '\n'.join(all_paragraphs)

    def _extract_from_json_ld(self, soup: BeautifulSoup) -> str:
        """Extract article body from JSON-LD structured data."""
        for script in soup.find_all('script', type='application/ld+json'):
            try:
                data = json.loads(script.string)

                if isinstance(data, list):
                    for item in data:
                        if content := self._extract_article_body_from_jsonld(item):
                            return content
                else:
                    if content := self._extract_article_body_from_jsonld(data):
                        return content
            except (json.JSONDecodeError, TypeError):
                continue

        return ""

    def _extract_article_body_from_jsonld(self, data: dict) -> str:
        """Extract articleBody from a JSON-LD object."""
        if not isinstance(data, dict):
            return ""

        if article_body := data.get('articleBody'):
            paragraphs = article_body.split('\n\n')
            html_paragraphs = [f'<p>{p.strip()}</p>' for p in paragraphs if p.strip()]
            return '\n'.join(html_paragraphs)

        if graph := data.get('@graph'):
            if isinstance(graph, list):
                for item in graph:
                    if item.get('@type') in ('NewsArticle', 'Article', 'WebPage'):
                        if article_body := item.get('articleBody'):
                            paragraphs = article_body.split('\n\n')
                            html_paragraphs = [f'<p>{p.strip()}</p>' for p in paragraphs if p.strip()]
                            return '\n'.join(html_paragraphs)

        return ""
