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
    SYSTEM_PROMPT = """You are an expert technology journalist writing for software engineers and AI practitioners. Your summaries are clear, direct, and technically informed while remaining accessible.

Core principles:
- Present information directly and factually—no meta-language like "This article explains..." or "The author discusses..."
- Use active voice and simple syntax
- Include technical details when they matter; omit jargon that doesn't add meaning
- Always connect stories to their practical implications for builders and practitioners
- Be skeptical of marketing language and press release hype—focus on substance"""

    # Static instruction prompt (cacheable) - separated from dynamic content
    INSTRUCTION_PROMPT = """Summarize the article below. Respond with valid JSON only—no other text.

CONTENT TYPE DETECTION:
First, classify the article as one of: news, analysis, tutorial, review, research, newsletter
- news: Announcements, product launches, funding, acquisitions, breaking developments
- analysis: Opinion pieces, commentary, predictions, industry analysis
- tutorial: How-to guides, technical walkthroughs, implementation guides
- review: Product reviews, comparisons, evaluations
- research: Academic papers, technical reports, benchmark studies
- newsletter: Multi-story digests, roundups, curated links

HEADLINE GUIDELINES (8-12 words):
- Lead with the most searchable noun (company name, product, technology)
- Use a strong, active verb
- Include one concrete detail (number, name, or outcome)
- Do NOT repeat the article's original headline verbatim
- Avoid vague words: "new," "big," "major," "revolutionary," "game-changing"
- Avoid clickbait: "You won't believe," "Here's why," "Everything you need to know"

Good: "Anthropic releases Claude 4 with 1M token context window"
Good: "Google open-sources Gemma 3 weights for commercial use"
Bad: "Anthropic announces major new AI model update"
Bad: "New Claude model is a game-changer for developers"

SUMMARY GUIDELINES:
Write 4-6 sentences as flowing prose (no bullet points).

For SINGLE-STORY articles:
- Sentence 1: State the core development—what happened, who did it, when
- Sentences 2-4: Include the most relevant of: technical specs, pricing, availability, limitations, methodology, key findings, competitive context
- Final sentence: Connect to broader implications for software development, AI capabilities, or the industry—but write it as a natural continuation, NOT as "This matters because..." or "This is significant for..."

Good final sentence: "The pricing undercuts GPT-4 by 60%, likely shifting which models developers default to for production workloads."
Bad final sentence: "This is important for developers because it offers a cheaper alternative."

For MULTI-STORY articles (newsletters, roundups):
- Write one paragraph per major story (3-4 sentences each)
- Separate paragraphs with blank lines
- Order by importance, not by original appearance
- Still end with an implications sentence for the most significant story

SPECIAL HANDLING BY CONTENT TYPE:
- analysis/opinion: Note the author's position neutrally (e.g., "argues that," "contends") without editorializing
- tutorial: Preserve the key actionable steps or techniques covered
- review: Include the verdict and primary pros/cons
- research: Note methodology, sample sizes, and any stated limitations
- news (press releases): Be skeptical—distinguish concrete announcements from aspirational claims

ADDITIONAL GUIDELINES:
- If the article contains a notable quote from a primary source that captures the story's essence, include it
- If information conflicts or is disputed, present both sides neutrally
- If content appears truncated or paywalled, summarize only what's available and note the limitation
- Spell out numbers ("8 billion" not "8B") and "percent" (not "%")
- Use active voice and simple verbs ("released" not "has released")
- Omit background readers likely know ("OpenAI is an AI company")

KEY POINTS GUIDELINES:
- 3-5 bullet points with distinct, scannable takeaways
- Include specific facts, numbers, dates, or names
- For multi-story articles, prioritize across all stories by importance

Respond with this exact JSON structure:
{
  "headline": "Your headline here",
  "summary": "Your summary paragraphs here. Use \\n\\n for paragraph breaks in multi-story summaries.",
  "key_points": ["First point", "Second point", "Third point"],
  "content_type": "news|analysis|tutorial|review|research|newsletter"
}"""

    # Critic prompt for the review step (used for long articles and newsletters)
    CRITIC_PROMPT = """Evaluate the following summary against quality standards, make corrections if needed, and write an improved headline.

You will receive the original article title and a JSON summary produced by a first-pass summarizer.

EVALUATION CRITERIA:

1. STRUCTURE:
   - For newsletters/digests: Each story gets its own paragraph, separated by blank lines
   - For single-story articles: 4-6 flowing sentences, no fragmentation
   - Summary length appropriate for content complexity

2. READABILITY:
   - No meta-language ("This article discusses...", "The author explains...")
   - Active voice throughout ("released" not "has been released")
   - Numbers spelled out ("8 billion" not "8B", "percent" not "%")
   - No unnecessary background readers likely know ("OpenAI is an AI company")

3. KEY POINTS:
   - 3-5 distinct takeaways with no overlap
   - Each includes specific facts, numbers, dates, or names
   - For analysis: author's position noted neutrally
   - For tutorials: key actionable steps preserved
   - For reviews: verdict and pros/cons included

4. HEADLINE (write a new one):
   - 8-12 words
   - Lead with most searchable noun (company, product, technology)
   - Strong active verb
   - One concrete detail (number, name, outcome)
   - Must NOT repeat the original article title
   - No vague words: "new," "big," "major," "game-changing"
   - No clickbait patterns

If the summary is already good, keep it unchanged but still write the headline fresh.

Respond with valid JSON only:
{
  "headline": "Your improved headline here",
  "summary": "The revised summary (or original text if no changes needed)",
  "key_points": ["Revised points (or original if no changes needed)"],
  "revisions_made": ["List of specific changes, or empty array if none"]
}"""

    def __init__(
        self,
        provider: LLMProvider,
        cache: "TieredCache | None" = None,
        default_model: Model = Model.HAIKU,
        critic_enabled: bool = True,
    ):
        """
        Initialize summarizer with an LLM provider.

        Args:
            provider: LLM provider instance (Anthropic, OpenAI, or Google)
            cache: Optional cache for storing summaries
            default_model: Default model tier for simple content
            critic_enabled: Enable critic step for long articles and newsletters
        """
        self.provider = provider
        self.cache = cache
        self.default_model = default_model
        self.critic_enabled = critic_enabled

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

        # Check if critic step should run
        content_type = self._extract_content_type(response.text)
        if self.critic_enabled and self._should_use_critic(content, content_type):
            critic_result = self._run_critic(response.text, title, url)
            if critic_result:
                summary = self._parse_response(critic_result, model, title, url)
            else:
                summary = self._parse_response(response.text, model, title, url)
        else:
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

    def _extract_content_type(self, text: str) -> str | None:
        """Extract content_type from LLM response JSON."""
        import json
        try:
            json_text = text.strip()
            if json_text.startswith("```"):
                lines = json_text.split("\n")
                json_text = "\n".join(lines[1:-1] if lines[-1].strip() == "```" else lines[1:])
            data = json.loads(json_text)
            return data.get("content_type")
        except (json.JSONDecodeError, KeyError, TypeError):
            return None

    def _should_use_critic(self, content: str, content_type: str | None) -> bool:
        """Check if critic step should run based on content characteristics."""
        word_count = len(content.split())
        if word_count > 2000:
            return True
        if content_type == "newsletter":
            return True
        return False

    def _run_critic(self, step1_response: str, title: str, url: str) -> str | None:
        """
        Run critic evaluation on step 1 output.

        Returns revised response text, or None on failure.
        """
        import json

        dynamic_content = f"Original article title: {title}\nURL: {url}\n\nFirst-pass summary:\n{step1_response}"

        try:
            if isinstance(self.provider, AnthropicProvider):
                response = self.provider.complete_with_cacheable_prefix(
                    system_prompt=self.SYSTEM_PROMPT,
                    instruction_prompt=self.CRITIC_PROMPT,
                    dynamic_content=dynamic_content,
                    model=self.provider.get_model_for_tier(ModelTier.FAST),
                    max_tokens=1024,
                )
            else:
                user_prompt = f"{self.CRITIC_PROMPT}\n\n{dynamic_content}"
                response = self.provider.complete(
                    user_prompt=user_prompt,
                    system_prompt=self.SYSTEM_PROMPT,
                    model=self.provider.get_model_for_tier(ModelTier.FAST),
                    max_tokens=1024,
                )

            # Validate the critic produced parseable JSON
            json_text = response.text.strip()
            if json_text.startswith("```"):
                lines = json_text.split("\n")
                json_text = "\n".join(lines[1:-1] if lines[-1].strip() == "```" else lines[1:])

            data = json.loads(json_text)

            # Log revisions for observability
            revisions = data.get("revisions_made", [])
            if revisions:
                print(f"Critic made {len(revisions)} revision(s): {revisions}")
            else:
                print("Critic: no revisions to summary, headline updated")

            return response.text

        except Exception as e:
            print(f"Critic step failed, using original summary: {e}")
            return None

    def _parse_response(self, text: str, model: Model, title: str = "", url: str = "") -> Summary:
        """Parse LLM response (JSON) into structured Summary."""
        import json

        headline = ""
        summary_text = ""
        key_points: list[str] = []

        # Try to parse as JSON first
        try:
            # Handle potential markdown code blocks around JSON
            json_text = text.strip()
            if json_text.startswith("```"):
                # Remove markdown code fence
                lines = json_text.split("\n")
                # Skip first line (```json) and last line (```)
                json_text = "\n".join(lines[1:-1] if lines[-1].strip() == "```" else lines[1:])

            data = json.loads(json_text)
            headline = data.get("headline", "")
            summary_text = data.get("summary", "")
            key_points = data.get("key_points", [])

            # Ensure key_points is a list of strings
            if isinstance(key_points, list):
                key_points = [str(p) for p in key_points if p]
            else:
                key_points = []

        except (json.JSONDecodeError, KeyError, TypeError):
            # Fallback to legacy text parsing for backwards compatibility
            headline, summary_text, key_points = self._parse_legacy_response(text, title)

        # Enforce length limits
        headline = headline[:200] if headline else ""
        key_points = key_points[:5]

        # Fallback if parsing produced empty results
        if not summary_text:
            summary_text = self._strip_markdown(text)

        if not headline:
            sentences = text.split(".")
            if sentences:
                headline = self._strip_markdown(sentences[0]) + "."
            else:
                headline = self._strip_markdown(text[:150])

        return Summary(
            title=title,
            one_liner=headline,
            full_summary=summary_text,
            key_points=key_points,
            model_used=model,
            cached=False
        )

    def _strip_markdown(self, s: str) -> str:
        """Remove markdown formatting like **bold** and #headers."""
        s = s.strip()
        while s.startswith("#"):
            s = s[1:].strip()
        s = s.replace("**", "")
        return s.strip()

    def _parse_legacy_response(self, text: str, title: str = "") -> tuple[str, str, list[str]]:
        """
        Fallback parser for non-JSON responses (backwards compatibility).
        Returns (headline, summary_text, key_points).
        """
        headline = ""
        summary_text = ""
        key_points: list[str] = []

        def is_section_header(line: str, section: str) -> bool:
            cleaned = self._strip_markdown(line).lower()
            return cleaned == f"{section}:" or cleaned.startswith(f"{section}:")

        def extract_after_colon(line: str) -> str:
            if ":" in line:
                return self._strip_markdown(line.split(":", 1)[1])
            return ""

        lines = text.strip().split("\n")
        current_section: str | None = None
        current_content: list[str] = []

        for line in lines:
            line_stripped = line.strip()
            if not line_stripped:
                continue

            if line_stripped.startswith("#") and title and self._strip_markdown(line_stripped) == title:
                continue

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
                if current_section == "summary":
                    summary_text = "\n".join(current_content).strip()
                    current_content = []
                current_section = "url"
            elif is_section_header(line_stripped, "key points") or "key point" in self._strip_markdown(line_stripped).lower():
                if current_section == "summary":
                    summary_text = "\n".join(current_content).strip()
                elif current_section == "headline":
                    headline = " ".join(current_content).strip()
                current_section = "points"
                current_content = []
            elif current_section == "points":
                cleaned = self._strip_markdown(line_stripped)
                if cleaned.startswith(("•", "-", "·")):
                    point = cleaned.lstrip("•-·").strip()
                    if point:
                        key_points.append(point)
                elif cleaned and cleaned[0].isdigit():
                    point = cleaned.lstrip("0123456789.)").strip()
                    if point:
                        key_points.append(point)
            elif current_section == "url":
                pass
            elif current_section and line_stripped:
                current_content.append(self._strip_markdown(line_stripped))

        if current_section == "headline" and not headline:
            headline = " ".join(current_content).strip()
        elif current_section == "summary" and not summary_text:
            summary_text = "\n".join(current_content).strip()

        return headline, summary_text, key_points

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
    cache: "TieredCache | None" = None,
    critic_enabled: bool = True,
) -> Summarizer:
    """Factory function to create a Summarizer instance."""
    return Summarizer(provider=provider, cache=cache, critic_enabled=critic_enabled)


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
