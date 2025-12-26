"""
Medium.com content extractor.
"""

import re

from bs4 import BeautifulSoup

from .base import ExtractedContent, SiteExtractor


class MediumExtractor(SiteExtractor):
    """Extractor for Medium.com articles."""

    DOMAINS = ['medium.com', 'towardsdatascience.com', 'betterprogramming.pub',
               'levelup.gitconnected.com', 'javascript.plainenglish.io']

    def extract(self, url: str, html: str) -> ExtractedContent:
        soup = BeautifulSoup(html, 'html.parser')

        # Title
        title = ""
        if h1 := soup.find('h1'):
            title = h1.get_text(strip=True)
        elif title_tag := soup.find('title'):
            title = title_tag.get_text(strip=True)
            title = re.sub(r'\s*[|\-–—]\s*Medium.*$', '', title)

        # Author
        author = None
        if author_link := soup.select_one('a[data-testid="authorName"]'):
            author = author_link.get_text(strip=True)
        elif author_meta := soup.find('meta', {'name': 'author'}):
            author = author_meta.get('content')

        # Published date
        published = None
        if time_elem := soup.find('time', datetime=True):
            published = time_elem.get('datetime')
        elif date_meta := soup.find('meta', property='article:published_time'):
            published = date_meta.get('content')

        # Check for paywall indicators
        is_paywalled = False
        paywall_indicators = [
            'memberOnlyContent', 'meteredContent', 'locked',
            'You have 2 free member-only', 'member-only story'
        ]
        html_lower = html.lower()
        for indicator in paywall_indicators:
            if indicator.lower() in html_lower:
                is_paywalled = True
                break

        # Reading time (Medium shows this)
        reading_time = None
        if rt_elem := soup.find(string=re.compile(r'\d+\s*min\s*read')):
            match = re.search(r'(\d+)\s*min', rt_elem)
            if match:
                reading_time = int(match.group(1))

        # Main content
        article = soup.find('article') or soup.find('main')
        content = ""
        if article:
            # Remove Medium's UI elements
            for selector in ['[data-testid="headerSocialShare"]', '[data-testid="responses"]',
                           '.pw-multi-vote-count', '.js-postActionsFooter']:
                for elem in article.select(selector):
                    elem.decompose()
            content = str(article)

        # Code blocks
        code_languages = self._extract_code_languages(soup)
        has_code = bool(soup.find('pre'))

        # Featured image
        featured_image = None
        if og_image := soup.find('meta', property='og:image'):
            featured_image = og_image.get('content')

        # Categories/tags from URL and content
        categories = []
        if '/tag/' in url:
            tag_match = re.search(r'/tag/([^/]+)', url)
            if tag_match:
                categories.append(tag_match.group(1).replace('-', ' ').title())

        # Word count
        text_content = BeautifulSoup(content, 'html.parser').get_text()
        word_count = len(text_content.split())

        if not reading_time:
            reading_time = self._estimate_reading_time(text_content)

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
            has_code_blocks=has_code,
            code_languages=code_languages,
            site_name="Medium",
            extractor_used="medium",
        )
