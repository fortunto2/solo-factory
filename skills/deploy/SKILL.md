---
name: solo-deploy
description: Use when "deploy it", "push to production", "set up hosting", or after /build completes and project needs hosting. Do NOT use before build is complete.
license: MIT
metadata:
  author: fortunto2
  version: "1.2.1"
  openclaw:
    emoji: "🚀"
allowed-tools: Read, Grep, Bash, Glob, Write, Edit, mcp__solograph__session_search, mcp__solograph__project_code_search, mcp__solograph__codegraph_query
argument-hint: "[platform]"
---

# /deploy

Deploy the project to its hosting platform. Reads the stack template YAML (`templates/stacks/{stack}.yaml`) for exact deploy config (platform, CLI tools, infra tier, CI/CD, monitoring), detects installed CLI tools, sets up database and environment, pushes code, and verifies deployment is live.

## Live Context
- Branch: !`git branch --show-current 2>/dev/null`
- Uncommitted: !`git status --short 2>/dev/null | wc -l | tr -d ' '` files
- Last commit: !`git log --oneline -1 2>/dev/null`

## References

- `templates/principles/dev-principles.md` — CI/CD, secrets, DNS, shared infra rules
- `dev-principles-my.md` (if exists) — personal infra extensions (auth, tunnels, monitoring)
- `templates/stacks/*.yaml` — Stack templates with deploy, infra, ci_cd, monitoring fields

> Paths are relative to the skill's plugin root. Search for these files via Glob if not found at expected location.

## When to use

After `/build` has completed all tasks (build stage is complete). This is the deployment engine.

Pipeline: `/build` → **`/deploy`** → `/review`

## MCP Tools (use if available)

- `session_search(query)` — find how similar projects were deployed before
- `project_code_search(query, project)` — find deployment patterns across projects
- `codegraph_query(query)` — check project dependencies and stack

If MCP tools are not available, fall back to Glob + Grep + Read.

## Pre-flight Checks

### 0. Check if deploy is needed

Read `docs/workflow.md` (if exists). If it contains "No deploy" or "no deploy stage" or "ship = commit":
- Output: "Deploy skipped — workflow.md says no deploy stage (CLI/local project)."
- Output `<solo:done/>` immediately.
- Do NOT proceed with any deploy steps.

Also: if project has NO deploy infrastructure (no Dockerfile, no deploy.sh, no wrangler.toml, no vercel.json, no sst.config.ts) AND workflow.md exists:
- Same: skip deploy, output done.

### 1. Verify build is complete (optional)
- If pipeline state tracking exists (`.solo/states/` directory), check `.solo/states/build`.
- If `.solo/states/` exists but `build` marker is missing: warn "Build may not be complete. Consider running `/build` first."
- If `.solo/states/` does not exist: skip this check and proceed with deployment.

### 2. Detect available CLI tools

Run in parallel — detect what's installed locally:
```bash
vercel --version 2>/dev/null && echo "VERCEL_CLI=yes" || echo "VERCEL_CLI=no"
wrangler --version 2>/dev/null && echo "WRANGLER_CLI=yes" || echo "WRANGLER_CLI=no"
npx supabase --version 2>/dev/null && echo "SUPABASE_CLI=yes" || echo "SUPABASE_CLI=no"
fly version 2>/dev/null && echo "FLY_CLI=yes" || echo "FLY_CLI=no"
sst version 2>/dev/null && echo "SST_CLI=yes" || echo "SST_CLI=no"
gh --version 2>/dev/null && echo "GH_CLI=yes" || echo "GH_CLI=no"
cargo --version 2>/dev/null && echo "CARGO_CLI=yes" || echo "CARGO_CLI=no"
```

Record which tools are available. Use them directly when found — do NOT `npx` if CLI is already installed globally.

