"""
URL Validator - Prevent SSRF attacks by blocking internal network access.

This module validates URLs before they are fetched to prevent Server-Side
Request Forgery (SSRF) attacks where an attacker could:
- Access internal network services (localhost, 127.0.0.1, etc.)
- Probe cloud metadata endpoints (169.254.169.254)
- Access internal infrastructure via private IP ranges
"""

import ipaddress
import socket
from urllib.parse import urlparse

from fastapi import HTTPException


class SSRFError(Exception):
    """Raised when a URL fails SSRF validation."""

    pass


# Blocked IP ranges (private, loopback, link-local, metadata)
BLOCKED_IP_RANGES = [
    # IPv4 private ranges
    ipaddress.ip_network("10.0.0.0/8"),
    ipaddress.ip_network("172.16.0.0/12"),
    ipaddress.ip_network("192.168.0.0/16"),
    # Loopback
    ipaddress.ip_network("127.0.0.0/8"),
    # Link-local
    ipaddress.ip_network("169.254.0.0/16"),
    # Reserved
    ipaddress.ip_network("0.0.0.0/8"),
    # Broadcast
    ipaddress.ip_network("255.255.255.255/32"),
    # Documentation ranges
    ipaddress.ip_network("192.0.2.0/24"),
    ipaddress.ip_network("198.51.100.0/24"),
    ipaddress.ip_network("203.0.113.0/24"),
    # IPv6 equivalents
    ipaddress.ip_network("::1/128"),  # Loopback
    ipaddress.ip_network("fc00::/7"),  # Unique local
    ipaddress.ip_network("fe80::/10"),  # Link-local
]

# Blocked hostnames
BLOCKED_HOSTNAMES = {
    "localhost",
    "localhost.localdomain",
    "ip6-localhost",
    "ip6-loopback",
    "metadata",
    "metadata.google.internal",
    "kubernetes.default",
    "kubernetes.default.svc",
}

# Allowed URL schemes
ALLOWED_SCHEMES = {"http", "https"}


def is_ip_blocked(ip_str: str) -> bool:
    """Check if an IP address is in a blocked range."""
    try:
        ip = ipaddress.ip_address(ip_str)
        for network in BLOCKED_IP_RANGES:
            if ip in network:
                return True
        return False
    except ValueError:
        # Invalid IP address format
        return False


def validate_url(url: str, resolve_dns: bool = True) -> str:
    """
    Validate a URL for SSRF attacks.

    Args:
        url: The URL to validate
        resolve_dns: Whether to resolve DNS and check the IP address

    Returns:
        The validated URL (may be normalized)

    Raises:
        SSRFError: If the URL fails validation
    """
    # Parse the URL
    try:
        parsed = urlparse(url)
    except Exception as e:
        raise SSRFError(f"Invalid URL format: {e}")

    # Check scheme
    if parsed.scheme.lower() not in ALLOWED_SCHEMES:
        raise SSRFError(f"URL scheme '{parsed.scheme}' is not allowed. Use http or https.")

    # Check for empty host
    if not parsed.hostname:
        raise SSRFError("URL must include a hostname")

    hostname = parsed.hostname.lower()

    # Check blocked hostnames
    if hostname in BLOCKED_HOSTNAMES:
        raise SSRFError(f"Access to '{hostname}' is not allowed")

    # Check if hostname is an IP address
    try:
        ip = ipaddress.ip_address(hostname)
        if is_ip_blocked(str(ip)):
            raise SSRFError(f"Access to IP address '{ip}' is not allowed")
    except ValueError:
        # Not an IP address, it's a hostname - check for blocked patterns
        if hostname.endswith(".local"):
            raise SSRFError("Access to .local domains is not allowed")
        if hostname.endswith(".internal"):
            raise SSRFError("Access to .internal domains is not allowed")
        if hostname.endswith(".localhost"):
            raise SSRFError("Access to .localhost domains is not allowed")

    # Resolve DNS and check the actual IP address
    if resolve_dns:
        try:
            # Get all IP addresses for the hostname
            addrinfo = socket.getaddrinfo(hostname, parsed.port or 80, proto=socket.IPPROTO_TCP)
            for family, _, _, _, sockaddr in addrinfo:
                ip_str = sockaddr[0]
                if is_ip_blocked(ip_str):
                    raise SSRFError(
                        f"Hostname '{hostname}' resolves to blocked IP address '{ip_str}'"
                    )
        except socket.gaierror:
            # DNS resolution failed - this will fail at fetch time anyway
            pass
        except SSRFError:
            raise
        except Exception:
            # Other resolution errors - let them proceed and fail at fetch time
            pass

    return url


def validate_url_or_raise_http(url: str, resolve_dns: bool = True) -> str:
    """
    Validate a URL, raising HTTPException on failure.

    Convenience wrapper for use in FastAPI route handlers.

    Args:
        url: The URL to validate
        resolve_dns: Whether to resolve DNS and check the IP address

    Returns:
        The validated URL

    Raises:
        HTTPException: 400 Bad Request if the URL fails validation
    """
    try:
        return validate_url(url, resolve_dns=resolve_dns)
    except SSRFError as e:
        raise HTTPException(status_code=400, detail=str(e))
