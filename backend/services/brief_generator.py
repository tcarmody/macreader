"""
Brief Generator - produces newsletter-ready blurbs from articles.

Features:
- Three lengths: sentence (20-30 words), short (60-80 words), paragraph (120-160 words)
- Three tones: neutral, opinionated, analytical
- Multi-provider support with Anthropic prompt caching
- Tiered cache (memory + disk)
- Batch generation with asyncio.gather
"""

import asyncio
import logging
from dataclasses import dataclass
from enum import Enum
from typing import TYPE_CHECKING

from ..providers import LLMProvider, AnthropicProvider
from ..providers.base import ModelTier

if TYPE_CHECKING:
    from ..cache import TieredCache

logger = logging.getLogger(__name__)


class BriefLength(str, Enum):
    SENTENCE = "sentence"
    SHORT = "short"
    PARAGRAPH = "paragraph"


class BriefTone(str, Enum):
    NEUTRAL = "neutral"
    OPINIONATED = "opinionated"
    ANALYTICAL = "analytical"


@dataclass
class Brief:
    article_id: int
    length: BriefLength
    tone: BriefTone
    content: str
    model_used: str
    cached: bool = False


# Technical terms used to detect content complexity (shared with Summarizer)
_TECHNICAL_TERMS = [
    "algorithm", "neural", "quantum", "blockchain", "protocol",
    "cryptographic", "machine learning", "artificial intelligence",
    "api", "infrastructure", "architecture", "microservices",
    "distributed", "consensus", "encryption", "compiler",
    "semiconductor", "genomic", "molecular", "theorem",
]

# ─── System prompt (static, cacheable) ───────────────────────────────────────

SYSTEM_PROMPT = """You are an expert newsletter editor writing concise, compelling briefs for busy readers. Your briefs are direct, clear, and ready to paste into a newsletter without editing."""

# ─── Instruction prompts per (length, tone) ──────────────────────────────────
# These are static (cacheable with Anthropic). The dynamic part (article content)
# is separated and passed as the trailing message content.

_INSTRUCTIONS: dict[tuple[BriefLength, BriefTone], str] = {
    (BriefLength.SENTENCE, BriefTone.NEUTRAL): (
        "Write a single sentence (20-30 words) summarizing what happened and why it matters. "
        "No filler words. No 'In this article...' framing. No labels or preamble. "
        "Return ONLY the sentence."
    ),
    (BriefLength.SENTENCE, BriefTone.OPINIONATED): (
        "Write a single sentence (20-30 words) that captures what happened and stakes a clear "
        "position on its significance. Be direct—take a side. "
        "No labels or preamble. Return ONLY the sentence."
    ),
    (BriefLength.SENTENCE, BriefTone.ANALYTICAL): (
        "Write a single sentence (20-30 words) that states what happened and names the most "
        "important implication or data point. Focus on significance over description. "
        "No labels or preamble. Return ONLY the sentence."
    ),
    (BriefLength.SHORT, BriefTone.NEUTRAL): (
        "Write a 3-sentence newsletter brief (60-80 words total). "
        "Sentence 1: what happened. Sentence 2: key context or detail. "
        "Sentence 3: why it matters to readers. "
        "No labels, no preamble. Return ONLY the brief."
    ),
    (BriefLength.SHORT, BriefTone.OPINIONATED): (
        "Write a 3-sentence newsletter brief (60-80 words total) with a clear point of view. "
        "Sentence 1: what happened. Sentence 2: the angle or implication you think matters most. "
        "Sentence 3: your take on what readers should do or think about this. "
        "No labels, no preamble. Return ONLY the brief."
    ),
    (BriefLength.SHORT, BriefTone.ANALYTICAL): (
        "Write a 3-sentence newsletter brief (60-80 words total) with an analytical lens. "
        "Sentence 1: what happened. Sentence 2: the data, mechanism, or context that explains it. "
        "Sentence 3: the downstream implication for the field or practitioners. "
        "No labels, no preamble. Return ONLY the brief."
    ),
    (BriefLength.PARAGRAPH, BriefTone.NEUTRAL): (
        "Write a newsletter paragraph (120-160 words) covering: what happened, relevant background, "
        "key details or specs, and what to watch next. Flowing prose, no bullet points. "
        "No labels, no preamble. Return ONLY the paragraph."
    ),
    (BriefLength.PARAGRAPH, BriefTone.OPINIONATED): (
        "Write a newsletter paragraph (120-160 words) with a clear editorial perspective. "
        "Cover what happened and the key facts, then take a stance: argue why this matters more "
        "(or less) than it appears, who wins, who loses, or what the real story is. "
        "Flowing prose, no bullet points. No labels, no preamble. Return ONLY the paragraph."
    ),
    (BriefLength.PARAGRAPH, BriefTone.ANALYTICAL): (
        "Write a newsletter paragraph (120-160 words) with an analytical frame. "
        "Cover what happened, explain the mechanism or data behind it, connect it to broader "
        "trends, and identify the key question or risk that remains open. "
        "Flowing prose, no bullet points. No labels, no preamble. Return ONLY the paragraph."
    ),
}

