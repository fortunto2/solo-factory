---
name: solo-init
description: One-time founder onboarding — generates personalized manifest, STREAM calibration, dev principles, and stack selection. Use when user says "set up solo factory", "initialize profile", "configure defaults", "first time setup", or "onboard me". Safe to re-run. Do NOT use for project scaffolding (use /scaffold).
license: MIT
metadata:
  author: fortunto2
  version: "2.0.0"
allowed-tools: Read, Grep, Bash, Glob, Write, Edit, AskUserQuestion
argument-hint: "[project-path]"
---

# /init

One-time founder onboarding. Asks key questions, generates personalized configuration files. Everything stored as readable markdown/YAML — edit anytime.

Two layers of config:
- **`~/.solo-factory/defaults.yaml`** — org-level (bundle IDs, GitHub org, Apple Team ID). Shared across all projects.
- **`.solo/`** in project — founder philosophy, dev principles, STREAM calibration, selected stacks. Per-project but usually the same.

The templates in `solo-factory/templates/` are defaults. This skill personalizes them based on your answers.

Run once after installing solo-factory. Safe to re-run — shows current values and lets you update them.

## Output Structure

```
~/.solo-factory/
└── defaults.yaml              # Org defaults (bundle IDs, GitHub, Team ID)

.solo/
├── manifest.md                # Your founder manifesto (generated from answers)
├── stream-framework.md         # STREAM calibrated to your risk/decision style
├── dev-principles.md          # Dev principles tuned to your preferences
└── stacks/                    # Only your selected stack templates
    ├── nextjs-supabase.yaml
    └── python-api.yaml
```

Other skills read from these:
- `/scaffold` reads `defaults.yaml` for `<org_domain>`, `<apple_dev_team>` placeholders + `.solo/stacks/` for stack templates
- `/validate` reads `manifest.md` for manifesto alignment check
- `/setup` reads `dev-principles.md` for workflow config
- `/stream` reads `stream-framework.md` for decision framework

## Steps

### 1. Check existing config

- Read `~/.solo-factory/defaults.yaml` — if exists, show current values
- Check if `.solo/` exists in project path
- If both exist, ask: "Reconfigure from scratch?" or "Keep existing and skip?"
- If neither exists, continue to step 2

### 2. Determine project path

If `$ARGUMENTS` contains a path, use it. Otherwise use current working directory.

### 3. Ask org defaults (AskUserQuestion, 4 questions)

```
Question 1: "What is your reverse-domain prefix for app IDs?"
Header: "Bundle ID"
multiSelect: false
Options:
- "co.superduperai" — "Example: co.superduperai.myapp"
- "com.mycompany" — "Example: com.mycompany.myapp"
- "io.myname" — "Example: io.myname.myapp"

Question 2: "Apple Developer Team ID? (optional, for iOS signing)"
Header: "Apple Team"
multiSelect: false
Options:
- "Skip" — "No iOS apps, skip for now"
- "Enter Team ID" — "10-char alphanumeric, find at developer.apple.com → Membership"

Question 3: "GitHub username or org for new repos?"
Header: "GitHub"
multiSelect: false
Options:
- "fortunto2" — "Personal GitHub account"
- "my-org" — "Organization account"

Question 4: "Where do you keep projects?"
Header: "Projects dir"
multiSelect: false
Options:
- "~/startups/active" — "Default solopreneur path"
- "~/projects" — "Standard projects directory"
- "~/code" — "Simple code directory"

Question 5: "Where is your solopreneur knowledge base repo?"
Header: "KB repo"
multiSelect: false
Options:
- "~/startups/solopreneur" — "Default solopreneur KB location"
- "Skip" — "No solopreneur KB, skip for now"
```

### 4. Create org defaults

```bash
mkdir -p ~/.solo-factory
```

Write `~/.solo-factory/defaults.yaml`:
```yaml
# Solo Factory — org defaults
# Used by /scaffold and other skills for placeholder replacement.
# Re-run /init to update these values.

org_domain: "<answer from 3.1>"
apple_dev_team: "<answer from 3.2>"
github_org: "<answer from 3.3>"
projects_dir: "<answer from 3.4>"
solopreneur_repo: "<answer from 3.5>"
```

### 5. Ask Round 1 — Philosophy & Values (AskUserQuestion, 4 questions)

