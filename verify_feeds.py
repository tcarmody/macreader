#!/usr/bin/env python3
"""
Diagnostic script to verify feed synchronization between database and API.
"""
import requests
import sqlite3
import json
from pathlib import Path

# Configuration
DB_PATH = Path("data/articles.db")
API_URL = "http://127.0.0.1:5005/feeds"

def get_feeds_from_db():
    """Get feeds directly from database."""
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()

    rows = cursor.execute("""
        SELECT f.id, f.name, f.url, f.category, f.last_fetched, f.fetch_error,
               COUNT(a.id) as article_count
        FROM feeds f
        LEFT JOIN articles a ON f.id = a.feed_id
        WHERE f.url NOT LIKE 'archive://%'
        GROUP BY f.id
        ORDER BY f.name
    """).fetchall()

    feeds = [dict(row) for row in rows]
    conn.close()
    return feeds

def get_feeds_from_api():
    """Get feeds from API endpoint."""
    try:
        response = requests.get(API_URL)
        response.raise_for_status()
        return response.json()
    except requests.exceptions.RequestException as e:
        print(f"Error fetching from API: {e}")
        return None

def categorize_feeds(feeds):
    """Separate RSS and newsletter feeds."""
    rss = []
    newsletters = []

    for feed in feeds:
        if feed['url'].startswith('newsletter://'):
            newsletters.append(feed)
        else:
            rss.append(feed)

    return rss, newsletters

def main():
    print("=" * 70)
    print("Feed Synchronization Diagnostic")
    print("=" * 70)

    # Get feeds from database
    print("\n📊 Checking database...")
    db_feeds = get_feeds_from_db()
    db_rss, db_newsletters = categorize_feeds(db_feeds)

    print(f"  Total feeds in DB: {len(db_feeds)}")
    print(f"  RSS feeds: {len(db_rss)}")
    print(f"  Newsletter feeds: {len(db_newsletters)}")

    # Get feeds from API
    print("\n🌐 Checking API...")
    api_feeds = get_feeds_from_api()

    if api_feeds is None:
        print("  ❌ Could not fetch feeds from API")
        print("  Make sure the backend is running: source rss_venv/bin/activate && python -m uvicorn backend.server:app --reload --port 5005")
        return

    api_rss, api_newsletters = categorize_feeds(api_feeds)

    print(f"  Total feeds from API: {len(api_feeds)}")
    print(f"  RSS feeds: {len(api_rss)}")
    print(f"  Newsletter feeds: {len(api_newsletters)}")

    # Compare
    print("\n🔍 Comparison:")
    if len(db_feeds) == len(api_feeds):
        print("  ✅ Feed counts match!")
    else:
        print(f"  ⚠️  Mismatch: DB has {len(db_feeds)}, API returns {len(api_feeds)}")

    # Show RSS feeds
    print("\n📰 RSS Feeds:")
    if api_rss:
        for feed in api_rss:
            category = feed.get('category') or 'Uncategorized'
            unread = feed.get('unread_count', 0)
            print(f"  • {feed['name']} ({category}) - {unread} unread")
    else:
        print("  (none)")

    # Show newsletter feeds
    print("\n📧 Newsletter Feeds:")
    if api_newsletters:
        for feed in api_newsletters:
            unread = feed.get('unread_count', 0)
            print(f"  • {feed['name']} - {unread} unread")
    else:
        print("  (none)")

    # Export for inspection
    output_file = Path("feed_diagnostic.json")
    with open(output_file, 'w') as f:
        json.dump({
            'database': db_feeds,
            'api': api_feeds
        }, f, indent=2)

    print(f"\n💾 Full feed data exported to: {output_file}")
    print("\nNext steps:")
    print("  1. Check if the web app is showing the same feeds listed above")
    print("  2. If different, try hard-refreshing the web app (Cmd+Shift+R)")
    print("  3. Check browser DevTools > Application > Storage to clear React Query cache")

if __name__ == "__main__":
    main()
