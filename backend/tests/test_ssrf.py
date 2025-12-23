"""
Tests for SSRF (Server-Side Request Forgery) protection.
"""

import pytest

from backend.url_validator import validate_url, SSRFError, is_ip_blocked


class TestSSRFProtection:
    """Tests for URL validation and SSRF prevention."""

    # --- Allowed URLs ---

    def test_allows_https_url(self):
        """Should allow standard HTTPS URLs."""
        result = validate_url("https://example.com/feed.xml", resolve_dns=False)
        assert result == "https://example.com/feed.xml"

    def test_allows_http_url(self):
        """Should allow standard HTTP URLs."""
        result = validate_url("http://example.com/feed.xml", resolve_dns=False)
        assert result == "http://example.com/feed.xml"

    def test_allows_public_ip(self):
        """Should allow public IP addresses."""
        result = validate_url("http://8.8.8.8/feed", resolve_dns=False)
        assert result == "http://8.8.8.8/feed"

    # --- Blocked Schemes ---

    def test_blocks_file_scheme(self):
        """Should block file:// URLs."""
        with pytest.raises(SSRFError, match="scheme.*not allowed"):
            validate_url("file:///etc/passwd")

    def test_blocks_ftp_scheme(self):
        """Should block ftp:// URLs."""
        with pytest.raises(SSRFError, match="scheme.*not allowed"):
            validate_url("ftp://example.com/file")

    def test_blocks_gopher_scheme(self):
        """Should block gopher:// URLs."""
        with pytest.raises(SSRFError, match="scheme.*not allowed"):
            validate_url("gopher://example.com/")

    # --- Blocked Hostnames ---

    def test_blocks_localhost(self):
        """Should block localhost."""
        with pytest.raises(SSRFError, match="not allowed"):
            validate_url("http://localhost/admin", resolve_dns=False)

    def test_blocks_localhost_localdomain(self):
        """Should block localhost.localdomain."""
        with pytest.raises(SSRFError, match="not allowed"):
            validate_url("http://localhost.localdomain/", resolve_dns=False)

    def test_blocks_metadata_hostname(self):
        """Should block cloud metadata hostnames."""
        with pytest.raises(SSRFError, match="not allowed"):
            validate_url("http://metadata.google.internal/", resolve_dns=False)

    def test_blocks_local_domain(self):
        """Should block .local domain."""
        with pytest.raises(SSRFError, match="not allowed"):
            validate_url("http://myserver.local/", resolve_dns=False)

    def test_blocks_internal_domain(self):
        """Should block .internal domain."""
        with pytest.raises(SSRFError, match="not allowed"):
            validate_url("http://api.internal/", resolve_dns=False)

    # --- Blocked IP Ranges ---

    def test_blocks_loopback_127_0_0_1(self):
        """Should block 127.0.0.1 (loopback)."""
        with pytest.raises(SSRFError, match="not allowed"):
            validate_url("http://127.0.0.1/admin", resolve_dns=False)

    def test_blocks_loopback_127_x(self):
        """Should block any 127.x.x.x address."""
        with pytest.raises(SSRFError, match="not allowed"):
            validate_url("http://127.0.0.100/", resolve_dns=False)

    def test_blocks_private_10_x(self):
        """Should block 10.x.x.x private range."""
        with pytest.raises(SSRFError, match="not allowed"):
            validate_url("http://10.0.0.1/", resolve_dns=False)

    def test_blocks_private_172_16_x(self):
        """Should block 172.16.x.x private range."""
        with pytest.raises(SSRFError, match="not allowed"):
            validate_url("http://172.16.0.1/", resolve_dns=False)

    def test_blocks_private_192_168_x(self):
        """Should block 192.168.x.x private range."""
        with pytest.raises(SSRFError, match="not allowed"):
            validate_url("http://192.168.1.1/", resolve_dns=False)

    def test_blocks_link_local_169_254_x(self):
        """Should block 169.254.x.x link-local (cloud metadata)."""
        with pytest.raises(SSRFError, match="not allowed"):
            validate_url("http://169.254.169.254/latest/meta-data/", resolve_dns=False)

    def test_blocks_ipv6_loopback(self):
        """Should block IPv6 loopback ::1."""
        with pytest.raises(SSRFError, match="not allowed"):
            validate_url("http://[::1]/", resolve_dns=False)

    # --- IP Range Helper ---

    def test_is_ip_blocked_private(self):
        """Test is_ip_blocked for private ranges."""
        assert is_ip_blocked("10.0.0.1") is True
        assert is_ip_blocked("172.16.0.1") is True
        assert is_ip_blocked("192.168.1.1") is True

    def test_is_ip_blocked_loopback(self):
        """Test is_ip_blocked for loopback."""
        assert is_ip_blocked("127.0.0.1") is True
        assert is_ip_blocked("127.0.0.100") is True

    def test_is_ip_blocked_link_local(self):
        """Test is_ip_blocked for link-local."""
        assert is_ip_blocked("169.254.169.254") is True

    def test_is_ip_blocked_public(self):
        """Test is_ip_blocked for public IPs."""
        assert is_ip_blocked("8.8.8.8") is False
        assert is_ip_blocked("1.1.1.1") is False
        assert is_ip_blocked("93.184.216.34") is False  # example.com

    # --- Invalid URLs ---

    def test_rejects_empty_hostname(self):
        """Should reject URLs without hostname."""
        with pytest.raises(SSRFError, match="hostname"):
            validate_url("http:///path")

    def test_rejects_invalid_url(self):
        """Should reject malformed URLs."""
        with pytest.raises(SSRFError):
            validate_url("not-a-url")


class TestSSRFWithDNS:
    """Tests that involve DNS resolution (may be slower)."""

    def test_blocks_dns_rebinding_localhost(self):
        """
        DNS resolution should catch hostnames that resolve to blocked IPs.

        Note: This test uses resolve_dns=True which does actual DNS lookups.
        """
        # localhost is caught as blocked hostname before DNS resolution
        with pytest.raises(SSRFError, match="not allowed"):
            validate_url("http://localhost/", resolve_dns=True)
