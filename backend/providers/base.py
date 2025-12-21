"""
Base LLM provider interface.

Defines the abstract interface that all provider implementations must follow.
"""

from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from enum import Enum


class ModelTier(Enum):
    """Model capability tiers for automatic selection."""
    FAST = "fast"      # Quick, cheap models (Haiku, GPT-4o-mini, Gemini Flash)
    STANDARD = "standard"  # Balanced models (Sonnet, GPT-4o, Gemini Pro)
    ADVANCED = "advanced"  # Most capable models (Opus, GPT-4, Gemini Ultra)


@dataclass
class ProviderCapabilities:
    """Describes what features a provider supports."""
    supports_system_prompt: bool = True
    supports_prompt_caching: bool = False
    supports_json_mode: bool = False
    supports_streaming: bool = True
    max_context_tokens: int = 128000


@dataclass
class LLMResponse:
    """Standardized response from any LLM provider."""
    text: str
    model: str
    input_tokens: int = 0
    output_tokens: int = 0
    cached_tokens: int = 0  # For providers with prompt caching
    metadata: dict = field(default_factory=dict)


class LLMProvider(ABC):
    """
    Abstract base class for LLM providers.

    All provider implementations must inherit from this class and implement
    the required methods. This ensures a consistent interface across
    Anthropic, OpenAI, Google, and any future providers.
    """

    @property
    @abstractmethod
    def name(self) -> str:
        """Return the provider name (e.g., 'anthropic', 'openai', 'google')."""
        pass

    @property
    @abstractmethod
    def capabilities(self) -> ProviderCapabilities:
        """Return the provider's capabilities."""
        pass

    @abstractmethod
    def get_model_for_tier(self, tier: ModelTier) -> str:
        """
        Get the appropriate model ID for a given capability tier.

        Args:
            tier: The desired model tier (FAST, STANDARD, ADVANCED)

        Returns:
            Model identifier string for this provider
        """
        pass

    @abstractmethod
    def complete(
        self,
        user_prompt: str,
        system_prompt: str | None = None,
        model: str | None = None,
        max_tokens: int = 1024,
        temperature: float = 0.0,
        use_cache: bool = False,
        json_mode: bool = False,
    ) -> LLMResponse:
        """
        Generate a completion from the model.

        Args:
            user_prompt: The user message/prompt
            system_prompt: Optional system prompt for context
            model: Specific model to use (defaults to provider's default)
            max_tokens: Maximum tokens in response
            temperature: Sampling temperature (0.0 = deterministic)
            use_cache: Enable prompt caching if supported
            json_mode: Request JSON-formatted response if supported

        Returns:
            LLMResponse with the generated text and metadata
        """
        pass

    async def complete_async(
        self,
        user_prompt: str,
        system_prompt: str | None = None,
        model: str | None = None,
        max_tokens: int = 1024,
        temperature: float = 0.0,
        use_cache: bool = False,
        json_mode: bool = False,
    ) -> LLMResponse:
        """
        Async version of complete.

        Default implementation wraps sync call in executor.
        Providers with native async support should override this.
        """
        import asyncio
        loop = asyncio.get_event_loop()
        return await loop.run_in_executor(
            None,
            lambda: self.complete(
                user_prompt=user_prompt,
                system_prompt=system_prompt,
                model=model,
                max_tokens=max_tokens,
                temperature=temperature,
                use_cache=use_cache,
                json_mode=json_mode,
            )
        )
