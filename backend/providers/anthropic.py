"""
Anthropic Claude provider implementation.

Supports Claude models with prompt caching for cost optimization.
"""

import anthropic

from ..config import config
from .base import LLMProvider, LLMResponse, ProviderCapabilities, ModelTier


class AnthropicProvider(LLMProvider):
    """
    Anthropic Claude provider with prompt caching support.

    Prompt caching can reduce costs by ~90% for repeated system prompts.
    """

    # Model mappings for each tier
    # 5.5 model IDs are pinned snapshots with no date suffix
    TIER_MODELS = {
        ModelTier.FAST: "claude-haiku-5-5",
        ModelTier.STANDARD: "claude-sonnet-5-5",
        ModelTier.ADVANCED: "claude-opus-5-5",
    }

    # Model aliases for convenience
    MODEL_ALIASES = {
        "haiku": "claude-haiku-5-5",
        "sonnet": "claude-sonnet-5-5",
        "opus": "claude-opus-5-5",
    }

    # Every call in this codebase is a single-pass structured request, so we
    # keep thinking off wherever the model allows it and keep max_tokens
    # meaning "room for the answer". Models from Sonnet 5 / Opus 4.7 onwards
    # reject temperature / top_p / top_k with a 400 and think by default out of
    # the max_tokens budget; how thinking is turned off differs per model.
    # Checked in order, so the 5.5 IDs must come before the "claude-sonnet-5" /
    # "claude-opus-5" prefixes they also match.
    THINKING_CONFIG = (
        # Thinking can't be disabled on Opus 5.5 - see _apply_sampling
        ("claude-opus-5-5", None),
        # Sonnet 5.5 rejects "disabled"; "between_tools" is its lowest setting
        ("claude-sonnet-5-5", {"type": "between_tools"}),
        ("claude-haiku-5-5", {"type": "disabled"}),
        ("claude-sonnet-5", {"type": "disabled"}),
        ("claude-opus-5", {"type": "disabled"}),
        ("claude-opus-4-7", {"type": "disabled"}),
        ("claude-opus-4-8", {"type": "disabled"}),
        ("claude-fable-5", {"type": "disabled"}),
    )

    # Opus 5.5 always thinks. Low effort keeps it short, and the headroom stops
    # thinking tokens from truncating an answer sized by the caller's max_tokens.
    ALWAYS_THINKING_EFFORT = "low"
    THINKING_HEADROOM_TOKENS = 8192

    # Models whose safety classifiers can decline a request and that support
    # server-side fallback: Anthropic retries some declines on the previous
    # model inside the same call. Haiku 5.5 can also decline but has no fallback.
    SERVER_FALLBACK_MODELS = ("claude-sonnet-5-5", "claude-opus-5-5")
    SERVER_FALLBACK_BETA = "server-side-fallback-2026-07-01"

    def __init__(
        self,
        api_key: str,
        default_model: str = "claude-sonnet-5-5",
        workspace_id: str | None = None,
    ):
        """
        Initialize Anthropic provider.

        Args:
            api_key: Anthropic API key
            default_model: Default model to use
            workspace_id: Workspace for keys that aren't scoped to one;
                defaults to config.ANTHROPIC_WORKSPACE_ID
        """
        if workspace_id is None:
            workspace_id = config.ANTHROPIC_WORKSPACE_ID
        workspace_id = workspace_id.strip()
        # A key that isn't scoped to a workspace gets a 400 on every request
        # that doesn't name one
        default_headers = {"anthropic-workspace-id": workspace_id} if workspace_id else None
        self.client = anthropic.Anthropic(api_key=api_key, default_headers=default_headers)
        self._default_model = self._resolve_model(default_model)

    def _resolve_model(self, model: str) -> str:
        """Resolve model alias to full model ID."""
        return self.MODEL_ALIASES.get(model, model)

    @classmethod
    def _apply_sampling(cls, kwargs: dict, model: str, temperature: float) -> None:
        """
        Set the sampling/thinking parameters this model accepts.

        Newer models reject temperature outright and need thinking turned off
        explicitly; older ones take temperature and have no thinking config.
        """
        for prefix, thinking in cls.THINKING_CONFIG:
            if model.startswith(prefix):
                if thinking is not None:
                    kwargs["thinking"] = dict(thinking)
                else:
                    kwargs["max_tokens"] += cls.THINKING_HEADROOM_TOKENS
                    # output_config / fallbacks go through extra_body: the
                    # pinned SDK doesn't type them on messages.create yet
                    kwargs.setdefault("extra_body", {})["output_config"] = {
                        "effort": cls.ALWAYS_THINKING_EFFORT
                    }
                break
        else:
            if temperature > 0:
                kwargs["temperature"] = temperature

        if model.startswith(cls.SERVER_FALLBACK_MODELS):
            kwargs.setdefault("extra_body", {})["fallbacks"] = "default"
            kwargs["extra_headers"] = {"anthropic-beta": cls.SERVER_FALLBACK_BETA}

    @staticmethod
    def _extract_text(response) -> str:
        """
        Return the answer text from a Messages API response.

        Reads blocks by type: a response can start with thinking or fallback
        blocks. A refusal comes back as HTTP 200 with no usable text.
        """
        if response.stop_reason == "refusal":
            details = getattr(response, "stop_details", None)
            category = getattr(details, "category", None) or "unspecified"
            raise RuntimeError(f"Claude declined the request (category: {category})")

        return "".join(
            block.text
            for block in response.content
            if getattr(block, "type", None) == "text"
        )

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
            max_context_tokens=1000000,
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
        self._apply_sampling(kwargs, resolved_model, temperature)
        if system:
            kwargs["system"] = system

        response = self.client.messages.create(**kwargs)

        # Extract usage info
        usage = response.usage
        cached_tokens = 0
        if hasattr(usage, "cache_read_input_tokens"):
            cached_tokens = usage.cache_read_input_tokens or 0

        return LLMResponse(
            text=self._extract_text(response),
            model=resolved_model,
            input_tokens=usage.input_tokens,
            output_tokens=usage.output_tokens,
            cached_tokens=cached_tokens,
            metadata={
                "stop_reason": response.stop_reason,
                "provider": "anthropic",
            }
        )

    def complete_chat(
        self,
        messages: list[dict],
        system_prompt: str | None = None,
        model: str | None = None,
        max_tokens: int = 1024,
        temperature: float = 0.7,
        use_cache: bool = False,
    ) -> LLMResponse:
        """
        Generate completion from multi-turn conversation using native Claude API.

        Args:
            messages: List of message dicts with 'role' and 'content'
            system_prompt: System prompt for context
            model: Model to use
            max_tokens: Maximum response tokens
            temperature: Sampling temperature
            use_cache: Enable prompt caching for system prompt

        Returns:
            LLMResponse with generated text
        """
        resolved_model = self._resolve_model(model) if model else self._default_model

        # Convert messages to Anthropic format
        anthropic_messages = []
        for msg in messages:
            anthropic_messages.append({
                "role": msg["role"],
                "content": msg["content"]
            })

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
            "messages": anthropic_messages,
        }
        self._apply_sampling(kwargs, resolved_model, temperature)
        if system:
            kwargs["system"] = system

        response = self.client.messages.create(**kwargs)

        # Extract usage info
        usage = response.usage
        cached_tokens = 0
        if hasattr(usage, "cache_read_input_tokens"):
            cached_tokens = usage.cache_read_input_tokens or 0

        return LLMResponse(
            text=self._extract_text(response),
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

        kwargs = {
            "model": resolved_model,
            "max_tokens": max_tokens,
            "system": [{
                "type": "text",
                "text": system_prompt,
                "cache_control": {"type": "ephemeral"}
            }],
            "messages": [{
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
            }],
        }
        self._apply_sampling(kwargs, resolved_model, temperature)

        response = self.client.messages.create(**kwargs)

        usage = response.usage
        cached_tokens = 0
        if hasattr(usage, "cache_read_input_tokens"):
            cached_tokens = usage.cache_read_input_tokens or 0

        return LLMResponse(
            text=self._extract_text(response),
            model=resolved_model,
            input_tokens=usage.input_tokens,
            output_tokens=usage.output_tokens,
            cached_tokens=cached_tokens,
            metadata={
                "stop_reason": response.stop_reason,
                "provider": "anthropic",
            }
        )
