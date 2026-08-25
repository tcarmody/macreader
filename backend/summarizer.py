"""
Summarizer - LLM-powered article summarization.

Features:
- Multi-provider support (Anthropic, OpenAI, Google)
- Automatic model selection (advanced for complex, fast for simple)
- Structured summary output (one-liner, full summary, key points)
- Cache integration
- Prompt caching for Anthropic (90% cost reduction)
"""

from dataclasses import dataclass
from enum import Enum
from typing import TYPE_CHECKING

from .providers import LLMProvider, AnthropicProvider
from .providers.base import ModelTier

if TYPE_CHECKING:
    from .cache import TieredCache


class Model(Enum):
    """Model tier selection for summarization."""
    SONNET = "standard"  # Default: Claude Sonnet 5 on Anthropic
    HAIKU = "fast"       # Quick, cheap model


@dataclass
class Summary:
    """Structured article summary."""
    title: str
    one_liner: str          # 1 sentence for feed view
    full_summary: str       # 3-5 paragraphs
    key_points: list[str]   # Bullet points
    model_used: Model
    cached: bool = False


class Summarizer:
    """LLM-powered article summarizer with multi-provider support."""

    # Technical terms that suggest complex content
    TECHNICAL_TERMS = [
        "algorithm", "neural", "quantum", "blockchain", "protocol",
        "cryptographic", "machine learning", "artificial intelligence",
        "api", "infrastructure", "architecture", "microservices",
        "distributed", "consensus", "encryption", "compiler",
        "semiconductor", "genomic", "molecular", "theorem",
    ]

    # Maximum content length to send to API
    MAX_CONTENT_LENGTH = 15000

    # Output budget for a summary or critic pass. Comfortably above the ~600
    # tokens a summary needs; the newer Claude tokenizers count more tokens for
    # the same text, so leave headroom rather than risk a truncated JSON object.
    MAX_OUTPUT_TOKENS = 2048

    # System prompt establishing the AI persona and quality standards
    SYSTEM_PROMPT = """You write summaries of AI and technology news for working software developers — most of them a year or a few into their careers, fluent in code but not specialists in machine learning. Your job is to tell them what happened, accurately and in as few words as it takes.

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
- Never narrate your process, explain your choices, or comment on the request. The output is the deliverable."""

    # Static instruction prompt (cacheable) - separated from dynamic content
    INSTRUCTION_PROMPT = """Summarize the article below.

Return one JSON object and nothing else: no preamble, no markdown code fences, no commentary before or after. Use exactly the four keys shown at the end of these instructions, and no others.

Every guideline below applies to all fields, not only the first one you write.

CONTENT TYPE DETECTION:
First, classify the article as one of: news, analysis, tutorial, review, research, newsletter
- news: Announcements, product launches, funding, acquisitions, breaking developments
- analysis: Opinion pieces, commentary, predictions, industry analysis
- tutorial: How-to guides, technical walkthroughs, implementation guides
- review: Product reviews, comparisons, evaluations
- research: Academic papers, technical reports, benchmark studies
- newsletter: Multi-story digests, roundups, curated links

HEADLINE GUIDELINES (8-12 words):
- Lead with the most searchable noun (company name, product, technology)
- Use a strong, active verb
- Include one concrete detail (number, name, or outcome)
- Do NOT repeat the article's original headline verbatim
- Avoid vague words: "new," "big," "major," "revolutionary," "game-changing," "unveils," "redefines"
- Avoid clickbait: "You won't believe," "Here's why," "Everything you need to know"
- State what happened; don't tell the reader how to feel about it

Good: "Anthropic releases Claude 4 with 1M token context window"
Good: "Google open-sources Gemma 3 weights for commercial use"
Bad: "Anthropic announces major new AI model update"
Bad: "New Claude model is a game-changer for developers"

SUMMARY GUIDELINES:
Write 4-5 sentences of plain prose. No headings or bullets inside the summary.

For SINGLE-STORY articles (news, analysis, tutorial, review, research):
- ONE paragraph only. No paragraph breaks. Long and complex stories get a single cohesive paragraph too — length is never a reason to split.
- Sentence 1: what happened, phrased so a reader could repeat it to a colleague.
- Sentences 2 through 4: the substance — the facts a developer would actually need. What it does, what it costs, what it replaces, what it requires, where the limits are. Leave out details that matter only to the company. Three sentences here is the ceiling, not a quota; use two if two will do.
- Final sentence: what the news means for a developer — what it changes about their tools, their options, or their picture of where AI is heading. This is the only place judgment belongs.

The final sentence is part of the 4-5 sentence budget, not an addition to it. Facts get at most four sentences so that the close still fits. If you find yourself out of room, cut a fact — a summary that lists five specifications and never says what they add up to is the failure this structure exists to prevent.

Write the close for most articles; the facts you just stated usually imply one. Good closes are concrete: "this gives developers another self-hostable option for local inference," or "the license change means existing commercial deployments need review."

Omit it only when the article genuinely gives you nothing to work with: a partnership with undisclosed terms, a funding round with no product news, a version bump with no user-visible change. Then end on the last fact and stop. The test is whether you can name something a developer would do differently, or understand differently, because of this news. If you can, write it. If you'd have to reach for "an important milestone for the industry" or "a notable development in the space," you can't — leave it out.

Good: "OpenAI released GPT-5.2 with a 400,000-token context window, up from 128,000. It runs on the same API endpoints as GPT-5, so existing code needs no change beyond the model string, and input pricing holds at $3 per million tokens. OpenAI reports a 12-point gain on SWE-bench Verified but has not released the evaluation harness. For most developers the practical difference is that a whole repository now fits in one request, which removes the main reason to build chunking logic into a project."
Bad: "OpenAI has unveiled its groundbreaking GPT-5.2 model, a game-changing leap that redefines what's possible with large context windows. With a massive 400,000-token capacity, developers can now seamlessly process entire codebases — and that's not just an incremental improvement, it's a paradigm shift in how we think about software development."

The Bad example fails on three counts worth naming: hype adjectives ("groundbreaking," "game-changing," "massive," "seamlessly"), significance claims scattered through the body instead of held to the end, and no usable specifics — no pricing, no endpoint compatibility, no benchmark caveat.

For MULTI-STORY articles (newsletters, roundups, digests):
- First, identify each distinct news story or topic in the article. Each story gets its own paragraph.
- Separate paragraphs with \\n\\n. This is the ONLY content type that uses paragraph breaks.
- Each paragraph: 2-4 sentences covering one story. Lead with what happened, add the facts that matter, done.
- Order paragraphs by importance, not by the order they appeared in the original.
- Skip filler items, listicles of minor links, or "quick hits" sections — focus on the 3-5 most substantial stories.
- If the most significant story supports it, close its paragraph with one sentence on what it means for a developer. Same rule as above: omit it rather than manufacture one.

SPECIAL HANDLING BY CONTENT TYPE:
- analysis/opinion: Note the author's position neutrally (e.g., "argues that," "contends") without editorializing
- tutorial: Preserve the key actionable steps or techniques covered
- review: Include the verdict and primary pros/cons
- research: Note methodology, sample sizes, and any stated limitations
- news (press releases): Be skeptical—distinguish concrete announcements from aspirational claims

ADDITIONAL GUIDELINES:
- Attribute performance claims, benchmark results, and superlatives to whoever made them, and note when the underlying data isn't public
- If the article contains a notable quote from a primary source that captures the story's essence, include it
- If information conflicts or is disputed, present both sides neutrally
- If content appears truncated or paywalled, summarize only what's available and note the limitation
- Spell out numerals one through nine; use digits for 10 and above, currency, and large round numbers ("$15.99" not "fifteen ninety-nine dollars"; "8 billion" not "8B"; "percent" not "%")
- Use active voice and simple verbs ("released" not "has released")
- Omit background readers likely know ("OpenAI is an AI company")

KEY POINTS GUIDELINES:
- 3-5 bullet points with distinct, scannable takeaways
- One sentence each, roughly 25 words or fewer
- Include specific facts, numbers, dates, or names
- Facts only. Significance belongs in the summary's closing sentence, if there is one, not here
- For multi-story articles, prioritize across all stories by importance

Stay inside the stated limits: 8-12 words for the headline, 4-5 sentences of summary, 3-5 key points. If you are close to the ceiling, cut a detail rather than running past it.

Respond with this exact JSON structure:
{
  "headline": "Your headline here",
  "summary": "Your summary paragraphs here. Use \\n\\n for paragraph breaks in multi-story summaries.",
  "key_points": ["First point", "Second point", "Third point"],
  "content_type": "news|analysis|tutorial|review|research|newsletter"
}"""

    # Critic prompt for the review step (used for long articles and newsletters)
    CRITIC_PROMPT = """You are an editor reviewing a draft summary for a news digest read by working software developers. Fix what's wrong, leave what works, and write a better headline. The target is a clear technical brief: factual, trustworthy, educational.

You will receive the original article title and a JSON summary produced by a first-pass summarizer.

Editing, not expanding: the revision should be the same length as the draft or shorter. The only reason to add words is a substantial story the draft dropped from a newsletter.

EVALUATION CRITERIA:

1. STRIP PROMOTIONAL AND MACHINE-SOUNDING LANGUAGE (most important):
   - Delete hype adjectives: revolutionary, groundbreaking, game-changing, cutting-edge, seamless, robust, powerful, unprecedented. Replace with the specific fact underneath, or with nothing.
   - Delete thought-leadership scaffolding: "In today's fast-paced world," "Here's the thing," "The bottom line," "It's not just X, it's Y."
   - Delete rhetorical-question openers and three-item lists built for rhythm rather than content.
   - Cut throat-clearing: "It is worth noting that," "Interestingly," "Notably," "In a move that."
   - Replace formal constructions with plain ones: "at a valuation of" → "valued at"; "the company announced that it will" → "the company will."
   - Kill "has been," "was announced," "is expected to" — find the active verb underneath.
   - Attribute claims the draft states as fact. "The fastest open model available" becomes "which the company says is the fastest open model available."

2. CHECK WHERE THE JUDGMENT SITS:
   - The body should be descriptive. If a significance claim appears in the first sentences ("a major step for the industry," "this changes everything about X"), cut it or move the substance into the closing sentence.
   - A closing assessment is optional. When the draft has one, it must say something specific about what changes for a developer — their tools, their options, their read on where AI is heading. When the draft ends on a vague gesture ("an important milestone," "a notable development in the space"), first try to rewrite it into a concrete consequence using facts from the article; if the article doesn't support one, delete the sentence and end on the last fact. Do not add a closing assessment to a draft that doesn't have one.
   - At most one closing assessment, one sentence. Not a running commentary.

3. CHECK IT TEACHES:
   - The reader is a developer a year or a few into their career, not an ML specialist. A term that would stop them gets a short defining clause; a term they know does not get explained.
   - Specifics earn their space: numbers, versions, prices, model names, limits. If the draft is vague where the article was specific, put the specifics back.

4. STRUCTURE (enforce strictly):
   - Single-story articles run 4-5 sentences. If the draft runs longer, cut the least useful fact rather than compressing sentences into fragments.
   - Single-story articles (news, analysis, tutorial, review, research): ONE paragraph. No paragraph breaks, period. If the draft has multiple paragraphs for a single story, merge them into one.
   - Newsletters/digests: Each distinct story gets its own paragraph separated by \\n\\n. If the draft blends multiple stories into one paragraph, split them apart. If it misses a substantial story from the original, add it.

5. KEY POINTS (tighten these):
   - Each bullet should be one sentence, max ~25 words. If it runs longer, split or trim.
   - 3-5 distinct takeaways with no overlap
   - Each includes a specific fact, number, date, or name
   - Facts only — move any significance claim into the summary's closing sentence, or cut it
   - Cut any bullet that just restates something already in the summary without adding a new fact

6. HEADLINE (write a new one):
   - 8-12 words
   - Lead with most searchable noun (company, product, technology)
   - Strong active verb
   - One concrete detail (number, name, outcome)
   - Must NOT repeat the original article title
   - No vague words: "new," "big," "major," "game-changing," "unveils," "redefines"
   - No clickbait patterns

7. BASICS:
   - No meta-language ("This article discusses...", "The author explains...")
   - Spell out numerals one through nine; use digits for 10+, currency, and large round numbers
   - No unnecessary background readers likely know ("OpenAI is an AI company")

Revise wherever a criterion above applies. If a passage already meets them, leave it alone — rewriting for its own sake tends to reintroduce the padding you just removed. Write the headline fresh every time.

Return one JSON object and nothing else: no preamble, no markdown code fences, no commentary. Use exactly these four keys:
{
  "headline": "Your improved headline here",
  "summary": "The revised summary",
  "key_points": ["Revised points"],
  "revisions_made": ["List of specific changes, or empty array if none"]
}"""

    def __init__(
        self,
        provider: LLMProvider,
        cache: "TieredCache | None" = None,
        default_model: Model = Model.SONNET,
        critic_enabled: bool = True,
    ):
        """
        Initialize summarizer with an LLM provider.

        Args:
            provider: LLM provider instance (Anthropic, OpenAI, or Google)
            cache: Optional cache for storing summaries
            default_model: Default model tier for simple content
            critic_enabled: Enable critic step for long articles and newsletters
        """
        self.provider = provider
        self.cache = cache
        self.default_model = default_model
        self.critic_enabled = critic_enabled

    def summarize(
        self,
        content: str,
        url: str,
        title: str = "",
        force_model: Model | None = None
    ) -> Summary:
        """
        Generate a summary for article content.

        Args:
            content: The article text to summarize
            url: URL used as cache key
            title: Optional article title
            force_model: Override automatic model selection

        Returns:
            Summary object with one-liner, full summary, and key points
        """
        # Check cache first
        if self.cache:
            if cached := self.cache.get(f"summary:{url}"):
                if isinstance(cached, dict):
                    # Handle legacy model names in cache (e.g., "claude-haiku-4-5")
                    # Convert to tier values ("fast", "standard")
                    cached_model = cached.get("model_used", self.default_model.value)
                    if cached_model not in [m.value for m in Model]:
                        cached_model = self._map_legacy_model_to_tier(cached_model)

                    return Summary(
                        title=cached.get("title", title),
                        one_liner=cached.get("one_liner", ""),
                        full_summary=cached.get("full_summary", ""),
                        key_points=cached.get("key_points", []),
                        model_used=Model(cached_model),
                        cached=True
                    )

        # Select model based on content complexity
        model = force_model or self._select_model(content)
        model_tier = ModelTier.STANDARD if model == Model.SONNET else ModelTier.FAST

        # Build article content
        article_content = self._build_article_content(content, title, url)

        # Generate summary using provider
        # Use cacheable prefix for Anthropic (90% cost savings)
        if isinstance(self.provider, AnthropicProvider):
            response = self.provider.complete_with_cacheable_prefix(
                system_prompt=self.SYSTEM_PROMPT,
                instruction_prompt=self.INSTRUCTION_PROMPT,
                dynamic_content=article_content,
                model=self.provider.get_model_for_tier(model_tier),
                max_tokens=self.MAX_OUTPUT_TOKENS,
            )
        else:
            # Other providers: combine prompts
            user_prompt = f"{self.INSTRUCTION_PROMPT}\n\n{article_content}"
            response = self.provider.complete(
                user_prompt=user_prompt,
                system_prompt=self.SYSTEM_PROMPT,
                model=self.provider.get_model_for_tier(model_tier),
                max_tokens=self.MAX_OUTPUT_TOKENS,
            )

        # Check if critic step should run
        content_type = self._extract_content_type(response.text)
        if self.critic_enabled and self._should_use_critic(content, content_type):
            critic_result = self._run_critic(response.text, title, url)
            if critic_result:
                summary = self._parse_response(critic_result, model, title, url)
            else:
                summary = self._parse_response(response.text, model, title, url)
        else:
            summary = self._parse_response(response.text, model, title, url)

        # Cache the result
        if self.cache:
            self.cache.set(f"summary:{url}", {
                "title": summary.title,
                "one_liner": summary.one_liner,
                "full_summary": summary.full_summary,
                "key_points": summary.key_points,
                "model_used": summary.model_used.value
            })

        return summary

    def _map_legacy_model_to_tier(self, model_name: str) -> str:
        """
        Map legacy model names to tier values.

        Handles cached summaries from before the multi-provider update
        that stored actual model names instead of tier values.

        Args:
            model_name: Legacy model name (e.g., "claude-haiku-4-5", "gpt-5.2-mini")

        Returns:
            Tier value ("fast" or "standard")
        """
        model_lower = model_name.lower()

        # Fast tier models - check for specific patterns
        # Anthropic: claude-haiku-4-5, claude-3-haiku, etc.
        if "haiku" in model_lower:
            return Model.HAIKU.value

        # Google: gemini-3.0-flash, gemini-2.0-flash, etc.
        if "flash" in model_lower:
            return Model.HAIKU.value

        # OpenAI: gpt-5.2-mini, gpt-4o-mini, etc.
        # Must check for "-mini" to avoid matching "gemini"
        if "-mini" in model_lower:
            return Model.HAIKU.value

        # Everything else maps to standard tier
        # (sonnet, opus, gpt-5.2, gpt-4o, gemini-pro, etc.)
        return Model.SONNET.value

    def _select_model(self, content: str) -> Model:
        """
        Select appropriate model based on content complexity.

        Uses standard tier for:
        - Long content (>2000 words)
        - Technical content
        """
        word_count = len(content.split())

        # Long content needs more capable model
        if word_count > 2000:
            return Model.SONNET

        # Check for technical terms
        content_lower = content.lower()
        technical_count = sum(
            1 for term in self.TECHNICAL_TERMS
            if term in content_lower
        )

        # More than 2 technical terms suggests complex content
        if technical_count > 2:
            return Model.SONNET

        return self.default_model

    def _build_article_content(self, content: str, title: str = "", url: str = "") -> str:
        """Build the dynamic article content portion of the prompt."""
        title_line = f"Original title: {title}\n" if title else ""
        url_line = f"URL: {url}\n" if url else ""

        # Truncate content if too long
        truncated_content = content[:self.MAX_CONTENT_LENGTH]
        if len(content) > self.MAX_CONTENT_LENGTH:
            truncated_content += "\n\n[Content truncated...]"

        return f"""{title_line}{url_line}
Article:
{truncated_content}"""

    def _extract_content_type(self, text: str) -> str | None:
        """Extract content_type from LLM response JSON."""
        import json
        try:
            json_text = text.strip()
            if json_text.startswith("```"):
                lines = json_text.split("\n")
                json_text = "\n".join(lines[1:-1] if lines[-1].strip() == "```" else lines[1:])
            data = json.loads(json_text)
            return data.get("content_type")
        except (json.JSONDecodeError, KeyError, TypeError):
            return None

    def _should_use_critic(self, content: str, content_type: str | None) -> bool:
        """Check if critic step should run based on content characteristics."""
        word_count = len(content.split())
        if word_count > 2000:
            return True
        if content_type == "newsletter":
            return True
        return False

    def _run_critic(self, step1_response: str, title: str, url: str) -> str | None:
        """
        Run critic evaluation on step 1 output.

        Returns revised response text, or None on failure.
        """
        import json

        dynamic_content = f"Original article title: {title}\nURL: {url}\n\nFirst-pass summary:\n{step1_response}"

        # The critic rewrites prose the first pass already produced, so it runs
        # on the same tier as the draft rather than a cheaper one.
        critic_model = self.provider.get_model_for_tier(ModelTier.STANDARD)

        try:
            if isinstance(self.provider, AnthropicProvider):
                response = self.provider.complete_with_cacheable_prefix(
                    system_prompt=self.SYSTEM_PROMPT,
                    instruction_prompt=self.CRITIC_PROMPT,
                    dynamic_content=dynamic_content,
                    model=critic_model,
                    max_tokens=self.MAX_OUTPUT_TOKENS,
                )
            else:
                user_prompt = f"{self.CRITIC_PROMPT}\n\n{dynamic_content}"
                response = self.provider.complete(
                    user_prompt=user_prompt,
                    system_prompt=self.SYSTEM_PROMPT,
                    model=critic_model,
                    max_tokens=self.MAX_OUTPUT_TOKENS,
                )

            # Validate the critic produced parseable JSON
            json_text = response.text.strip()
            if json_text.startswith("```"):
                lines = json_text.split("\n")
                json_text = "\n".join(lines[1:-1] if lines[-1].strip() == "```" else lines[1:])

            data = json.loads(json_text)

            # Log revisions for observability
            revisions = data.get("revisions_made", [])
            if revisions:
                print(f"Critic made {len(revisions)} revision(s): {revisions}")
            else:
                print("Critic: no revisions to summary, headline updated")

            return response.text

        except Exception as e:
            print(f"Critic step failed, using original summary: {e}")
            return None

    def _parse_response(self, text: str, model: Model, title: str = "", url: str = "") -> Summary:
        """Parse LLM response (JSON) into structured Summary."""
        import json

        headline = ""
        summary_text = ""
        key_points: list[str] = []

        # Try to parse as JSON first
        try:
            # Handle potential markdown code blocks around JSON
            json_text = text.strip()
            if json_text.startswith("```"):
                # Remove markdown code fence
                lines = json_text.split("\n")
                # Skip first line (```json) and last line (```)
                json_text = "\n".join(lines[1:-1] if lines[-1].strip() == "```" else lines[1:])

            data = json.loads(json_text)
            headline = data.get("headline", "")
            summary_text = data.get("summary", "")
            key_points = data.get("key_points", [])

            # Ensure key_points is a list of strings
            if isinstance(key_points, list):
                key_points = [str(p) for p in key_points if p]
            else:
                key_points = []

        except (json.JSONDecodeError, KeyError, TypeError):
            # Fallback to legacy text parsing for backwards compatibility
            headline, summary_text, key_points = self._parse_legacy_response(text, title)

        # Enforce length limits
        headline = headline[:200] if headline else ""
        key_points = key_points[:5]

        # Fallback if parsing produced empty results
        if not summary_text:
            summary_text = self._strip_markdown(text)

        if not headline:
            sentences = text.split(".")
            if sentences:
                headline = self._strip_markdown(sentences[0]) + "."
            else:
                headline = self._strip_markdown(text[:150])

        return Summary(
            title=title,
            one_liner=headline,
            full_summary=summary_text,
            key_points=key_points,
            model_used=model,
            cached=False
        )

    def _strip_markdown(self, s: str) -> str:
        """Remove markdown formatting like **bold** and #headers."""
        s = s.strip()
        while s.startswith("#"):
            s = s[1:].strip()
        s = s.replace("**", "")
        return s.strip()

    def _parse_legacy_response(self, text: str, title: str = "") -> tuple[str, str, list[str]]:
        """
        Fallback parser for non-JSON responses (backwards compatibility).
        Returns (headline, summary_text, key_points).
        """
        headline = ""
        summary_text = ""
        key_points: list[str] = []

        def is_section_header(line: str, section: str) -> bool:
            cleaned = self._strip_markdown(line).lower()
            return cleaned == f"{section}:" or cleaned.startswith(f"{section}:")

        def extract_after_colon(line: str) -> str:
            if ":" in line:
                return self._strip_markdown(line.split(":", 1)[1])
            return ""

        lines = text.strip().split("\n")
        current_section: str | None = None
        current_content: list[str] = []

        for line in lines:
            line_stripped = line.strip()
            if not line_stripped:
                continue

            if line_stripped.startswith("#") and title and self._strip_markdown(line_stripped) == title:
                continue

            if is_section_header(line_stripped, "headline"):
                if current_section == "summary":
                    summary_text = "\n".join(current_content).strip()
                current_section = "headline"
                current_content = []
                rest = extract_after_colon(line_stripped)
                if rest:
                    current_content.append(rest)
            elif is_section_header(line_stripped, "summary"):
                if current_section == "headline":
                    headline = " ".join(current_content).strip()
                current_section = "summary"
                current_content = []
                rest = extract_after_colon(line_stripped)
                if rest:
                    current_content.append(rest)
            elif is_section_header(line_stripped, "url"):
                if current_section == "summary":
                    summary_text = "\n".join(current_content).strip()
                    current_content = []
                current_section = "url"
            elif is_section_header(line_stripped, "key points") or "key point" in self._strip_markdown(line_stripped).lower():
                if current_section == "summary":
                    summary_text = "\n".join(current_content).strip()
                elif current_section == "headline":
                    headline = " ".join(current_content).strip()
                current_section = "points"
                current_content = []
            elif current_section == "points":
                cleaned = self._strip_markdown(line_stripped)
                if cleaned.startswith(("•", "-", "·")):
                    point = cleaned.lstrip("•-·").strip()
                    if point:
                        key_points.append(point)
                elif cleaned and cleaned[0].isdigit():
                    point = cleaned.lstrip("0123456789.)").strip()
                    if point:
                        key_points.append(point)
            elif current_section == "url":
                pass
            elif current_section and line_stripped:
                current_content.append(self._strip_markdown(line_stripped))

        if current_section == "headline" and not headline:
            headline = " ".join(current_content).strip()
        elif current_section == "summary" and not summary_text:
            summary_text = "\n".join(current_content).strip()

        return headline, summary_text, key_points

    async def summarize_async(
        self,
        content: str,
        url: str,
        title: str = "",
        force_model: Model | None = None
    ) -> Summary:
        """
        Async version of summarize.

        Note: Wraps sync call in executor for now.
        """
        import asyncio
        loop = asyncio.get_event_loop()
        return await loop.run_in_executor(
            None,
            lambda: self.summarize(content, url, title, force_model)
        )


def create_summarizer(
    provider: LLMProvider,
    cache: "TieredCache | None" = None,
    critic_enabled: bool = True,
) -> Summarizer:
    """Factory function to create a Summarizer instance."""
    return Summarizer(provider=provider, cache=cache, critic_enabled=critic_enabled)


# Backwards compatibility: create summarizer from API key (uses Anthropic)
def create_summarizer_from_api_key(
    api_key: str,
    cache: "TieredCache | None" = None
) -> Summarizer:
    """
    Create a Summarizer using Anthropic provider (legacy API).

    Deprecated: Use create_summarizer(provider, cache) instead.
    """
    from .providers import AnthropicProvider
    provider = AnthropicProvider(api_key=api_key)
    return Summarizer(provider=provider, cache=cache)
