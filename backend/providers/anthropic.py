"""
Anthropic Claude provider implementation.

Supports Claude models with prompt caching for cost optimization.
"""

import anthropic

from .base import LLMProvider, LLMResponse, ProviderCapabilities, ModelTier


class AnthropicProvider(LLMProvider):
    """
    Anthropic Claude provider with prompt caching support.

    Prompt caching can reduce costs by ~90% for repeated system prompts.
    """

    # Model mappings for each tier
    TIER_MODELS = {
        ModelTier.FAST: "claude-haiku-4-5-20251001",
        ModelTier.STANDARD: "claude-sonnet-4-5-20250514",
        ModelTier.ADVANCED: "claude-opus-4-5-20251218",
    }

    # Model aliases for convenience
    MODEL_ALIASES = {
        "haiku": "claude-haiku-4-5-20251001",
        "sonnet": "claude-sonnet-4-5-20250514",
        "opus": "claude-opus-4-5-20251218",
        # Legacy aliases
        "claude-haiku-4-5": "claude-haiku-4-5-20251001",
        "claude-sonnet-4-5": "claude-sonnet-4-5-20250514",
        "claude-opus-4-5": "claude-opus-4-5-20251218",
    }

    def __init__(
        self,
        api_key: str,
        default_model: str = "claude-haiku-4-5-20251001",
    ):
        """
        Initialize Anthropic provider.

        Args:
            api_key: Anthropic API key
            default_model: Default model to use
        """
        self.client = anthropic.Anthropic(api_key=api_key)
        self._default_model = self._resolve_model(default_model)

    def _resolve_model(self, model: str) -> str:
        """Resolve model alias to full model ID."""
        return self.MODEL_ALIASES.get(model, model)

    @property
    def name(self) -> str:
        return "anthropic"

    @property
    def capabilities(self) -> ProviderCapabilities:
        return ProviderCapabilities(
            supports_system_prompt=True,
            supports_prompt_caching=True,
            supports_json_mode=False,  # Claude doesn't have native JSON mode
            supports_streaming=True,
            max_context_tokens=200000,
        )

    def get_model_for_tier(self, tier: ModelTier) -> str:
        return self.TIER_MODELS[tier]

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
        Generate a completion using Claude.

        Args:
            user_prompt: The user message
            system_prompt: Optional system prompt
            model: Model to use (defaults to instance default)
            max_tokens: Maximum response tokens
            temperature: Sampling temperature
            use_cache: Enable prompt caching (reduces costs ~90%)
            json_mode: Ignored for Anthropic (use prompt instructions instead)

        Returns:
            LLMResponse with generated text
        """
        resolved_model = self._resolve_model(model) if model else self._default_model

        # Build messages
        messages = [{"role": "user", "content": user_prompt}]

        # Build system prompt with optional caching
        system = None
        if system_prompt:
            if use_cache:
                system = [{
                    "type": "text",
                    "text": system_prompt,
                    "cache_control": {"type": "ephemeral"}
                }]
            else:
                system = system_prompt

        # Make API call
        kwargs = {
            "model": resolved_model,
            "max_tokens": max_tokens,
            "messages": messages,
        }
        if temperature > 0:
            kwargs["temperature"] = temperature
        if system:
            kwargs["system"] = system

        response = self.client.messages.create(**kwargs)

        # Extract usage info
        usage = response.usage
        cached_tokens = 0
        if hasattr(usage, "cache_read_input_tokens"):
            cached_tokens = usage.cache_read_input_tokens or 0

        return LLMResponse(
            text=response.content[0].text,
            model=resolved_model,
            input_tokens=usage.input_tokens,
            output_tokens=usage.output_tokens,
            cached_tokens=cached_tokens,
            metadata={
                "stop_reason": response.stop_reason,
                "provider": "anthropic",
            }
        )

    def complete_with_cacheable_prefix(
        self,
        system_prompt: str,
        instruction_prompt: str,
        dynamic_content: str,
        model: str | None = None,
        max_tokens: int = 1024,
        temperature: float = 0.0,
    ) -> LLMResponse:
        """
        Generate completion with multi-part caching.

        This is optimized for the summarization use case where:
        - system_prompt is always the same (cached)
        - instruction_prompt is always the same (cached)
        - dynamic_content changes per article (not cached)

        Args:
            system_prompt: Static system prompt (cached)
            instruction_prompt: Static instructions (cached)
            dynamic_content: Variable content (not cached)
            model: Model to use
            max_tokens: Maximum response tokens
            temperature: Sampling temperature

        Returns:
            LLMResponse with generated text
        """
        resolved_model = self._resolve_model(model) if model else self._default_model

        response = self.client.messages.create(
            model=resolved_model,
            max_tokens=max_tokens,
            temperature=temperature if temperature > 0 else anthropic.NOT_GIVEN,
            system=[{
                "type": "text",
                "text": system_prompt,
                "cache_control": {"type": "ephemeral"}
            }],
            messages=[{
                "role": "user",
                "content": [
                    {
                        "type": "text",
                        "text": instruction_prompt,
                        "cache_control": {"type": "ephemeral"}
                    },
                    {
                        "type": "text",
                        "text": dynamic_content
                    }
                ]
            }]
        )

        usage = response.usage
        cached_tokens = 0
        if hasattr(usage, "cache_read_input_tokens"):
            cached_tokens = usage.cache_read_input_tokens or 0

        return LLMResponse(
            text=response.content[0].text,
            model=resolved_model,
            input_tokens=usage.input_tokens,
            output_tokens=usage.output_tokens,
            cached_tokens=cached_tokens,
            metadata={
                "stop_reason": response.stop_reason,
                "provider": "anthropic",
            }
        )
