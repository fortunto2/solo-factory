# Universal Development Principles

Principles applied to EVERY project regardless of stack. Injected into PRDs during generation.

---

## SOLID

### Single Responsibility Principle (SRP)
One class/module — one reason to change.
```
# Bad: UserService does auth + profile + email
# Good: AuthService, ProfileService, EmailService
```

### Open/Closed Principle (OCP)
Open for extension, closed for modification. New behavior through composition, not editing existing code.

### Liskov Substitution Principle (LSP)
Subtypes must be interchangeable with base types without breaking the contract.

### Interface Segregation Principle (ISP)
Many specific interfaces are better than one universal. Client should not depend on methods it doesn't use.

### Dependency Inversion Principle (DIP)
Dependencies point toward abstractions, not implementations. High-level modules don't depend on low-level ones.

---

## DRY — Don't Repeat Yourself

Every piece of knowledge should have a single, unambiguous representation in the system.

**But:** 3 similar lines of code are better than a premature abstraction. Duplicate until you see a pattern (Rule of Three).

---

## KISS — Keep It Simple, Stupid

- Minimum complexity for the current task
- Don't design for hypothetical future requirements
- Simple solution that works > elegant solution that's hard to maintain

---

## TDD — Test-Driven Development

**When to use:**
- Business logic and validation
- Complex calculations
- Edge cases and error handling
- API contracts

**When NOT to use:**
- UI layout/styling (visual tests are cheaper)
- One-off scripts
- Early-stage prototypes (tests after validation)

**Cycle:** Red -> Green -> Refactor

---

## CLI-First Testing

Every project should have a **CLI utility** that mirrors the core business logic without UI.

**Why:**
- **Integration testing** — verifies full pipeline end-to-end without browser/simulator
- **Debugging** — CLI is faster to launch, simpler to debug than UI
- **Pipeline-friendly** — CI/CD can run `make integration` without headless browser
- **Separation of concerns** — if logic works through CLI, it doesn't depend on UI framework

**Pattern:**
```
lib/pipeline/       # Business logic (pure functions, no UI)
cli/main.ts         # CLI wrapper — calls the same functions as UI
app/                # UI — calls the same functions from lib/pipeline/
Makefile            # make integration — runs CLI with test data
```

**Rules:**
- CLI uses **the same modules** as UI (DRY — one implementation, two entry points)
- CLI must work **without LLM / without network** (deterministic fallback)
- `make integration` — mandatory Makefile target, runs CLI smoke test
- `/solo:scaffold` generates CLI stub, `/solo:build` uses `make integration` after pipeline tasks

---

## DDD — Domain-Driven Design

### Bounded Contexts
Each domain has its own language and boundaries. User in auth context != User in billing context.

### Aggregates
A group of related objects that change atomically. One aggregate root — one entry point.

### Ubiquitous Language
Code speaks the language of the business. Not `processItem()`, but `validateOrder()`.

---

## Clean Architecture

```
[Entities] <- [Use Cases] <- [Adapters] <- [Frameworks]
```

- Dependencies point inward (toward business logic)
- Framework is an implementation detail, not the center of architecture
- Business logic doesn't know about DB, UI, HTTP

---

## Project Documentation

Every project must have three documentation files at root.

### Required Files

| File | Audience | Contents |
|------|----------|----------|
| **README.md** | Humans | Description, setup, run, test, deploy, tech stack |
| **CLAUDE.md** | AI agents | Architecture, commands, structure, Do/Don't, stack with versions |
| **docs/prd.md** | Everyone | Problem, solution, features, metrics, timeline |

`CLAUDE.md` is the agent instructions file. The agent reads it first. Contains everything for AI to work autonomously: structure, commands, architectural decisions, constraints.

### AICODE- Comments (Long-Term Agent Memory)

Single-line comments with `AICODE-` prefix — a memory layer right in the code. AI agents grep for them before working on a file.

| Prefix | Purpose | Who writes |
|--------|---------|-----------|
| `AICODE-NOTE` | Context, complex logic explanation | AI or human |
| `AICODE-TODO` | Task for next session | AI |
| `AICODE-ASK` | Question from AI to human | AI |

**Rules:**
- Single-line comments only (not block)
- Always in English (grepable)
- AI must search for `AICODE-` in a file before working on it
- `AICODE-ASK` after human answers -> rewrite as `AICODE-NOTE`
- `AICODE-TODO` after completion -> delete
- Don't overuse: max 2-3 per file, only where context is truly needed

**Examples:**

```typescript
// AICODE-NOTE: OSC sequence parsing splits across WebSocket chunks, handle partial sequences
// AICODE-TODO: Extract login overlay logic into separate module
// AICODE-ASK: Should we add timeout for incomplete OSC sequences?
```

