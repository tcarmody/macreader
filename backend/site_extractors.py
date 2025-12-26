"""
Site-Specific Content Extractors - Custom extraction logic for common publishers.

Provides specialized extractors for sites that don't work well with generic extraction:
- Medium: Handles paywalled content markers, series info
- Substack: Extracts newsletter-specific metadata
- GitHub: Parses release notes, READMEs, discussions
- YouTube: Extracts video metadata and descriptions
- Twitter/X: Handles thread content

Each extractor returns enhanced metadata beyond what trafilatura provides.
"""

import re
import json
import logging
from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from typing import Optional
from urllib.parse import urlparse, parse_qs

from bs4 import BeautifulSoup

logger = logging.getLogger(__name__)


@dataclass
class ExtractedContent:
    """Enhanced content extraction result with rich metadata."""
    title: str
    content: str  # HTML content
    author: Optional[str] = None
    published: Optional[str] = None  # ISO format date

    # Enhanced metadata
    reading_time_minutes: Optional[int] = None
    word_count: Optional[int] = None
    categories: list[str] = field(default_factory=list)
    tags: list[str] = field(default_factory=list)

    # Series/collection info
    series_name: Optional[str] = None
    series_part: Optional[int] = None
    series_total: Optional[int] = None

    # Media
    featured_image: Optional[str] = None
    images: list[str] = field(default_factory=list)
    has_video: bool = False
    video_embed_url: Optional[str] = None

    # Content indicators
    is_paywalled: bool = False
    is_truncated: bool = False
    has_code_blocks: bool = False
    code_languages: list[str] = field(default_factory=list)

    # Source info
    site_name: Optional[str] = None
    canonical_url: Optional[str] = None
    extractor_used: str = "generic"


class SiteExtractor(ABC):
    """Base class for site-specific extractors."""

    # Domains this extractor handles
    DOMAINS: list[str] = []

    @classmethod
    def can_handle(cls, url: str) -> bool:
        """Check if this extractor can handle the given URL."""
        url_lower = url.lower()
        return any(domain in url_lower for domain in cls.DOMAINS)

    @abstractmethod
    def extract(self, url: str, html: str) -> ExtractedContent:
        """Extract content from the HTML."""
        pass

    def _estimate_reading_time(self, text: str) -> int:
        """Estimate reading time in minutes based on word count."""
        words = len(text.split())
        # Average reading speed: 200-250 words per minute
        return max(1, round(words / 225))

    def _extract_code_languages(self, soup: BeautifulSoup) -> list[str]:
        """Extract programming languages from code blocks."""
        languages = set()

        # Check class names on pre/code blocks
        for code in soup.find_all(['pre', 'code']):
            classes = code.get('class', [])
            for cls in classes:
                # Common patterns: language-python, lang-js, highlight-ruby
                match = re.match(r'(?:language-|lang-|highlight-)(\w+)', cls)
                if match:
                    languages.add(match.group(1).lower())

        # Also check data-language attributes
        for elem in soup.find_all(attrs={'data-language': True}):
            languages.add(elem['data-language'].lower())

        return list(languages)

    def _clean_html_content(self, soup: BeautifulSoup) -> str:
        """Remove unwanted elements and return cleaned HTML."""
        # Remove common noise elements
        for selector in [
            'script', 'style', 'nav', 'header', 'footer', 'aside',
            'noscript', 'iframe', 'form', 'button', 'input',
            '[class*="ad-"]', '[class*="advertisement"]',
            '[class*="social"]', '[class*="share"]',
            '[class*="related"]', '[class*="recommended"]',
            '[class*="newsletter"]', '[class*="subscribe"]',
            '[id*="comment"]', '[class*="comment"]',
        ]:
            for elem in soup.select(selector):
                elem.decompose()

        return str(soup)


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


