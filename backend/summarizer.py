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

    # System prompt establishing the AI persona and quality standards
    SYSTEM_PROMPT = """You are an expert technical journalist specializing in AI and technology news. Your summaries are written for AI developers, researchers, and technology professionals who value precision, technical depth, and direct communication.

Core principles:
- Present information directly and factually in active voice
- Avoid meta-language like 'This article explains...', 'This is important because...', or 'The author discusses...'
- Include technical details, specifications, and industry implications
- Use clear, straightforward language without hype, exaggeration, or marketing speak
- Focus on what matters to technical practitioners: capabilities, limitations, pricing, availability

Style conventions:
- Use active voice and non-compound verbs (e.g., 'banned' not 'has banned')
- Spell out numbers and 'percent' (e.g., '8 billion', not '8B' or '%')
- Use smart quotes, not straight quotes
- Use 'U.S.' and 'U.K.' with periods; use 'AI' without periods
- Avoid the words 'content' and 'creator' when possible"""

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
            system=self.SYSTEM_PROMPT,
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
        """Build the summarization prompt using documented strategy."""
        title_context = f"Original title: {title}\n\n" if title else ""

        # Truncate content if too long
        truncated_content = content[:self.MAX_CONTENT_LENGTH]
        if len(content) > self.MAX_CONTENT_LENGTH:
            truncated_content += "\n\n[Content truncated...]"

        return f"""Summarize the article below following these guidelines:

Structure:
1. HEADLINE: Create a headline in sentence case that:
   - Captures the core news or development
   - Uses strong, specific verbs
   - Avoids repeating exact phrases from the summary

2. SUMMARY: A focused summary of three to five sentences:
   - First sentence: State the core announcement, finding, or development
   - Following sentences: Include 2-3 of these elements as relevant:
     • Technical specifications (model sizes, performance metrics, capabilities)
     • Pricing, availability, and access details
     • Key limitations or constraints
     • Industry implications or competitive context
     • Concrete use cases or applications
   - Prioritize information that answers: What changed? What can it do? What does it cost? When is it available?

3. KEY POINTS: 3-5 bullet points highlighting the most important takeaways

Style guidelines:
- Use active voice (e.g., 'Company released product' not 'Product was released by company')
- Use non-compound verbs (e.g., 'banned' instead of 'has banned')
- Avoid self-explanatory phrases like 'This article explains...', 'This is important because...', or 'The author discusses...'
- Present information directly without meta-commentary
- Avoid the words 'content' and 'creator'
- Spell out numbers (e.g., '8 billion' not '8B', '100 million' not '100M')
- Spell out 'percent' instead of using the '%' symbol
- Use 'U.S.' and 'U.K.' with periods; use 'AI' without periods
- Use smart quotes, not straight quotes

Additional guidelines:
- For product launches: Always include pricing and availability if mentioned
- For research papers: Include key metrics, dataset sizes, or performance improvements
- For company news: Focus on concrete actions, not just announcements or intentions
- Omit background information readers likely already know (e.g., 'OpenAI is an AI company')

Provide your response in exactly this format:

HEADLINE:
[Your headline here]

SUMMARY:
[Your 3-5 sentence summary here]

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
        headline = ""
        full_summary = ""
        key_points: list[str] = []

        # Split response into sections
        lines = text.strip().split("\n")
        current_section: str | None = None
        current_content: list[str] = []

        for line in lines:
            line_stripped = line.strip()
            line_lower = line_stripped.lower()

            # Detect section headers (support both old and new formats)
            if line_lower == "headline:" or line_lower.startswith("headline:"):
                # Save previous section if any
                if current_section == "summary":
                    full_summary = "\n".join(current_content).strip()
                current_section = "headline"
                current_content = []
                # Check if headline is on same line
                if ":" in line_stripped and len(line_stripped.split(":", 1)) > 1:
                    rest = line_stripped.split(":", 1)[1].strip()
                    if rest:
                        current_content.append(rest)
            elif line_lower == "summary:" or line_lower.startswith("summary:"):
                if current_section == "headline":
                    headline = " ".join(current_content).strip()
                current_section = "summary"
                current_content = []
                # Check if summary starts on same line
                if ":" in line_stripped and len(line_stripped.split(":", 1)) > 1:
                    rest = line_stripped.split(":", 1)[1].strip()
                    if rest:
                        current_content.append(rest)
            elif "key point" in line_lower or line_lower == "key points:":
                if current_section == "summary":
                    full_summary = "\n".join(current_content).strip()
                elif current_section == "headline":
                    headline = " ".join(current_content).strip()
                current_section = "points"
                current_content = []
            # Legacy format support
            elif "one-sentence" in line_lower or line_lower.startswith("one sentence"):
                if current_section == "summary":
                    full_summary = "\n".join(current_content).strip()
                current_section = "headline"
                current_content = []
            elif "full summary" in line_lower:
                if current_section == "headline":
                    headline = " ".join(current_content).strip()
                current_section = "summary"
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
        if current_section == "headline" and not headline:
            headline = " ".join(current_content).strip()
        elif current_section == "summary" and not full_summary:
            full_summary = "\n".join(current_content).strip()

        # Fallback: if parsing failed, use entire response
        if not full_summary:
            full_summary = text.strip()

        if not headline:
            # Take first sentence as headline
            sentences = text.split(".")
            if sentences:
                headline = sentences[0].strip() + "."
            else:
                headline = text[:150]

        # Enforce length limits
        headline = headline[:200]
        key_points = key_points[:5]

        return Summary(
            title=title,
            one_liner=headline,  # Use headline as the one-liner
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