```swift
// AICODE-NOTE: MLX model loads async on first inference, ~4GB download
// AICODE-TODO: Add structured JSON parsing for LLM response instead of placeholder
```

```python
# AICODE-NOTE: Embedding backend switch triggers full collection rebuild
# AICODE-ASK: Should we support incremental reindex on backend change?
```

### Two-Step Development (Implementation Plan)

For complex features — a two-step process:
1. **Plan** — AI explores codebase, writes implementation plan (markdown), gets approval
2. **Execute** — AI implements per plan, leaving `AICODE-NOTE` on complex areas

This stabilizes AI work on complex tasks: the plan captures context, and AICODE comments preserve it between sessions.

### Continuous Documentation (Tech Debt Discipline)

After EVERY completed task, the agent must check and update documentation. This isn't a separate step — it's part of the definition of "done".

**Checklist after every task:**

| What to check | When to update |
|---------------|----------------|
| `CLAUDE.md` | Added skill, command, stack, phase, MCP tool, key file |
| `README.md` | Changed public API, setup, project description |
| `docs/workflow.md` | Changed TDD policy, commit strategy, workflow |
| `docs/prd.md` | Changed features, metrics, scope |
| `AICODE-TODO` in touched files | Completed -> delete, new -> add |
| `AICODE-NOTE` on complex logic | Wrote non-obvious code -> annotate |
| Dead code | Remove unused imports, files, exports |
| Linter + tests | Always — task not done with failing lint/tests |

**Principle:** documentation that doesn't update with code is tech debt. Better to update now in 2 minutes than debug later for an hour.

---

## Privacy-First (from Manifesto)

- **All data local** — SQLite/SwiftData, not Firebase/Supabase for private data
- **No external API calls** after model download (where possible)
- **User controls everything** — export, delete, own their data
- **Offline-first** — app works without internet

---

## Internationalization (i18n)

All projects are multilingual by default. UI and content — English first, then localize.

### Principles

- **English first** — all UI, strings, errors written in EN. Localization added later
- **No hardcoded strings in UI** — all strings through i18n keys from day one
- **Single source of truth** — keys stored in one place (JSON/Localizable)
- **Pluralization** — account for plural forms across languages

### i18n by Stack

| Stack | Library | String Format |
|-------|---------|--------------|
| **Next.js / Web** | `next-intl` | JSON (`messages/en.json`, `messages/ru.json`) |
| **Astro** | `@astrojs/i18n` or `paraglide-js` | JSON |
| **iOS Swift** | `String Catalog` (Xcode 16) | `.xcstrings` (native) |
| **Kotlin Android** | Android Resources | `res/values/strings.xml`, `res/values-ru/strings.xml` |
| **Python** (API / ML) | `gettext` or simple dict | `.po` / `.json` |
| **Cloudflare Workers** | `@formatjs/intl` or simple JSON | JSON |

---

## Shared Infrastructure

### Auth

Shared auth across all apps using Supabase Auth:

- **Backend:** Supabase Auth (Google Sign-In, RLS)
- **iOS:** Swift Package
- **Android:** Kotlin module
- **Web:** React provider + SignInButton
- **Realtime:** Supabase Realtime (presence, change subscriptions)

Don't write your own auth — use a shared module.

### Payments

| Platform | Solution |
|----------|----------|
| **Web** | Stripe (Checkout Session + Customer Portal + Webhooks) |
| **iOS** | StoreKit 2 |
| **Android** | Google Play Billing |

### Email — Resend + React Email

