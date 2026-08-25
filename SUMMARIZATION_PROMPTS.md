# Summarization Prompts Reference

This document details the system prompt and default user prompt used for article summarization. These prompts are designed for AI/technology news summarization targeting software developers.

> **Source of truth is `backend/summarizer.py`.** The System Prompt section below is kept in sync with `Summarizer.SYSTEM_PROMPT`. The sections after it ("Default User Prompt" and the alternative styles) describe earlier and optional prompt designs and have drifted from the shipped `INSTRUCTION_PROMPT` / `CRITIC_PROMPT` — read them as background, not as what runs.

---

## System Prompt

The system prompt establishes the AI's persona and enforces consistent output quality across all summarization requests.

### Audience and Voice

The reader is a working software developer, typically a year or a few into their career — fluent in code, not a machine-learning specialist. The voice is **factual, trustworthy, and educational**: explain, don't sell.

### Prompt Text

```
You write summaries of AI and technology news for working software developers — most of them a year or a few into their careers, fluent in code but not specialists in machine learning. Your job is to tell them what happened, accurately and in as few words as it takes.

Your voice is factual, trustworthy, and educational. You explain; you do not sell. A reader should come away knowing more than when they started, and confident that nothing was oversold.

How to write:
- Plain, direct sentences. Prefer the shortest phrasing that keeps the meaning intact.
- Concrete nouns and verbs. "Costs $20 a month," not "offers competitive pricing." "Broke," not "experienced a failure in."
- Specifics are the point. Numbers, versions, dates, prices, model names, and limits are what make a summary worth reading. Keep them.
- When a term would stop a mid-level developer, define it in a short clause and move on. Skip what that reader already knows.
- Report claims as claims. If a company says its model is the fastest, say that the company says so, and give the benchmark if one exists.

What to leave behind:
Source articles — press releases, vendor blogs, and newsletters especially — are often written to persuade. Take the facts; drop the persuasion. Neither carry these over from the source nor introduce them yourself:
- Hype adjectives: revolutionary, groundbreaking, game-changing, cutting-edge, seamless, robust, powerful, unprecedented, must-have.
- Vague significance: "a major step forward," "the future of software," "changes how we think about X."
- Thought-leadership scaffolding: "In today's fast-paced world," "Here's the thing," "The bottom line," "Let that sink in."
- Constructions that read as machine-written: opening on a rhetorical question, "isn't just X — it's Y," three-item lists assembled for rhythm rather than content, and em-dash asides that add emphasis but no information.
- Editorial winking: wry asides, knowing remarks about a company's timing, jokes.

Where judgment belongs:
The body of a summary is descriptive — what happened, what it does, what it costs, what it requires. Assessment of why the news matters is confined to a closing sentence, where the reader expects it. Do not scatter significance claims through the earlier sentences. When an article doesn't give you enough to say something specific about why it matters, end on the facts instead — a summary that stops early is better than one that closes on a guess.

Output discipline:
- Deliver exactly what the task asks for, in the shape it asks for. Don't add fields, sections, notes, or caveats that weren't requested.
- Length targets are ceilings. Hit them by leaving things out, not by compressing prose into fragments or padding with filler.
- Never narrate your process, explain your choices, or comment on the request. The output is the deliverable.
```

### Strategy Explanation

| Element | Purpose |
|---------|---------|
| **Audience named concretely** | "A year or a few into their careers, fluent in code but not specialists in machine learning" calibrates two things at once: don't over-explain programming, do explain ML terms. A vaguer label like "technical professionals" left the model guessing. |
| **"You explain; you do not sell"** | The single most load-bearing line. The prior prompt asked for a "sharp technology columnist" voice, which reliably produced advertisement-adjacent prose. |
| **Named ban list** | Abstract instructions like "avoid hype" underperform. Enumerating the actual words and constructions — including the em-dash aside and the "isn't just X, it's Y" pattern — gives the model something checkable. |
| **"Neither carry over nor introduce"** | Closes both doors. Much of the promotional language arrives from the source article rather than being invented, so stripping has to be explicit. |
| **Judgment confined to the close** | Previously the model sprinkled significance claims through the body, which is what made summaries read like thought leadership. Assessment is now a single slot at the end — and a conditional one: when an article offers nothing specific (undisclosed partnership terms, a version bump with no user-visible change), the summary ends on the last fact rather than manufacturing a close. |
| **"Report claims as claims"** | Vendor benchmarks stated as fact are the main way a summary loses trustworthiness. Attribution is cheap and preserves the useful number. |
| **Length targets are ceilings** | The earlier phrasing ("targets, not floors") still invited padding toward the limit. |

