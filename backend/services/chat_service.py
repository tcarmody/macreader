"""
Chat service: business logic for article chat conversations.

Handles context building, LLM calls, and message management for
refining summaries and Q&A about article content.
"""

from typing import TYPE_CHECKING

from fastapi import HTTPException

from ..database import Database
from ..database.models import DBArticle, DBChatMessage

if TYPE_CHECKING:
    from ..providers.base import LLMProvider


# Maximum tokens to use for article content in context
MAX_ARTICLE_TOKENS = 8000  # ~32K characters
# Maximum number of messages to include in context
MAX_HISTORY_MESSAGES = 20

CHAT_SYSTEM_PROMPT = """You are a helpful assistant that answers questions about articles and helps refine article summaries.

You have access to:
1. The article's title, URL, and publication date
2. The existing summary and key points (if available)
3. The full article content (which may be truncated for length)

Your role:
- Answer questions about the article accurately based on its content
- Help refine summaries when asked (make them more detailed, simpler, focus on specific aspects, etc.)
- Provide clarifications about technical terms or concepts mentioned
- Highlight important points the user might have missed
- Be concise but thorough

When refining summaries:
- Maintain accuracy to the original article
- Adjust tone/detail level based on user requests
- Keep the same structured format (headline, summary, key points) unless asked otherwise

When answering questions:
- Base your answers on the article content provided
- If the article doesn't contain information to answer a question, say so
- Cite specific parts of the article when relevant"""


def _truncate_content(content: str, max_chars: int = 32000) -> str:
    """Truncate content to fit within context limits."""
    if not content or len(content) <= max_chars:
        return content or ""

    # Try to truncate at a sentence boundary
    truncated = content[:max_chars]
    last_period = truncated.rfind(". ")
    if last_period > max_chars * 0.8:  # Only if we keep at least 80%
        truncated = truncated[:last_period + 1]

    return truncated + "\n\n[Content truncated for length]"


def _build_article_context(article: DBArticle) -> str:
    """Build the article context string for the system prompt."""
    parts = []

    # Basic metadata
    parts.append(f"ARTICLE TITLE: {article.title}")
    parts.append(f"URL: {article.source_url or article.url}")

    if article.published_at:
        parts.append(f"PUBLISHED: {article.published_at.strftime('%Y-%m-%d')}")

    if article.author:
        parts.append(f"AUTHOR: {article.author}")

    # Existing summary if available
    if article.summary_full:
        parts.append(f"\nEXISTING SUMMARY:\n{article.summary_full}")

    if article.key_points:
        points_str = "\n".join(f"- {p}" for p in article.key_points)
        parts.append(f"\nKEY POINTS:\n{points_str}")

    # Article content
    if article.content:
        truncated = _truncate_content(article.content)
        parts.append(f"\nARTICLE CONTENT:\n{truncated}")
    else:
        parts.append("\n[Article content not available]")

    return "\n".join(parts)


class ChatService:
    """Service for article chat conversations."""

    def __init__(
        self,
        db: Database,
        provider: "LLMProvider | None" = None,
    ):
        self.db = db
        self.provider = provider

    async def send_message(
        self,
        article_id: int,
        user_id: int,
        message: str,
    ) -> DBChatMessage:
        """
        Send a message in an article chat and get the assistant's response.

        Args:
            article_id: Article being discussed
            user_id: User sending the message
            message: User's message content

        Returns:
            The assistant's response message

        Raises:
            HTTPException: If article not found or provider not configured
        """
        if not self.provider:
            raise HTTPException(
                status_code=503,
                detail="Chat unavailable: LLM provider not configured"
            )

        # Get article
        article = self.db.get_article_with_user_state(article_id, user_id)
        if not article:
            raise HTTPException(status_code=404, detail="Article not found")

        # Get or create chat
        chat = self.db.chat.get_or_create_chat(article_id, user_id)

        # Save user message
        self.db.chat.add_message(chat.id, "user", message)

        # Get conversation history
        history = self.db.chat.get_messages(chat.id, limit=MAX_HISTORY_MESSAGES)

        # Build messages for LLM
        messages = [{"role": m.role, "content": m.content} for m in history]

        # Build context
        article_context = _build_article_context(article)
        system_prompt = f"{CHAT_SYSTEM_PROMPT}\n\n---\n\n{article_context}"

        # Call LLM
        try:
            response = await self.provider.complete_chat_async(
                messages=messages,
                system_prompt=system_prompt,
                max_tokens=2048,
                temperature=0.7,
                use_cache=True,  # Cache system prompt with article context
            )
        except Exception as e:
            raise HTTPException(
                status_code=500,
                detail=f"Failed to generate response: {str(e)}"
            )

        # Save assistant response
        assistant_message = self.db.chat.add_message(
            chat.id,
            "assistant",
            response.text,
            model_used=response.model,
        )

        return assistant_message

    def get_chat_history(
        self,
        article_id: int,
        user_id: int,
        limit: int = 50,
    ) -> list[DBChatMessage]:
        """
        Get chat history for an article.

        Returns empty list if no chat exists.
        """
        chat = self.db.chat.get_chat(article_id, user_id)
        if not chat:
            return []

        return self.db.chat.get_messages(chat.id, limit=limit)

    def clear_chat(self, article_id: int, user_id: int) -> bool:
        """
        Clear chat history for an article.

        Returns True if chat was deleted, False if it didn't exist.
        """
        return self.db.chat.delete_chat(article_id, user_id)

    def has_chat(self, article_id: int, user_id: int) -> bool:
        """Check if a chat exists for this article/user pair."""
        chat = self.db.chat.get_chat(article_id, user_id)
        return chat is not None
