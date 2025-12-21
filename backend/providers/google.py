"""
Google Gemini provider implementation.

Supports Gemini models with JSON mode for structured outputs.
Uses the new google-genai SDK.
"""

from google import genai
from google.genai import types

from .base import LLMProvider, LLMResponse, ProviderCapabilities, ModelTier


class GoogleProvider(LLMProvider):
    """
    Google Gemini provider with JSON mode support.
    """

    # Model mappings for each tier
    TIER_MODELS = {
        ModelTier.FAST: "gemini-3.0-flash",
        ModelTier.STANDARD: "gemini-3.0-pro",
        ModelTier.ADVANCED: "gemini-3.0-pro",
    }

    # Model aliases for convenience
    MODEL_ALIASES = {
        "flash": "gemini-3.0-flash",
        "pro": "gemini-3.0-pro",
        "gemini-flash": "gemini-3.0-flash",
        "gemini-pro": "gemini-3.0-pro",
        "fast": "gemini-3.0-flash",
        "standard": "gemini-3.0-pro",
        # Legacy aliases
        "gemini-2.0-flash": "gemini-2.0-flash",
        "gemini-2.5-pro": "gemini-2.5-pro",
    }

    def __init__(
        self,
        api_key: str,
        default_model: str = "gemini-3.0-flash",
    ):
        """
        Initialize Google Gemini provider.

        Args:
            api_key: Google AI API key
            default_model: Default model to use
        """
        self.client = genai.Client(api_key=api_key)
        self._api_key = api_key
        self._default_model = self._resolve_model(default_model)

    def _resolve_model(self, model: str) -> str:
        """Resolve model alias to full model ID."""
        return self.MODEL_ALIASES.get(model, model)

    @property
    def name(self) -> str:
        return "google"

    @property
    def capabilities(self) -> ProviderCapabilities:
        return ProviderCapabilities(
            supports_system_prompt=True,
            supports_prompt_caching=False,
            supports_json_mode=True,
            supports_streaming=True,
            max_context_tokens=1000000,  # Gemini has very large context
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
        Generate a completion using Gemini.

        Args:
            user_prompt: The user message
            system_prompt: Optional system prompt
            model: Model to use (defaults to instance default)
            max_tokens: Maximum response tokens
            temperature: Sampling temperature
            use_cache: Ignored for Google
            json_mode: Request JSON-formatted response

        Returns:
            LLMResponse with generated text
        """
        resolved_model = self._resolve_model(model) if model else self._default_model

        # Build generation config
        config_kwargs = {
            "max_output_tokens": max_tokens,
            "temperature": temperature,
        }

        # Add system instruction if provided
        if system_prompt:
            config_kwargs["system_instruction"] = system_prompt

        # Add JSON mode if requested
        if json_mode:
            config_kwargs["response_mime_type"] = "application/json"

        config = types.GenerateContentConfig(**config_kwargs)

        response = self.client.models.generate_content(
            model=resolved_model,
            contents=user_prompt,
            config=config,
        )

        # Extract usage metadata
        input_tokens = 0
        output_tokens = 0
        if hasattr(response, "usage_metadata") and response.usage_metadata:
            input_tokens = response.usage_metadata.prompt_token_count or 0
            output_tokens = response.usage_metadata.candidates_token_count or 0

        return LLMResponse(
            text=response.text,
            model=resolved_model,
            input_tokens=input_tokens,
            output_tokens=output_tokens,
            cached_tokens=0,
            metadata={
                "provider": "google",
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

        For Google, this uses system_instruction for the system prompt
        and combines instruction_prompt + dynamic_content as the user message.

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
