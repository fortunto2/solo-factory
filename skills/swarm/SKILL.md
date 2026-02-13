---
name: solo-swarm
description: Launch 3 parallel research agents (market, users, tech) to investigate an idea from multiple angles simultaneously. Use when user says "swarm research", "parallel research", "investigate fast", "3 agents", "team research", or wants faster alternative to /research. Produces research.md. Do NOT use for solo research (use /research) or idea scoring (use /validate).
license: MIT
metadata:
  author: fortunto2
  version: "1.5.0"
allowed-tools: Read, Grep, Glob, Bash, WebSearch, WebFetch, Write, mcp__solograph__web_search, mcp__solograph__kb_search, mcp__solograph__project_info, mcp__solograph__codegraph_query, mcp__solograph__codegraph_explain, mcp__solograph__project_code_search, mcp__solograph__session_search
argument-hint: "[idea name or description]"
---

# /swarm

Create an agent team to research "$ARGUMENTS" from multiple perspectives in parallel.

## Team Structure

Spawn 3 teammates, each with a distinct research focus:

### 1. Market Researcher
Focus: competitors, market size, pricing models, business models.
- Search for direct and indirect competitors
- Find market reports with TAM/SAM/SOM figures
- Analyze pricing strategies and monetization
- Identify market gaps and opportunities
- Check Product Hunt, G2, Capterra for existing products

### 2. User Researcher
Focus: pain points, user sentiment, feature requests.
- Search Reddit (via SearXNG `engines: reddit`, MCP `web_search`, or WebSearch `site:reddit.com`)
- Search Hacker News for tech community opinions (`site:news.ycombinator.com`)
- If MCP `session_search` available: check if this idea was researched before in past sessions
- Find app reviews and ratings
- Extract direct user quotes about frustrations
- Identify unmet needs and feature requests

### 3. Technical Analyst
Focus: feasibility, tech stack, existing solutions, implementation complexity.
- Search GitHub for open-source alternatives (`site:github.com <query>`)
- Evaluate tech stack options
- If MCP `project_info` available: check existing projects for reusable code
- If MCP `codegraph_explain` available: get architecture overview of similar projects in portfolio
- If MCP `codegraph_query` available: find shared packages across projects
- If MCP `project_code_search` available: search for reusable patterns, services, infrastructure across projects
- Assess implementation complexity and timeline

## Search Backends

Teammates should use both:
- **MCP `web_search`** (if available) — wraps SearXNG with engine routing
- **WebSearch** (built-in) — broad discovery, market reports
- **WebFetch** — scrape specific URLs for details

**Domain filtering:** use `site:github.com`, `site:reddit.com` etc. for strict filtering.

Check SearXNG availability if not using MCP:
```bash
curl -sf http://localhost:8013/health && echo "searxng_ok" || echo "searxng_down"
```

## Coordination

- Each teammate writes findings to a shared task list
- Require plan approval before teammates start deep research
- After all complete, synthesize findings into `research.md`
- Use the research.md format from `/research` skill

## Output

After team completes, the lead should:
1. Synthesize findings from all 3 teammates
2. Write `research.md` to `4-opportunities/<project-name>/` (solopreneur KB) or `docs/` (any project)
3. Provide GO / NO-GO / PIVOT recommendation
4. Suggest next step: `/validate <idea>`

## Common Issues

### Agent team not available
**Cause:** `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` env var not set.
**Fix:** Ensure `.claude/settings.json` has `"env": {"CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"}`.

### Teammates produce overlapping findings
**Cause:** Research areas not clearly separated.
**Fix:** Each teammate has a distinct focus (market/users/tech). The lead synthesizes and deduplicates findings.

### SearXNG not available for teammates
**Cause:** SSH tunnel not active.
**Fix:** Run `make search-tunnel` before starting swarm. Teammates fall back to WebSearch if SearXNG unavailable.
