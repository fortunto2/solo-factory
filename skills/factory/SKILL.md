---
name: solo-factory
description: Use when "install solo factory", "set up solo", "install all solo skills", "startup toolkit", "solo factory setup", or first-time installation of the startup pipeline.
license: MIT
metadata:
  author: fortunto2
  version: "1.1.1"
  openclaw:
    emoji: "🏭"
allowed-tools: Bash, Read, Write, AskUserQuestion
argument-hint: "[--mcp] [--skills-only]"
---

# /factory

One-command setup for the entire Solo Factory startup toolkit.

## What gets installed

**23 skills** — full startup pipeline from idea to shipped product:

| Phase | Skills |
|-------|--------|
| Analysis | research, deep-research, validate, stream |
| Development | scaffold, setup, plan, build, deploy, review |
| Promotion | seo-audit, content-gen, community-outreach, video-promo, landing-gen, metrics-track |
| Utilities | init, audit, retro, pipeline, humanize, index-youtube, you2idea-extract |

**MCP server** (optional) — [solograph](https://github.com/fortunto2/solograph), one binary, provides 5 read tools:
- `kb_search` — full-text (BM25) search over the knowledge base
- `session_search` — search past Claude Code sessions
- `symbol_search` — definitions across every project
- `project_info` — the projects, one project's make-up, who uses a package
- `source_search` — indexed sources; `related` for videos sharing topics, no query for the sources and topics

When the knowledge base's `.solograph.yaml` has a `brain:` section it adds two: `brain_start`
(an orient page: the map of the memory plus today's state) and `capture` (an agent writes one
append-only note back: a decision, finding or handoff). Web search is a separate MCP server.

## Steps

1. **Parse arguments** from `$ARGUMENTS`:
   - `--mcp` — also configure solograph MCP server
   - `--skills-only` — skip MCP setup (default)
   - No args — install skills, ask about MCP

2. **Detect agent and choose install method:**

   ```bash
   # Check what's available
   command -v npx >/dev/null 2>&1 && echo "npx: ok"
   command -v clawhub >/dev/null 2>&1 && echo "clawhub: ok"
   ```

   **Method A (recommended): `npx skills`** — works with any AI agent, installs from GitHub directly.
   **Method B: `clawhub install`** — for OpenClaw users who prefer ClawHub registry.
   **Method C: Claude Code plugin** — if user is on Claude Code, suggest plugin instead.

3. **Install all 23 skills:**

   **Method A — npx skills (recommended, works immediately):**

   ```bash
   npx skills add fortunto2/solo-factory --all
   ```

   This single command installs all skills from GitHub to all detected agents (Claude Code, Cursor, Copilot, Gemini CLI, Codex, etc.). No account or publishing required.

   **Method B — clawhub (OpenClaw users):**

   ```bash
   # Check login
   clawhub whoami 2>/dev/null || echo "Run: clawhub login"

   # Install available skills
   for skill in \
     audit build community-outreach content-gen deploy \
     humanize index-youtube init landing-gen metrics-track \
     pipeline plan research retro review \
     scaffold seo-audit setup stream deep-research \
     validate video-promo you2idea-extract; do
     echo -n "Installing solo-$skill... "
     clawhub install "solo-$skill" 2>&1 | tail -1
     sleep 2
   done
   ```

   If some skills are not yet on ClawHub, fall back to Method A for those.

   **Method C — Claude Code plugin (all-in-one):**

   ```bash
   claude plugin marketplace add https://github.com/fortunto2/solo-factory
   claude plugin install solo@solo --scope user
   ```

   This installs all 23 skills + 3 agents + hooks + MCP auto-start in one command.

4. **MCP setup** (if `--mcp` or user agreed):

   Ask: "Set up solograph MCP for code intelligence and KB search?"

   **4a. Install the binary** (skip if `~/.solo/bin/solograph --version` works):
   ```bash
   curl -fL -o ~/.solo/bin/solograph --create-dirs \
     https://github.com/fortunto2/solograph/releases/latest/download/solograph-macos-arm64   # or solograph-linux-x86_64
   chmod +x ~/.solo/bin/solograph
   ```
   Or from source: `cargo install --git https://github.com/fortunto2/solograph solograph --root ~/.solo`.

   **4b. Configure MCP:**

   For OpenClaw (via mcporter):
   ```bash
   mcporter config add solograph --stdio "$HOME/.solo/bin/solograph"
   ```

   For Claude Code (via .mcp.json):
   ```json
   {
     "mcpServers": {
       "solograph": {
         "command": "/Users/<you>/.solo/bin/solograph"
       }
     }
   }
   ```

   **4c. Verify:**
   ```bash
   ~/.solo/bin/solograph --version
   ~/.solo/bin/solograph scan   # builds the project registry and the symbol index
   ```

5. **Report results:**

   ```
   ## Solo Factory Setup Complete

   **Install method:** npx skills / clawhub / Claude Code plugin
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

### npx skills: command not found
**Fix:** Install Node.js 18+. npx comes with npm.

### clawhub: some skills not found
**Cause:** Not all skills published to ClawHub yet.
**Fix:** Use `npx skills add fortunto2/solo-factory --all` instead.

### solograph: command not found (for MCP)
**Fix:** download the binary (step 4a) into `~/.solo/bin/`, or `cargo install` it from source.

### MCP tools not working
**Fix:** Test with `~/.solo/bin/solograph --version`. Check `.mcp.json` or mcporter config: the command must be the binary's absolute path.
