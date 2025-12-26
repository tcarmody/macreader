"""
Gmail IMAP Client for fetching newsletters.

Uses XOAUTH2 authentication with OAuth access tokens.
"""

import email
import imaplib
import logging
from dataclasses import dataclass
from typing import TYPE_CHECKING

from .oauth import generate_xoauth2_string, get_valid_access_token, GmailOAuthError
from ..email_parser import parse_eml_bytes, extract_article_content, EmailParseError

if TYPE_CHECKING:
    from ..database import Database


logger = logging.getLogger(__name__)


class GmailIMAPError(Exception):
    """Gmail IMAP operation error."""
    pass


@dataclass
class FetchedEmail:
    """Represents a fetched email from Gmail."""
    uid: int
    raw_bytes: bytes
    subject: str | None = None


class GmailIMAPClient:
    """Gmail IMAP client with OAuth2 authentication."""

    IMAP_HOST = "imap.gmail.com"
    IMAP_PORT = 993

    def __init__(self, email_address: str):
        self.email_address = email_address
        self.imap: imaplib.IMAP4_SSL | None = None

    def connect(self, access_token: str):
        """
        Connect to Gmail IMAP using XOAUTH2.

        Args:
            access_token: Valid OAuth access token
        """
        try:
            self.imap = imaplib.IMAP4_SSL(self.IMAP_HOST, self.IMAP_PORT)

            # Authenticate using XOAUTH2
            auth_string = generate_xoauth2_string(self.email_address, access_token)

            # Use AUTHENTICATE command with XOAUTH2
            self.imap.authenticate("XOAUTH2", lambda x: auth_string.encode())

            logger.info(f"Connected to Gmail IMAP as {self.email_address}")

        except imaplib.IMAP4.error as e:
            raise GmailIMAPError(f"IMAP authentication failed: {e}")
        except Exception as e:
            raise GmailIMAPError(f"IMAP connection failed: {e}")

    def disconnect(self):
        """Close the IMAP connection."""
        if self.imap:
            try:
                self.imap.close()
                self.imap.logout()
            except Exception:
                pass
            self.imap = None

    def list_labels(self) -> list[str]:
        """
        List all available Gmail labels/folders.

        Returns:
            List of label names
        """
        if not self.imap:
            raise GmailIMAPError("Not connected")

        try:
            status, labels_data = self.imap.list()

            if status != "OK":
                raise GmailIMAPError("Failed to list labels")

            labels = []
            for label_info in labels_data:
                if isinstance(label_info, bytes):
                    # Parse label from response like: (\HasNoChildren) "/" "Newsletters"
                    decoded = label_info.decode("utf-8", errors="replace")
                    # Extract the label name (last quoted string or last part)
                    if '"' in decoded:
                        parts = decoded.split('"')
                        if len(parts) >= 2:
                            label_name = parts[-2]  # Get the quoted label name
                            labels.append(label_name)
                    else:
                        # Fallback: take everything after the last space
                        parts = decoded.split()
                        if parts:
                            labels.append(parts[-1])

            # Sort and return unique labels
            return sorted(set(labels))

        except imaplib.IMAP4.error as e:
            raise GmailIMAPError(f"Failed to list labels: {e}")

    def select_label(self, label: str) -> int:
        """
        Select a Gmail label/folder.

        Args:
            label: Label name to select

        Returns:
            Number of messages in the label
        """
        if not self.imap:
            raise GmailIMAPError("Not connected")

        try:
            # Gmail labels may need quoting
            status, data = self.imap.select(f'"{label}"')

            if status != "OK":
                raise GmailIMAPError(f"Failed to select label: {label}")

            # data[0] contains the message count
            count = int(data[0]) if data and data[0] else 0
            logger.info(f"Selected label '{label}' with {count} messages")
            return count

        except imaplib.IMAP4.error as e:
            raise GmailIMAPError(f"Failed to select label '{label}': {e}")

    def fetch_since_uid(self, since_uid: int = 0) -> list[FetchedEmail]:
        """
        Fetch emails with UID greater than since_uid.

        Args:
            since_uid: Fetch emails with UID > this value (0 for all)

        Returns:
            List of FetchedEmail objects
        """
        if not self.imap:
            raise GmailIMAPError("Not connected")

        try:
            # Search for UIDs greater than the given UID
            if since_uid > 0:
                search_criteria = f"UID {since_uid + 1}:*"
            else:
                search_criteria = "ALL"

            status, data = self.imap.uid("search", None, search_criteria)

            if status != "OK":
                raise GmailIMAPError("Failed to search emails")

            # Parse UIDs from response
            uid_list = data[0].decode().split() if data[0] else []

            if not uid_list:
                logger.info("No new emails to fetch")
                return []

            # Filter out UIDs <= since_uid (in case search includes boundary)
            uids_to_fetch = [int(uid) for uid in uid_list if int(uid) > since_uid]

            if not uids_to_fetch:
                return []

            logger.info(f"Fetching {len(uids_to_fetch)} new emails")

            emails = []
            for uid in uids_to_fetch:
                try:
                    # Fetch the full email
                    status, msg_data = self.imap.uid("fetch", str(uid), "(RFC822)")

                    if status != "OK" or not msg_data or not msg_data[0]:
                        logger.warning(f"Failed to fetch email UID {uid}")
                        continue

                    # Extract raw email bytes
                    raw_email = msg_data[0][1] if isinstance(msg_data[0], tuple) else None

                    if raw_email:
                        # Try to get subject for logging
                        subject = None
                        try:
                            msg = email.message_from_bytes(raw_email)
                            subject = msg.get("Subject", "")
                        except Exception:
                            pass

                        emails.append(FetchedEmail(
                            uid=uid,
                            raw_bytes=raw_email,
                            subject=subject
                        ))

                except Exception as e:
                    logger.warning(f"Error fetching email UID {uid}: {e}")
                    continue

            return emails

        except imaplib.IMAP4.error as e:
            raise GmailIMAPError(f"Failed to fetch emails: {e}")

    def get_highest_uid(self) -> int:
        """
        Get the highest UID in the currently selected mailbox.

        Returns:
            Highest UID or 0 if empty
        """
        if not self.imap:
            raise GmailIMAPError("Not connected")

        try:
            status, data = self.imap.uid("search", None, "ALL")

            if status != "OK" or not data[0]:
                return 0

            uid_list = data[0].decode().split()
            if not uid_list:
                return 0

            return max(int(uid) for uid in uid_list)

        except Exception as e:
            logger.warning(f"Error getting highest UID: {e}")
            return 0


