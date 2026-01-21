"""
Chat routes: article chat for summary refinement and Q&A.
"""

from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException

from ..auth import verify_api_key, get_current_user
from ..config import get_db, get_chat_service
from ..database import Database
from ..services.chat_service import ChatService
from ..schemas import (
    ChatMessageRequest,
    ChatMessageResponse,
    ChatHistoryResponse,
)

router = APIRouter(
    prefix="/articles/{article_id}/chat",
    tags=["chat"],
    dependencies=[Depends(verify_api_key)]
)


@router.get("")
async def get_chat_history(
    article_id: int,
    db: Annotated[Database, Depends(get_db)],
    user_id: Annotated[int, Depends(get_current_user)],
    limit: int = 50,
) -> ChatHistoryResponse:
    """Get chat history for an article.

    Returns empty list if no chat exists yet.
    """
    # Verify article exists
    article = db.get_article(article_id)
    if not article:
        raise HTTPException(status_code=404, detail="Article not found")

    # Get chat history directly from DB (doesn't require LLM provider)
    chat = db.chat.get_chat(article_id, user_id)
    if not chat:
        return ChatHistoryResponse(
            article_id=article_id,
            messages=[],
            has_chat=False,
        )

    messages = db.chat.get_messages(chat.id, limit=limit)

    return ChatHistoryResponse(
        article_id=article_id,
        messages=[ChatMessageResponse.from_db(m) for m in messages],
        has_chat=len(messages) > 0,
    )


@router.post("")
async def send_message(
    article_id: int,
    request: ChatMessageRequest,
    db: Annotated[Database, Depends(get_db)],
    chat_service: Annotated[ChatService | None, Depends(get_chat_service)],
    user_id: Annotated[int, Depends(get_current_user)],
) -> ChatMessageResponse:
    """Send a message to chat about an article.

    Creates a new chat if one doesn't exist.
    Returns the assistant's response.
    """
    # Validate message first (before checking service)
    if not request.message.strip():
        raise HTTPException(status_code=400, detail="Message cannot be empty")

    # Require chat service for sending messages
    if not chat_service:
        raise HTTPException(
            status_code=503,
            detail="Chat service not configured: LLM provider required"
        )

    response_message = await chat_service.send_message(
        article_id=article_id,
        user_id=user_id,
        message=request.message.strip(),
    )

    return ChatMessageResponse.from_db(response_message)


@router.delete("")
async def clear_chat(
    article_id: int,
    db: Annotated[Database, Depends(get_db)],
    user_id: Annotated[int, Depends(get_current_user)],
) -> dict:
    """Clear chat history for an article.

    Returns success status.
    """
    # Verify article exists
    article = db.get_article(article_id)
    if not article:
        raise HTTPException(status_code=404, detail="Article not found")

    # Delete chat directly from DB (doesn't require LLM provider)
    deleted = db.chat.delete_chat(article_id, user_id)

    return {
        "success": True,
        "deleted": deleted,
        "message": "Chat history cleared" if deleted else "No chat history to clear"
    }
