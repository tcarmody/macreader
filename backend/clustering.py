"""
Clustering - Claude-powered topic clustering for articles.

Groups articles by semantic topic using Claude API to identify
themes across titles and summaries.
"""

import anthropic
import hashlib
import json
from dataclasses import dataclass
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from .cache import TieredCache
    from .database import DBArticle


@dataclass
class Topic:
    """Represents a topic cluster."""
    id: str
    label: str
    article_ids: list[int]


@dataclass
class ClusteringResult:
    """Result of clustering operation."""
    topics: list[Topic]
    cached: bool = False


class Clusterer:
    """Claude-powered article clusterer."""

    # Model to use for clustering
    MODEL = "claude-haiku-4-5-20251001"

    # Cache TTL in seconds (1 hour)
    CACHE_TTL = 3600

    def __init__(
        self,
        api_key: str,
        cache: "TieredCache | None" = None
    ):
        self.client = anthropic.Anthropic(api_key=api_key)
        self.cache = cache

    def cluster(
        self,
        articles: list["DBArticle"],
        min_clusters: int | None = None,
        max_clusters: int | None = None
    ) -> ClusteringResult:
        """
        Group articles into topic clusters.

        Args:
            articles: List of articles to cluster
            min_clusters: Minimum number of topic clusters (auto-calculated if None)
            max_clusters: Maximum number of topic clusters (auto-calculated if None)

        Returns:
            ClusteringResult with list of Topic objects
        """
        if len(articles) < 2:
            # Not enough articles to cluster
            return ClusteringResult(
                topics=[Topic(
                    id="all",
                    label="All Articles",
                    article_ids=[a.id for a in articles]
                )],
                cached=False
            )

        # Scale cluster count based on number of articles
        # Aim for ~3-5 articles per cluster on average
        num_articles = len(articles)
        if min_clusters is None:
            min_clusters = max(2, num_articles // 5)
        if max_clusters is None:
            max_clusters = max(min_clusters + 2, num_articles // 3, 10)

        # Generate cache key from article IDs
        cache_key = self._make_cache_key(articles)

        # Check cache first
        if self.cache:
            cached = self.cache.get(cache_key)
            if cached and isinstance(cached, dict):
                topics = [
                    Topic(
                        id=t["id"],
                        label=t["label"],
                        article_ids=t["article_ids"]
                    )
                    for t in cached.get("topics", [])
                ]
                if topics:
                    return ClusteringResult(topics=topics, cached=True)

        # Build prompt with article info
        prompt = self._build_prompt(articles, min_clusters, max_clusters)

        # Call Claude API
        response = self.client.messages.create(
            model=self.MODEL,
            max_tokens=1024,
            messages=[{
                "role": "user",
                "content": prompt
            }]
        )

        # Parse response
        result = self._parse_response(response, articles)

        # Cache the result
        if self.cache and result.topics:
            self.cache.set(
                cache_key,
                {
                    "topics": [
                        {
                            "id": t.id,
                            "label": t.label,
                            "article_ids": t.article_ids
                        }
                        for t in result.topics
                    ]
                },
                ttl=self.CACHE_TTL
            )

        return result

    def _make_cache_key(self, articles: list["DBArticle"]) -> str:
        """Generate cache key from sorted article IDs."""
        ids = sorted(a.id for a in articles)
        id_str = ",".join(str(i) for i in ids)
        hash_val = hashlib.sha256(id_str.encode()).hexdigest()[:16]
        return f"clustering:{hash_val}"

    def _build_prompt(
        self,
        articles: list["DBArticle"],
        min_clusters: int,
        max_clusters: int
    ) -> str:
        """Build the clustering prompt."""
        # Format articles for the prompt
        article_lines = []
        for article in articles:
            # Use summary if available, otherwise first part of content
            description = article.summary_short or ""
            if not description and article.content:
                description = article.content[:150] + "..."

            article_lines.append(
                f"[id={article.id}] \"{article.title}\" - {description}"
            )

        articles_text = "\n".join(article_lines)

        return f"""Analyze these article titles and summaries. Group them into {min_clusters}-{max_clusters} specific topic clusters.

Articles:
{articles_text}

Return your response as valid JSON with this exact structure:
{{
  "topics": [
    {{"label": "Topic Name", "article_ids": [1, 2, 3]}}
  ]
}}

Rules:
- Create SPECIFIC, NARROW topics - not broad categories
- BAD: "Technology" or "Politics" (too broad)
- GOOD: "OpenAI GPT Models", "EU AI Regulation", "Tesla Earnings" (specific)
- Each topic should ideally have 2-5 articles
- If a topic would have 6+ articles, split it into more specific subtopics
- Every article must be assigned to exactly one topic
- Use short but specific topic labels (2-5 words)
- If an article doesn't fit any group, put it in "Other" topic
- Return ONLY the JSON, no other text"""

    def _parse_response(
        self,
        response,
        articles: list["DBArticle"]
    ) -> ClusteringResult:
        """Parse Claude's response into ClusteringResult."""
        text = response.content[0].text.strip()

        # Try to extract JSON from response
        try:
            # Handle case where response has markdown code blocks
            if "```" in text:
                # Extract JSON from code block
                start = text.find("```")
                end = text.rfind("```")
                if start != end:
                    json_text = text[start:end]
                    # Remove ```json or ``` prefix
                    json_text = json_text.split("\n", 1)[-1] if "\n" in json_text else json_text[3:]
                    text = json_text.strip()

            data = json.loads(text)
        except json.JSONDecodeError:
            # Fallback: put all articles in one group
            return ClusteringResult(
                topics=[Topic(
                    id="all",
                    label="All Articles",
                    article_ids=[a.id for a in articles]
                )],
                cached=False
            )

        # Parse topics from response
        topics: list[Topic] = []
        assigned_ids: set[int] = set()
        all_article_ids = {a.id for a in articles}

        for i, topic_data in enumerate(data.get("topics", [])):
            label = topic_data.get("label", f"Topic {i + 1}")
            article_ids = topic_data.get("article_ids", [])

            # Filter to only valid article IDs
            valid_ids = [
                aid for aid in article_ids
                if aid in all_article_ids and aid not in assigned_ids
            ]

            if valid_ids:
                topics.append(Topic(
                    id=f"topic_{i}",
                    label=label,
                    article_ids=valid_ids
                ))
                assigned_ids.update(valid_ids)

        # Handle any unassigned articles
        unassigned = [aid for aid in all_article_ids if aid not in assigned_ids]
        if unassigned:
            topics.append(Topic(
                id="other",
                label="Other",
                article_ids=unassigned
            ))

        return ClusteringResult(topics=topics, cached=False)

    async def cluster_async(
        self,
        articles: list["DBArticle"],
        min_clusters: int | None = None,
        max_clusters: int | None = None
    ) -> ClusteringResult:
        """
        Async version of cluster.

        Note: anthropic SDK is sync, so this wraps the sync call.
        """
        import asyncio
        loop = asyncio.get_event_loop()
        return await loop.run_in_executor(
            None,
            lambda: self.cluster(articles, min_clusters, max_clusters)
        )


def create_clusterer(
    api_key: str,
    cache: "TieredCache | None" = None
) -> Clusterer:
    """Factory function to create a Clusterer instance."""
    return Clusterer(api_key=api_key, cache=cache)