@dataclass
class GmailFetchResult:
    """Result of a Gmail fetch operation."""
    success: bool
    imported: int = 0
    failed: int = 0
    skipped: int = 0  # Duplicates
    errors: list[str] | None = None
    message: str | None = None


async def fetch_newsletters_from_gmail(db: "Database") -> GmailFetchResult:
    """
    Fetch newsletters from Gmail and import them.

    Args:
        db: Database instance

    Returns:
        GmailFetchResult with import statistics
    """
    config = db.get_gmail_config()

    if not config:
        return GmailFetchResult(
            success=False,
            message="Gmail not configured"
        )

    if not config.get("is_enabled", True):
        return GmailFetchResult(
            success=False,
            message="Gmail polling is disabled"
        )

    try:
        # Get valid access token (refresh if needed)
        access_token, email_address = await get_valid_access_token(db)

        # Connect to Gmail IMAP
        client = GmailIMAPClient(email_address)
        client.connect(access_token)

        try:
            # Select the monitored label
            label = config.get("monitored_label", "Newsletters")
            client.select_label(label)

            # Fetch emails since last UID
            last_uid = config.get("last_fetched_uid", 0)
            emails = client.fetch_since_uid(last_uid)

            if not emails:
                return GmailFetchResult(
                    success=True,
                    message="No new emails to import"
                )

            imported = 0
            failed = 0
            skipped = 0
            errors = []
            max_uid = last_uid

            for fetched in emails:
                try:
                    # Parse email using existing parser
                    parsed = parse_eml_bytes(fetched.raw_bytes)

                    # Extract article content
                    article_html = extract_article_content(parsed)

                    if not article_html or len(article_html.strip()) < 50:
                        logger.warning(f"Email '{fetched.subject}' has insufficient content")
                        skipped += 1
                        max_uid = max(max_uid, fetched.uid)
                        continue

                    # Generate unique URL for this newsletter
                    date_str = parsed.date.strftime("%Y%m%d%H%M%S") if parsed.date else "unknown"
                    newsletter_url = f"newsletter://gmail/{parsed.sender_email}_{date_str}"

                    # Import to database
                    item_id = db.add_standalone_item(
                        url=newsletter_url,
                        title=parsed.title,
                        content=article_html,
                        content_type="newsletter",
                        author=parsed.author,
                        published_at=parsed.date,
                    )

                    if item_id:
                        imported += 1
                        logger.info(f"Imported newsletter: {parsed.title}")
                    else:
                        # Duplicate
                        skipped += 1
                        logger.debug(f"Skipped duplicate: {parsed.title}")

                    max_uid = max(max_uid, fetched.uid)

                except EmailParseError as e:
                    failed += 1
                    errors.append(f"Parse error for '{fetched.subject}': {e}")
                    max_uid = max(max_uid, fetched.uid)
                except Exception as e:
                    failed += 1
                    errors.append(f"Import error for '{fetched.subject}': {e}")
                    max_uid = max(max_uid, fetched.uid)

            # Update last fetched UID
            if max_uid > last_uid:
                db.update_gmail_last_fetched_uid(max_uid)

            return GmailFetchResult(
                success=True,
                imported=imported,
                failed=failed,
                skipped=skipped,
                errors=errors if errors else None,
                message=f"Imported {imported} newsletters" + (f", {skipped} skipped" if skipped else "")
            )

        finally:
            client.disconnect()

    except GmailOAuthError as e:
        return GmailFetchResult(
            success=False,
            message=f"Authentication error: {e}"
        )
    except GmailIMAPError as e:
        return GmailFetchResult(
            success=False,
            message=f"IMAP error: {e}"
        )
    except Exception as e:
        logger.exception("Gmail fetch error")
        return GmailFetchResult(
            success=False,
            message=f"Unexpected error: {e}"
        )