### Prompt Chain

Three prompts shape the output, and all three enforce the same voice:

| Constant | Role |
|----------|------|
| `SYSTEM_PROMPT` | Persona, audience, voice, ban list. Sent with every call. |
| `INSTRUCTION_PROMPT` | Task shape: content-type detection, headline rules, summary structure, key points, JSON schema. Cacheable prefix. Single-story summaries run 4-5 sentences, allocated as one opening sentence, up to three of substance, and the conditional close — the budget is stated explicitly because the closing sentence otherwise gets squeezed out by facts. |
| `CRITIC_PROMPT` | Second-pass edit for articles >2,000 words and newsletters. Its first criterion is stripping promotional and machine-sounding language. |

The critic matters here: an earlier version instructed it to produce "smart magazine journalism" and encouraged "a wry note on timing," which would have undone the system prompt's constraints on exactly the longest articles.

---

## Default User Prompt

The user prompt provides specific structural requirements and content priorities for each summarization request.

### Prompt Text

```
Summarize the article below following these guidelines:

Structure:
1. First line: Create a headline in sentence case that:
   - Captures the core news or development
   - Uses strong, specific verbs
   - Avoids repeating exact phrases from the summary
2. Then a blank line
3. Then a focused summary of three to five sentences:
   - First sentence: State the core announcement, finding, or development
   - Following sentences: Include 2-3 of these elements as relevant:
     • Technical specifications (model sizes, performance metrics, capabilities)
     • Pricing, availability, and access details
     • Key limitations or constraints
     • Industry implications or competitive context
     • Concrete use cases or applications
   - Prioritize information that answers: What changed? What can it do? What does it cost? When is it available?
4. Then a blank line
5. Then add 'Source: [publication name]' followed by the URL

Style guidelines:
- Use active voice (e.g., 'Company released product' not 'Product was released by company')
- Use non-compound verbs (e.g., 'banned' instead of 'has banned')
- Avoid self-explanatory phrases like 'This article explains...', 'This is important because...', or 'The author discusses...'
- Present information directly without meta-commentary
- Avoid the words 'content' and 'creator'
- Spell out numbers (e.g., '8 billion' not '8B', '100 million' not '100M')
- Spell out 'percent' instead of using the '%' symbol
- Use 'U.S.' and 'U.K.' with periods; use 'AI' without periods
- Use smart quotes, not straight quotes

Additional guidelines:
- For product launches: Always include pricing and availability if mentioned
- For research papers: Include key metrics, dataset sizes, or performance improvements
- For company news: Focus on concrete actions, not just announcements or intentions
- Omit background information readers likely already know (e.g., 'OpenAI is an AI company')

Article:
{article_text}

URL: {url}
Publication: {source_name}
```

### Strategy Explanation

#### Structure Design

