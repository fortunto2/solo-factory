---
name: solo-reddit
description: Use when "reddit comment", "engage reddit", "build karma", "post to reddit", or need to participate in Reddit threads. NOT for thread discovery (/community-outreach) or social copy (/content-gen).
license: MIT
metadata:
  author: fortunto2
  version: "1.0.0"
  openclaw:
    emoji: "🤖"
allowed-tools: Read, Grep, Glob, Write, Edit, Bash, AskUserQuestion, WebSearch, WebFetch, mcp__solograph__web_search, mcp__solograph__kb_search, mcp__solograph__project_info, mcp__playwright__browser_navigate, mcp__playwright__browser_snapshot, mcp__playwright__browser_click, mcp__playwright__browser_type, mcp__playwright__browser_wait_for, mcp__playwright__browser_tabs
argument-hint: "<command> [subreddit] — commands: comment, post, find, status, setup"
---

# /reddit

Reddit engagement automation — from finding relevant posts to writing authentic comments and tracking results. Comment-first strategy: build karma and reputation before any self-promotion.

## Philosophy

- **Value first, product never** (in comments) — genuinely help, mention product only when directly asked
- **Comment-first** — 30+ comments before any self-promotional post
- **Read before write** — analyze post, existing comments, subreddit culture before drafting
- **Track everything** — karma growth, engagement rates, what works

## Routing

| User says | Action |
|-----------|--------|
| `/reddit setup <project>` | Go to **Setup** section |
| `/reddit find [subreddit]` | Go to **Find Posts** section |
| `/reddit comment [url]` | Go to **Comment** section |
| `/reddit post <subreddit>` | Go to **Write Post** section |
| `/reddit status` | Go to **Status** section |
| `/reddit batch [subreddit]` | Go to **Batch Mode** — find + comment x3 |

## MCP Tools

### Playwright (required for posting)
- `browser_navigate(url)` — go to Reddit page
- `browser_snapshot()` — read page structure (accessibility tree, NOT screenshots)
- `browser_click(ref)` — click elements
- `browser_type(ref, text)` — type text
- `browser_wait_for(state)` — wait for page load

### SoloGraph (optional, for search)
- `web_search(query)` — search Reddit threads
- `kb_search(query)` — find project context
- `project_info(name)` — get project details

If MCP tools not available, use WebSearch/WebFetch as fallback.

### Scripts (no MCP needed)
- `scripts/check-karma.sh <username>` — check karma, account age, posting readiness
- `scripts/search-posts.sh <subreddit> [query] [sort]` — find posts via Reddit JSON API
- `scripts/check-post.sh <url>` — read post content + top comments

Use scripts first (faster, no Playwright needed). Fall back to Playwright for posting.

## Setup

First-time setup for a project. Creates profile and tracking files.

1. **Parse project** from `$ARGUMENTS` or ask user.
2. **Read PRD/README** to extract: problem, solution, ICP, key features, competitor names.
3. **Identify target subreddits** — search for where ICP hangs out:
   - Language/framework subs (r/rust, r/python, r/javascript)
   - Domain subs (r/selfhosted, r/devops, r/ClaudeAI)
   - General tech (r/programming, r/webdev)
4. **Research each subreddit:**
   - Read sidebar rules (via WebFetch or Playwright)
   - Check self-promotion policy
   - Note posting format, flairs, weekly threads
   - Find top posts to understand culture
5. **Write profile** to `docs/reddit/profile.md`:

```markdown
# Reddit Profile: {Project Name}

**Product:** {one-line}
**ICP:** {target persona}
**Value prop for Reddit:** {what genuine help can we offer}

## Target Subreddits

| Subreddit | Members | Self-promo | Culture | Best content type |
|-----------|---------|------------|---------|-------------------|
| r/xxx | NNNk | rules... | tone... | type... |

## Search Keywords
- Problem: {what users complain about}
- Solution: {what users search for}
- Competitors: {names for "vs" and "alternative" threads}

## Voice Guide
- Tone: {casual/technical/friendly}
- Never say: {banned phrases — "game-changer", "revolutionary", etc.}
- Always: {disclose affiliation, lead with value}
```

