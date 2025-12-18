"""
Summarizer - Claude API integration for article summarization.

Features:
- Automatic model selection (Sonnet for complex, Haiku for simple)
- Structured summary output (one-liner, full summary, key points)
- Cache integration
"""

import anthropic
from dataclasses import dataclass
from enum import Enum
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from .cache import TieredCache


class Model(Enum):
    """Available Claude models for summarization."""
    SONNET = "claude-sonnet-4-5-20250514"
    HAIKU = "claude-haiku-4-5-20251001"


@dataclass
class Summary:
    """Structured article summary."""
    title: str
    one_liner: str          # 1 sentence for feed view
    full_summary: str       # 3-5 paragraphs
    key_points: list[str]   # Bullet points
    model_used: Model
    cached: bool = False


class Summarizer:
    """Claude-powered article summarizer."""

    # Technical terms that suggest complex content
    TECHNICAL_TERMS = [
        "algorithm", "neural", "quantum", "blockchain", "protocol",
        "cryptographic", "machine learning", "artificial intelligence",
        "api", "infrastructure", "architecture", "microservices",
        "distributed", "consensus", "encryption", "compiler",
        "semiconductor", "genomic", "molecular", "theorem",
    ]

    # Maximum content length to send to API
    MAX_CONTENT_LENGTH = 15000

    def __init__(
        self,
        api_key: str,
        cache: "TieredCache | None" = None,
        default_model: Model = Model.HAIKU
    ):
        self.client = anthropic.Anthropic(api_key=api_key)
        self.cache = cache
        self.default_model = default_model

    def summarize(
        self,
        content: str,
        url: str,
        title: str = "",
        force_model: Model | None = None
    ) -> Summary:
        """
        Generate a summary for article content.

        Args:
            content: The article text to summarize
            url: URL used as cache key
            title: Optional article title
            force_model: Override automatic model selection

        Returns:
            Summary object with one-liner, full summary, and key points
        """
        # Check cache first
        if self.cache:
            if cached := self.cache.get(f"summary:{url}"):
                if isinstance(cached, dict):
                    return Summary(
                        title=cached.get("title", title),
                        one_liner=cached.get("one_liner", ""),
                        full_summary=cached.get("full_summary", ""),
                        key_points=cached.get("key_points", []),
                        model_used=Model(cached.get("model_used", self.default_model.value)),
                        cached=True
                    )

        # Select model based on content complexity
        model = force_model or self._select_model(content)

        # Generate summary
        response = self.client.messages.create(
            model=model.value,
            max_tokens=1024,
            messages=[{
                "role": "user",
                "content": self._build_prompt(content, title)
            }]
        )

        summary = self._parse_response(response, model, title)

        # Cache the result
        if self.cache:
            self.cache.set(f"summary:{url}", {
                "title": summary.title,
                "one_liner": summary.one_liner,
                "full_summary": summary.full_summary,
                "key_points": summary.key_points,
                "model_used": summary.model_used.value
            })

        return summary

    def _select_model(self, content: str) -> Model:
        """
        Select appropriate model based on content complexity.

        Uses Sonnet for:
        - Long content (>2000 words)
        - Technical content
        """
        word_count = len(content.split())

        # Long content needs more capable model
        if word_count > 2000:
            return Model.SONNET

        # Check for technical terms
        content_lower = content.lower()
        technical_count = sum(
            1 for term in self.TECHNICAL_TERMS
            if term in content_lower
        )

        # More than 2 technical terms suggests complex content
        if technical_count > 2:
            return Model.SONNET

        return self.default_model

    def _build_prompt(self, content: str, title: str = "") -> str:
        """Build the summarization prompt."""
        title_context = f"Title: {title}\n\n" if title else ""

        # Truncate content if too long
        truncated_content = content[:self.MAX_CONTENT_LENGTH]
        if len(content) > self.MAX_CONTENT_LENGTH:
            truncated_content += "\n\n[Content truncated...]"

        return f"""Summarize this article. Provide your response in exactly this format:

ONE-SENTENCE SUMMARY:
[A single sentence of max 150 characters summarizing the key point]

FULL SUMMARY:
[A comprehensive summary in 3-5 paragraphs covering the main points]

KEY POINTS:
- [First key point]
- [Second key point]
- [Third key point]
- [Optional fourth point]
- [Optional fifth point]

{title_context}Article:
{truncated_content}"""

    def _parse_response(self, response, model: Model, title: str = "") -> Summary:
        """Parse Claude's response into structured Summary."""
        text = response.content[0].text

        # Default values
        one_liner = ""
        full_summary = ""
        key_points: list[str] = []

        # Split response into sections
        lines = text.strip().split("\n")
        current_section: str | None = None
        current_content: list[str] = []

        for line in lines:
            line_stripped = line.strip()
            line_lower = line_stripped.lower()

            # Detect section headers
            if "one-sentence" in line_lower or line_lower.startswith("one sentence"):
                if current_section == "full":
                    full_summary = "\n".join(current_content).strip()
                current_section = "one_liner"
                current_content = []
            elif "full summary" in line_lower or line_lower == "summary:":
                if current_section == "one_liner":
                    one_liner = " ".join(current_content).strip()
                current_section = "full"
                current_content = []
            elif "key point" in line_lower or line_lower == "key points:":
                if current_section == "full":
                    full_summary = "\n".join(current_content).strip()
                elif current_section == "one_liner":
                    one_liner = " ".join(current_content).strip()
                current_section = "points"
                current_content = []
            elif current_section == "points":
                # Extract bullet point
                if line_stripped.startswith(("•", "-", "*", "·")):
                    point = line_stripped.lstrip("•-*·").strip()
                    if point:
                        key_points.append(point)
                elif line_stripped and line_stripped[0].isdigit():
                    # Numbered list (1., 2., etc.)
                    point = line_stripped.lstrip("0123456789.)").strip()
                    if point:
                        key_points.append(point)
            elif current_section and line_stripped:
                current_content.append(line_stripped)

        # Handle final section
        if current_section == "one_liner" and not one_liner:
            one_liner = " ".join(current_content).strip()
        elif current_section == "full" and not full_summary:
            full_summary = "\n".join(current_content).strip()

        # Fallback: if parsing failed, use entire response
        if not full_summary:
            full_summary = text.strip()

        if not one_liner:
            # Take first sentence
            sentences = text.split(".")
            if sentences:
                one_liner = sentences[0].strip() + "."
            else:
                one_liner = text[:150]

        # Enforce length limits
        one_liner = one_liner[:200]
        key_points = key_points[:5]

        return Summary(
            title=title,
            one_liner=one_liner,
            full_summary=full_summary,
            key_points=key_points,
            model_used=model,
            cached=False
        )

    async def summarize_async(
        self,
        content: str,
        url: str,
        title: str = "",
        force_model: Model | None = None
    ) -> Summary:
        """
        Async version of summarize.

        Note: anthropic SDK is sync, so this wraps the sync call.
        For true async, we'd need to use httpx directly.
        """
        import asyncio
        loop = asyncio.get_event_loop()
        return await loop.run_in_executor(
            None,
            lambda: self.summarize(content, url, title, force_model)
        )


def create_summarizer(
    api_key: str,
    cache: "TieredCache | None" = None
) -> Summarizer:
    """Factory function to create a Summarizer instance."""
    return Summarizer(api_key=api_key, cache=cache)
