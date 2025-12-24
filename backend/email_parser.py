"""
Email Parser - Extract content from .eml files for newsletter import.

Handles:
- Standard .eml (RFC 822) format
- HTML and plain text email bodies
- Common newsletter formats (Substack, Beehiiv, ConvertKit, etc.)
- Metadata extraction (sender, subject, date)
"""

import email
import re
from dataclasses import dataclass
from datetime import datetime
from email import policy
from email.message import EmailMessage
from pathlib import Path
from typing import Optional

from bs4 import BeautifulSoup


class EmailParseError(Exception):
    """Error during email parsing."""
    pass


@dataclass
class ParsedEmail:
    """Result of parsing an email file."""
    subject: str
    sender: str
    sender_email: str
    date: Optional[datetime]
    content_html: Optional[str]
    content_text: Optional[str]
    newsletter_name: Optional[str] = None
    unsubscribe_url: Optional[str] = None

    @property
    def title(self) -> str:
        """Get the best title for this email."""
        return self.subject or "Untitled Newsletter"

    @property
    def author(self) -> str:
        """Get the author/sender name."""
        return self.newsletter_name or self.sender or self.sender_email

    @property
    def content(self) -> str:
        """Get the best content (HTML preferred, fallback to text)."""
        return self.content_html or self.content_text or ""


def parse_eml_file(file_path: Path) -> ParsedEmail:
    """
    Parse an .eml file and extract newsletter content.

    Args:
        file_path: Path to the .eml file

    Returns:
        ParsedEmail with extracted content

    Raises:
        EmailParseError: If parsing fails
    """
    try:
        content = file_path.read_bytes()
        return parse_eml_bytes(content)
    except EmailParseError:
        raise
    except Exception as e:
        raise EmailParseError(f"Failed to read email file: {e}")


def parse_eml_bytes(content: bytes) -> ParsedEmail:
    """
    Parse email content from bytes.

    Args:
        content: Raw email bytes

    Returns:
        ParsedEmail with extracted content

    Raises:
        EmailParseError: If parsing fails
    """
    try:
        msg = email.message_from_bytes(content, policy=policy.default)
        return _extract_email_content(msg)
    except EmailParseError:
        raise
    except Exception as e:
        raise EmailParseError(f"Failed to parse email: {e}")


def parse_eml_string(content: str) -> ParsedEmail:
    """
    Parse email content from string.

    Args:
        content: Raw email string

    Returns:
        ParsedEmail with extracted content

    Raises:
        EmailParseError: If parsing fails
    """
    try:
        msg = email.message_from_string(content, policy=policy.default)
        return _extract_email_content(msg)
    except EmailParseError:
        raise
    except Exception as e:
        raise EmailParseError(f"Failed to parse email: {e}")


def _extract_email_content(msg: EmailMessage) -> ParsedEmail:
    """Extract content from an email message object."""
    # Extract headers
    subject = msg.get("Subject", "")
    from_header = msg.get("From", "")
    date_header = msg.get("Date", "")

    # Parse sender
    sender, sender_email = _parse_from_header(from_header)

    # Parse date
    parsed_date = None
    if date_header:
        try:
            parsed_date = email.utils.parsedate_to_datetime(date_header)
        except (ValueError, TypeError):
            pass

    # Extract body content
    content_html = None
    content_text = None

    if msg.is_multipart():
        for part in msg.walk():
            content_type = part.get_content_type()
            if content_type == "text/html" and not content_html:
                payload = part.get_payload(decode=True)
                if payload:
                    charset = part.get_content_charset() or "utf-8"
                    try:
                        content_html = payload.decode(charset, errors="replace")
                    except (LookupError, UnicodeDecodeError):
                        content_html = payload.decode("utf-8", errors="replace")
            elif content_type == "text/plain" and not content_text:
                payload = part.get_payload(decode=True)
                if payload:
                    charset = part.get_content_charset() or "utf-8"
                    try:
                        content_text = payload.decode(charset, errors="replace")
                    except (LookupError, UnicodeDecodeError):
                        content_text = payload.decode("utf-8", errors="replace")
    else:
        content_type = msg.get_content_type()
        payload = msg.get_payload(decode=True)
        if payload:
            charset = msg.get_content_charset() or "utf-8"
            try:
                decoded = payload.decode(charset, errors="replace")
            except (LookupError, UnicodeDecodeError):
                decoded = payload.decode("utf-8", errors="replace")

            if content_type == "text/html":
                content_html = decoded
            else:
                content_text = decoded

    # Clean up HTML content
    if content_html:
        content_html = _clean_newsletter_html(content_html)

    # Try to detect newsletter name and unsubscribe URL
    newsletter_name = _detect_newsletter_name(msg, content_html)
    unsubscribe_url = _find_unsubscribe_url(msg, content_html)

    return ParsedEmail(
        subject=subject,
        sender=sender,
        sender_email=sender_email,
        date=parsed_date,
        content_html=content_html,
        content_text=content_text,
        newsletter_name=newsletter_name,
        unsubscribe_url=unsubscribe_url,
    )


def _parse_from_header(from_header: str) -> tuple[str, str]:
    """
    Parse the From header into name and email.

    Examples:
        "John Doe <john@example.com>" -> ("John Doe", "john@example.com")
        "john@example.com" -> ("", "john@example.com")
    """
    if not from_header:
        return "", ""

    # Try to extract "Name <email>" format
    match = re.match(r'^"?([^"<]*)"?\s*<([^>]+)>', from_header)
    if match:
        name = match.group(1).strip()
        email_addr = match.group(2).strip()
        return name, email_addr

    # Just an email address
    email_match = re.search(r'[\w\.-]+@[\w\.-]+', from_header)
    if email_match:
        return "", email_match.group(0)

    return "", from_header


