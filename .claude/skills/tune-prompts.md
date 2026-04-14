---
name: tune-prompts
description: Iterate on summarizer and brief generator prompts by running test articles through the pipeline and comparing output
user_invocable: true
---

# Tune Prompts

Iterate on the AI summarization prompts in this project. The goal is to make targeted edits to prompts, run a test article through the pipeline, and compare before/after output — all without restarting the server.

## Prompt locations

The prompts live in two files:

1. **Summarizer** (`backend/summarizer.py`):
   - `SYSTEM_PROMPT` — persona and quality standards
   - `INSTRUCTION_PROMPT` — summarization instructions, content type detection, headline/summary/key-points guidelines
   - `CRITIC_PROMPT` — second-pass evaluation criteria and headline rewrite

2. **Brief Generator** (`backend/services/brief_generator.py`):
   - `SYSTEM_PROMPT` — newsletter editor persona
   - `_INSTRUCTIONS` dict — per-(length, tone) instruction prompts

## Workflow

1. **Ask the user** which prompt they want to iterate on (summarizer system, summarizer instructions, critic, or brief generator) and what aspect they want to change. If they already specified this, skip asking.

2. **Read the current prompt** from the source file.

3. **Show the current prompt** to the user and propose specific edits based on what they want to change. Keep edits surgical — change only what's needed.

4. **Get a test article.** Ask the user for one of:
   - An article ID from the database (fetch via `source rss_venv/bin/activate && python3 -c "..."` using the Database class)
   - A URL to fetch content from
   - Paste raw text
   
   If they don't have a preference, pick a recent article from the database:
   ```bash
   source rss_venv/bin/activate && python3 -c "
   from backend.database import Database
   import asyncio
   async def main():
       db = Database('data/articles.db')
       await db.initialize()
       rows = await db.execute_query('SELECT id, title, length(content) as len FROM articles WHERE content IS NOT NULL AND length(content) > 500 ORDER BY published_date DESC LIMIT 5')
       for r in rows:
           print(f'  [{r[\"id\"]}] {r[\"title\"]} ({r[\"len\"]} chars)')
   asyncio.run(main())
   "
   ```

5. **Run the BEFORE test** using the current prompts (read the article content, call the summarizer via Python):
   ```bash
   source rss_venv/bin/activate && python3 -c "
   import json, os
   from backend.providers import AnthropicProvider
   from backend.summarizer import Summarizer
   from backend.database import Database
   import asyncio

   async def main():
       db = Database('data/articles.db')
       await db.initialize()
       article = await db.get_article(ARTICLE_ID)
       
       provider = AnthropicProvider(api_key=os.environ['ANTHROPIC_API_KEY'])
       summarizer = Summarizer(provider=provider, critic_enabled=True)
       result = summarizer.summarize(article['content'], article['url'], article['title'])
       
       print('=== HEADLINE ===')
       print(result.one_liner)
       print()
       print('=== SUMMARY ===')
       print(result.full_summary)
       print()
       print('=== KEY POINTS ===')
       for kp in result.key_points:
           print(f'  - {kp}')
       print()
       print(f'Model: {result.model_used.value}')
   
   asyncio.run(main())
   "
   ```

6. **Apply the prompt edit** to the source file using the Edit tool.

7. **Run the AFTER test** with the same article and the modified prompts (same script as step 5).

8. **Show a side-by-side comparison** of BEFORE vs AFTER output, highlighting:
   - Headline differences
   - Summary structure and tone changes
   - Key points quality
   - Whether the change achieved the user's goal

9. **Ask the user**: keep the change, revert it, or iterate further?
   - If they want to revert, undo the edit
   - If they want to iterate, go back to step 3 with the current state

## Guidelines

- Never change prompt structure (JSON output format, field names) without warning — it will break parsing in `_parse_response`.
- The critic prompt runs only for articles >2000 words or newsletters. If testing critic changes, pick a long article or force it.
- For brief generator changes, use the brief generator's own test path, not the summarizer.
- Keep the user informed about estimated API cost per test run (~$0.005-0.02 per summarization).
- If the user wants to test the same change across multiple articles, batch them.
