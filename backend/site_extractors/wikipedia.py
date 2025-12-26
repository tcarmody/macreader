"""
Wikipedia content extractor.
"""

import re

from bs4 import BeautifulSoup

from .base import ExtractedContent, SiteExtractor


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
