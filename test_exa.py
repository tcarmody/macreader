#!/usr/bin/env python3
"""Quick test script to verify Exa API is working."""

import os
import sys
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

# Add backend to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from exa_py import Exa

# Get API key
api_key = os.getenv("EXA_API_KEY")
if not api_key:
    print("ERROR: EXA_API_KEY not set in .env")
    sys.exit(1)

print(f"Testing Exa API with key: {api_key[:10]}...")

try:
    # Initialize Exa client
    client = Exa(api_key)

    # Test search
    print("\nSearching for: 'artificial intelligence machine learning'")
    response = client.search(
        query="artificial intelligence machine learning",
        num_results=3
    )

    print(f"\n✓ Success! Found {len(response.results)} results:\n")

    for i, result in enumerate(response.results, 1):
        print(f"{i}. {result.title}")
        print(f"   URL: {result.url}")
        print(f"   Score: {getattr(result, 'score', 'N/A')}")
        print()

except Exception as e:
    print(f"\n✗ Error: {e}")
    import traceback
    traceback.print_exc()
    sys.exit(1)