# Max content characters sent to the API
_MAX_CONTENT_LENGTH = 8000


class BriefGenerator:
    """LLM-powered newsletter brief generator."""

    def __init__(
        self,
        provider: LLMProvider,
        cache: "TieredCache | None" = None,
    ):
        self._provider = provider
        self._cache = cache

    # ─── Public API ──────────────────────────────────────────────────────────

    async def generate(
        self,
        article_id: int,
        title: str,
        content: str,
        length: BriefLength,
        tone: BriefTone,
    ) -> Brief:
        """Generate a brief for a single article. Returns cached result if available."""
        cache_key = self._cache_key(article_id, length, tone)

        if self._cache:
            cached = self._cache.get(cache_key)
            if cached:
                return Brief(
                    article_id=article_id,
                    length=length,
                    tone=tone,
                    content=cached["content"],
                    model_used=cached["model_used"],
                    cached=True,
                )

        brief = await self._generate_uncached(article_id, title, content, length, tone)

        if self._cache:
            self._cache.set(
                cache_key,
                {"content": brief.content, "model_used": brief.model_used},
                ttl=7,  # 7-day TTL (shorter than summaries — briefs can be refreshed per tone)
            )

        return brief

    async def generate_batch(
        self,
        items: list[dict],  # [{"article_id": int, "title": str, "content": str}]
        length: BriefLength,
        tone: BriefTone,
    ) -> list[Brief]:
        """Generate briefs for multiple articles concurrently (max 20)."""
        items = items[:20]
        tasks = [
            self.generate(
                article_id=item["article_id"],
                title=item["title"],
                content=item["content"],
                length=length,
                tone=tone,
            )
            for item in items
        ]
        return list(await asyncio.gather(*tasks, return_exceptions=False))

    # ─── Internal ────────────────────────────────────────────────────────────

    async def _generate_uncached(
        self,
        article_id: int,
        title: str,
        content: str,
        length: BriefLength,
        tone: BriefTone,
    ) -> Brief:
        model_tier = self._select_model(content, length)
        model = self._provider.get_model_for_tier(model_tier)
        instruction = _INSTRUCTIONS[(length, tone)]
        dynamic = self._build_dynamic(title, content)

        loop = asyncio.get_event_loop()

        if isinstance(self._provider, AnthropicProvider):
            response = await loop.run_in_executor(
                None,
                lambda: self._provider.complete_with_cacheable_prefix(
                    system_prompt=SYSTEM_PROMPT,
                    instruction_prompt=instruction,
                    dynamic_content=dynamic,
                    model=model,
                    max_tokens=300,
                    temperature=0.3,
                ),
            )
        else:
            full_prompt = f"{instruction}\n\n{dynamic}"
            response = await loop.run_in_executor(
                None,
                lambda: self._provider.complete(
                    user_prompt=full_prompt,
                    system_prompt=SYSTEM_PROMPT,
                    model=model,
                    max_tokens=300,
                    temperature=0.3,
                ),
            )

        content_out = response.text.strip()
        logger.debug(
            "Brief generated: article_id=%d length=%s tone=%s model=%s tokens=%d",
            article_id, length.value, tone.value, response.model,
            response.input_tokens + response.output_tokens,
        )

        return Brief(
            article_id=article_id,
            length=length,
            tone=tone,
            content=content_out,
            model_used=response.model,
        )

    def _select_model(self, content: str, length: BriefLength) -> ModelTier:
        """Select model tier. Sentence/short always use FAST; paragraph uses STANDARD for complex content."""
        if length in (BriefLength.SENTENCE, BriefLength.SHORT):
            return ModelTier.FAST

        # Paragraph: use STANDARD for long or technical content
        words = len(content.split())
        if words > 2000:
            return ModelTier.STANDARD
        technical_hits = sum(
            1 for term in _TECHNICAL_TERMS if term in content.lower()
        )
        if technical_hits > 2:
            return ModelTier.STANDARD
        return ModelTier.FAST

    def _build_dynamic(self, title: str, content: str) -> str:
        """Build the dynamic (per-article) part of the prompt."""
        truncated = content[:_MAX_CONTENT_LENGTH]
        return f"Title: {title}\n\n{truncated}"

    @staticmethod
    def _cache_key(article_id: int, length: BriefLength, tone: BriefTone) -> str:
        return f"brief:{article_id}:{length.value}:{tone.value}"
