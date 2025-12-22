"""
Summarizer - LLM-powered article summarization.

Features:
- Multi-provider support (Anthropic, OpenAI, Google)
- Automatic model selection (advanced for complex, fast for simple)
- Structured summary output (one-liner, full summary, key points)
- Cache integration
- Prompt caching for Anthropic (90% cost reduction)
"""

from dataclasses import dataclass
from enum import Enum
from typing import TYPE_CHECKING

from .providers import LLMProvider, AnthropicProvider
from .providers.base import ModelTier

if TYPE_CHECKING:
    from .cache import TieredCache


class Model(Enum):
    """Model tier selection for summarization."""
    SONNET = "standard"  # Balanced model
    HAIKU = "fast"       # Quick, cheap model


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
    """LLM-powered article summarizer with multi-provider support."""

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
    SYSTEM_PROMPT = """You are an expert journalist. Your summaries are written for a general educated audience and should be quickly readable by anyone.

Core principles:
- Use clear, simple, jargon-free language in straightforward syntax
- Present information directly and factually in active voice
- Avoid meta-language like 'This article explains...', 'This is important because...', or 'The author discusses...'
- Avoid stilted language, complex sentence constructions, and obscure vocabulary
- Include technical details sparingly and only when they help the reader understand the story
- Include relevant details like pricing and availability when mentioned
- Focus on what happened, why it matters, and what comes next

Style conventions:
- Use active voice and non-compound verbs (e.g., 'banned' not 'has banned')
- Spell out numbers and 'percent' (e.g., '8 billion', not '8B' or '%')
- Use smart quotes, not straight quotes
- Use 'U.S.' and 'U.K.' with periods; use 'AI' without periods
- Avoid the words 'content' and 'creator' when possible"""

    # Static instruction prompt (cacheable) - separated from dynamic content
    INSTRUCTION_PROMPT = """Summarize the article below following these guidelines:

Structure:
1. HEADLINE: Create a headline in sentence case that:
   - Captures the core news or development
   - Uses strong, specific verbs
   - Avoids repeating exact phrases from the summary

2. SUMMARY: A focused summary of five sentences in paragraph form (no bullet points):
   - First sentence: State the core announcement, finding, or development
   - Following sentences: Include 2-3 of these elements as relevant:
     Technical specifications, pricing/availability, key limitations, industry context, or concrete use cases
   - Prioritize information that answers: What changed? What can it do? What does it cost? When is it available?
   - Write as flowing prose, NOT as a list of bullet points

3. KEY POINTS: 3-5 bullet points that highlight distinct, scannable takeaways.
   - These must be different from the summary sentences - extract specific facts, numbers, or implications not fully covered in the summary
   - Do not simply rephrase what the summary already says

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
[Your five sentence summary here]

URL: [article URL will be provided]

KEY POINTS:
- [First key point]
- [Second key point]
- [Third key point]
- [Optional fourth point]
- [Optional fifth point]"""

    def __init__(
        self,
        provider: LLMProvider,
        cache: "TieredCache | None" = None,
        default_model: Model = Model.HAIKU
    ):
        """
        Initialize summarizer with an LLM provider.

        Args:
            provider: LLM provider instance (Anthropic, OpenAI, or Google)
            cache: Optional cache for storing summaries
            default_model: Default model tier for simple content
        """
        self.provider = provider
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
                    # Handle legacy model names in cache (e.g., "claude-haiku-4-5")
                    # Convert to tier values ("fast", "standard")
                    cached_model = cached.get("model_used", self.default_model.value)
                    if cached_model not in [m.value for m in Model]:
                        cached_model = self._map_legacy_model_to_tier(cached_model)

                    return Summary(
                        title=cached.get("title", title),
                        one_liner=cached.get("one_liner", ""),
                        full_summary=cached.get("full_summary", ""),
                        key_points=cached.get("key_points", []),
                        model_used=Model(cached_model),
                        cached=True
                    )

        # Select model based on content complexity
        model = force_model or self._select_model(content)
        model_tier = ModelTier.STANDARD if model == Model.SONNET else ModelTier.FAST

        # Build article content
        article_content = self._build_article_content(content, title, url)

        # Generate summary using provider
        # Use cacheable prefix for Anthropic (90% cost savings)
        if isinstance(self.provider, AnthropicProvider):
            response = self.provider.complete_with_cacheable_prefix(
                system_prompt=self.SYSTEM_PROMPT,
                instruction_prompt=self.INSTRUCTION_PROMPT,
                dynamic_content=article_content,
                model=self.provider.get_model_for_tier(model_tier),
                max_tokens=1024,
            )
        else:
            # Other providers: combine prompts
            user_prompt = f"{self.INSTRUCTION_PROMPT}\n\n{article_content}"
            response = self.provider.complete(
                user_prompt=user_prompt,
                system_prompt=self.SYSTEM_PROMPT,
                model=self.provider.get_model_for_tier(model_tier),
                max_tokens=1024,
            )

        summary = self._parse_response(response.text, model, title, url)

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

    def _map_legacy_model_to_tier(self, model_name: str) -> str:
        """
        Map legacy model names to tier values.

        Handles cached summaries from before the multi-provider update
        that stored actual model names instead of tier values.

        Args:
            model_name: Legacy model name (e.g., "claude-haiku-4-5", "gpt-5.2-mini")

        Returns:
            Tier value ("fast" or "standard")
        """
        model_lower = model_name.lower()

        # Fast tier models - check for specific patterns
        # Anthropic: claude-haiku-4-5, claude-3-haiku, etc.
        if "haiku" in model_lower:
            return Model.HAIKU.value

        # Google: gemini-3.0-flash, gemini-2.0-flash, etc.
        if "flash" in model_lower:
            return Model.HAIKU.value

        # OpenAI: gpt-5.2-mini, gpt-4o-mini, etc.
        # Must check for "-mini" to avoid matching "gemini"
        if "-mini" in model_lower:
            return Model.HAIKU.value

        # Everything else maps to standard tier
        # (sonnet, opus, gpt-5.2, gpt-4o, gemini-pro, etc.)
        return Model.SONNET.value

    def _select_model(self, content: str) -> Model:
        """
        Select appropriate model based on content complexity.

        Uses standard tier for:
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

    def _build_article_content(self, content: str, title: str = "", url: str = "") -> str:
        """Build the dynamic article content portion of the prompt."""
        title_line = f"Original title: {title}\n" if title else ""
        url_line = f"URL: {url}\n" if url else ""

        # Truncate content if too long
        truncated_content = content[:self.MAX_CONTENT_LENGTH]
        if len(content) > self.MAX_CONTENT_LENGTH:
            truncated_content += "\n\n[Content truncated...]"

        return f"""{title_line}{url_line}
