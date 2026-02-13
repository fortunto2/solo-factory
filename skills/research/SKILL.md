---
name: solo-research
description: Deep market research — competitor analysis, user pain points, SEO/ASO keywords, naming/domain availability, and TAM/SAM/SOM sizing. Use when user says "research this idea", "find competitors", "check the market", "domain availability", "market size", or "analyze opportunity". Do NOT use for idea scoring (use /validate) or SEO auditing existing pages (use /seo-audit).
license: MIT
metadata:
  author: fortunto2
  version: "1.6.0"
allowed-tools: Read, Grep, Bash, Glob, Write, Edit, WebSearch, WebFetch, AskUserQuestion, mcp__solograph__kb_search, mcp__solograph__web_search, mcp__solograph__session_search, mcp__solograph__project_info
argument-hint: "[idea name or description]"
---

# /research

Deep research before PRD generation. Produces a structured `research.md` with competitive analysis, user pain points, SEO/ASO keywords, naming/domain options, and market sizing.

## MCP Tools (use if available)

If MCP tools are available, prefer them over CLI:
- `kb_search(query, n_results)` — search knowledge base for related docs
- `web_search(query, engines, include_raw_content)` — SearXNG web search with engine routing
- `session_search(query, project)` — find how similar research was done before
- `project_info(name)` — check project details

MCP `web_search` supports engine override: `engines="reddit"`, `engines="youtube"`, etc.
If MCP tools are not available, use Claude WebSearch/WebFetch as fallback.

## Search Strategy: Hybrid (SearXNG + Claude WebSearch)

Use **both** backends together. Each has strengths:

| Step | Best backend | Why |
|------|-------------|-----|
| **Competitors** | Claude WebSearch + `site:producthunt.com` + `site:g2.com` | Broad discovery + Product Hunt + B2B reviews |
| **Reddit / Pain points** | SearXNG `engines: reddit` (or MCP `web_search`) | PullPush API, selftext in content |
| **YouTube reviews** | SearXNG `engines: youtube` + `/transcript` | Video reviews (views = demand) |
| **Market size** | Claude WebSearch | Synthesizes numbers from 10 sources |
| **SEO / ASO** | Claude WebSearch | Broader coverage, trend data |
| **Page scraping** | SearXNG `include_raw_content` | Up to 5000 chars of page content |
| **Hacker News** | SearXNG `site:news.ycombinator.com` | Via Google (native HN engine broken) |
| **Funding / Companies** | SearXNG `site:crunchbase.com` | Competitor funding, team size |

### SearXNG Availability

If MCP `web_search` is available, use it (it wraps SearXNG).
Otherwise, check local availability:
```bash
curl -sf http://localhost:8013/health && echo "searxng_ok" || echo "searxng_down"
```
If unavailable — use Claude WebSearch for everything.

### SearXNG via curl (when MCP not available)

```bash
# General query
curl -s -X POST 'http://localhost:8013/search' \
  -H 'Content-Type: application/json' \
  -d '{"query": "<query>", "max_results": 10, "include_raw_content": true}'

# Force Reddit only
curl -s -X POST 'http://localhost:8013/search' \
  -H 'Content-Type: application/json' \
  -d '{"query": "<query>", "max_results": 10, "engines": "reddit", "include_raw_content": true}'

# YouTube transcript
curl -s -X POST 'http://localhost:8013/transcript' \
  -H 'Content-Type: application/json' \
  -d '{"video_id": "<VIDEO_ID_or_URL>", "max_length": 5000}'
```

## Steps

1. **Parse the idea** from `$ARGUMENTS`. If empty, ask the user what idea they want to research.

2. **Detect product type** — infer from the idea description:
   - Keywords like "app", "mobile", "iPhone", "Android" → mobile (ios/android)
   - Keywords like "website", "SaaS", "dashboard", "web app" → web
   - Keywords like "CLI", "terminal", "command line" → cli
   - Keywords like "API", "backend", "service" → api
   - Keywords like "extension", "plugin", "browser" → web (extension)
   - Default if unclear → web
   - Only ask via AskUserQuestion if truly ambiguous (e.g., "build a todo app" could be web or mobile)
   - This determines which research sections apply (ASO for mobile, SEO for web, etc.)

