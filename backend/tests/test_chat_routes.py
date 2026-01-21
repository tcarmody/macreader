"""
Tests for chat routes.
"""

import pytest


class TestGetChatHistory:
    """Tests for GET /articles/{article_id}/chat endpoint."""

    def test_get_chat_empty_history(self, client_with_data):
        """Should return empty list when no chat exists."""
        client, data = client_with_data
        article_id = data["article_ids"][0]
        response = client.get(f"/articles/{article_id}/chat")
        assert response.status_code == 200
        result = response.json()
        assert result["article_id"] == article_id
        assert result["messages"] == []
        assert result["has_chat"] is False

    def test_get_chat_article_not_found(self, client):
        """Should return 404 for non-existent article."""
        response = client.get("/articles/99999/chat")
        assert response.status_code == 404


class TestSendMessage:
    """Tests for POST /articles/{article_id}/chat endpoint."""

    def test_send_message_service_not_configured(self, client_with_data):
        """Should return 503 when chat service not configured."""
        client, data = client_with_data
        article_id = data["article_ids"][0]
        response = client.post(
            f"/articles/{article_id}/chat",
            json={"message": "What is this article about?"}
        )
        # Chat service is disabled in tests (no API key)
        assert response.status_code == 503
        assert "not configured" in response.json()["detail"].lower()

    def test_send_empty_message(self, client_with_data):
        """Should return 400 for empty message."""
        client, data = client_with_data
        article_id = data["article_ids"][0]
        response = client.post(
            f"/articles/{article_id}/chat",
            json={"message": ""}
        )
        assert response.status_code == 400
        assert "empty" in response.json()["detail"].lower()

    def test_send_whitespace_only_message(self, client_with_data):
        """Should return 400 for whitespace-only message."""
        client, data = client_with_data
        article_id = data["article_ids"][0]
        response = client.post(
            f"/articles/{article_id}/chat",
            json={"message": "   \n\t  "}
        )
        assert response.status_code == 400
        assert "empty" in response.json()["detail"].lower()


class TestClearChat:
    """Tests for DELETE /articles/{article_id}/chat endpoint."""

    def test_clear_chat_no_history(self, client_with_data):
        """Should succeed even when no chat exists."""
        client, data = client_with_data
        article_id = data["article_ids"][0]
        response = client.delete(f"/articles/{article_id}/chat")
        assert response.status_code == 200
        result = response.json()
        assert result["success"] is True
        assert result["deleted"] is False

    def test_clear_chat_article_not_found(self, client):
        """Should return 404 for non-existent article."""
        response = client.delete("/articles/99999/chat")
        assert response.status_code == 404


class TestChatRepository:
    """Tests for chat repository directly."""

    def test_get_or_create_chat(self, test_db):
        """Should create a new chat or return existing."""
        # Create test data
        user_id = test_db.users.get_or_create_api_user()
        feed_id = test_db.add_feed("https://test.com/feed", "Test")
        article_id = test_db.add_article(feed_id, "https://test.com/1", "Test Article")

        # First call creates chat
        chat1 = test_db.chat.get_or_create_chat(article_id, user_id)
        assert chat1.id is not None
        assert chat1.article_id == article_id
        assert chat1.user_id == user_id

        # Second call returns same chat
        chat2 = test_db.chat.get_or_create_chat(article_id, user_id)
        assert chat2.id == chat1.id

    def test_add_and_get_messages(self, test_db):
        """Should add messages and retrieve them in order."""
        user_id = test_db.users.get_or_create_api_user()
        feed_id = test_db.add_feed("https://test.com/feed", "Test")
        article_id = test_db.add_article(feed_id, "https://test.com/1", "Test Article")

        chat = test_db.chat.get_or_create_chat(article_id, user_id)

        # Add messages
        msg1 = test_db.chat.add_message(chat.id, "user", "Hello")
        msg2 = test_db.chat.add_message(chat.id, "assistant", "Hi there!", "haiku")
        msg3 = test_db.chat.add_message(chat.id, "user", "How are you?")

        # Get messages
        messages = test_db.chat.get_messages(chat.id)
        assert len(messages) == 3
        assert messages[0].content == "Hello"
        assert messages[0].role == "user"
        assert messages[1].content == "Hi there!"
        assert messages[1].role == "assistant"
        assert messages[1].model_used == "haiku"
        assert messages[2].content == "How are you?"

    def test_delete_chat(self, test_db):
        """Should delete chat and all messages."""
        user_id = test_db.users.get_or_create_api_user()
        feed_id = test_db.add_feed("https://test.com/feed", "Test")
        article_id = test_db.add_article(feed_id, "https://test.com/1", "Test Article")

        chat = test_db.chat.get_or_create_chat(article_id, user_id)
        test_db.chat.add_message(chat.id, "user", "Test message")

        # Delete chat
        deleted = test_db.chat.delete_chat(article_id, user_id)
        assert deleted is True

        # Verify chat is gone
        chat_after = test_db.chat.get_chat(article_id, user_id)
        assert chat_after is None

        # Delete again should return False
        deleted_again = test_db.chat.delete_chat(article_id, user_id)
        assert deleted_again is False

    def test_message_limit(self, test_db):
        """Should respect limit parameter when getting messages."""
        user_id = test_db.users.get_or_create_api_user()
        feed_id = test_db.add_feed("https://test.com/feed", "Test")
        article_id = test_db.add_article(feed_id, "https://test.com/1", "Test Article")

        chat = test_db.chat.get_or_create_chat(article_id, user_id)

        # Add 5 messages
        for i in range(5):
            test_db.chat.add_message(chat.id, "user", f"Message {i}")

        # Get only 2
        messages = test_db.chat.get_messages(chat.id, limit=2)
        assert len(messages) == 2
        assert messages[0].content == "Message 0"
        assert messages[1].content == "Message 1"

    def test_separate_chats_per_user(self, test_db):
        """Each user should have their own chat per article."""
        # Create two users
        user1_id = test_db.users.get_or_create_api_user()
        user2_id = test_db.users.get_or_create("user2@test.com", "User 2", "test")

        feed_id = test_db.add_feed("https://test.com/feed", "Test")
        article_id = test_db.add_article(feed_id, "https://test.com/1", "Test Article")

        # Create chats for both users on same article
        chat1 = test_db.chat.get_or_create_chat(article_id, user1_id)
        chat2 = test_db.chat.get_or_create_chat(article_id, user2_id)

        # Should be different chats
        assert chat1.id != chat2.id

        # Messages should be separate
        test_db.chat.add_message(chat1.id, "user", "User 1 message")
        test_db.chat.add_message(chat2.id, "user", "User 2 message")

        messages1 = test_db.chat.get_messages(chat1.id)
        messages2 = test_db.chat.get_messages(chat2.id)

        assert len(messages1) == 1
        assert len(messages2) == 1
        assert messages1[0].content == "User 1 message"
        assert messages2[0].content == "User 2 message"