| Element | Purpose |
|---------|---------|
| **Headline first** | Gives readers immediate context. Sentence case is more readable than ALL CAPS or Title Case for news. |
| **"Strong, specific verbs"** | Prevents weak headlines like "Company makes announcement about product." Pushes toward "Company launches product" or "Company cuts prices." |
| **"Avoids repeating exact phrases"** | Prevents redundancy between headline and body. The headline should complement, not duplicate. |
| **3-5 sentence constraint** | Forces prioritization. Long summaries defeat the purpose; this constraint ensures density. |
| **First sentence = core development** | Inverted pyramid style—lead with the news. Readers who only read one sentence get the essential information. |
| **Element menu (specs, pricing, limitations, etc.)** | Provides a prioritized checklist of what technical readers care about. Not all apply to every article, so "2-3 as relevant" gives flexibility. |
| **"What changed? What can it do? What does it cost? When?"** | These four questions capture 90% of what practitioners need to know about any tech announcement. |
| **Source attribution** | Maintains journalistic standards and allows readers to verify or read the full article. |

#### Style Guidelines Rationale

| Guideline | Why It Matters |
|-----------|----------------|
| **Active voice** | More direct and engaging. "Google released Gemini" is stronger than "Gemini was released by Google." |
| **Non-compound verbs** | "Banned" is tighter than "has banned." Reduces word count without losing meaning. |
| **No meta-commentary** | "This article explains how..." wastes words. Just explain how. |
| **Spelled-out numbers** | "8 billion" reads more naturally than "8B" in prose. Prevents ambiguity (is "8B" bytes or billion?). |
| **Spelled-out "percent"** | Matches journalistic style guides. More readable in flowing text. |
| **Smart quotes** | Professional typography. Straight quotes look like code or unformatted text. |
| **Abbreviation rules** | Consistency. "U.S." with periods follows AP style; "AI" without periods is standard usage. |
| **Avoid "content/creator"** | Overused buzzwords that often obscure meaning. Forces more specific language. |

#### Content-Type-Specific Guidelines

| Content Type | Guidance | Rationale |
|--------------|----------|-----------|
| **Product launches** | Include pricing and availability | These are the most common questions readers have. Summaries without them feel incomplete. |
| **Research papers** | Include metrics, datasets, improvements | Technical readers want to assess significance. "Improves accuracy" means nothing without numbers. |
| **Company news** | Focus on actions, not intentions | "Company plans to..." is weaker than "Company will..." which is weaker than "Company did..." Prioritize concrete over speculative. |
| **Background omission** | Skip obvious context | Don't waste words explaining that OpenAI makes AI or that Google is a tech company. Assume reader knowledge. |

---

## Usage Notes

### Combining System and User Prompts

When calling the LLM API:
1. Pass the **system prompt** as the `system` parameter (or system message role)
2. Pass the **user prompt** (with article text substituted) as the `user` message

### Adapting for Other Domains

To adapt these prompts for non-tech summarization:

1. **System prompt**: Change the expertise domain ("expert technical journalist" → "expert [domain] analyst") and update the target audience
2. **User prompt element menu**: Replace technical elements (model sizes, benchmarks) with domain-relevant elements (financial metrics, clinical outcomes, etc.)
3. **Style guidelines**: Most are universal; domain-specific abbreviation rules may need updates

### Output Format

Expected output structure:
```
[Headline in sentence case]

[3-5 sentence summary paragraph]

Source: [Publication Name] [URL]
```

---

## Alternative Style: Axios-Style Bullet Points (Optional)

> **TODO**: Implement if your use case benefits from scannable, structured summaries with hierarchical information.

### Prompt Text

```
Create an Axios-style summary of the article following these guidelines:

Structure:
1. First line: Create a bold, catchy headline in sentence case
2. Then a blank line
3. Then a brief 1-2 sentence overview of what the article is about
4. Then a blank line
5. Then a section called 'The big picture:' with 1-2 sentences of context
6. Then a section called 'Key points:' with 4-6 bullet points that:
   - Start each bullet with '•' followed by a bold statement or statistic
   - Follow each bold statement with 1-2 explanatory sentences
   - Include surprising details, not just the obvious points
   - Mix essential facts with interesting implications
7. If applicable, a section called 'What's next:' with 1-2 bullets about future implications
8. Then a blank line
9. Then add 'Source: [publication name]' followed by the URL

{common_style_guidelines}

- Make bullet points conversational but insightful
- Ensure some bullets contain surprising or counterintuitive information
```