3. **Search knowledge base** for existing related content:
   - If MCP `kb_search` available: `kb_search(query="<idea keywords>", n_results=5)`
   - Otherwise: Grep for keywords in `.md` files
   - Check if `research.md` or `prd.md` already exist for this idea.

4. **Competitive analysis** — use Claude WebSearch (primary) + SearXNG (scraping):
   - `"<idea> competitors alternatives 2026"` — broad discovery
   - `"<idea> app review pricing"` — pricing data
   - SearXNG `include_raw_content=true`: scrape competitor URLs for detailed pricing
   - SearXNG/MCP `engines: reddit`: `"<idea> vs"` — user opinions
   - `"site:producthunt.com <idea>"` — Product Hunt launches
   - `"site:g2.com <idea>"` or `"site:capterra.com <idea>"` — B2B reviews
   - `"site:crunchbase.com <competitor>"` — funding, team size
   - For each competitor extract: name, URL, pricing, key features, weaknesses

5. **User pain points** — use SearXNG reddit (primary) + YouTube + Claude WebSearch:
   - SearXNG/MCP `engines: reddit`: `"<problem>"` — Reddit via PullPush API
   - SearXNG/MCP `engines: youtube`: `"<problem> review"` — video reviews
   - SearXNG `/transcript`: extract subtitles from top 2-3 YouTube videos
   - `"site:news.ycombinator.com <problem>"` — Hacker News opinions
   - Claude WebSearch: `"<problem> frustrating OR annoying"` — broader sweep
   - Synthesis: top 5 pain points with quotes and source URLs

6. **SEO / ASO analysis** (depends on product type from step 2):

   **For web apps:**
   - `"<competitor> SEO keywords ranking"` — competitor keywords
   - `"<problem domain> search volume trends 2026"` — demand signals
   - SearXNG `include_raw_content`: scrape competitor pages for meta tags
   - Result: keyword table (keyword, intent, competition, relevance)

   **For mobile apps:**
   - `"<category> App Store top apps keywords 2026"` — category landscape
   - `"site:reddit.com <competitor app> review"` — user complaints
   - Result: ASO keywords, competitor ratings, common complaints

7. **Naming, domains, and company registration:**
   - Generate 7-10 name candidates (mix of descriptive + invented/brandable)
   - Domain availability: triple verification (whois → dig → RDAP)
   - Trademark + company name conflict checks

   See `references/domain-check.md` for TLD priority tiers, bash scripts, gotchas, and trademark check methods.

8. **Market sizing** (TAM/SAM/SOM) — use Claude WebSearch (primary):
   - `"<market> market size 2025 2026 report"` — synthesizes numbers
   - `"<market> growth rate CAGR billion"` — growth projections
   - Extrapolation: TAM → SAM → SOM (Year 1)

9. **Write `research.md`** — write to `4-opportunities/<project-name>/research.md` if in solopreneur KB, otherwise to `docs/research.md` in the current project. Create the directory if needed.

10. **Output summary:**
    - Key findings (3-5 bullets)
    - Recommendation: GO / NO-GO / PIVOT with brief reasoning
    - Path to generated research.md
    - Suggested next step: `/validate <idea>`

## research.md Format

See `references/research-template.md` for the full output template (frontmatter, 6 sections, tables).

## Notes

- Always use kebab-case for project directory names
- If research.md already exists, ask before overwriting
- Run SearXNG and Claude WebSearch queries in parallel when independent

## Common Issues

### SearXNG not available
**Cause:** SSH tunnel not active or server down.
**Fix:** Run `make search-tunnel` in solopreneur. Skill automatically falls back to Claude WebSearch if SearXNG unavailable.

### Domain check returns wrong results
**Cause:** `.app`/`.dev` whois shows TLD creation date for unregistered domains.
**Fix:** Use the triple verification method (whois -> dig -> RDAP). Check Name Server and Registrar fields, not creation date.

### research.md already exists
**Cause:** Previous research run for this idea.
**Fix:** Skill asks before overwriting. Choose to merge new findings or start fresh.
