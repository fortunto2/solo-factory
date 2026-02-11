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

### Connection to DDD

SGR is the technical implementation of DDD:
- **Bounded Context** -> separate set of schemas
- **Aggregate** -> root schema with nested ones
- **Ubiquitous Language** -> field names and enums = language of business
- **Value Objects** -> enums and typed wrappers

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

*These principles are injected into every PRD during generation.*
