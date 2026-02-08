# Extending Two-Pass Summarization to All Articles

## Current state

The critic pipeline runs after step 1 only when `_should_use_critic` returns `True`:
- Word count > 2000
- `content_type == "newsletter"`

For all other articles, step 1's output is used directly. The critic always uses FAST tier (Haiku).

## Goal

Run the critic on every article. The headline quality improvement alone justifies it — generating the summary first, then writing the headline with full context, is a better decomposition than doing both simultaneously.

## What needs to change

### 1. Remove the gate

`_should_use_critic` currently filters. To run on all articles, simplify the check in `summarize()` from:

```python
if self.critic_enabled and self._should_use_critic(content, content_type):
```

to:

```python
if self.critic_enabled:
```

`_should_use_critic` and `_extract_content_type` become dead code and can be removed. The `critic_enabled` flag stays — it's the kill switch for cost control or testing.

### 2. Separate headline from step 1

Right now step 1 generates a headline that gets thrown away when the critic runs. For short articles (the new population), this wastes ~10-15 output tokens per article.

Remove headline from step 1's `INSTRUCTION_PROMPT`:
- Delete the HEADLINE GUIDELINES section
- Change the JSON schema to remove `"headline"`
- Step 1 returns: `{summary, key_points, content_type}`

The critic then becomes the sole headline author for all articles.

This requires updating `_parse_response` to handle responses without a headline field (return empty string, let the critic fill it in). The fallback path (critic fails) needs a simple headline derivation — use the first sentence of the summary, truncated to 200 chars.

### 3. Tune the critic prompt for short articles

The current `CRITIC_PROMPT` is newsletter-heavy (structure checks for multi-story content, paragraph separation). For a 300-word product announcement, most of those checks are irrelevant noise.

Add a content-type-aware preamble to the critic's dynamic content:

```
Content type: {content_type}
Word count: {word_count}
```

This lets the critic self-calibrate without needing separate prompts. The existing evaluation criteria already cover single-story articles ("4-6 flowing sentences, no fragmentation") — they just need equal weight.

### 4. Measure before and after

Before enabling globally, collect data on how often the critic actually changes things. Add a `critic_revised` boolean column to the articles table (or store in the existing `model_used` field as `"fast+critic"` vs `"standard+critic"`).

Track:
- **Revision rate**: What percentage of articles get revised? If it's < 10%, the critic is mostly rubber-stamping and the cost isn't justified for short articles.
- **Revision type breakdown**: Are changes mostly headline rewrites (expected) or summary corrections (indicates step 1 prompt needs tuning)?
- **Latency impact**: Background tasks, so not user-facing, but monitor task queue depth.

### 5. Cost projection

Current (critic on ~20% of articles):
- 100 articles/day: ~$0.07 (80 single-pass + 20 two-pass)

Proposed (critic on 100% of articles):
- 100 articles/day: ~$0.15 (100 two-pass)
- 1,000 articles/day: ~$1.50

The critic call is cheap (Haiku, ~300 input tokens from step 1 output + cached system/instruction prompts, ~200 output tokens). The main cost is the extra API call latency, not dollars.

### 6. Rollout sequence

**Phase 1 — Measure (no code change needed)**
Turn on logging of `revisions_made` from the critic for the current long/newsletter population. Run for a week. Confirm the critic is making meaningful changes > 50% of the time.

**Phase 2 — Remove gate, keep headline in step 1**
Change `_should_use_critic` to `return True`. This is a one-line change. Step 1 still generates a headline (wasted work but zero risk). Run for a week with the revision rate metric. If the critic revises < 10% of short articles, reconsider.

**Phase 3 — Remove headline from step 1**
Once Phase 2 proves the critic is valuable across all articles, strip headline generation from `INSTRUCTION_PROMPT`. Update `_parse_response` fallback. This saves ~10-15 tokens per article and simplifies the step 1 prompt.

**Phase 4 — Cleanup**
Remove `_should_use_critic`, `_extract_content_type`, and the content-type gate. Update tests to reflect the new always-on behavior.

## Files to modify

- `backend/summarizer.py` — Gate removal, prompt changes, fallback logic
- `backend/tests/test_summarizer.py` — Update trigger tests, add short-article critic tests
- `backend/database/connection.py` — Optional: add `critic_revised` column for metrics
- `backend/database/article_repository.py` — Optional: store revision flag

## Risks

- **Cost creep at scale**: At 10,000 articles/day the critic adds ~$15/day. Mitigate with the `critic_enabled` flag and per-feed opt-out if needed.
- **Critic degrades short summaries**: The critic might over-edit concise summaries of simple articles. Phase 2 measurement catches this.
- **Latency for auto-summarize**: Feed refresh with `auto_summarize` enabled will take ~2x longer per article. Acceptable since it's async, but monitor task queue depth.
