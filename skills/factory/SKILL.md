---
name: solo-factory
description: Install the full Solo Factory toolkit — 23 startup skills + solograph MCP server for code intelligence, KB search, and web search. Use when user says "install solo factory", "set up solo", "install all solo skills", "startup toolkit", or "solo factory setup". This is the one-command entry point for the entire solopreneur pipeline.
license: MIT
metadata:
  author: fortunto2
  version: "1.0.0"
  openclaw:
    emoji: "🏭"
    requires:
      bins: ["clawhub"]
    install:
      - id: clawhub
        kind: node
        package: clawhub
        bins: ["clawhub"]
        label: "Install ClawHub CLI"
allowed-tools: Bash, Read, Write, AskUserQuestion
argument-hint: "[--mcp] [--skills-only]"
---

# /factory

One-command setup for the entire Solo Factory solopreneur toolkit.

## What gets installed

**23 skills** — full startup pipeline from idea to shipped product:

| Phase | Skills |
|-------|--------|
| Analysis | research, validate, stream, swarm |
| Development | scaffold, setup, plan, build, deploy, review |
| Promotion | seo-audit, content-gen, community-outreach, video-promo, landing-gen, metrics-track |
| Utilities | init, audit, retro, pipeline, humanize, index-youtube, you2idea-extract |

**MCP server** (optional) — [solograph](https://github.com/fortunto2/solograph) provides 11 tools:
- `kb_search` — semantic search over knowledge base
- `session_search` — search past Claude Code sessions
- `codegraph_query` / `codegraph_explain` / `codegraph_stats` — code intelligence
- `project_info` / `project_code_search` — project registry
- `web_search` — web search via SearXNG or Tavily

## Steps

1. **Parse arguments** from `$ARGUMENTS`:
   - `--mcp` — also configure solograph MCP server
   - `--skills-only` — skip MCP setup (default)
   - No args — install skills, ask about MCP

2. **Check prerequisites:**

   ```bash
   command -v clawhub >/dev/null 2>&1 && echo "clawhub: ok" || echo "clawhub: missing — run: npm i -g clawhub"
   ```

   If clawhub is missing, tell the user to install it: `npm i -g clawhub` or `pnpm add -g clawhub`.

   Check if logged in:
   ```bash
   clawhub whoami 2>/dev/null || echo "not logged in"
   ```
   If not logged in, tell the user: `clawhub login` (GitHub OAuth).

3. **Install all 23 skills from ClawHub:**

   Run the following bash command (installs all solo-* skills with 2s delay to avoid rate limits):

   ```bash
   for skill in \
     audit build community-outreach content-gen deploy \
     humanize index-youtube init landing-gen metrics-track \
     pipeline plan research retro review \
     scaffold seo-audit setup stream swarm \
     validate video-promo you2idea-extract; do
     echo -n "Installing solo-$skill... "
     clawhub install "solo-$skill" 2>&1 | tail -1
     sleep 2
   done
   ```

   If any skill fails (not yet published), note it and continue. Report summary at the end.

4. **MCP setup** (if `--mcp` or user agreed):

   Ask via AskUserQuestion: "Do you want to set up solograph MCP for code intelligence and KB search?" with options:
   - "Yes, configure MCP" — proceed to step 4a
   - "No, skills only" — skip to step 5

   **4a. Check uv/uvx:**
   ```bash
   command -v uvx >/dev/null 2>&1 && echo "uvx: ok" || echo "uvx: missing"
   ```
   If missing: "Install uv first: https://docs.astral.sh/uv/"

   **4b. Configure MCP via mcporter** (if mcporter available):
   ```bash
   mcporter config add solograph --stdio "uvx solograph"
   ```

   **4c. Or manual config** — write to the appropriate config file.

   For Claude Code, add to `.mcp.json` in the project root:
   ```json
   {
     "mcpServers": {
       "solograph": {
         "command": "uvx",
         "args": ["solograph"]
       }
     }
   }
   ```

   For OpenClaw, add to mcporter config:
   ```bash
   mcporter config add solograph --stdio "uvx solograph"
   ```

   **4d. Verify MCP:**
   ```bash
   uvx solograph --help
   ```

5. **Report results:**

   ```
   ## Solo Factory Setup Complete

   **Skills installed:** X/23
   **MCP configured:** yes/no
   **Failed:** [list any failures]

   ### Quick start

   Try these commands:
   - `/solo-research "your startup idea"` — scout the market
   - `/solo-validate "your startup idea"` — score + generate PRD
   - `/solo-stream "should I quit my job"` — decision framework

   ### Full pipeline

   research → validate → scaffold → setup → plan → build → deploy → review

   ### More info

   GitHub: https://github.com/fortunto2/solo-factory
   MCP: https://github.com/fortunto2/solograph
   ```

## Common Issues

### clawhub: command not found
**Fix:** `npm i -g clawhub` or `pnpm add -g clawhub`

### clawhub: not logged in
**Fix:** `clawhub login` (uses GitHub OAuth)

### Some skills not found on ClawHub
**Cause:** Not all skills published yet, or rate limit during batch publish.
**Fix:** Install from GitHub instead: `npx skills add fortunto2/solo-factory --all`

### uvx: command not found (for MCP)
**Fix:** Install uv: `curl -LsSf https://astral.sh/uv/install.sh | sh`

### MCP tools not working
**Cause:** solograph not installed or config wrong.
**Fix:** Test with `uvx solograph --help`. Check `.mcp.json` or mcporter config.
