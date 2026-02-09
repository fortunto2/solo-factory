---
name: solo-swarm
description: Launch 3 research agents in parallel — market, users, tech — fast answers
license: MIT
metadata:
  author: fortunto2
  version: "1.3.0"
allowed-tools: Read, Grep, Glob, Bash, WebSearch, WebFetch, Write, mcp__codegraph__web_search, mcp__codegraph__kb_search, mcp__codegraph__project_info, mcp__codegraph__codegraph_query
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
- Find app reviews and ratings
- Extract direct user quotes about frustrations
- Identify unmet needs and feature requests

### 3. Technical Analyst
Focus: feasibility, tech stack, existing solutions, implementation complexity.
- Search GitHub for open-source alternatives (`site:github.com <query>`)
- Evaluate tech stack options
- If MCP `project_info` available: check existing projects for reusable code
- If MCP `codegraph_query` available: find shared packages across projects
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
2. Write `research.md` to `3-opportunities/<project-name>/` (solopreneur KB) or `docs/` (any project)
3. Provide GO / NO-GO / PIVOT recommendation
4. Suggest next step: `/validate <idea>`
