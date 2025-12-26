"""
GitHub content extractor for releases, READMEs, and discussions.
"""

import re
from urllib.parse import urlparse

from bs4 import BeautifulSoup

from .base import ExtractedContent, SiteExtractor


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