Transactional and broadcast email for web projects. [Docs](https://resend.com/docs/llms-full.txt)

- `resend` (Node.js SDK) + `react-email` (templates as React components)
- Auth: Bearer token (`RESEND_API_KEY=re_...`), store in `sst secret set` / env
- Monorepo: `@repo/email` package for templates and send utility

**Sending:**
```typescript
import { Resend } from 'resend';
import { WelcomeEmail } from '@repo/email/templates/welcome';

const resend = new Resend(process.env.RESEND_API_KEY);

await resend.emails.send({
  from: 'App <hello@app.com>',
  to: user.email,
  subject: 'Welcome',
  react: <WelcomeEmail name={user.name} />,
});
```

**Broadcast (marketing):**
- Contacts: `resend.contacts.create({ email, audienceId })`
- Sends: `resend.broadcasts.create({ audienceId, from, subject, html })`
- Personalization: `{{{FIRST_NAME|there}}}` in template
- Unsubscribe: add `{{{RESEND_UNSUBSCRIBE_URL}}}` in HTML

**Webhook (delivery tracking):**
- Endpoint: `app/api/email/webhook/route.ts`
- Events: `email.sent`, `email.delivered`, `email.bounced`, `email.complained`
- Verify signature via `svix` (Resend uses Svix)

**Rules:**
- One domain per Resend — verify DNS (DKIM, SPF, DMARC)
- React Email for templates (JSX → HTML), not raw HTML
- `text` auto-generated from HTML, no need to set explicitly
- Dev: Resend provides test domain `onboarding@resend.dev`

### Validation

| Stack | Library | Pattern |
|-------|---------|---------|
| **Web (TS)** | `zod` | Schema -> infer type, form + API validation |
| **Python** | `pydantic` | BaseModel, Field, validators |
| **Swift** | Codable + custom validation | Protocol-based |
| **Kotlin** | kotlinx.serialization | Data class + validation |

---

## Infrastructure & DevOps

### Two Tools, No More

| Project Type | Tool | Providers |
|-------------|------|-----------|
| **Web / Serverless** (Next.js, Astro, CF Workers) | **SST** (`sst.config.ts`) | Cloudflare Pages/Workers, AWS Lambda |
| **Python backends / VPS / Docker** | **Pulumi** (Python, `infra/__main__.py`) | Hetzner VPS, AWS, Fly.io |
| **MVP / prototype** | **Fly.io** (`fly.toml`) | Fly.io |
| **Mobile** | Native stores | App Store, Play Store |

### Principles

- **Serverless by default.** VPS only for persistent process, GPU, or when serverless is more expensive
- **Infrastructure in the repo.** `sst.config.ts` or `infra/` — no external playbooks
- **Provider per task.** Cloudflare for edge, Hetzner for cheap VPS, Fly.io for quick launch

### CI/CD — GitHub Actions Everywhere

```yaml
# SST projects
- run: npx sst deploy --stage ${{ github.ref == 'refs/heads/main' && 'prod' || 'dev' }}

# Pulumi projects
- run: pulumi up --yes --stack ${{ github.ref == 'refs/heads/main' && 'prod' || 'dev' }}
```

### DNS — Always Cloudflare

All domains through Cloudflare. SSL, CDN, DDoS protection — out of the box.

### Cloudflare Tunnel — Expose Services Without Open Ports

Instead of Traefik/nginx reverse proxy, opening firewall ports, and manual SSL certs — use a `cloudflared` tunnel in docker-compose. The tunnel connects outbound to Cloudflare edge, no open ports needed.

**When:** any backend/API on VPS or local machine that needs internet exposure.

**Why better than Traefik/nginx:** zero open ports, automatic SSL, no firewall rules, no DNS propagation wait, works behind NAT.

**Setup:**
```bash
cloudflared tunnel create <name>                    # Create tunnel (saves credentials.json)
cloudflared tunnel route dns <name> api.example.com # Bind subdomain
```

**docker-compose:**
```yaml
  tunnel:
    image: cloudflare/cloudflared:latest
    restart: always
    command: tunnel --no-autoupdate run
    volumes:
      - ./cloudflared-config.yml:/etc/cloudflared/config.yml:ro
      - /path/to/credentials.json:/etc/cloudflared/credentials.json:ro
    depends_on:
      service:
        condition: service_healthy
```

**cloudflared-config.yml:**
```yaml
tunnel: <tunnel-id>
credentials-file: /etc/cloudflared/credentials.json
ingress:
  - hostname: api.example.com
    service: http://service-name:port
  - service: http_status:404
```

**Requirements:** domain must be on Cloudflare DNS. Never commit credentials.json to git.

### Secrets

- SST: `sst secret set`
- Pulumi: `pulumi config set --secret`
- No `.env` files in git

### Monitoring

- **PostHog** for analytics and errors (all projects, EU hosting)
- Cloudflare Analytics for edge (in addition to PostHog)

---

## SGR — Schema-Guided Reasoning (Schemas First)

All projects built **from schemas to logic**, not the other way around. Schemas are the contract between AI agent, business logic, and UI.

### Principle: Schemas -> Logic -> UI

1. **Define the domain** — typed schemas first (models, enums, value objects)
2. **Then logic** — services work with schemas, not raw data
3. **UI last** — displays schemas, doesn't parse strings

### SGR by Stack

| Stack | Schemas | Example |
|-------|---------|---------|
| **Python** | `Pydantic BaseModel` | `class Receipt(BaseModel): amount: Decimal, category: Category` |
| **Web (TS)** | `Zod schema -> infer type` | `const ReceiptSchema = z.object({...}); type Receipt = z.infer<typeof ReceiptSchema>` |
| **iOS Swift** | `@Model` (SwiftData) / `Codable struct` | `@Model class Receipt { var amount: Decimal, ... }` |
| **Kotlin** | `data class` + `kotlinx.serialization` | `@Serializable data class Receipt(val amount: BigDecimal, ...)` |

### For AI Agents

When an AI agent works on a project, it MUST:
- **Read schemas first** — `Models/`, `schemas/`, `types/` before any work
- **Generate structured output** — through typed schemas, not strings
- **Validate at boundaries** — agent input/output goes through schema validation
- **Document the domain** — enums, value objects, aggregates as code, not comments

For LLM-powered features with structured output, consider BAML — see the dedicated section below.

### Connection to DDD

SGR is the technical implementation of DDD:
- **Bounded Context** -> separate set of schemas
- **Aggregate** -> root schema with nested ones
- **Ubiquitous Language** -> field names and enums = language of business
- **Value Objects** -> enums and typed wrappers

---

## BAML — Structured LLM Output (Schema Engineering)

[BAML](https://github.com/BoundaryML/baml) (Boundary AI Markup Language) — a DSL that turns prompt engineering into schema engineering. Define LLM functions in `.baml` files with typed inputs and outputs. Compiler (Rust) generates Python/TS/Ruby/Go/Java clients.

**When to use:** any project that calls LLMs and needs structured output — classification, extraction, tool calling, agentic workflows.

### Core Idea

One `.baml` file gives you: prompt, schema, streaming parser, retries, and a ready SDK to import. No manual JSON parsing, no hoping the LLM returns valid output.

```baml
enum Sentiment { POSITIVE  NEGATIVE  NEUTRAL }

function ClassifyReview(text: string) -> Sentiment {
  client GPT4o
  prompt #"
    Classify the sentiment: {{ text }}
    {{ ctx.output_format }}
  "#
}
```

```python
from baml_client import b
result = b.ClassifyReview("Great product!")  # typed: Sentiment
```

### Why It Matters

- **Auto-fixes broken LLM output** in milliseconds without re-requesting — saves API cost, enables cheaper models
- **2-4x fewer tokens** than JSON Schema for output format description
- **Provider-independent** — works with OpenAI, Anthropic, local models (Ollama, llama.cpp)
- **Typed tool calling** — union types for multi-tool dispatch, streaming out of the box

### BAML vs Pydantic + Structured Output vs Raw OpenAI

| | Raw OpenAI | Pydantic + Structured Output | BAML |
|---|---|---|---|
| **Typing** | dict (runtime errors) | typed (Pydantic class) | typed (generated class) |
| **Validation** | manual | auto (OpenAI only) | auto (any provider) |
| **Retry on bad JSON** | manual | no | auto |
| **Prompt location** | in code string | in code string | separate `.baml` file |
| **Local models** | no | no | yes |
| **Token efficiency** | baseline | baseline | 2-4x less |
| **Tool calling** | JSON dict, manual parse | typed but OpenAI-only | typed union, any provider |
| **Testing** | write yourself | write yourself | built-in playground |

### Decision Guide

| Situation | Approach |
|-----------|----------|
| Simple LLM call, OpenAI only | Pydantic + `response_format` is enough |
| Multiple providers or local models | BAML |
| Many prompts, need organization | BAML (prompts as files, not strings) |
| Complex tool calling (10+ tools) | BAML (union types, streaming) |
| Existing Pydantic/Zod codebase, no LLM layer | Keep Pydantic/Zod for data validation, add BAML for LLM layer |

### Integration

BAML doesn't compete with Pydantic/Zod — it sits above them. Pydantic validates data, BAML validates LLM responses and generates types. In a new project, BAML replaces Pydantic in the LLM layer. In an existing project, they coexist.

### Hybrid Strategy: BAML + SGR Together

Use SGR (constrained decoding) where precision matters, BAML (schema-as-prompt) where reasoning matters:

| Task | Approach | Why |
|------|----------|-----|
| Tool routing (`NextStep`) | SGR (`response_format`) | Exact branch selection, no hallucinations |
| Extraction (documents, receipts) | BAML (SAP) | Free reasoning before parsing → better quality |
| Classification (tickets, priorities) | SGR | Simple enums, constrained decoding handles well |
| Complex reasoning (gap analysis, review) | BAML (SAP) | Needs full chain-of-thought |
| On-device iOS | SGR (`@Generable`) | BAML doesn't support Apple Foundation Models |
| Prompt iteration/testing | BAML Playground | Valuable even without BAML runtime |

```python
# SGR — tool dispatch (constrained decoding is optimal)
completion = client.chat.completions.parse(
    model="gpt-4o-mini",
    response_format=NextStep,  # Union[SendEmail, SearchKB, ...]
    messages=messages,
)
```

```
// BAML — extraction with reasoning (baml_src/extract_invoice.baml)
function ExtractInvoice(doc: image) -> Invoice {
  client GPT4o
  prompt #"
    Analyze this document carefully.
    First describe what you see, then extract the data.
    {{ ctx.output_format }}
  "#
}

class Invoice {
  vendor string
  total float
  items InvoiceItem[]
  confidence float @description("0.0-1.0 extraction confidence")
}
```

```python
# Python call — BAML lets model "think" first, then parses
from baml_client import baml as b
invoice = await b.ExtractInvoice(document_image)
```

**What's useful now** (even without full migration):
- BAML Playground (VSCode extension) — fast prompt iteration
- SAP for extraction tasks — noticeable quality boost over constrained decoding
- Declarative retry/fallback — replaces manual try/except
- Typed streaming — objects, not tokens (useful for UI agents)

**Risks:** weekly DSL updates may break, no iOS support, small community (~2K stars), `.baml` files are not portable.

Ref: https://docs.boundaryml.com

---

## Error Handling

### Fail Fast
Check invariants early, before starting work. Don't mask errors.

### Graceful Degradation
At system boundaries (UI, API) — show user-friendly messages. Inside — let it crash with a clear stack trace.

### Validate at Boundaries
- User input — validate (Zod, Pydantic)
- Internal code — trust the types
- External APIs — validate responses

---

## Development Workflow

### Project Lifecycle

```
# 1. Ideation & Validation
/solo:research -> /solo:validate -> /solo:scaffold

# 2. Project Bootstrap
/solo:scaffold <name> <stack>       # Create project: structure, deps, git, GitHub
/solo:setup                         # Dev workflow config (0 questions)

# 3. Development (per feature)
/solo:plan "Feature X"              # Explore code -> spec + plan (0 questions)
/solo:build                         # TDD execution

# 4. Parallel work (when needed)
/agent-teams:team-feature           # 2-4 agents on different parts
/agent-teams:team-review            # Parallel code review
/agent-teams:team-debug             # Debug complex bugs

# 5. Distribution (Фабрика)
/solo:seo-audit <url>               # SEO health check, score 0-100
/solo:content-gen <project>         # Content pack (video, LinkedIn, Reddit, Twitter)
/solo:landing-gen <project>         # Landing page content + A/B headlines
/solo:community-outreach <project>  # Reddit/HN/PH thread drafts
/solo:video-promo <project>         # Video script + storyboard
/solo:metrics-track <project>       # PostHog funnel + KPI thresholds
```

### Plan → Build — File-Based Development Workflow

Lightweight feature lifecycle through `docs/plan/` and `docs/workflow.md`. No framework, just files.

**Setup** (created via `/solo:setup`, 0 questions):
- `docs/workflow.md` — TDD policy, commit strategy, verification checkpoints

**Track = unit of work** (feature, bug, refactoring):
```
docs/plan/{name}_{date}/
  spec.md           # Specification (problem, solution, acceptance criteria)
  plan.md           # Phases, tasks, dependencies, [x]/[ ] progress
```

**Daily cycle:**
```
/solo:plan "Add user auth"    # Explore code -> spec + plan (0 questions)
/solo:build                   # TDD: task -> test -> code -> verify -> commit
/solo:build                   # Continue — auto-resume current track
```

### Agent Teams — Parallel Work

Multiple agents work simultaneously with file ownership separation.

**Presets:**

| Preset | Agents | When |
|--------|--------|------|
| `team-feature` | 2-4 implementer | Parallel feature dev with file ownership |
| `team-review` | 3-5 reviewer | Code review by dimension (security, perf, arch, testing, a11y) |
| `team-debug` | 2-4 debugger | Parallel debugging with competing hypotheses |
| `team-research` | 2-3 researcher | Parallel research (differs from `/swarm`) |

**Key principles:**
- **File ownership** — each agent owns its files, no conflicts
- **Dependency management** — tasks with explicit dependencies (`blockedBy`)
- **Integration points** — coordination via messaging between agents
- **Evidence-based debugging** — hypotheses with confidence levels and file:line citations

**Commands:**

| Command | When |
|---------|------|
| `/agent-teams:team-spawn` | Create team (preset or custom composition) |
| `/agent-teams:team-feature` | Parallel development |
| `/agent-teams:team-review` | Multi-review |
| `/agent-teams:team-debug` | Debug with hypotheses |
| `/agent-teams:team-status` | Team status |
| `/agent-teams:team-delegate` | Rebalance tasks |
| `/agent-teams:team-shutdown` | Shut down team |

### Implementation Principles

- TDD: test first -> then code -> verify
- Each task = separate git commit
- Phase checkpoints: tests + linter between phases
- Auto-update `plan.md` progress markers
- On error — don't skip, fix it

### When to Use What

| Situation | Tool |
|-----------|------|
| Simple task (< 30 min) | Just do it, no plan needed |
| Feature (1-3 days) | `/solo:plan` -> `/solo:build` |
| Large feature (3+ days) | Plan + Agent Teams (parallel) |
| Code review | `/agent-teams:team-review` |
| Complex bug | `/agent-teams:team-debug` |
| Refactoring | `/solo:plan` (for tracking) |

---

## Code Quality Tools

Unified linting, formatting, and type-checking toolset. All projects use pre-commit hooks.

### By Language

| Language | Linter | Formatter | Type checker | Tests |
|----------|--------|-----------|--------------|-------|
| **Python** | `ruff` (replaces flake8, isort, pyflakes) | `ruff format` (replaces black) | `ty` (Astral, extremely fast, replaces mypy/pyright) | `pytest` + `hypothesis` |
| **TypeScript** | `eslint` (flat config v9, typescript-eslint) | `prettier` | `tsc --noEmit` (strict mode) | `vitest` |
| **Bash** | `shellcheck` | — | — | `bats` (Bash Automated Testing System) |
| **Swift** | `swiftlint` | `swift-format` | Swift compiler | `XCTest` |
| **Kotlin** | `ktlint` | `ktlint --format` | Kotlin compiler | `JUnit 5` |

### Principles

- **Astral toolchain for Python** — ruff + ty + uv. One vendor, maximum speed
- **pre-commit is mandatory.** Linter + formatter + tests before commit, not after
- **Autofix by default.** `ruff --fix`, `prettier --write` — don't waste time on manual fixes
- **Type checking mandatory for Python.** `ty` (Astral) — instantaneous, replaces mypy/pyright
- **shellcheck for bash.** Pipeline scripts are critical — `set -euo pipefail` + shellcheck catch bugs before production

---

## Agent Self-Discipline

Principles for fighting AI agent degradation. Applied to all skills and pipelines.
Sources: [Ouroboros](https://github.com/razzant/ouroboros), [OpenAI Harness Engineering](https://openai.com/index/harness-engineering/), [Mitchell Hashimoto](https://mitchellh.com/writing/my-ai-adoption-journey).

### Drift Detector — recognize degradation

| Anti-pattern | What happens | Fix |
|-------------|--------------|-----|
| **Task queue mode** | Every response = "Scheduled task X" instead of working | Do the task now, don't schedule |
| **Report mode** | Writes bullet-point reports instead of acting | Code > report. Iteration without commit = not an iteration |
| **Permission mode** | Asks "should I?" when it already knows the answer | Act, escalate only on genuine ambiguity |
| **Amnesia** | Forgets context after 3 messages | Re-read CLAUDE.md and task context |
| **Scope creep** | Fixes one thing, refactors half the project | One commit = one task. No more |

### Complexity Thresholds

- **Function > 150 lines** -> decompose. No exceptions
- **Module > 1000 lines** -> split. One module ~ one LLM context
- **CLAUDE.md > 40,000 chars** -> trim. Map, not encyclopedia
- **Plan > 15 tasks** -> split into multiple tracks
- Minimalism is about code, not capabilities. Do more with less code.

### Evolution = Commit

- Iteration without commit = not an iteration
- Analysis without action = preparation, not progress
- Each commit = one coherent transformation

### Three-Axis Reflection (after every significant task)

1. **Technical:** did the project grow technically? (code, tools, architecture)
2. **Cognitive:** did understanding improve? (strategy, decisions, patterns)
3. **Process:** did the workflow improve? (harness, skills, pipeline, docs)

If only one axis was served — think about what's missing.

### Harness First

When agent makes a mistake — don't retry the prompt, fix the harness:
1. Simple issues -> update CLAUDE.md (constraints, Do/Don't)
2. Recurring issues -> linter or structural test
3. Pattern works well -> capture as golden principle

> "When the agent struggles, treat it as a signal — fix the harness, not the prompt."

---

## Memory Hierarchy Maintenance

Claude Code loads CLAUDE.md files, rules, and auto-memory at session start. Keeping this hierarchy clean reduces context waste and improves agent accuracy.

### Loading Order

1. User memory (`~/.claude/CLAUDE.md`) — personal preferences, stack bias
2. User rules (`~/.claude/rules/*.md`) — universal conventions (AI comments, Context7)
3. Auto-memory (`~/.claude/projects/{key}/memory/MEMORY.md`) — cross-session learning, first 200 lines
4. Project hierarchy (root to CWD) — each level: `CLAUDE.md`, `.claude/rules/*.md`

### Principles

- **Inheritance over duplication.** Generic info lives at parent level, project-specific at leaf. Don't repeat AWS docs in every project — put them in the workspace CLAUDE.md
- **Conditional rules for domain content.** Large domain-specific sections (analytics, deployment, MCP) belong in `.claude/rules/{topic}.md` with `paths:` frontmatter. They load only when working on matching files
- **40k char budget.** Total startup context should stay under 40k chars. Use `/memory-audit` to check
- **CLAUDE.md is a map, not an encyclopedia.** Quick reference: structure, commands, key files, constraints. Move detailed docs to rules or separate files
- **Self-contained fallback.** Each project should work if cloned standalone — add brief Prerequisites section pointing to parent for full docs
- **User-level rules for universal patterns.** Conventions used across all projects (AI comments, library docs lookup) belong in `~/.claude/rules/`, not duplicated per project

### Maintenance Checklist

| When | Action |
|------|--------|
| New project | Run `/memory-audit` to check inheritance chain |
| CLAUDE.md > 300 lines | Extract sections to conditional `.claude/rules/` |
| Same section in 2+ files | Move to highest common parent |
| Rule > 30 lines without `paths:` | Add `paths:` frontmatter or move to CLAUDE.md |
| New workspace | Set up parent CLAUDE.md with shared infra docs |

### Audit Tool

```bash
# Rich tree display + optimization hints
uv run python solo-factory/scripts/memory_map.py /path/to/project --audit

# All projects in directory
uv run python solo-factory/scripts/memory_map.py --all-projects --audit

# Or via skill
/memory-audit [path]
```

---

## Skills Development (Claude Code / Agent Skills)

Skills are reusable instruction packages (folder with `SKILL.md`) that teach Claude specific workflows. Based on [Anthropic's Complete Guide to Building Skills](https://docs.anthropic.com).

### Structure

```
your-skill-name/
├── SKILL.md            # Required — instructions + YAML frontmatter
├── scripts/            # Optional — executable code (Python, Bash)
├── references/         # Optional — docs loaded as needed
└── assets/             # Optional — templates, fonts, icons
```

### Progressive Disclosure (3 levels)

1. **Frontmatter** (always in system prompt) — name + description, enough for Claude to decide when to load
2. **SKILL.md body** (loaded when relevant) — full instructions and guidance
3. **Linked files** (on-demand) — references/, scripts/ — Claude navigates as needed

This minimizes token usage while maintaining specialized expertise.

### Frontmatter Rules

```yaml
---
name: kebab-case-name
description: What it does + when to use it + key capabilities. Under 1024 chars.
---
```

- **name:** kebab-case only, no spaces/capitals/underscores, should match folder name
- **description:** include trigger phrases users would say. Formula: `[What it does] + [When to use it] + [Key capabilities]`
- **File must be exactly `SKILL.md`** (case-sensitive, no variations)
- No XML angle brackets (`< >`) in frontmatter
- No `README.md` inside skill folder — all docs go in SKILL.md or references/

### Writing Instructions

- Be specific and actionable (command examples with expected output, not "validate the data")
- Include error handling (common issues, troubleshooting steps)
- Reference bundled resources clearly (`consult references/api-guide.md for...`)
- Keep SKILL.md under 5,000 words — move detailed docs to `references/`
- Use bullet points and numbered lists over prose
- Put critical instructions at the top

### Description Quality (triggers)

Good descriptions include trigger phrases users would actually say:

```yaml
# Good — specific + triggers
description: Manages sprint workflows including task creation and tracking.
  Use when user mentions "sprint", "Linear tasks", or "create tickets".

# Bad — too vague
description: Helps with projects.

# Bad — too technical, no user triggers
description: Implements the Project entity model with hierarchical relationships.
```

### MCP Conditional Pattern

Skills should work with AND without MCP tools. Use "IF available" pattern:

```markdown
IF MCP tool `create_project` is available, use it.
Otherwise, generate the project structure locally.
```

### Project-Level Skills

Skills in `.claude/skills/` are scoped to that project. Place domain-specific workflows here rather than at user-level (which loads everywhere).

| Scope | Location | When |
|-------|----------|------|
| User-level | `~/.claude/skills/` | Universal workflows (rare) |
| Plugin | `solo-factory/skills/` | Shared across all projects via plugin |
| Project | `project/.claude/skills/` | Domain-specific (CRM, deployment, etc.) |

### Context Budget

Skills are on-demand (not counted in base memory budget), but too many enabled skills degrade performance. Keep SKILL.md under 5,000 words. If you have 20+ skills enabled, consider selective enablement or skill "packs" for related capabilities.

### Testing

1. **Trigger test:** does it activate on relevant queries and NOT on unrelated ones?
2. **Functional test:** does it produce correct output?
3. **Performance comparison:** fewer messages, fewer errors, less tokens than without skill?

Iterate on one task until it succeeds, then extract into a skill.

---

## Opus 4.6 Prompting Rules

Rules for writing prompts in skills, CLAUDE.md, and agent configs.

### 1. Prompt Hygiene

**No ALL-CAPS pressure.** Opus 4.6 over-triggers on CRITICAL, MUST, NEVER, ALWAYS, MANDATORY, WARNING. The model follows instructions without shouting — pressure adds nervousness to output, not compliance.

```
# Bad
**CRITICAL: You MUST ALWAYS check tests. NEVER skip this step.**

# Good
Check tests after each change. This catches regressions early.
```

**Explain WHY, not just WHAT.** The model generalizes better from explanations than bare rules.

```
# Bad
Do NOT use --no-verify on commits.

# Good
Commit with hooks enabled — they catch formatting and lint issues before they reach the repo.
```

**Positive framing over prohibitions.** "Do X" works better than "Don't do Y". The model sometimes fixates on the forbidden action.

```
# Bad
Do NOT search the entire project. Do NOT read all files.

# Good
Search only the directories relevant to the current task. Load what you need.
```

**No anti-patterns in examples.** Show only desired behavior. The model may latch onto a "bad" example and reproduce it.

**No "if in doubt, use this tool".** Triggers aggressive tool invocation. Use specific conditions instead.

### 2. Output Calibration

**Tone table (flat vs alive).** Concrete examples calibrate output better than abstract "be concise" instructions.

| Flat (avoid) | Alive (aim for) |
|---|---|
| "Done. The file has been updated." | "Done. Cleaned up that config and pushed." |
| "I found 3 results matching your query." | "Three hits. The second one's interesting." |
| "I don't have access to that." | "Can't get in. Permissions issue or it doesn't exist." |

**Stock phrase filter.** AI crutch phrases that signal "an LLM wrote this":
- "it's worth noting", "at the end of the day", "deep dive", "game-changer"
- "seamless", "revolutionary", "cutting-edge", "leverage" (promotional inflation)

**Em dashes (—) — AI writing tell.** Replace with commas, periods, colons. Opus overloads text with em dashes.

**No sycophancy.** "If you're not actually impressed, don't say you are." Genuine reactions only.

### 3. Agent Behavior

- **Resourcefulness before questions.** Read the file. Check context. Search. Then ask. Come with answers, not questions.
- **Specificity over volume.** Say something concrete or say less. Empty responses are worse than short ones.
- **Tone by context.** Serious tasks, errors, bad news — direct and calm. Routine — can add life. Switch, don't get stuck in one mode.

---

## Agent-Readable Content (Markdown for Agents)

All content sites (blogs, landing pages, docs) should serve markdown versions for AI agents. Reduces token usage ~80% and makes content accessible to Claude Code, Cursor, and other agents.

### Cloudflare Markdown for Agents

If the site is behind Cloudflare (Pro/Business/Enterprise) — enable "Markdown for Agents" in dashboard (Quick Actions). Any request with `Accept: text/markdown` returns clean markdown instead of HTML.

```bash
curl https://example.com/blog/post -H "Accept: text/markdown"
# Response: Content-Type: text/markdown, x-markdown-tokens: 725
```

### /llms.txt — Discovery File for Agents

Every content site should have `/llms.txt` at root — a content map for AI agents (like robots.txt for LLMs).

```markdown
# MySite
> Brief description of the site

## Docs
- [Getting Started](/docs/start): Setup guide
- [API Reference](/docs/api): Full API docs
```

### Implementation by Stack

| Stack | How to implement |
|-------|-----------------|
| **Astro (Cloudflare Pages)** | Enable CF Markdown for Agents + static `public/llms.txt` + content collections expose `.md` raw |
| **Next.js (Vercel/CF)** | Route handler `app/llms.txt/route.ts` + MDX/content as API (`Accept: text/markdown` -> raw markdown) |
| **Cloudflare Workers** | Enable CF Markdown for Agents in dashboard. Custom: check `Accept` header, return markdown |
| **Any behind Cloudflare** | Dashboard -> Quick Actions -> Markdown for Agents (toggle) |

### Principles

- **Markdown is first-class.** Content stored as markdown, HTML generated from it, not the other way around
- **Content negotiation.** `Accept: text/markdown` -> markdown, else HTML. `x-markdown-tokens` header in response
- **llms.txt mandatory** for content sites. Auto-generated from sitemap or content collections
- **Content-Signal header.** `Content-Signal: ai-train=no, search=yes, ai-input=yes` — control how AI uses your content

Ref: https://blog.cloudflare.com/markdown-for-agents/
Ref: https://llmstxt.org/

---

## Background Jobs and Pipelines

Tool selection: **cron -> CF Workers Cron -> Prefect -> Temporal -> Trigger.dev**

**Rule:** start with cron. Move to Temporal when you need fan-out, retry, and multiple projects on one VPS.

---

*These principles are injected into every PRD during generation.*
