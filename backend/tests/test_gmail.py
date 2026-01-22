"""
Tests for Gmail IMAP integration.
"""

from datetime import datetime, timezone, timedelta
from unittest.mock import AsyncMock, MagicMock, patch
import pytest

from backend.gmail.oauth import generate_xoauth2_string
from backend.gmail.imap import (
    GmailIMAPClient,
    GmailIMAPError,
    GmailFetchResult,
    FetchedEmail,
    fetch_newsletters_from_gmail,
)


class TestXOAuth2String:
    """Tests for XOAUTH2 authentication string generation."""

    def test_generates_correct_format(self):
        """XOAUTH2 string should have correct format with control characters."""
        result = generate_xoauth2_string("user@gmail.com", "access_token_123")

        # Should contain user, auth bearer, and control characters
        assert result == "user=user@gmail.com\x01auth=Bearer access_token_123\x01\x01"

    def test_not_base64_encoded(self):
        """XOAUTH2 string should NOT be base64-encoded (imaplib handles that)."""
        result = generate_xoauth2_string("test@example.com", "token")

        # Should contain raw control characters, not base64
        assert "\x01" in result
        assert "user=" in result
        assert "auth=Bearer" in result

    def test_handles_special_characters_in_email(self):
        """Should handle special characters in email address."""
        result = generate_xoauth2_string("user+tag@gmail.com", "token")
        assert "user=user+tag@gmail.com" in result

    def test_handles_long_token(self):
        """Should handle long access tokens."""
        long_token = "ya29." + "a" * 200
        result = generate_xoauth2_string("user@gmail.com", long_token)
        assert long_token in result


class TestGmailIMAPClient:
    """Tests for Gmail IMAP client."""

    def test_init_sets_email(self):
        """Client should store email address."""
        client = GmailIMAPClient("test@gmail.com")
        assert client.email_address == "test@gmail.com"
        assert client.imap is None

    def test_connect_raises_on_auth_failure(self):
        """Connect should raise GmailIMAPError on authentication failure."""
        client = GmailIMAPClient("test@gmail.com")

        with patch("imaplib.IMAP4_SSL") as mock_imap:
            mock_instance = MagicMock()
            mock_imap.return_value = mock_instance
            mock_instance.authenticate.side_effect = Exception("Auth failed")

            with pytest.raises(GmailIMAPError, match="IMAP connection failed"):
                client.connect("bad_token")

    def test_disconnect_handles_no_connection(self):
        """Disconnect should handle case when not connected."""
        client = GmailIMAPClient("test@gmail.com")
        # Should not raise
        client.disconnect()

    def test_list_labels_raises_when_not_connected(self):
        """list_labels should raise when not connected."""
        client = GmailIMAPClient("test@gmail.com")

        with pytest.raises(GmailIMAPError, match="Not connected"):
            client.list_labels()

    def test_select_label_raises_when_not_connected(self):
        """select_label should raise when not connected."""
        client = GmailIMAPClient("test@gmail.com")

        with pytest.raises(GmailIMAPError, match="Not connected"):
            client.select_label("INBOX")

    def test_fetch_since_uid_raises_when_not_connected(self):
        """fetch_since_uid should raise when not connected."""
        client = GmailIMAPClient("test@gmail.com")

        with pytest.raises(GmailIMAPError, match="Not connected"):
            client.fetch_since_uid(0)