class GitHubExtractor(SiteExtractor):
    """Extractor for GitHub pages (releases, READMEs, discussions)."""

    DOMAINS = ['github.com']

    def extract(self, url: str, html: str) -> ExtractedContent:
        soup = BeautifulSoup(html, 'html.parser')
        parsed_url = urlparse(url)
        path_parts = parsed_url.path.strip('/').split('/')

        # Determine content type from URL
        content_type = "repository"
        if len(path_parts) >= 3:
            if path_parts[2] == "releases":
                content_type = "release"
            elif path_parts[2] == "discussions":
                content_type = "discussion"
            elif path_parts[2] == "issues":
                content_type = "issue"
            elif path_parts[2] == "pull":
                content_type = "pull_request"
            elif path_parts[2] == "blob":
                content_type = "file"

        # Title
        title = ""
        if content_type == "release":
            if release_title := soup.select_one('.release-header .f1'):
                title = release_title.get_text(strip=True)
        if not title:
            if h1 := soup.find('h1'):
                title = h1.get_text(strip=True)
            elif title_tag := soup.find('title'):
                title = title_tag.get_text(strip=True)
                title = re.sub(r'\s*·\s*GitHub.*$', '', title)

        # Author
        author = None
        if author_link := soup.select_one('.author, .user-mention'):
            author = author_link.get_text(strip=True).lstrip('@')

        # Published date
        published = None
        if relative_time := soup.find('relative-time', datetime=True):
            published = relative_time.get('datetime')
        elif time_elem := soup.find('time', datetime=True):
            published = time_elem.get('datetime')

        # Main content
        content = ""
        if content_type == "release":
            # Release notes
            if release_body := soup.select_one('.markdown-body'):
                content = str(release_body)
        elif content_type in ("issue", "discussion", "pull_request"):
            # Issue/PR/Discussion body
            if issue_body := soup.select_one('.comment-body, .markdown-body'):
                content = str(issue_body)
        elif content_type == "file":
            # README or other markdown file
            if readme := soup.select_one('#readme .markdown-body'):
                content = str(readme)
        else:
            # Repository main page - get README
            if readme := soup.select_one('#readme .markdown-body'):
                content = str(readme)

        # Repository name as site_name
        site_name = None
        if len(path_parts) >= 2:
            site_name = f"{path_parts[0]}/{path_parts[1]}"

        # Code blocks (very common on GitHub)
        code_languages = self._extract_code_languages(soup)
        has_code = bool(soup.find('pre'))

        # Tags (for releases)
        tags = []
        if content_type == "release":
            if tag_elem := soup.select_one('.css-truncate-target'):
                tags.append(tag_elem.get_text(strip=True))

        # Word count and reading time
        text_content = BeautifulSoup(content, 'html.parser').get_text()
        word_count = len(text_content.split())
        reading_time = self._estimate_reading_time(text_content)

        return ExtractedContent(
            title=title,
            content=content,
            author=author,
            published=published,
            reading_time_minutes=reading_time,
            word_count=word_count,
            tags=tags,
            has_code_blocks=has_code,
            code_languages=code_languages,
            site_name=site_name,
            extractor_used=f"github_{content_type}",
        )


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


