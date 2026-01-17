"""
OpenAI provider implementation.

Supports GPT models with JSON mode for structured outputs.
"""

from openai import OpenAI

from .base import LLMProvider, LLMResponse, ProviderCapabilities, ModelTier


class OpenAIProvider(LLMProvider):
    """
    OpenAI GPT provider with JSON mode support.
    """

    # Model mappings for each tier
    TIER_MODELS = {
        ModelTier.FAST: "gpt-5.2-mini",
        ModelTier.STANDARD: "gpt-5.2",
        ModelTier.ADVANCED: "gpt-5.2",
    }

    # Model aliases for convenience
    MODEL_ALIASES = {
        "gpt5": "gpt-5.2",
        "gpt5-mini": "gpt-5.2-mini",
        "gpt-5": "gpt-5.2",
        "gpt-5.2": "gpt-5.2",
        "fast": "gpt-5.2-mini",
        "standard": "gpt-5.2",
        # Legacy aliases
        "gpt4": "gpt-4o",
        "gpt4-mini": "gpt-4o-mini",
        "gpt-4": "gpt-4o",
        "gpt-4o": "gpt-4o",
        "gpt-4o-mini": "gpt-4o-mini",
    }

    def __init__(
        self,
        api_key: str,
        default_model: str = "gpt-5.2-mini",
        organization: str | None = None,
    ):
        """
        Initialize OpenAI provider.

        Args:
            api_key: OpenAI API key
            default_model: Default model to use
            organization: Optional organization ID
        """
        self.client = OpenAI(api_key=api_key, organization=organization)
        self._default_model = self._resolve_model(default_model)

    def _resolve_model(self, model: str) -> str:
        """Resolve model alias to full model ID."""
        return self.MODEL_ALIASES.get(model, model)

    @property
    def name(self) -> str:
        return "openai"

    @property
    def capabilities(self) -> ProviderCapabilities:
        return ProviderCapabilities(
            supports_system_prompt=True,
            supports_prompt_caching=False,  # OpenAI has caching but less explicit
            supports_json_mode=True,
            supports_streaming=True,
            max_context_tokens=128000,
        )

    # get_model_for_tier inherited from LLMProvider base class

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
        Generate a completion using GPT.

        Args:
            user_prompt: The user message
            system_prompt: Optional system prompt
            model: Model to use (defaults to instance default)
            max_tokens: Maximum response tokens
            temperature: Sampling temperature
            use_cache: Ignored for OpenAI (automatic caching)
            json_mode: Request JSON-formatted response

        Returns:
            LLMResponse with generated text
        """
        resolved_model = self._resolve_model(model) if model else self._default_model

        # Build messages
        messages = []
        if system_prompt:
            messages.append({"role": "system", "content": system_prompt})
        messages.append({"role": "user", "content": user_prompt})

        # Build request kwargs
        kwargs = {
            "model": resolved_model,
            "messages": messages,
            "max_tokens": max_tokens,
            "temperature": temperature,
        }

        # Add JSON mode if requested
        if json_mode:
            kwargs["response_format"] = {"type": "json_object"}

        response = self.client.chat.completions.create(**kwargs)

        # Extract response data
        choice = response.choices[0]
        usage = response.usage

        return LLMResponse(
            text=choice.message.content or "",
            model=resolved_model,
            input_tokens=usage.prompt_tokens if usage else 0,
            output_tokens=usage.completion_tokens if usage else 0,
            cached_tokens=0,
            metadata={
                "finish_reason": choice.finish_reason,
                "provider": "openai",
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
        Generate completion with structured prompts.

        For OpenAI, this combines instruction_prompt and dynamic_content
        into the user message since OpenAI doesn't have explicit prompt caching.

        Args:
            system_prompt: System prompt
            instruction_prompt: Static instructions
            dynamic_content: Variable content
            model: Model to use
            max_tokens: Maximum response tokens
            temperature: Sampling temperature

        Returns:
            LLMResponse with generated text
        """
        # Combine instruction and dynamic content
        user_prompt = f"{instruction_prompt}\n\n{dynamic_content}"

        return self.complete(
            user_prompt=user_prompt,
            system_prompt=system_prompt,
            model=model,
            max_tokens=max_tokens,
            temperature=temperature,
        )