```
Question 1: "What drives you to build products?"
Header: "Motivation"
multiSelect: true
Options:
- "Privacy & data ownership" — "Users own their data, on-device processing, no cloud dependency"
- "Speed to market" — "Ship fast, learn fast, iterate. Market teaches better than planning"
- "Creative freedom" — "Build what doesn't exist yet, express ideas through products"
- "Financial independence" — "Revenue-generating products, sustainable solo business"

Question 2: "What will you NEVER build?"
Header: "Hard no's"
multiSelect: true
Options:
- "Dark patterns & addiction" — "No engagement tricks, no manipulative UX, no vanity metrics"
- "Surveillance & tracking" — "No selling user data, no hidden analytics, no ad-tech"
- "Subscription traps" — "No lock-in, no cancellation friction, honest pricing"
- "Exploitation" — "No extracting value from vulnerable people, no discrimination"

Question 3: "How do you think about user data?"
Header: "Data philosophy"
multiSelect: false
Options:
- "Offline-first (Recommended)" — "All data local by default. Cloud only when user explicitly chooses"
- "Cloud-first" — "Cloud storage with strong encryption. Convenience over full local control"
- "Hybrid" — "Sensitive data local, non-sensitive in cloud. User chooses per data type"

Question 4: "Default pricing model for your products?"
Header: "Pricing"
multiSelect: false
Options:
- "Free + one-time purchase" — "Free tier with paid upgrade, no recurring fees"
- "Freemium + subscription" — "Free core, subscription for premium features"
- "Open source + services" — "Code is free, charge for hosting/support/custom work"
- "Pay once, own forever" — "One-time purchase, all updates included"
```

### 6. Ask Round 2 — Development Preferences (AskUserQuestion, 4 questions)

```
Question 1: "Your TDD approach?"
Header: "Testing"
multiSelect: false
Options:
- "TDD moderate (Recommended)" — "Test business logic & APIs. Skip tests for UI layout and prototypes"
- "TDD strict" — "Test everything. Red-Green-Refactor for every feature"
- "Tests after" — "Write code first, add tests for critical paths later"
- "Minimal" — "Only test what breaks. Integration tests over unit tests"

Question 2: "How do you handle infrastructure?"
Header: "Infrastructure"
multiSelect: false
Options:
- "Serverless-first (Recommended)" — "Vercel/Cloudflare/Lambda. VPS only for persistent processes or GPU"
- "VPS / Docker" — "Hetzner/Fly.io/DigitalOcean. Full control, predictable costs"
- "Platform-managed" — "Railway/Render/Heroku. Zero DevOps, higher cost"
- "Self-hosted" — "Own hardware or dedicated servers. Maximum control"

Question 3: "Commit and code review style?"
Header: "Workflow"
multiSelect: false
Options:
- "Conventional commits + auto" — "feat:/fix:/chore: prefixes, AI auto-commits per task"
- "Squash & merge" — "Feature branches, squash on merge, clean history"
- "Trunk-based" — "Commit directly to main, small frequent changes"

Question 4: "Documentation level?"
Header: "Docs"
multiSelect: false
Options:
- "CLAUDE.md + AICODE comments (Recommended)" — "AI-optimized docs: CLAUDE.md, AICODE-NOTE/TODO/ASK in code"
- "Comprehensive" — "Full docs: README, CLAUDE.md, ADRs, inline comments, API docs"
- "Minimal" — "README + code comments only. Code should be self-documenting"
```

### 7. Ask Round 3 — Decision Style & Stacks (AskUserQuestion, 3 questions)

```
Question 1: "How do you make decisions?"
Header: "Risk style"
multiSelect: false
Options:
- "Barbell: safe + bold bets" — "90% conservative, 10% high-risk/high-reward experiments"
- "Calculated risks" — "Research thoroughly, then commit. Reversible decisions fast, irreversible slow"
- "Move fast, fix later" — "Speed over analysis. Default to action, course-correct on feedback"
- "Conservative" — "Proven technologies, established markets. Minimize downside"

Question 2: "What's your ultimate filter for decisions?"
Header: "Priority"
multiSelect: false
Options:
- "Time (Recommended)" — "Time is the only non-renewable resource. Is this worth my finite hours?"
- "Learning" — "Every project is an experiment. Optimize for skills and knowledge gained"
- "Impact" — "Will this change something for real people? Meaningful > profitable"
- "Freedom" — "Does this increase or decrease my optionality and independence?"

Question 3: "Which stacks do you work with?"
Header: "Stacks"
multiSelect: true
Options:
- "Next.js + Supabase" — "Next.js 16, React 19, Tailwind 4, shadcn-ui, Supabase, Drizzle"
- "iOS Swift" — "SwiftUI, CoreML, StoreKit 2, async/await"
- "Python API" — "FastAPI, Pydantic, SQLAlchemy, PostgreSQL"
- "Python ML" — "uv, Pydantic, MLX, sentence-transformers, CLI-first"
```

If user selects "Other" for stacks, ask a follow-up about which additional stacks they need from the full list:
- `kotlin-android` — Jetpack Compose, Room, Koin
- `cloudflare-workers` — Hono, D1, R2, Durable Objects
- `astro-static` — Astro 5, Cloudflare Pages
- `nextjs-ai-agents` — extends Next.js + Vercel AI SDK
- `python-scraper` — curl_cffi, playwright, BeautifulSoup

### 8. Load default templates

Find the templates directory. Check these locations in order:
1. Skill's own repo: look for `templates/` relative to this SKILL.md (traverse up to find `solo-factory/templates/`)
2. If nothing found: use inline defaults from this skill