class TestFetchNewslettersFromGmail:
    """Tests for the main fetch function."""

    @pytest.fixture
    def mock_db(self):
        """Create a mock database."""
        db = MagicMock()
        db.get_gmail_config.return_value = {
            "email": "test@gmail.com",
            "access_token": "valid_token",
            "refresh_token": "refresh_token",
            "token_expires_at": (datetime.now(timezone.utc) + timedelta(hours=1)).isoformat(),
            "monitored_label": "Newsletters",
            "last_fetched_uid": 0,
            "is_enabled": True,
        }
        return db

    @pytest.mark.asyncio
    async def test_returns_error_when_not_configured(self):
        """Should return error when Gmail is not configured."""
        db = MagicMock()
        db.get_gmail_config.return_value = None

        result = await fetch_newsletters_from_gmail(db)

        assert result.success is False
        assert "not configured" in result.message

    @pytest.mark.asyncio
    async def test_returns_error_when_disabled(self):
        """Should return error when Gmail polling is disabled."""
        db = MagicMock()
        db.get_gmail_config.return_value = {
            "is_enabled": False,
        }

        result = await fetch_newsletters_from_gmail(db)

        assert result.success is False
        assert "disabled" in result.message

    @pytest.mark.asyncio
    async def test_fetch_all_ignores_last_uid(self, mock_db):
        """fetch_all=True should fetch from UID 0."""
        mock_db.get_gmail_config.return_value["last_fetched_uid"] = 100

        with patch("backend.gmail.imap.get_valid_access_token") as mock_token, \
             patch("backend.gmail.imap.GmailIMAPClient") as mock_client_class:

            mock_token.return_value = ("token", "test@gmail.com")
            mock_client = MagicMock()
            mock_client_class.return_value = mock_client
            mock_client.fetch_since_uid.return_value = []

            await fetch_newsletters_from_gmail(mock_db, fetch_all=True)

            # Should be called with 0, not 100
            mock_client.fetch_since_uid.assert_called_once_with(0)

    @pytest.mark.asyncio
    async def test_normal_fetch_uses_last_uid(self, mock_db):
        """Normal fetch should use last_fetched_uid."""
        mock_db.get_gmail_config.return_value["last_fetched_uid"] = 50

        with patch("backend.gmail.imap.get_valid_access_token") as mock_token, \
             patch("backend.gmail.imap.GmailIMAPClient") as mock_client_class:

            mock_token.return_value = ("token", "test@gmail.com")
            mock_client = MagicMock()
            mock_client_class.return_value = mock_client
            mock_client.fetch_since_uid.return_value = []

            await fetch_newsletters_from_gmail(mock_db, fetch_all=False)

            # Should be called with 50
            mock_client.fetch_since_uid.assert_called_once_with(50)

    @pytest.mark.asyncio
    async def test_returns_success_with_no_new_emails(self, mock_db):
        """Should return success when no new emails."""
        with patch("backend.gmail.imap.get_valid_access_token") as mock_token, \
             patch("backend.gmail.imap.GmailIMAPClient") as mock_client_class:

            mock_token.return_value = ("token", "test@gmail.com")
            mock_client = MagicMock()
            mock_client_class.return_value = mock_client
            mock_client.fetch_since_uid.return_value = []

            result = await fetch_newsletters_from_gmail(mock_db)

            assert result.success is True
            assert "No new emails" in result.message


class TestGmailRoutes:
    """Tests for Gmail API routes."""

    def test_status_returns_not_connected(self, client):
        """Status should show not connected when no config."""
        response = client.get("/gmail/status")
        assert response.status_code == 200
        data = response.json()
        assert data["connected"] is False

    def test_labels_requires_connection(self, client):
        """Labels endpoint should fail when not connected."""
        response = client.get("/gmail/labels")
        # Should return 401 (OAuth error) since not configured
        assert response.status_code == 401

    def test_fetch_requires_connection(self, client):
        """Fetch endpoint should fail when not connected."""
        response = client.post("/gmail/fetch")
        assert response.status_code == 200
        data = response.json()
        assert data["success"] is False
        assert "not configured" in data["message"]

    def test_fetch_all_parameter(self, client):
        """Fetch endpoint should accept fetch_all parameter."""
        response = client.post("/gmail/fetch?fetch_all=true")
        assert response.status_code == 200
        data = response.json()
        # Will fail because not configured, but parameter should be accepted
        assert data["success"] is False

    def test_config_update_requires_connection(self, client):
        """Config update should fail when not connected."""
        response = client.put(
            "/gmail/config",
            json={"monitored_label": "Test"}
        )
        assert response.status_code == 404
        assert "not connected" in response.json()["detail"]

    def test_disconnect_works_when_not_connected(self, client):
        """Disconnect should succeed even when not connected."""
        response = client.delete("/gmail/disconnect")
        assert response.status_code == 200
        data = response.json()
        assert data["success"] is True