### 3. Load project context (parallel reads)
- `CLAUDE.md` — stack name, architecture, deploy platform
- `docs/prd.md` — product requirements, deployment notes
- `docs/workflow.md` — CI/CD policy (if exists)
- `package.json` or `pyproject.toml` — dependencies, scripts
- `wrangler.toml`, `sst.config.ts`, `vercel.json` — platform configs (if exist)
- `docs/plan/*/plan.md` — **active plan** (look for deploy-related phases/tasks)

**Plan-driven deploy:** If the active plan contains deploy phases or tasks (e.g. "deploy Python backend to VPS", "run deploy.sh", "set up Docker on server"), treat those as **primary deploy instructions**. The plan knows the project-specific deploy targets that the generic stack YAML may not cover. Execute plan deploy tasks in addition to (or instead of) the standard platform deploy below.

### 3b. Detect project type

Classify the project to select the right deploy strategy:

| Signal | Project Type | Deploy Target |
|--------|-------------|---------------|
| `package.json` + `next.config.*` | web (Next.js) | Vercel / CF Pages |
| `wrangler.toml` | web (Workers) | Cloudflare Workers |
| `Cargo.toml` + `[lib]` only | library (Rust crate) | crates.io |
| `Cargo.toml` + `[[bin]]` only | CLI/TUI tool | crates.io + GitHub Releases |
| `Cargo.toml` + `[[bin]]` + `[lib]` | library + CLI | crates.io + GitHub Releases |
| `pyproject.toml` + `[project.scripts]` | CLI (Python) | PyPI |
| `pyproject.toml` (no scripts, no web) | library (Python) | PyPI |
| `*.xcodeproj` | iOS app | App Store (manual) |

**For CLI/TUI/library projects:** skip web deploy steps (Vercel, CF, etc.) — go directly to package registry deploy (crates.io, PyPI, npm).

### 3c. Cross-compile compatibility check (Rust/native projects)

**When:** `Cargo.toml` exists AND CI/CD will build on a different architecture (e.g., GitHub Actions x86_64 vs local Apple Silicon).

```bash
# Check for native/system dependencies that may fail cross-compile
grep -r 'links\s*=' Cargo.toml 2>/dev/null         # C library bindings
grep -r 'build\s*=' Cargo.toml 2>/dev/null          # build.rs (may compile C code)
grep -rn 'sys' Cargo.toml 2>/dev/null | grep -v '#' # *-sys crates (native bindings)
```

**Known cross-compile risks:**
- `ort-sys` / `onnxruntime-sys` — no prebuilt binaries for all targets, requires local build
- `ffmpeg-sys` / `ffmpeg-next` — needs FFmpeg installed on CI runner
- `openssl-sys` — use `rustls` instead for pure-Rust TLS
- Any `*-sys` crate — check if prebuilt binaries exist for CI target architecture

**If risky deps found:**
1. Check if CI matrix includes the required target (`.github/workflows/*.yml`)
2. Recommend adding cross-compile toolchain to CI, OR
3. Recommend replacing native dep with pure-Rust alternative, OR
4. Add the dep to CI install step: `apt-get install` / `brew install`
5. Report in deploy summary which deps may block CI

### 4. Read stack template YAML

Extract the **stack name** from `CLAUDE.md` (look for `stack:` field or tech stack section).

Read the stack template to get exact deploy configuration:

**Search order** (first found wins):
1. `templates/stacks/{stack}.yaml` — relative to this skill's plugin root
2. `.solo/stacks/{stack}.yaml` — user's local overrides (from `/init`)
3. Search via Glob for `**/stacks/{stack}.yaml` in project or parent directories

Extract these fields from the YAML:
- `deploy` — target platform(s): `vercel`, `cloudflare_workers`, `cloudflare_pages`, `docker`, `hetzner`, `app_store`, `play_store`, `local`
- `deploy_cli` — CLI tools and their use cases (e.g. `vercel (local preview, env vars, promote)`)
- `infra` — infrastructure tool and tier (e.g. `sst (sst.config.ts) — Tier 1`)
- `ci_cd` — CI/CD system (e.g. `github_actions`)
- `monitoring` — monitoring/analytics (e.g. `posthog`)
- `database` / `orm` — database and ORM if any (affects migration step)
- `storage` — storage services if any (R2, D1, KV, etc.)
- `notes` — stack-specific deployment notes