6. **Create tracking file** `docs/reddit/tracking.md`:

```markdown
# Reddit Tracking

## Stats
- Account: {username}
- Starting karma: {N}
- Comments posted: 0
- Posts made: 0

## Activity Log
<!-- entries added by /reddit comment and /reddit post -->
```

## Find Posts

Find posts worth commenting on in a subreddit.

1. **Load profile** from `docs/reddit/profile.md`.
2. **Search** for relevant threads:
   - Via WebSearch: `"{keyword}" site:reddit.com/r/{subreddit}` for each keyword group
   - Or via Playwright: navigate to `reddit.com/r/{subreddit}/new/` and `reddit.com/r/{subreddit}/rising/`
3. **Filter posts:**
   - Less than 7 days old (prefer < 24h for visibility)
   - 2-30 comments (active but not buried)
   - Matches problem/solution/competitor keywords
   - NOT already commented on (check tracking)
4. **Score and rank** top 5 posts by:
   - Relevance to our expertise (high)
   - Comment count sweet spot (medium = best)
   - Recency (newer = better)
   - Can we genuinely help? (must be yes)
5. **Output** ranked list with URLs, titles, why each is good.

## Comment

Write and optionally post a comment on a specific Reddit post.

### Step 1: Load Context
- Read `docs/reddit/profile.md` for voice guide
- Read `docs/reddit/tracking.md` to check we haven't commented on this post
- Read `references/style-guide.md` for comment patterns

### Step 2: Deep Analysis
Navigate to the post URL (via Playwright or WebFetch):
- **Read the full post** — understand what OP actually asks
- **Read existing comments** — understand tone, what's been said, gaps
- **Identify OP's intent:** asking for help? sharing experience? seeking opinions?
- **Decide angle:** what unique value can we add that others haven't?

### Step 3: Draft Comment
Write a comment following these rules:
- **Match subreddit tone** — casual for r/ClaudeAI, technical for r/rust
- **Lead with value** — first 2-3 sentences directly address OP's question
- **Be specific** — code snippets, numbers, concrete steps > vague advice
- **1-2 focused points** — don't try to cover everything
- **No product mention** unless directly relevant AND we have 10+ comments in this sub
- **If mentioning product:** last paragraph, with "I work on X" disclosure

### Step 4: Anti-Spam Review
Check the draft against `references/spam-signals.md`:
- [ ] No marketing language ("game-changer", "revolutionary", "10x")
- [ ] No link in first comment on a subreddit
- [ ] Not a copy of any previous comment
- [ ] Directly addresses OP's question (not tangential)
- [ ] Would be useful even if product didn't exist
- [ ] Reads like a human, not a press release
- [ ] No emoji overuse (0-1 max)

If any check fails: rewrite.

### Step 5: Post (if Playwright available and user approves)
1. `browser_navigate(post_url)`
2. `browser_snapshot()` — find comment input
3. `browser_click(comment_box_ref)`
4. `browser_type(comment_box_ref, comment_text)`
5. `browser_click(submit_button_ref)`
6. `browser_snapshot()` — verify posted, get permalink

If Playwright not available: copy comment to clipboard via `pbcopy`.

### Step 6: Track
Update `docs/reddit/tracking.md`:
```markdown
### {YYYY-MM-DD HH:MM} r/{subreddit}
- **Post:** [{title}]({url})
- **Comment:** [{permalink}]({comment_url})
- **Angle:** {what value we provided}
- **Product mentioned:** yes/no
```

## Write Post

Create a Reddit post for a specific subreddit.

1. **Pre-flight checks:**
   - Do we have 10+ tracked comments in this subreddit? If no: STOP, comment more first.
   - Check subreddit rules for post format, flairs, allowed content types.
   - Check if showcase/self-promo threads exist (e.g., "Showoff Saturday").

