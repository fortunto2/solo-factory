[![GitHub stars](https://img.shields.io/github/stars/fortunto2/solo-factory?style=flat-square)](https://github.com/fortunto2/solo-factory/stargazers)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=flat-square)](LICENSE)
[![Skills: 44](https://img.shields.io/badge/skills-44-blue?style=flat-square)](#skills)
[![Agents: 3](https://img.shields.io/badge/agents-3-green?style=flat-square)](#agents)
[![MCP Tools: 11](https://img.shields.io/badge/MCP_tools-11-purple?style=flat-square)](#mcp-integration)
[![Stacks: 9](https://img.shields.io/badge/stacks-9-orange?style=flat-square)](#available-stacks)

# Solo Factory

**Your own path. Multiple stacks. Ship everything.**

> From shower thought to deployed product — 44 skills, 3 agents, and a code intelligence MCP server that knows every project you've ever built.

```
/solo:research → /solo:validate → /solo:scaffold → /solo:setup → /solo:plan → /solo:build → /solo:deploy → /solo:launch → /solo:review
```

## Why?

You're a solopreneur juggling iOS, Next.js, Python, Kotlin — and you want to validate, scaffold, and ship them all without slowing down.

Most AI coding tools help you write code. Solo Factory helps you **run a startup** — from market research and idea validation to deployment and promotion. Every skill is designed for one-person teams moving fast across multiple projects and stacks.

- **No context switching** — one pipeline handles research, coding, deployment, and marketing
- **Stack-agnostic** — 9 templates from SwiftUI to Cloudflare Workers
- **Code intelligence** — MCP server indexes all your projects, searches past sessions, and provides semantic code search
- **Works without MCP** — skills gracefully fall back to Glob, Grep, Read, WebSearch

## Install

### Option 1: Skills (any AI agent)

```bash
npx skills add fortunto2/solo-factory --all
```

Works with Claude Code, Cursor, Copilot, Gemini CLI, Codex, and more.

### Option 2: Claude Code Plugin (skills + agents + MCP)

```bash
claude plugin marketplace add https://github.com/fortunto2/solo-factory
claude plugin install solo@solo --scope user
```

The plugin auto-starts [solograph](https://github.com/fortunto2/solograph) MCP server via `uvx` — 11 tools available instantly.

**Prerequisite:** [uv](https://docs.astral.sh/uv/) (for `uvx solograph`).

### Option 3: OpenClaw (ClawHub)

```bash
clawhub install solo-research       # Install one skill
clawhub search "solo"               # Browse all solo-* skills
```

### Option 4: MCP only (no skills)

```bash
claude mcp add -s project solograph -- uvx solograph
```

### Verify

```bash
npx skills list              # skills.sh
claude plugin list            # Claude Code plugin
```

## Skills

### Analysis (4 skills)

| Command | What it does |
|---------|-------------|
| `/solo:research <idea>` | Scout the market — competitors, SEO keywords, domains, TAM/SAM/SOM |
| `/solo:swarm <idea>` | 3 parallel research agents (market + users + tech) for faster deep dive |
| `/solo:validate <idea>` | S.E.E.D. niche check + STREAM scoring + Devil's Advocate → PRD |
| `/solo:domain <name>` | Is the name actually free — RDAP/whois, App Store, Google Play, GitHub, trademarks |

**Examples:**
```
/solo:research "receipt scanning app for freelancers"
→ 12 competitors, 3 niches, 2 personas, JTBD interview script, domain available, TAM $2.1B

/solo:validate "AI habit tracker"
→ Score: 7.2/10, Stack: ios-swift, beachhead: fitness enthusiasts 25-35
→ Pricing: one-time $9.99 (no server costs), PRD with 14 acceptance criteria
```

### Development (8 skills)

| Command | What it does |
|---------|-------------|
| `/solo:scaffold <name> <stack>` | PRD → running project with configs, CLAUDE.md, git repo, GitHub push |
| `/solo:setup` | Wire dev workflow (TDD, linting, CI) — zero questions asked |
| `/solo:plan <feature>` | Explore codebase, write spec + phased plan with file-level tasks |
| `/solo:build [track-id]` | Execute plan with TDD, auto-commit, and phase gates |
| `/solo:deploy [platform]` | Deploy — detect CLI tools, set up DB, push, verify live |
| `/solo:review [focus]` | Final quality gate — tests, coverage, security, acceptance criteria |
| `/solo:diagnose <bug>` | Hard-bug loop — build a red-capable feedback loop first, hypothesise second |
| `/solo:grill <plan>` | Relentless one-question-at-a-time interview to stress-test a plan before building |

**Examples:**
```
/solo:scaffold my-app nextjs-supabase
→ Project created, GitHub repo pushed, CLAUDE.md configured

/solo:plan "Add Stripe subscription billing"
→ 3-phase plan: schema → API routes → checkout UI, 12 tasks total

/solo:build
→ TDD loop: write test → implement → green → commit, phase by phase
```

### Mobile & Apple (7 skills)

| Command | What it does |
|---------|-------------|
| `/solo:ios-dev` | Build the iPhone app — SwiftUI or KMP hybrid, Claude Code ↔ Xcode workflow, device builds |
| `/solo:ios-release` | TestFlight and App Store via the `asc` CLI — upload, submit, attribution links |
| `/solo:android-release` | Play Console via CLI — internal/open testing, AAB upload, staged rollout |
| `/solo:apple-app-icon` | iOS 26+ layered `.icon` generated from an SVG by script, every appearance checked |
| `/solo:swiftui-design-system` | 12-column grid, spacing/type/motion scales, a codemod that migrates literals |
| `/solo:i18n` | One language → many, and keeping it there: RTL, plurals, spoken numbers, store listings |
| `/solo:model-shrink` | Trained model → device: ONNX, int8, Core ML, on-device benchmark, download-on-demand |

**Apple ships its own agent skills inside Xcode 27** — SwiftUI invalidation, `ForEach` identity,
`@Observable`, App Intents, Liquid Glass, String Catalogs — in the same `SKILL.md` + `references/`
format, and their header says they supersede anything a model learned elsewhere. Export them into
`~/.agents/skills` so any agent can read them with no Xcode running:

```bash
make apple-skills-check    # what an export would bring, writes nothing
make apple-skills          # export
```

What is in the set, and the rules that most often hit real code:
[`skills/swiftui-design-system/references/apple-xcode-skills.md`](skills/swiftui-design-system/references/apple-xcode-skills.md).

### Promotion (12 skills)

| Command | What it does |
|---------|-------------|
| `/solo:launch` | GTM launch strategy — beachhead, channels, pricing, timeline, growth loops |
| `/solo:customer-finder` | Evidence-backed shortlist of first customers from public signals + outreach openers |
| `/solo:seo-audit <url>` | SEO health check — meta tags, JSON-LD, sitemap, score 0-100 |
| `/solo:landing-gen` | Landing page content — hero, features, A/B headlines, CTA, SEO meta |
| `/solo:content-gen` | Social media pack — LinkedIn post, Reddit draft, Twitter/X thread + release notes |
| `/solo:community-outreach` | Find Reddit/HN/PH threads, draft value-first responses + launch checklist |
| `/solo:video-promo` | Promo video plan — 30-45s script, storyboard, Remotion config |
| `/solo:metrics-track` | PostHog event funnel, KPI benchmarks, A/B test template, kill/iterate/scale |
| `/solo:legal` | Privacy policy + terms of service — privacy-first, manifest-aligned |
| `/solo:seo-cli` | Run the `seo` CLI — SEO+GEO score, agent-audit (can an AI agent read the site?), reindex |
| `/solo:reddit` | Write and post Reddit comments that carry value, build karma without burning the account |
| `/solo:github-outreach` | Scan a competitor library's dependents, reach the repos that would switch |

**Examples:**
```
/solo:launch
→ Beachhead: freelance designers 25-35, Channel: r/freelance + ProductHunt, Pricing: one-time $29

/solo:content-gen
→ LinkedIn post + Reddit answer + Twitter thread + release notes from git history

/solo:legal
→ Privacy policy (GDPR-ready), Terms of Service, App Store privacy labels
```

### Utility (14 skills)

| Command | What it does |
|---------|-------------|
| `/solo:pipeline research <idea>` | Automated research → validate loop |
| `/solo:pipeline dev <name> <stack>` | Automated scaffold → setup → plan → build → deploy → review |
| `/solo:stream <decision>` | STREAM 6-layer decision framework for high-stakes choices |
| `/solo:init` | One-time founder onboarding — manifest, calibration, stack selection |
| `/solo:factory` | Install the full Solo Factory toolkit in one command |
| `/solo:retro` | Post-pipeline retrospective — score process, find waste, suggest fixes |
| `/solo:audit` | KB health check — broken links, frontmatter, tag inconsistencies |
| `/solo:memory-audit` | Claude Code memory hierarchy — loaded files, char counts, optimization hints |
| `/solo:humanize` | Strip AI writing patterns — em dashes, stock phrases, performed authenticity |
| `/solo:index-youtube` | Index YouTube channel transcripts for semantic search |
| `/solo:you2idea-extract` | Extract startup ideas from YouTube video transcripts |
| `/solo:knowledge` | Answer from the methodology base — harness engineering, SGR, launch playbook |
| `/solo:sgr` | Design schema-guided reasoning — schemas, tool dispatch, constrained decoding |
| `/solo:skill-audit` | Score a skill against the best-practice checklist, 12 dimensions |
| `/solo:terminal-eyes` | Terminal tuned for hours of reading agent output — flicker, polarity, ANSI palette, bell. Lives in [its own repo](https://github.com/fortunto2/terminal-eyes) (submodule) |

**Examples:**
```
/solo:pipeline dev "my-app" "nextjs-supabase"
→ Hands-free: scaffold → setup → plan → build → deploy → review

/solo:humanize
→ Rewrites AI-sounding copy into natural, human text
```

## Agents

| Agent | Model | Specialization |
|-------|-------|----------------|
| `researcher` | Sonnet | Market research, competitors, pain points, web + KB search |
| `code-analyst` | Haiku | Codebase exploration, dependency analysis, Cypher queries |
| `idea-validator` | Sonnet | Idea validation, STREAM scoring, PRD generation |

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

### Swarm mode (10-15 min, 3 parallel agents)

```
/solo:swarm "AI-powered habit tracker"
/solo:validate "AI-powered habit tracker"
```

### Automated pipeline (hands-free)

```bash
# Research pipeline — research → validate, fully automated
/solo:pipeline research "AI therapist app"

# Dev pipeline — scaffold → setup → plan → build → deploy → review
/solo:pipeline dev "my-app" "nextjs-supabase"
/solo:pipeline dev "my-app" "ios-swift" --feature "user onboarding"
```

**Pipeline signals** — 2 universal tags, bash owns all state:
- `<solo:done/>` — stage complete (bash creates marker in `.solo/states/`)
- `<solo:redo/>` — go back to build (bash removes `.solo/states/build`)

**Stage markers** live in `{project}/.solo/states/` (build, deploy, review). Reset: `rm -rf .solo/states/`

**Per-iteration logs:**
```
~/.solo/pipelines/{project}/
├── iter-001-scaffold.log
├── iter-002-setup.log
├── iter-003-plan.log
├── iter-004-build.log
└── progress.md             # Injected into next iteration prompt
```

**Two pipeline modes:**

| Mode | Launch | Best for |
|------|--------|----------|
| **Interactive** | `/pipeline dev ...` in Claude Code | Quick runs, single session |
| **Big Head** | `make bighead-dev` or `solo-dev.sh` | Long pipelines, tmux dashboard, logs |

### Manual pipeline: idea to shipped product

```bash
/solo:research "my-app"              # Scout the market
/solo:validate "my-app"              # Score + generate PRD
/solo:scaffold my-app nextjs-supabase # Create project
/solo:setup                          # Wire dev workflow
/solo:plan "User auth with OAuth"    # Write battle plan
/solo:build                          # Ship it
/solo:deploy                         # Deploy to Vercel/CF/Fly
/solo:review                         # Final quality gate
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
| `astro-hybrid` | Astro 5 SSG+SSR, Cloudflare Pages/Workers, R2 CDN, Orama |
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
| `web_fetch` | Fetch a URL with browser-like headers, tags stripped |

Web search lives on its own MCP server, `searxng`, so it stays up when the graph does
not and needs no FalkorDB:

| Tool | Purpose |
|------|---------|
| `web_search` | Web search via [SearXNG](https://github.com/fortunto2/searxng-docker-tavily-adapter) or [Tavily](https://tavily.com) |
| `web_extract` | One page as markdown: negotiated from the site when it serves markdown, otherwise extracted with trafilatura. Size presets + pagination |
| `youtube_transcript` | Video captions as text |

Without MCP, skills fall back to Glob, Grep, Read, WebSearch/WebFetch.

### Web Search Setup (optional)

The `web_search` tool connects to any Tavily-compatible API:

**Self-hosted (recommended, private, free):**
```bash
git clone https://github.com/fortunto2/searxng-docker-tavily-adapter.git
cd searxng-docker-tavily-adapter && cp config.example.yaml config.yaml
# set server.secret_key: openssl rand -hex 32
docker compose up -d
# → localhost:8013 (API) + localhost:8999 (UI)
```

Run it on a machine with a residential IP. Search engines CAPTCHA-wall datacenter
address ranges, so on a VPS or a cloud container most engines get blocked within a
few queries and no header tuning fixes it.

`web_extract` needs the self-hosted adapter — it maps to `POST /extract`, which
Tavily cloud does not have. `web_search` works against either.

Register the search server as `searxng` (tools resolve as `mcp__searxng__web_search`):

```json
{"mcpServers": {"searxng": {
  "command": "uv",
  "args": ["run", "--project", "/path/to/searxng-docker-tavily-adapter/searxng_mcp", "searxng-mcp"],
  "env": {"TAVILY_API_URL": "http://localhost:8013"}
}}}
```

**Or Tavily cloud:** set `TAVILY_API_URL=https://api.tavily.com` and `TAVILY_API_KEY` in plugin env.

## Structure

```
solo-factory/
├── .claude-plugin/
│   ├── plugin.json          # Plugin manifest
│   └── marketplace.json     # Marketplace manifest
├── skills/                  # 44 skills
│   ├── research/            # Scout the market
│   ├── validate/            # Score → PRD
│   ├── scaffold/            # PRD → project
│   ├── setup/               # Wire dev workflow
│   ├── plan/                # Code research → battle plan
│   ├── build/               # TDD execution
│   ├── deploy/              # Deploy to hosting
│   ├── review/              # Final quality gate
│   ├── swarm/               # 3 parallel research agents
│   ├── stream/              # Decision framework
│   ├── pipeline/            # Automated multi-skill loop
│   ├── seo-audit/           # SEO health check
│   ├── landing-gen/         # Landing page content
│   ├── content-gen/         # Social media pack
│   ├── community-outreach/  # Reddit/HN/PH outreach
│   ├── customer-finder/     # First-customer prospecting
│   ├── video-promo/         # Promo video plan
│   ├── metrics-track/       # PostHog metrics
│   ├── humanize/            # Strip AI patterns
│   ├── audit/               # KB health check
│   ├── memory-audit/        # Memory hierarchy audit
│   ├── init/                # Founder onboarding
│   ├── factory/             # Full toolkit install
│   ├── retro/               # Pipeline retrospective
│   ├── launch/              # GTM launch strategy
│   ├── legal/               # Privacy policy + terms
│   ├── index-youtube/       # YouTube transcript indexing
│   ├── you2idea-extract/    # Ideas from YouTube
│   ├── diagnose/            # Hard-bug feedback loop
│   ├── grill/               # One-question-at-a-time plan interview
│   ├── domain/              # Name availability across registries + stores
│   ├── ios-dev/             # SwiftUI / KMP iPhone development
│   ├── ios-release/         # TestFlight + App Store via asc CLI
│   ├── android-release/     # Play Console releases
│   ├── apple-app-icon/      # Layered .icon from SVG
│   ├── swiftui-design-system/ # Grid, scales, codemod
│   ├── i18n/                # Localization, RTL, store listings
│   ├── model-shrink/        # ONNX / int8 / Core ML on device
│   ├── seo-cli/             # seo CLI: SEO+GEO + agent-audit
│   ├── reddit/              # Reddit comments and karma
│   ├── github-outreach/     # Competitor dependents scan
│   ├── knowledge/           # Methodology base lookup
│   ├── terminal-eyes/       # submodule → fortunto2/terminal-eyes (+ Lumen menu bar app)
│   ├── sgr/                 # Schema-guided reasoning
│   └── skill-audit/         # Score a skill against the checklist
├── agents/
│   ├── researcher.md        # Deep research (sonnet)
│   ├── code-analyst.md      # Code intelligence (haiku)
│   └── idea-validator.md    # Idea validation (sonnet)
├── commands/
│   ├── dev.md               # End-to-end feature development
│   └── investigate.md       # Bug investigation and fix
├── hooks/
│   ├── hooks.json           # SessionStart + Stop hook
│   └── pipeline-stop.sh     # Pipeline progression
├── scripts/
│   ├── bighead              # Interactive pipeline launcher (Rich CLI)
│   ├── solo-dev.sh          # Dev pipeline bash loop
│   ├── solo-research.sh     # Research pipeline bash loop
│   ├── solo-dashboard.sh    # tmux dashboard manager
│   ├── solo-stream-fmt.py   # Colored stream formatter
│   └── sync-apple-skills.sh # Export Apple's Xcode 27 skills
├── templates/
│   └── stacks/              # 9 stack YAML templates
└── rules/
    ├── routing.md           # Agent & skill routing table
    ├── ai-comments.md       # AI-NOTE/TODO/ASK conventions
    └── debugging.md         # Background debugging practices
```

## Works well with

- [solograph](https://github.com/fortunto2/solograph) — MCP server for code intelligence, KB, sessions, web search
- [Agent Teams](https://github.com/anthropics/agents) — parallel feature dev, code review, debugging
- [Context7](https://github.com/upstash/context7) — latest library docs for scaffolding

## Contributing

PRs welcome! If you have ideas for new skills, stacks, or improvements — open an issue or submit a PR.

## Known Issues

- **Windows:** pipeline scripts (`solo-dev.sh`, `solo-research.sh`) require WSL or Git Bash
- **Without uv:** MCP server won't auto-start. Install [uv](https://docs.astral.sh/uv/) first

## License

MIT

## Author

Rustam Salavatov ([@fortunto2](https://github.com/fortunto2))

---

If Solo Factory helps you ship faster, consider giving it a star. It helps others discover the project.