**Use the YAML values as the source of truth** for all deploy decisions below. The YAML overrides the fallback tier matrix.

### 5. Detect platform (fallback if no YAML)

If stack YAML was not found, use this fallback matrix:

| Stack | Platform | Tier |
|-------|----------|------|
| `nextjs-supabase` / `nextjs-ai-agents` | Vercel + Supabase | Tier 1 |
| `cloudflare-workers` | Cloudflare Workers (wrangler) | Tier 1 |
| `astro-static` / `astro-hybrid` | Cloudflare Pages (wrangler) | Tier 1 |
| `python-api` | Cloudflare Workers (MVP) or Pulumi + Hetzner (production) | Tier 1/2 |
| `python-ml` | skip (CLI tool, no hosting needed) | — |
| `rust-native` | crates.io (library/CLI crate) or binary release (GitHub Releases) | Tier 1 |
| `ios-swift` | skip (App Store is manual) | — |
| `kotlin-android` | skip (Play Store is manual) | — |

If `$ARGUMENTS` specifies a platform, use that instead of auto-detection or YAML.

**Auto-deploy platforms** (from YAML `deploy` field or fallback):
- `vercel` / `cloudflare_pages` — auto-deploy on push. Push to GitHub is sufficient if project is already linked. Only run manual deploy for initial setup.
- `cloudflare_workers` — `wrangler deploy` needed (no git-based auto-deploy for Workers).
- `docker` / `hetzner` — manual deploy via SSH or Pulumi.

## Deployment Steps

### Step 1. Git — Clean State + Push

```bash
git status
git log --oneline -5
```

If dirty, commit remaining changes:
```bash
git add -A
git commit -m "chore: pre-deploy cleanup"
```

Ensure remote exists and push:
```bash
git remote -v
git push origin main
```

If no remote, create GitHub repo:
```bash
gh repo create {project-name} --private --source=. --push
```

**For platforms with auto-deploy (Vercel, CF Pages):** pushing to main triggers deployment automatically. Skip manual deploy commands if project is already linked.

### Step 2. Database Setup

**Supabase** (if `supabase/` dir or Supabase deps detected):
```bash
# If supabase CLI available:
supabase db push          # apply migrations
supabase gen types --lang=typescript --local > db/types.ts  # optional: regenerate types
```
If no CLI: guide user to Supabase dashboard for migration.

**Drizzle ORM** (if `drizzle.config.ts` exists):
```bash
npx drizzle-kit push      # push schema to database
npx drizzle-kit generate  # generate migration files (if needed)
```

**D1 (Cloudflare)** (if `wrangler.toml` has D1 bindings):
```bash
wrangler d1 migrations apply {db-name}
```

If database is not configured yet, list what's needed and continue — don't block on it.

### Step 3. Environment Variables

Read `.env.example` or `.env.local.example` to identify required variables.

Generate platform-specific instructions:

**Vercel:**
```bash
# If vercel CLI is available and project is linked:
vercel env ls  # show current env vars

# Guide user:
echo "Set env vars: vercel env add VARIABLE_NAME"
echo "Or via dashboard: https://vercel.com/[team]/[project]/settings/environment-variables"
```

**Cloudflare:**
```bash
wrangler secret put VARIABLE_NAME  # interactive prompt for value
# Or in wrangler.toml [vars] section for non-secret values
```

**Do NOT create or modify `.env` files with real secrets.**
List what's needed, let user set values.

### Step 4. Platform Deploy

See `references/platform-commands.md` for full deploy, env var, and log commands per platform.