Read the default files:
- `templates/principles/manifest.md`
- `templates/principles/stream-framework.md`
- `templates/principles/dev-principles.md`
- `templates/stacks/*.yaml` (list available stacks)

### 9. Generate personalized files

Create `.solo/` directory in the project path.

#### 9a. Generate `manifest.md`

Read the default `templates/principles/manifest.md`. Generate a PERSONALIZED version based on Round 1 answers:

- **Motivation** answers → "Why I Build" section
- **Hard no's** answers → "What I Won't Build" section
- **Data philosophy** answer → "Data & Privacy" section
- **Pricing** answer → "Pricing Philosophy" section

Keep the structure of the template but rewrite sections to reflect the founder's specific choices. Keep the "Principles" section (AI is foundation, Offline-first, One pain → one feature, Speed over perfection, Antifragile architecture) but adjust emphasis based on answers. For example:
- If they chose "Privacy & data ownership" → emphasize "Privacy isn't a feature, it's architecture"
- If they chose "Speed to market" → emphasize "Ship > Perfect"
- If they chose "Cloud-first" → soften offline-first language, emphasize encryption instead

The generated manifest should feel personal, not templated. Use active voice, first person.

#### 9b. Generate `stream-framework.md`

Read the default `templates/principles/stream-framework.md`. Copy it as-is BUT add a personalized "My Calibration" section at the top based on Round 3 answers:

```markdown
## My Calibration

- **Risk style:** [their answer]
- **Ultimate filter:** [their answer]
- **Default approach:** [derived from answers]
```

For example:
- "Barbell" + "Time" → "Default: 90% proven tech, 10% experiments. Kill anything not worth the hours."
- "Move fast" + "Learning" → "Default: ship first, learn from feedback. Every failure is data."

Keep the full 6-layer framework and 5-step decision process unchanged — these are universal.

#### 9c. Generate `dev-principles.md`

Read the default `templates/principles/dev-principles.md`. Copy it but personalize the "Development Workflow" section based on Round 2 answers:

- **TDD** answer → set TDD level in workflow section
- **Infrastructure** answer → adjust Infrastructure & DevOps section emphasis
- **Commits** answer → set commit style in workflow
- **Docs** answer → adjust Documentation section

All other sections (SOLID, DRY, KISS, DDD, Clean Architecture, SGR, i18n, etc.) stay as-is — they're universal.

#### 9d. Copy selected stacks

For each stack selected in Round 3, copy the YAML file from `templates/stacks/` to `.solo/stacks/`.

Map the answers:
- "Next.js + Supabase" → `nextjs-supabase.yaml`
- "iOS Swift" → `ios-swift.yaml`
- "Python API" → `python-api.yaml`
- "Python ML" → `python-ml.yaml`
- "Kotlin Android" → `kotlin-android.yaml`
- "Cloudflare Workers" → `cloudflare-workers.yaml`
- "Astro Static" → `astro-static.yaml`
- "Next.js AI Agents" → `nextjs-ai-agents.yaml`
- "Python Scraper" → `python-scraper.yaml`

### 10. Verify Solograph MCP (optional check)

- Try reading `~/.solo/registry.yaml`
- If exists: "Solograph detected — code graph ready"
- If not: "Tip: install Solograph for code search across projects (`pip install solograph`)"

### 11. Summary

```
Solo Factory initialized!

Org config:
  Config:         ~/.solo-factory/defaults.yaml
  org_domain:     <value>
  apple_dev_team: <value>
  github_org:     <value>
  projects_dir:   <value>

Founder profile:
  Manifest:       .solo/manifest.md
  Dev Principles: .solo/dev-principles.md
  STREAM:          .solo/stream-framework.md
  Stacks:         .solo/stacks/ (N stacks)

These files are yours — edit anytime.
Other skills read from .solo/ automatically.

Next steps:
  /validate "your idea"          — validate with your manifest
  /scaffold app nextjs-supabase  — scaffold with your stack
```

### Edge cases

- If `~/.solo-factory/defaults.yaml` exists but `.solo/` doesn't — ask if they want to skip org defaults and just do founder profile
- If `.solo/` already exists — ask: "Reconfigure from scratch?" or "Keep existing and skip?"
- If templates directory not found — generate from inline knowledge (this skill has all the context needed)
- If user answers "Other" to any question — use their free-text input in generation
- For stacks, always show what was NOT selected: "Other available stacks: ... (run /init again to add)"

## Common Issues

### Templates directory not found
**Cause:** solo-factory not installed as submodule or templates moved.
**Fix:** Skill generates from inline knowledge if templates missing. To fix permanently, ensure `solo-factory/templates/` exists.

### Stacks not copied to .solo/
**Cause:** Stack selection answer didn't map to a template file.
**Fix:** Check available stacks in `templates/stacks/`. Re-run `/init` and select from the list.

### defaults.yaml already exists
**Cause:** Previously initialized.
**Fix:** Skill detects existing config and asks whether to reconfigure. Choose "Reconfigure from scratch" to overwrite.
