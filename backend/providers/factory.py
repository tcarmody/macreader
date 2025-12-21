"""
Provider factory for creating LLM provider instances.

Handles provider selection based on configuration and available API keys.
"""

from enum import Enum

from .base import LLMProvider
from .anthropic import AnthropicProvider
from .openai import OpenAIProvider
from .google import GoogleProvider


class ProviderType(Enum):
    """Available LLM provider types."""
    ANTHROPIC = "anthropic"
    OPENAI = "openai"
    GOOGLE = "google"


def create_provider(
    provider_type: ProviderType | str,
    api_key: str,
    default_model: str | None = None,
    **kwargs,
) -> LLMProvider:
    """
    Create an LLM provider instance.

    Args:
        provider_type: The provider to create (anthropic, openai, google)
        api_key: API key for the provider
        default_model: Optional default model override
        **kwargs: Additional provider-specific arguments

    Returns:
        Configured LLMProvider instance

    Raises:
        ValueError: If provider_type is unknown
    """
    # Normalize provider type
    if isinstance(provider_type, str):
        try:
            provider_type = ProviderType(provider_type.lower())
        except ValueError:
            raise ValueError(
                f"Unknown provider: {provider_type}. "
                f"Available: {[p.value for p in ProviderType]}"
            )

    # Create provider instance
    if provider_type == ProviderType.ANTHROPIC:
        return AnthropicProvider(
            api_key=api_key,
            default_model=default_model or "claude-haiku-4-5",
        )
    elif provider_type == ProviderType.OPENAI:
        return OpenAIProvider(
            api_key=api_key,
            default_model=default_model or "gpt-5.2-mini",
            organization=kwargs.get("organization"),
        )
    elif provider_type == ProviderType.GOOGLE:
        return GoogleProvider(
            api_key=api_key,
            default_model=default_model or "gemini-3-flash-preview",
        )
    else:
        raise ValueError(f"Unknown provider type: {provider_type}")


def get_provider_from_env(
    anthropic_key: str | None = None,
    openai_key: str | None = None,
    google_key: str | None = None,
    preferred_provider: str | None = None,
    default_model: str | None = None,
) -> LLMProvider | None:
    """
    Create a provider from available environment keys.

    Tries providers in order of preference, returning the first
    one with a valid API key configured.

    Args:
        anthropic_key: Anthropic API key (or None if not set)
        openai_key: OpenAI API key (or None if not set)
        google_key: Google API key (or None if not set)
        preferred_provider: Preferred provider name (anthropic, openai, google)
        default_model: Optional model override

    Returns:
        Configured LLMProvider or None if no keys available
    """
    # Map of provider types to their API keys
    providers = {
        ProviderType.ANTHROPIC: anthropic_key,
        ProviderType.OPENAI: openai_key,
        ProviderType.GOOGLE: google_key,
    }

    # If preferred provider specified and has a key, use it
    if preferred_provider:
        try:
            pref_type = ProviderType(preferred_provider.lower())
            if providers.get(pref_type):
                return create_provider(
                    pref_type,
                    providers[pref_type],
                    default_model=default_model,
                )
        except ValueError:
            pass  # Invalid provider name, fall through to default order

    # Otherwise try in default order: Anthropic > OpenAI > Google
    for provider_type, api_key in providers.items():
        if api_key:
            return create_provider(
                provider_type,
                api_key,
                default_model=default_model,
            )

    return None