Use the detected platform from pre-flight checks:
- **Vercel** — `vercel link` → `vercel` (preview) → `vercel --prod`
- **Cloudflare Workers** — `wrangler deploy`
- **Cloudflare Pages** — `wrangler pages deploy ./out`
- **SST** — `sst deploy --stage prod`

For auto-deploy platforms (Vercel, CF Pages): `git push origin main` is sufficient if already linked.

### Step 4b. Rust/Crates.io Deploy

**Detect:** `Cargo.toml` exists at project root AND cargo CLI is available.

**Determine deploy target** from Cargo.toml:
- If `[lib]` section exists or crate is a library → **crates.io publish**
- If only `[[bin]]` → **binary release** (GitHub Releases)
- If both → do both (publish crate + attach binary to release)

**Pre-publish checklist:**
```bash
# 1. Verify tests + clippy pass
cargo test
cargo clippy --all-targets -- -D warnings

# 2. Check Cargo.toml has required fields for crates.io
grep -E '^(name|version|description|license|repository)' Cargo.toml

# 3. Dry run publish
cargo publish --dry-run
```

**Required Cargo.toml fields** for crates.io (fail without them):
- `name`, `version`, `description`, `license` (or `license-file`), `repository`

If missing fields: add them, commit, then proceed.

**Publish to crates.io:**
```bash
# Check if already published at this version
CRATE_NAME=$(grep '^name' Cargo.toml | head -1 | sed 's/.*= *"//' | sed 's/".*//')
CRATE_VER=$(grep '^version' Cargo.toml | head -1 | sed 's/.*= *"//' | sed 's/".*//')

# Publish (requires `cargo login` — if not authenticated, note in report and skip)
cargo publish
```

**If publish fails:**
- `already uploaded` → version already exists, bump version in Cargo.toml
- `not logged in` → note in report: "Run `cargo login` with crates.io API token"
- `dependency not on crates.io` → check path/git dependencies, replace with crates.io versions

**Binary release (optional, for CLI tools):**
```bash
# Build release binary
cargo build --release

# Create GitHub release with binary attached
BINARY_NAME=$(grep '^name' Cargo.toml | head -1 | sed 's/.*= *"//' | sed 's/".*//')
gh release create "v${CRATE_VER}" --title "v${CRATE_VER}" --generate-notes \
  "target/release/${BINARY_NAME}#${BINARY_NAME}-$(uname -s)-$(uname -m)"
```

**Verify crate on crates.io:**
```bash
# Wait a few seconds for index to update, then check
curl -s "https://crates.io/api/v1/crates/${CRATE_NAME}/${CRATE_VER}" | head -100
```

### Step 5. Verify Deployment

After deployment, verify it actually works:

```bash
STATUS=$(curl -s -o /dev/null -w "%{http_code}" https://{deployment-url})
BODY=$(curl -s https://{deployment-url} | head -200)
```

**If HTTP status is not 200:** check env vars, fix, redeploy. See `references/platform-commands.md` for platform-specific env var and error resolution commands.

**Do NOT output `<solo:done/>` until the live URL returns HTTP 200 and page loads without errors.** If you cannot fix the issue, output `<solo:redo/>` to go back to build. Output pipeline signals ONLY if `.solo/states/` directory exists.

### Step 6. Post-Deploy Log Monitoring

After verifying HTTP 200, **tail production logs** to catch runtime errors. See `references/platform-commands.md` for platform-specific log commands and what to look for.

**What to do with log errors:**
- **Env var missing** → fix with platform CLI (see Step 3), redeploy
- **DB connection error** → check connection string, IP allowlist
- **Runtime crash / unhandled error** → if `.solo/states/` exists, output `<solo:redo/>` to go back to build with fix; otherwise fix and redeploy
- **No errors in 30 lines of logs** → proceed to report

**If logs show zero traffic (fresh deploy), make a few test requests:**
```bash
curl -s https://{deployment-url}/           # homepage
curl -s https://{deployment-url}/api/health  # API health (if exists)
```
Then re-check logs for any errors triggered by these requests.