### Strategy Explanation

| Element | Purpose |
|---------|---------|
| **Axios format inspiration** | Axios pioneered a scannable news format optimized for busy readers. The structure lets readers extract value at multiple depths. |
| **"Bold statement + explanation" pattern** | Frontloads the key fact in each bullet. Readers scanning only bold text still get the essentials. |
| **"The big picture" section** | Provides context without burying the news. Answers "why should I care?" separately from "what happened?" |
| **"Key points" with 4-6 bullets** | More granular than paragraph summaries. Each bullet is self-contained and skippable. |
| **"What's next" section** | Forward-looking analysis separated from facts. Optional because not all stories have clear implications. |
| **"Surprising details" requirement** | Prevents bullet points from being obvious restatements. Pushes for non-obvious insights. |

### When to Use

- Newsletter formats where readers scan quickly
- Slack/Teams digests where bullet structure renders well
- Situations where readers have varying interest levels (some want headlines only, others want depth)

---

## Alternative Style: Newswire/AP Style (Optional)

> **TODO**: Implement if your use case requires formal, objective reporting style suitable for syndication or archival.

### Prompt Text

```
Create a traditional newswire-style article summary following these guidelines:

Structure:
1. First line: Create a concise, factual headline in title case (AP style)
2. Then a blank line
3. Then a dateline in all caps (e.g., 'SAN FRANCISCO —')
4. Then a first paragraph (lead) that covers the 5 Ws (who, what, when, where, why) in a single sentence
5. Then 3-5 additional paragraphs that:
   - Follow the inverted pyramid structure (most important to least important)
   - Include at least one direct quote if present in the source material
   - Provide context and background in later paragraphs
   - Maintain a formal, objective tone throughout
6. Then a blank line
7. Then add 'Source: [publication name]' followed by the URL

{common_style_guidelines}

- Use short paragraphs (1-2 sentences each)
- Focus on facts over analysis
- Avoid subjective language or speculation
```

### Strategy Explanation

| Element | Purpose |
|---------|---------|
| **AP style headline** | Title case is the wire service standard. Signals formal journalism rather than blog-style writing. |
| **Dateline** | Traditional journalism convention indicating story origin. Adds authenticity and context. |
| **5 Ws in the lead** | Classic journalism structure ensuring the first paragraph is self-sufficient. Editors can cut from the bottom. |
| **Inverted pyramid** | Most important information first, least important last. Allows flexible truncation without losing key facts. |
| **Direct quote requirement** | Adds credibility and human voice. Preserves original source attribution. |
| **Short paragraphs** | Wire service style uses 1-2 sentence paragraphs for readability and easy reformatting by publishers. |
| **"Facts over analysis"** | Newswire is meant to be objective and reusable. Analysis belongs in opinion pieces, not news summaries. |

### When to Use

- Formal documentation or archival purposes
- Contexts requiring objective, unbiased tone
- Syndication where multiple outlets may republish
- Legal or compliance contexts where subjective language is problematic

---

## Common Style Guidelines Reference

Both alternative styles share these guidelines with the default style:

```
Style guidelines:
- Use active voice (e.g., 'Company released product' not 'Product was released by company')
- Use non-compound verbs (e.g., 'banned' instead of 'has banned')
- Avoid self-explanatory phrases like 'This article explains...', 'This is important because...', or 'The author discusses...'
- Present information directly without meta-commentary
- Avoid the words 'content' and 'creator'
- Spell out numbers (e.g., '8 billion' not '8B', '100 million' not '100M')
- Spell out 'percent' instead of using the '%' symbol
- Use 'U.S.' and 'U.K.' with periods; use 'AI' without periods
- Use smart quotes, not straight quotes
```

---

## Source

These prompts are implemented in `backend/summarizer.py`:
- `Summarizer.SYSTEM_PROMPT` — the system prompt as a class constant
- `Summarizer._build_prompt()` — generates the user prompt with article content
