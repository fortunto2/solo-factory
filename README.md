# Solo Factory

Your own path. Multiple stacks. Ship everything.

You're a solopreneur juggling iOS, Next.js, Python, Kotlin — and you want to validate, scaffold, and ship them all without slowing down. Solo Factory gives you 9 skills, 3 agents, and a code intelligence MCP server that knows every project you've ever built.

From "shower thought" to deployed product in one pipeline:

```
/solo:research → /solo:validate → /solo:scaffold → /solo:setup → /solo:plan → /solo:build
```

## Install

### Option 1: Skills (any AI agent)

```bash
npx skills add fortunto2/solo-factory --all
```

Installs 9 skills for all detected agents (Claude Code, Cursor, Copilot, Gemini CLI, Codex, etc.).

### Option 2: Claude Code Plugin (skills + agents + MCP)

```bash
claude plugin marketplace add https://github.com/fortunto2/solo-factory
claude plugin install solo@solo --scope user
```

The plugin auto-starts [solograph](https://github.com/fortunto2/solograph) MCP server via `uvx` — 11 tools available instantly.

**Prerequisite:** [uv](https://docs.astral.sh/uv/) (for `uvx solograph`).

### Option 3: MCP only (no skills)

```bash
claude mcp add -s project solograph -- uvx solograph
```

Or add manually to `.mcp.json`:
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

### Verify

```bash
npx skills list              # skills.sh
claude plugin list            # Claude Code plugin
```

## Skills

| # | Command | What it does |
|---|---------|-------------|
| 1 | `/solo:research <idea>` | Scout the market — competitors, SEO, naming, domains, sizing |
| 2 | `/solo:validate <idea>` | Score + stack + PRD (go or kill in 5 min) |
| 3 | `/solo:scaffold <name> <stack>` | PRD to running project in 2 min |
| 4 | `/solo:setup [name]` | Wire dev workflow (0 questions) |
| 5 | `/solo:plan <description>` | Explore code, write battle plan |
| 6 | `/solo:build [track-id]` | Ship it — TDD, auto-commit, phase gates |
| - | `/solo:swarm <idea>` | 3 parallel research agents (market + users + tech) |
| - | `/solo:stream <decision>` | 6-layer decision filter |
| - | `/solo:audit [focus]` | KB health check — links, metadata, gaps |

## Agents

| Agent | Model | Specialization |
|-------|-------|----------------|
| `researcher` | Sonnet | Market research, competitors, pain points |
| `code-analyst` | Haiku | Codebase exploration, dependency analysis |
| `idea-validator` | Sonnet | Idea validation, scoring, PRD pipeline |

## Workflows

### Quick check (5 min)

```
/solo:validate "Parent dashboard for tracking kid's homework"
```

### Deep dive (15-20 min)

```
/solo:research "receipt scanning app"
/solo:validate "receipt scanning app"
```

### Swarm mode (10-15 min, 3 agents)

```
/solo:swarm "AI-powered habit tracker"
/solo:validate "AI-powered habit tracker"
```

### Full pipeline: idea to shipped product

```bash
/solo:research "my-app"              # Scout the market
/solo:validate "my-app"              # Score + generate PRD
/solo:scaffold my-app nextjs-supabase # Create project
/solo:setup                          # Wire dev workflow
/solo:plan "User auth with OAuth"    # Write battle plan
/solo:build                          # Ship it
```

## Available Stacks

| Stack | Tech |
|-------|------|
| `ios-swift` | SwiftUI, CoreML, StoreKit 2 |
| `nextjs-supabase` | Next.js 16, React 19, Tailwind 4, shadcn-ui, Supabase |
| `nextjs-ai-agents` | extends nextjs-supabase + Vercel AI SDK, MCP |
| `cloudflare-workers` | Hono, D1, R2, Durable Objects |
| `kotlin-android` | Jetpack Compose, Room, Koin |
| `astro-static` | Astro 5, Cloudflare Pages |
| `python-api` | FastAPI, Pydantic, SQLAlchemy, Alembic |
| `python-ml` | uv, Pydantic, FalkorDB, MLX |

## MCP Integration

Skills auto-detect and use [solograph](https://github.com/fortunto2/solograph) tools when available:

| Tool | What it does |
|------|-------------|
| `kb_search` | Semantic search over knowledge base (FalkorDB vectors, RU+EN) |
| `session_search` | Search past Claude Code sessions ("how did I solve X?") |
| `codegraph_query` | Cypher queries against code intelligence graph |
| `codegraph_stats` | Graph statistics (projects, files, symbols, packages) |
| `codegraph_explain` | Architecture overview of any project |
| `codegraph_shared` | Shared packages across projects |
| `project_code_search` | Semantic code search (auto-indexes on first call) |
| `project_code_reindex` | Reindex project code after changes |
| `project_info` | Project registry (stacks, status, last commit) |
| `web_search` | Web search via [SearXNG](https://github.com/fortunto2/searxng-docker-tavily-adapter) or [Tavily](https://tavily.com) |

Without MCP, skills fall back to Glob, Grep, Read, WebSearch/WebFetch.

### Web Search Setup (optional)

The `web_search` tool connects to any Tavily-compatible API:

**Self-hosted (recommended, private, free):**
```bash
git clone https://github.com/fortunto2/searxng-docker-tavily-adapter.git
cd searxng-docker-tavily-adapter && cp config.example.yaml config.yaml
docker compose up -d
# → localhost:8013 (API) + localhost:8999 (UI)
```

**Or Tavily cloud:** set `TAVILY_API_URL=https://api.tavily.com` and `TAVILY_API_KEY` in plugin env.

## Structure

```
solo-factory/
├── .claude-plugin/
│   ├── plugin.json          # Plugin manifest
│   └── marketplace.json     # Marketplace manifest
├── skills/
│   ├── research/            # Scout the market
│   ├── validate/            # Score → PRD
│   ├── scaffold/            # PRD → project
│   ├── setup/               # Wire dev workflow
│   ├── plan/                # Code research → battle plan
│   ├── build/               # TDD execution
│   ├── swarm/               # 3 parallel research agents
│   ├── stream/               # Decision framework
│   └── audit/               # KB health check
├── agents/
│   ├── researcher.md        # Deep research (sonnet)
│   ├── code-analyst.md      # Code intelligence (haiku)
│   └── idea-validator.md    # Idea validation (sonnet)
└── hooks/
    └── hooks.json           # SessionStart info
```

## Works well with

- [solograph](https://github.com/fortunto2/solograph) — MCP server for code intelligence, KB, sessions, web search
- [Agent Teams](https://github.com/anthropics/agents) — parallel feature dev, code review, debugging
- [Context7](https://github.com/upstash/context7) — latest library docs for scaffolding

## Manage

```bash
claude plugin update solo@solo       # Update
claude plugin disable solo@solo      # Disable
claude plugin enable solo@solo       # Re-enable
claude plugin uninstall solo@solo    # Uninstall
claude plugin marketplace remove solo # Remove marketplace
```

## License

MIT

## Author

Rustam Salavatov ([@fortunto2](https://github.com/fortunto2))
