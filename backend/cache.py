"""
Cache - Unified caching with pluggable backends.

Provides:
- MemoryCache: Fast in-memory cache with LRU eviction
- DiskCache: Persistent disk cache with TTL
- TieredCache: Memory -> Disk fallback
"""

from abc import ABC, abstractmethod
from dataclasses import dataclass
from datetime import datetime, timedelta
from pathlib import Path
from typing import Any
import json
import hashlib


@dataclass
class CacheEntry:
    key: str
    value: Any
    created_at: datetime
    expires_at: datetime | None


class CacheBackend(ABC):
    """Abstract base class for cache backends."""

    @abstractmethod
    def get(self, key: str) -> Any | None:
        """Get a value from cache."""
        pass

    @abstractmethod
    def set(self, key: str, value: Any, ttl: int | None = None) -> None:
        """Set a value in cache with optional TTL in seconds."""
        pass

    @abstractmethod
    def delete(self, key: str) -> None:
        """Delete a value from cache."""
        pass

    @abstractmethod
    def clear(self) -> None:
        """Clear all values from cache."""
        pass


class MemoryCache(CacheBackend):
    """Fast in-memory cache with LRU eviction."""

    def __init__(self, max_size: int = 256):
        self.max_size = max_size
        self._cache: dict[str, CacheEntry] = {}
        self._access_order: list[str] = []  # Track access order for LRU

    def get(self, key: str) -> Any | None:
        if key not in self._cache:
            return None

        entry = self._cache[key]

        # Check expiration
        if entry.expires_at and entry.expires_at < datetime.now():
            self.delete(key)
            return None

        # Update access order (move to end for LRU)
        if key in self._access_order:
            self._access_order.remove(key)
        self._access_order.append(key)

        return entry.value

    def set(self, key: str, value: Any, ttl: int | None = None) -> None:
        # Evict if at capacity
        while len(self._cache) >= self.max_size and key not in self._cache:
            self._evict_oldest()

        expires_at = datetime.now() + timedelta(seconds=ttl) if ttl else None

        self._cache[key] = CacheEntry(
            key=key,
            value=value,
            created_at=datetime.now(),
            expires_at=expires_at
        )

        # Update access order
        if key in self._access_order:
            self._access_order.remove(key)
        self._access_order.append(key)

    def delete(self, key: str) -> None:
        self._cache.pop(key, None)
        if key in self._access_order:
            self._access_order.remove(key)

    def clear(self) -> None:
        self._cache.clear()
        self._access_order.clear()

    def _evict_oldest(self):
        """Evict least recently used entry."""
        if self._access_order:
            oldest_key = self._access_order.pop(0)
            self._cache.pop(oldest_key, None)

    @property
    def size(self) -> int:
        return len(self._cache)


class DiskCache(CacheBackend):
    """Persistent disk cache for summaries."""

    def __init__(self, cache_dir: Path, ttl_days: int = 30):
        self.cache_dir = cache_dir
        self.ttl_days = ttl_days
        self.cache_dir.mkdir(parents=True, exist_ok=True)

    def _key_to_path(self, key: str) -> Path:
        """Convert cache key to file path."""
        hashed = hashlib.sha256(key.encode()).hexdigest()[:16]
        return self.cache_dir / f"{hashed}.json"

    def get(self, key: str) -> Any | None:
        path = self._key_to_path(key)
        if not path.exists():
            return None

        try:
            data = json.loads(path.read_text())

            # Verify key matches (handle hash collisions)
            if data.get("key") != key:
                return None

            # Check TTL
            created = datetime.fromisoformat(data["created_at"])
            if datetime.now() - created > timedelta(days=self.ttl_days):
                path.unlink(missing_ok=True)
                return None

            return data["value"]

        except (json.JSONDecodeError, KeyError, ValueError):
            # Corrupted cache file
            path.unlink(missing_ok=True)
            return None

    def set(self, key: str, value: Any, ttl: int | None = None) -> None:
        path = self._key_to_path(key)
        data = {
            "key": key,
            "value": value,
            "created_at": datetime.now().isoformat()
        }

        try:
            path.write_text(json.dumps(data, default=str))
        except (TypeError, IOError):
            # Skip caching if value isn't JSON serializable or disk error
            pass

    def delete(self, key: str) -> None:
        path = self._key_to_path(key)
        path.unlink(missing_ok=True)

    def clear(self) -> None:
        """Clear all cached files."""
        for file in self.cache_dir.glob("*.json"):
            file.unlink(missing_ok=True)

    def cleanup_expired(self) -> int:
        """Remove expired cache entries. Returns count of removed entries."""
        removed = 0
        for file in self.cache_dir.glob("*.json"):
            try:
                data = json.loads(file.read_text())
                created = datetime.fromisoformat(data["created_at"])
                if datetime.now() - created > timedelta(days=self.ttl_days):
                    file.unlink()
                    removed += 1
            except (json.JSONDecodeError, KeyError, ValueError):
                file.unlink(missing_ok=True)
                removed += 1
        return removed


class TieredCache(CacheBackend):
    """Two-tier cache: memory (fast) -> disk (persistent)."""

    def __init__(
        self,
        cache_dir: Path,
        memory_size: int = 256,
        ttl_days: int = 30
    ):
        self.memory = MemoryCache(max_size=memory_size)
        self.disk = DiskCache(cache_dir, ttl_days=ttl_days)

    def get(self, key: str) -> Any | None:
        # Check memory first
        if value := self.memory.get(key):
            return value

        # Fall back to disk
        if value := self.disk.get(key):
            # Promote to memory for faster subsequent access
            self.memory.set(key, value)
            return value

        return None

    def set(self, key: str, value: Any, ttl: int | None = None) -> None:
        # Store in both tiers
        self.memory.set(key, value, ttl)
        self.disk.set(key, value, ttl)

    def delete(self, key: str) -> None:
        self.memory.delete(key)
        self.disk.delete(key)

    def clear(self) -> None:
        self.memory.clear()
        self.disk.clear()

    def cleanup_expired(self) -> int:
        """Remove expired disk cache entries."""
        return self.disk.cleanup_expired()


# Helper function to create a cache instance from settings
def create_cache(cache_dir: str | Path, memory_size: int = 256, ttl_days: int = 30) -> TieredCache:
    """Factory function to create a TieredCache instance."""
    return TieredCache(
        cache_dir=Path(cache_dir),
        memory_size=memory_size,
        ttl_days=ttl_days
    )