class TestGmailConfigWithDatabase:
    """Tests for Gmail configuration with actual database."""

    def test_save_and_retrieve_config(self, test_db):
        """Should save and retrieve Gmail config."""
        expires = datetime.now(timezone.utc) + timedelta(hours=1)

        test_db.save_gmail_config(
            email="test@gmail.com",
            access_token="access123",
            refresh_token="refresh456",
            token_expires_at=expires,
            monitored_label="MyNewsletters",
            poll_interval_minutes=15,
        )

        config = test_db.get_gmail_config()

        assert config is not None
        assert config["email"] == "test@gmail.com"
        assert config["access_token"] == "access123"
        assert config["refresh_token"] == "refresh456"
        assert config["monitored_label"] == "MyNewsletters"
        assert config["poll_interval_minutes"] == 15
        assert config["last_fetched_uid"] == 0
        assert config["is_enabled"] is True

    def test_update_last_fetched_uid(self, test_db):
        """Should update last fetched UID."""
        expires = datetime.now(timezone.utc) + timedelta(hours=1)

        test_db.save_gmail_config(
            email="test@gmail.com",
            access_token="access123",
            refresh_token="refresh456",
            token_expires_at=expires,
        )

        test_db.update_gmail_last_fetched_uid(42)

        config = test_db.get_gmail_config()
        assert config["last_fetched_uid"] == 42

    def test_update_config_settings(self, test_db):
        """Should update config settings."""
        expires = datetime.now(timezone.utc) + timedelta(hours=1)

        test_db.save_gmail_config(
            email="test@gmail.com",
            access_token="access123",
            refresh_token="refresh456",
            token_expires_at=expires,
        )

        test_db.update_gmail_config(
            monitored_label="NewLabel",
            poll_interval_minutes=60,
            is_enabled=False,
        )

        config = test_db.get_gmail_config()
        assert config["monitored_label"] == "NewLabel"
        assert config["poll_interval_minutes"] == 60
        assert config["is_enabled"] is False

    def test_delete_config(self, test_db):
        """Should delete Gmail config."""
        expires = datetime.now(timezone.utc) + timedelta(hours=1)

        test_db.save_gmail_config(
            email="test@gmail.com",
            access_token="access123",
            refresh_token="refresh456",
            token_expires_at=expires,
        )

        test_db.delete_gmail_config()

        config = test_db.get_gmail_config()
        assert config is None

    def test_save_replaces_existing_config(self, test_db):
        """Saving new config should replace existing one."""
        expires = datetime.now(timezone.utc) + timedelta(hours=1)

        # Save first config
        test_db.save_gmail_config(
            email="first@gmail.com",
            access_token="token1",
            refresh_token="refresh1",
            token_expires_at=expires,
        )

        # Save second config (should replace)
        test_db.save_gmail_config(
            email="second@gmail.com",
            access_token="token2",
            refresh_token="refresh2",
            token_expires_at=expires,
        )

        config = test_db.get_gmail_config()
        assert config["email"] == "second@gmail.com"
        assert config["access_token"] == "token2"


class TestNewsletterFeeds:
    """Tests for newsletter feed functionality."""

    def test_get_or_create_newsletter_feed_creates_new(self, test_db):
        """Should create a new feed for a newsletter sender."""
        feed_id = test_db.get_or_create_newsletter_feed(
            sender_email="newsletter@example.com",
            sender_name="Example Newsletter",
            newsletter_name="The Example"
        )

        assert feed_id is not None
        feed = test_db.get_feed(feed_id)
        assert feed is not None
        assert feed.name == "The Example"
        assert feed.category == "Newsletters"
        assert feed.url == "newsletter://newsletter@example.com"

    def test_get_or_create_newsletter_feed_returns_existing(self, test_db):
        """Should return existing feed for same sender."""
        feed_id1 = test_db.get_or_create_newsletter_feed(
            sender_email="newsletter@example.com",
            sender_name="Example Newsletter",
            newsletter_name="The Example"
        )

        feed_id2 = test_db.get_or_create_newsletter_feed(
            sender_email="newsletter@example.com",
            sender_name="Different Name",
            newsletter_name="Different Newsletter"
        )

        assert feed_id1 == feed_id2

    def test_get_or_create_newsletter_feed_uses_sender_name_fallback(self, test_db):
        """Should use sender_name when newsletter_name is None."""
        feed_id = test_db.get_or_create_newsletter_feed(
            sender_email="author@example.com",
            sender_name="John Doe",
            newsletter_name=None
        )

        feed = test_db.get_feed(feed_id)
        assert feed.name == "John Doe"

    def test_is_newsletter_feed(self, test_db):
        """Should correctly identify newsletter feeds."""
        # Create a newsletter feed
        newsletter_feed_id = test_db.get_or_create_newsletter_feed(
            sender_email="test@example.com",
            sender_name="Test",
        )

        # Create a regular RSS feed
        rss_feed_id = test_db.add_feed(
            url="https://example.com/feed.xml",
            name="RSS Feed"
        )

        assert test_db.is_newsletter_feed(newsletter_feed_id) is True
        assert test_db.is_newsletter_feed(rss_feed_id) is False

    def test_different_senders_get_different_feeds(self, test_db):
        """Each sender should get their own feed."""
        feed_id1 = test_db.get_or_create_newsletter_feed(
            sender_email="sender1@example.com",
            sender_name="Sender One",
        )

        feed_id2 = test_db.get_or_create_newsletter_feed(
            sender_email="sender2@example.com",
            sender_name="Sender Two",
        )

        assert feed_id1 != feed_id2

        feed1 = test_db.get_feed(feed_id1)
        feed2 = test_db.get_feed(feed_id2)
        assert feed1.name == "Sender One"
        assert feed2.name == "Sender Two"