class WikipediaExtractor(SiteExtractor):
    """Extractor for Wikipedia articles."""

    DOMAINS = ['wikipedia.org', 'wikimedia.org']

    def extract(self, url: str, html: str) -> ExtractedContent:
        soup = BeautifulSoup(html, 'html.parser')

        # Title
        title = ""
        if h1 := soup.find('h1', id='firstHeading'):
            title = h1.get_text(strip=True)
        elif title_tag := soup.find('title'):
            title = title_tag.get_text(strip=True)
            title = re.sub(r'\s*-\s*Wikipedia.*$', '', title)

        # Main content
        content = ""
        if content_div := soup.find('div', id='mw-content-text'):
            # Remove reference sections, navboxes, etc.
            for selector in ['.reflist', '.navbox', '.sistersitebox',
                           '.mw-editsection', '.mw-empty-elt', '.noprint',
                           '#coordinates', '.ambox', '.hatnote']:
                for elem in content_div.select(selector):
                    elem.decompose()
            content = str(content_div)

        # Categories
        categories = []
        if cat_links := soup.select('#mw-normal-catlinks a'):
            categories = [link.get_text(strip=True) for link in cat_links[1:6]]  # Skip "Categories" link

        # Word count and reading time
        text_content = BeautifulSoup(content, 'html.parser').get_text()
        word_count = len(text_content.split())
        reading_time = self._estimate_reading_time(text_content)

        # Featured image
        featured_image = None
        if infobox_img := soup.select_one('.infobox img'):
            featured_image = infobox_img.get('src')
            if featured_image and featured_image.startswith('//'):
                featured_image = 'https:' + featured_image

        return ExtractedContent(
            title=title,
            content=content,
            categories=categories,
            reading_time_minutes=reading_time,
            word_count=word_count,
            featured_image=featured_image,
            site_name="Wikipedia",
            extractor_used="wikipedia",
        )


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
        # Bloomberg uses various author selectors
        if author_elem := soup.select_one('[class*="author"], .byline, [data-component="byline"]'):
            author = author_elem.get_text(strip=True)
            # Clean up "By Author Name" format
            author = re.sub(r'^By\s+', '', author, flags=re.I)
        elif author_meta := soup.find('meta', {'name': 'author'}):
            author = author_meta.get('content')

        # Published date
        published = None
        if time_elem := soup.find('time', datetime=True):
            published = time_elem.get('datetime')
        elif date_meta := soup.find('meta', property='article:published_time'):
            published = date_meta.get('content')

        # Try to extract content from JSON-LD first (Bloomberg stores article text here)
        content = ""
        content = self._extract_from_json_ld(soup)

        # Main content - Bloomberg uses various article body selectors
        if not content or len(content) < 500:
            # Bloomberg-specific: look for the main story body
            # They often use data attributes or specific class patterns
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
                    # Check if this has meaningful content (multiple paragraphs)
                    paragraphs = article_body.find_all('p')
                    if len(paragraphs) >= 2:
                        # Clone to avoid modifying original
                        from copy import copy
                        body_copy = copy(article_body)

                        # Remove Bloomberg's UI elements
                        for noise_selector in [
                            '[class*="newsletter"]', '[class*="subscribe"]',
                            '[class*="related"]', '[class*="recommended"]',
                            '[class*="ad-"]', '[class*="promo"]', '[class*="Promo"]',
                            '[class*="recirc"]', '[class*="Recirc"]',
                            '[class*="terminal"]', '[class*="Terminal"]',
                            'aside', 'nav', 'footer', 'script', 'style',
                            '[data-component="related"]', '[data-component="newsletter"]',
                        ]:
                            for elem in body_copy.select(noise_selector):
                                elem.decompose()
                        content = str(body_copy)
                        break

            # If we still don't have content, try finding article tag and extracting just paragraphs
            if not content or len(content) < 500:
                if article := soup.find('article'):
                    # Get only direct paragraph children or paragraphs in the main content area
                    article_paragraphs = []
                    for p in article.find_all('p'):
                        text = p.get_text(strip=True)
                        # Only substantial paragraphs that look like article content
                        if len(text) > 100:
                            article_paragraphs.append(str(p))
                    if article_paragraphs:
                        content = '\n'.join(article_paragraphs)

        # If still no content, try to grab article paragraphs more carefully
        if not content or len(content) < 500:
            # Find all paragraphs that look like article content
            # but filter out navigation/related content more aggressively
            all_paragraphs = []
            noise_phrases = [
                'subscribe', 'sign up', 'newsletter', 'cookie', 'privacy',
                'more from bloomberg', 'top reads', 'related', 'before it\'s here',
                'bloomberg terminal', 'learn more', 'gift this article',
                'add us on', 'contact us', 'send a tip', 'site feedback',
                'take our survey', 'provide news feedback', 'report an error',
                'by bloomberg', 'updated', 'read more', 'see also'
            ]

            for p in soup.find_all('p'):
                text = p.get_text(strip=True)
                text_lower = text.lower()

                # Skip short paragraphs
                if len(text) < 80:
                    continue

                # Skip paragraphs with noise phrases
                if any(phrase in text_lower for phrase in noise_phrases):
                    continue

                # Skip if parent is likely navigation/sidebar
                parent_classes = ' '.join(p.parent.get('class', [])).lower() if p.parent else ''
                if any(x in parent_classes for x in ['related', 'sidebar', 'nav', 'footer', 'promo', 'ad-']):
                    continue

                all_paragraphs.append(str(p))

            if all_paragraphs:
                content = '\n'.join(all_paragraphs)

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

    def _extract_from_json_ld(self, soup: BeautifulSoup) -> str:
        """Extract article body from JSON-LD structured data."""
        for script in soup.find_all('script', type='application/ld+json'):
            try:
                data = json.loads(script.string)

                # Handle array of JSON-LD objects
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

        # Check for articleBody directly
        if article_body := data.get('articleBody'):
            # Convert plain text to paragraphs
            paragraphs = article_body.split('\n\n')
            html_paragraphs = [f'<p>{p.strip()}</p>' for p in paragraphs if p.strip()]
            return '\n'.join(html_paragraphs)

        # Check for @graph which may contain the article
        if graph := data.get('@graph'):
            if isinstance(graph, list):
                for item in graph:
                    if item.get('@type') in ('NewsArticle', 'Article', 'WebPage'):
                        if article_body := item.get('articleBody'):
                            paragraphs = article_body.split('\n\n')
                            html_paragraphs = [f'<p>{p.strip()}</p>' for p in paragraphs if p.strip()]
                            return '\n'.join(html_paragraphs)

        return ""


# Registry of all extractors
SITE_EXTRACTORS: list[type[SiteExtractor]] = [
    MediumExtractor,
    SubstackExtractor,
    GitHubExtractor,
    YouTubeExtractor,
    TwitterExtractor,
    WikipediaExtractor,
    BloombergExtractor,
]


def get_extractor_for_url(url: str) -> Optional[SiteExtractor]:
    """Get the appropriate site-specific extractor for a URL, if available."""
    for extractor_class in SITE_EXTRACTORS:
        if extractor_class.can_handle(url):
            return extractor_class()
    return None


def extract_with_site_extractor(url: str, html: str) -> Optional[ExtractedContent]:
    """
    Try to extract content using a site-specific extractor.

    Returns None if no site-specific extractor is available.
    """
    extractor = get_extractor_for_url(url)
    if extractor:
        try:
            return extractor.extract(url, html)
        except Exception as e:
            logger.warning(f"Site extractor failed for {url}: {e}")
            return None
    return None