def _clean_newsletter_html(html: str) -> str:
    """
    Clean newsletter HTML for better readability.

    Removes:
    - Tracking pixels
    - Email client preview text
    - Excessive wrapper tables
    - Inline styles (partially)
    """
    soup = BeautifulSoup(html, "html.parser")

    # Remove tracking pixels (1x1 images)
    for img in soup.find_all("img"):
        width = img.get("width", "")
        height = img.get("height", "")
        if width in ("1", "0") or height in ("1", "0"):
            img.decompose()
            continue
        # Also check style
        style = img.get("style", "")
        if "width:1px" in style or "height:1px" in style or "width:0" in style:
            img.decompose()

    # Remove hidden preview text spans
    for span in soup.find_all("span"):
        style = span.get("style", "")
        if "display:none" in style or "visibility:hidden" in style:
            span.decompose()
        elif "max-height:0" in style and "overflow:hidden" in style:
            span.decompose()

    # Remove script and style tags
    for tag in soup.find_all(["script", "style", "head"]):
        tag.decompose()

    # Remove empty divs that are just spacers
    for div in soup.find_all("div"):
        if not div.get_text(strip=True) and not div.find("img"):
            # Check if it's just a spacer
            style = div.get("style", "")
            if "height:" in style and not div.find_all():
                div.decompose()

    # Unwrap excessive table wrappers (common in email templates)
    # Keep the content but remove unnecessary nesting
    for table in soup.find_all("table"):
        # If table has only one row with one cell, and no important styling
        rows = table.find_all("tr", recursive=False)
        if len(rows) == 1:
            cells = rows[0].find_all(["td", "th"], recursive=False)
            if len(cells) == 1:
                # Check if it's just a layout wrapper
                cell = cells[0]
                role = table.get("role", "")
                if role != "presentation":
                    continue
                # Replace table with its content
                cell.unwrap()
                if rows[0].parent:
                    rows[0].unwrap()
                table.unwrap()

    # Remove common footer elements
    for elem in soup.find_all(class_=re.compile(r"footer|unsubscribe|preferences", re.I)):
        elem.decompose()

    return str(soup)


def _detect_newsletter_name(msg: EmailMessage, html: Optional[str]) -> Optional[str]:
    """Try to detect the newsletter name from headers or content."""
    # Check List-Id header (common for mailing lists)
    list_id = msg.get("List-Id", "")
    if list_id:
        # Extract name from "Newsletter Name <list.example.com>"
        match = re.match(r'^"?([^"<]+)"?\s*<', list_id)
        if match:
            return match.group(1).strip()

    # Check X-Mailer or custom headers for known platforms
    x_mailer = msg.get("X-Mailer", "")
    if "Substack" in x_mailer:
        # For Substack, use the sender name
        from_header = msg.get("From", "")
        name, _ = _parse_from_header(from_header)
        if name:
            return name

    # Try to find newsletter name in HTML
    if html:
        soup = BeautifulSoup(html, "html.parser")
        # Look for common newsletter title patterns
        for selector in [
            "h1.newsletter-title",
            ".newsletter-name",
            "[data-newsletter-title]",
        ]:
            elem = soup.select_one(selector)
            if elem:
                return elem.get_text(strip=True)

    return None


def _find_unsubscribe_url(msg: EmailMessage, html: Optional[str]) -> Optional[str]:
    """Find the unsubscribe URL from headers or content."""
    # Check List-Unsubscribe header
    list_unsub = msg.get("List-Unsubscribe", "")
    if list_unsub:
        # Extract URL from "<http://...>" or "<mailto:...>"
        urls = re.findall(r'<(https?://[^>]+)>', list_unsub)
        if urls:
            return urls[0]

    # Look in HTML content
    if html:
        soup = BeautifulSoup(html, "html.parser")
        for link in soup.find_all("a", href=True):
            href = link.get("href", "")
            text = link.get_text(strip=True).lower()
            if "unsubscribe" in text or "unsubscribe" in href.lower():
                if href.startswith("http"):
                    return href

    return None


def extract_article_content(parsed_email: ParsedEmail) -> str:
    """
    Extract clean article content from a parsed email.

    Uses the HTML content if available, otherwise falls back to plain text.
    Further cleans the content for article display.

    Args:
        parsed_email: Parsed email data

    Returns:
        Cleaned HTML content suitable for article display
    """
    if parsed_email.content_html:
        return _extract_article_from_html(parsed_email.content_html)
    elif parsed_email.content_text:
        # Convert plain text to simple HTML
        paragraphs = parsed_email.content_text.split("\n\n")
        html_parts = [f"<p>{_escape_html(p)}</p>" for p in paragraphs if p.strip()]
        return "\n".join(html_parts)
    return ""


def _extract_article_from_html(html: str) -> str:
    """Extract the main article content from newsletter HTML."""
    soup = BeautifulSoup(html, "html.parser")

    # Try to find the main content area
    # Different newsletters use different structures
    main_content = None

    # Common content selectors
    selectors = [
        "article",
        ".post-content",
        ".email-content",
        ".newsletter-content",
        ".body-content",
        '[role="article"]',
        ".post",
        "main",
    ]

    for selector in selectors:
        main_content = soup.select_one(selector)
        if main_content:
            break

    # If no specific content area found, use the body
    if not main_content:
        main_content = soup.body or soup

    # Remove remaining navigation, headers, footers
    for tag in main_content.find_all(["nav", "header", "footer"]):
        tag.decompose()

    # Remove social sharing buttons
    for elem in main_content.find_all(class_=re.compile(r"share|social|button", re.I)):
        elem.decompose()

    return str(main_content)


def _escape_html(text: str) -> str:
    """Escape HTML special characters."""
    return (
        text.replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace('"', "&quot;")
    )