Article:
{truncated_content}"""

    def _parse_response(self, text: str, model: Model, title: str = "", url: str = "") -> Summary:
        """Parse LLM response into structured Summary."""
        # Default values
        headline = ""
        summary_text = ""
        key_points: list[str] = []

        def strip_markdown(s: str) -> str:
            """Remove markdown formatting like **bold** and #headers."""
            s = s.strip()
            # Remove leading # for headers
            while s.startswith("#"):
                s = s[1:].strip()
            # Remove ** bold markers
            s = s.replace("**", "")
            return s.strip()

        def is_section_header(line: str, section: str) -> bool:
            """Check if line is a section header (with or without markdown)."""
            cleaned = strip_markdown(line).lower()
            return cleaned == f"{section}:" or cleaned.startswith(f"{section}:")

        def extract_after_colon(line: str) -> str:
            """Extract content after the colon in a header line."""
            if ":" in line:
                return strip_markdown(line.split(":", 1)[1])
            return ""

        # Split response into sections
        lines = text.strip().split("\n")
        current_section: str | None = None
        current_content: list[str] = []

        for line in lines:
            line_stripped = line.strip()

            # Skip empty lines
            if not line_stripped:
                continue

            # Skip lines that are just the article title repeated
            if line_stripped.startswith("#") and title and strip_markdown(line_stripped) == title:
                continue

            # Detect section headers
            if is_section_header(line_stripped, "headline"):
                if current_section == "summary":
                    summary_text = "\n".join(current_content).strip()
                current_section = "headline"
                current_content = []
                rest = extract_after_colon(line_stripped)
                if rest:
                    current_content.append(rest)
            elif is_section_header(line_stripped, "summary"):
                if current_section == "headline":
                    headline = " ".join(current_content).strip()
                current_section = "summary"
                current_content = []
                rest = extract_after_colon(line_stripped)
                if rest:
                    current_content.append(rest)
            elif is_section_header(line_stripped, "url"):
                # Skip URL line - we don't need it
                if current_section == "summary":
                    summary_text = "\n".join(current_content).strip()
                    current_content = []
                current_section = "url"
            elif is_section_header(line_stripped, "key points") or "key point" in strip_markdown(line_stripped).lower():
                if current_section == "summary":
                    summary_text = "\n".join(current_content).strip()
                elif current_section == "headline":
                    headline = " ".join(current_content).strip()
                current_section = "points"
                current_content = []
            elif current_section == "points":
                # Extract bullet point
                cleaned = strip_markdown(line_stripped)
                if cleaned.startswith(("•", "-", "·")):
                    point = cleaned.lstrip("•-·").strip()
                    if point:
                        key_points.append(point)
                elif cleaned and cleaned[0].isdigit():
                    point = cleaned.lstrip("0123456789.)").strip()
                    if point:
                        key_points.append(point)
            elif current_section == "url":
                # Skip URL content
                pass
            elif current_section and line_stripped:
                # Add content to current section (strip markdown from content too)
                current_content.append(strip_markdown(line_stripped))

        # Handle final section
        if current_section == "headline" and not headline:
            headline = " ".join(current_content).strip()
        elif current_section == "summary" and not summary_text:
            summary_text = "\n".join(current_content).strip()

        # Fallback: if parsing failed, use entire response
        if not summary_text:
            summary_text = strip_markdown(text)

        if not headline:
            # Take first sentence as headline
            sentences = text.split(".")
            if sentences:
                headline = strip_markdown(sentences[0]) + "."
            else:
                headline = strip_markdown(text[:150])

        # Enforce length limits
        headline = headline[:200]
        key_points = key_points[:5]

        # Build clean full summary (just the summary text - headline and key points displayed separately by UI)
        full_summary = summary_text

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

        Note: Wraps sync call in executor for now.
        """
        import asyncio
        loop = asyncio.get_event_loop()
        return await loop.run_in_executor(
            None,
            lambda: self.summarize(content, url, title, force_model)
        )


def create_summarizer(
    provider: LLMProvider,
    cache: "TieredCache | None" = None
) -> Summarizer:
    """Factory function to create a Summarizer instance."""
    return Summarizer(provider=provider, cache=cache)


# Backwards compatibility: create summarizer from API key (uses Anthropic)
def create_summarizer_from_api_key(
    api_key: str,
    cache: "TieredCache | None" = None
) -> Summarizer:
    """
    Create a Summarizer using Anthropic provider (legacy API).

    Deprecated: Use create_summarizer(provider, cache) instead.
    """
    from .providers import AnthropicProvider
    provider = AnthropicProvider(api_key=api_key)
    return Summarizer(provider=provider, cache=cache)
