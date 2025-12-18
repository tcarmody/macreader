"""OPML parser for importing and exporting feed subscriptions."""

import xml.etree.ElementTree as ET
from dataclasses import dataclass


@dataclass
class OPMLFeed:
    """A feed entry from an OPML file."""
    url: str
    title: str | None
    category: str | None


@dataclass
class OPMLDocument:
    """Parsed OPML document."""
    title: str | None
    feeds: list[OPMLFeed]


def parse_opml(xml_content: str) -> OPMLDocument:
    """
    Parse OPML XML content and extract feed subscriptions.

    Handles both flat and nested (categorized) OPML structures.

    Args:
        xml_content: Raw OPML XML string

    Returns:
        OPMLDocument with title and list of feeds

    Raises:
        ValueError: If XML is invalid or not OPML format
    """
    try:
        root = ET.fromstring(xml_content)
    except ET.ParseError as e:
        raise ValueError(f"Invalid XML: {e}")

    # Verify it's an OPML document
    if root.tag.lower() != "opml":
        raise ValueError(f"Not an OPML document (root element: {root.tag})")

    # Get document title from head
    doc_title = None
    head = root.find("head")
    if head is not None:
        title_elem = head.find("title")
        if title_elem is not None and title_elem.text:
            doc_title = title_elem.text.strip()

    # Find body element
    body = root.find("body")
    if body is None:
        raise ValueError("OPML document missing <body> element")

    feeds: list[OPMLFeed] = []
    _parse_outlines(body, feeds, category=None)

    return OPMLDocument(title=doc_title, feeds=feeds)


def _parse_outlines(
    element: ET.Element,
    feeds: list[OPMLFeed],
    category: str | None
) -> None:
    """
    Recursively parse outline elements.

    OPML outlines can be:
    1. Feed entries (have xmlUrl attribute)
    2. Category folders (have children but no xmlUrl)
    """
    for outline in element.findall("outline"):
        xml_url = outline.get("xmlUrl") or outline.get("xmlurl")

        if xml_url:
            # This is a feed entry
            title = (
                outline.get("title") or
                outline.get("text") or
                None
            )
            feeds.append(OPMLFeed(
                url=xml_url,
                title=title.strip() if title else None,
                category=category
            ))
        else:
            # This might be a category folder
            folder_name = outline.get("title") or outline.get("text")
            # Recursively process children with this category
            _parse_outlines(
                outline,
                feeds,
                category=folder_name.strip() if folder_name else category
            )


def generate_opml(feeds: list[OPMLFeed], title: str = "Feed Subscriptions") -> str:
    """
    Generate OPML XML from a list of feeds.

    Feeds with categories are grouped into folders.

    Args:
        feeds: List of OPMLFeed objects
        title: Document title

    Returns:
        OPML XML string
    """
    root = ET.Element("opml", version="2.0")

    # Head section
    head = ET.SubElement(root, "head")
    title_elem = ET.SubElement(head, "title")
    title_elem.text = title

    # Body section
    body = ET.SubElement(root, "body")

    # Group feeds by category
    categorized: dict[str | None, list[OPMLFeed]] = {}
    for feed in feeds:
        cat = feed.category
        if cat not in categorized:
            categorized[cat] = []
        categorized[cat].append(feed)

    # Add uncategorized feeds first
    if None in categorized:
        for feed in categorized[None]:
            _add_feed_outline(body, feed)
        del categorized[None]

    # Add categorized feeds in folders
    for category, cat_feeds in sorted(categorized.items()):
        folder = ET.SubElement(body, "outline", text=category, title=category)
        for feed in cat_feeds:
            _add_feed_outline(folder, feed)

    # Generate XML string with declaration
    return '<?xml version="1.0" encoding="UTF-8"?>\n' + ET.tostring(
        root, encoding="unicode"
    )


def _add_feed_outline(parent: ET.Element, feed: OPMLFeed) -> None:
    """Add a feed outline element to parent."""
    attrs = {
        "type": "rss",
        "xmlUrl": feed.url,
    }
    if feed.title:
        attrs["text"] = feed.title
        attrs["title"] = feed.title
    else:
        attrs["text"] = feed.url

    ET.SubElement(parent, "outline", **attrs)