2. **Determine post type:**
   | Type | When to use |
   |------|-------------|
   | Experience sharing | We solved a hard problem — share the story |
   | Technical deep-dive | Interesting approach worth discussing |
   | Tool announcement | Only in subs that allow it, with heavy context |
   | Question/discussion | Genuine question that sparks conversation |

3. **Draft post:**
   - Title: specific, accurate, matches sub format (check top posts)
   - Body: value-first structure from `references/post-templates.md`
   - Links: max 1-2, put extras in first comment
   - Flair: match subreddit requirements

4. **Review against rules:**
   - 90/10 rule: 90% value, 10% promotional
   - No clickbait titles
   - Follows subreddit-specific format
   - Would you upvote this if it wasn't yours?

5. **Post** via Playwright or copy to clipboard.

6. **After posting:**
   - Monitor comments for 2 hours
   - Reply to every comment (boosts ranking)
   - Track in `docs/reddit/tracking.md`

## Batch Mode

Efficient mode: find 3 posts + write 3 comments in one session.

1. Load profile and tracking.
2. Run `scripts/check-karma.sh` to verify account status.
3. Run `scripts/search-posts.sh` for target subreddit.
4. For top 3 candidates, run **Comment** flow sequentially.
5. Wait 5-10 minutes between comments (rate limiting).
6. Write structured summary to `docs/reddit/batch-{date}.json`:

```json
{
  "date": "2026-03-25",
  "subreddit": "r/ClaudeAI",
  "comments_posted": 3,
  "posts": [
    {"url": "...", "title": "...", "angle": "...", "product_mentioned": false}
  ],
  "karma_before": 37,
  "karma_after": null
}
```

7. Print human summary: 3 comments posted, links, karma status.

## Status

Show current Reddit engagement stats.

1. Read `docs/reddit/tracking.md`.
2. Count: total comments, comments per subreddit, posts made.
3. Calculate: comments since last promotional post (10:1 ratio check).
4. Show readiness: "Ready to post in r/X" or "Need N more comments in r/X".

## Critical Rules

1. **Never post without reading the full thread** — context is everything
2. **Never mention product in first 10 comments** in any subreddit
3. **Never post same content to multiple subreddits** — customize each
4. **Never argue with moderators** — accept removal gracefully
5. **Always disclose affiliation** when mentioning your product
6. **Minimum 5 minute gap** between comments (avoid rate limiting)
7. **No vote manipulation** — never ask for upvotes anywhere
8. **Use `browser_snapshot` not `browser_take_screenshot`** — saves tokens
9. **Navigate by URL** (`browser_navigate`) not clicking links — prevents errors

## Gotchas

1. **Reddit spam filter on low-karma accounts** — new or inactive accounts get auto-filtered. Build 50+ karma with genuine comments before any self-promo posts. If filtered: message mods via modmail (sidebar link), don't repost.
2. **Links trigger spam filter** — first comment with a link in a new subreddit often gets caught. Post text-only comments first, add links only after established.
3. **Subreddit AI content rules** — r/rust and others may remove posts with AI-generated content. Be transparent about AI-assisted development but ensure comments are genuinely human-directed.
4. **Rate limiting** — Reddit throttles new/low-karma accounts. If you see "you're doing that too much", wait 10 minutes. Don't retry immediately.
5. **Old Reddit vs New Reddit** — `old.reddit.com` has better search. Use `new.reddit.com` for posting (Playwright works better with new UI).
6. **Playwright login state** — Reddit login persists in browser session. If logged out: user must log in manually (`browser_navigate("https://www.reddit.com/login")`), skill can't enter credentials.

## Notes

- This skill complements `/community-outreach` (which finds threads) and `/content-gen` (which generates post copy). Use `/reddit` for the actual engagement loop.
- For Reddit Ads, see the `reddit-ads` skill from kostja94/marketing-skills.
- Karma builds compound: each good comment makes the next one more visible.