### Step 7. Post-Deploy Report

```
Deployment: {project-name}

  Platform:  {platform}
  URL:       {deployment-url}
  Branch:    main
  Commit:    {sha}

  Done:
    - [x] Code pushed to GitHub
    - [x] Deployed to {platform}
    - [x] Database migrations applied (or N/A)

  Manual steps remaining:
    - [ ] Set environment variables (listed above)
    - [ ] Custom domain (optional)
    - [ ] PostHog / analytics setup (optional)

  Next: /review — final quality gate
```

## Completion

### Signal completion

If `.solo/states/` directory exists, output this exact tag ONCE and ONLY ONCE — the pipeline detects the first occurrence:
```
<solo:done/>
```
**Do NOT repeat the signal tag anywhere else in the response.** One occurrence only.
If `.solo/states/` directory does not exist, skip the signal tag.

## Error Handling

### CLI not found
**Cause:** Platform CLI not installed.
**Fix:** Install the specific CLI: `npm i -g vercel`, `npm i -g wrangler`, `brew install supabase/tap/supabase`.

### Deploy fails — build error
**Cause:** Build works locally but fails on platform (different Node version, missing env vars).
**Fix:** Check platform build logs. Ensure `engines` in package.json matches platform. Set missing env vars.

### Database connection fails
**Cause:** DATABASE_URL not set or network rules block connection.
**Fix:** Check connection string, platform's DB dashboard, IP allowlist.

### Git push rejected
**Cause:** Remote has diverged.
**Fix:** `git pull --rebase origin main`, resolve conflicts, push again.

## Verification Gate

Before reporting "deployment successful":
1. **Run** `curl -s -o /dev/null -w "%{http_code}"` against the deployment URL.
2. **Verify** HTTP 200 (not 404, 500, or redirect loop).
3. **Check** the actual page content matches expectations (not a blank page or error).
4. **Only then** report the deployment as successful.

Never say "deployment should be live" — verify it IS live.

## Pipeline / Autonomous Mode

When running in a pipeline (`--print`, no human watching):

1. **NEVER call AskUserQuestion** — responses are lost between iterations, causing infinite retry loops (observed: 5 wasted iterations on OpenWok deploy)
2. **Make autonomous deploy decisions:**
   - No deploy CLI installed → install via brew/npm if possible, otherwise create Dockerfile + .dockerignore, push code, mark "Ready for manual deploy"
   - No auth/credentials → create all deploy configs, push to GitHub, write state file with auth instructions, signal done
   - Multiple platform options → pick based on: stack YAML > Next.js/React → Vercel, Python → Cloudflare Workers (MVP) or Hetzner (prod), static → Cloudflare Pages
3. **Skip over blockers** — browser login, manual approval, missing API keys → note in report, continue
4. **Always signal completion** — partial deploy (configs created + code pushed) is better than infinite retry. Output `<solo:done/>` even if actual deployment requires manual auth step.

## Critical Rules

1. **Use installed CLIs** — detect `vercel`, `wrangler`, `supabase`, `fly`, `sst` before falling back to `npx`.
2. **Auto-deploy aware** — if platform auto-deploys on push, just push. Don't run manual deploy commands unnecessarily.
3. **NEVER commit secrets** — no .env files with real values, no API keys in code.
4. **Preview before production** — deploy preview first, verify, then promote to prod.
5. **Check build locally first** — `pnpm build` / `uv build` (or equivalent) before deploying.
6. **Check production logs** — always tail logs after deploy, catch runtime errors before declaring success.
7. **Report all URLs** — deployment URL + platform dashboard links.
8. **Infrastructure in repo** — prefer `sst.config.ts` or `wrangler.toml` over manual dashboard config.
9. **Verify before claiming done** — HTTP 200 from the live URL + clean logs, not just "deploy command succeeded".
