---
name: solo-github-outreach
description: Use when "github outreach", "competitor dependents", "dependents scan", "propose our lib", or targeting users of competitor libraries. NOT for Reddit (/reddit) or social copy (/content-gen).
license: MIT
metadata:
  author: fortunto2
  version: "1.0.0"
  openclaw:
    emoji: "🎯"
allowed-tools: Read, Grep, Glob, Write, Edit, Bash, AskUserQuestion, WebSearch, WebFetch, mcp__solograph__web_search, mcp__solograph__project_info
argument-hint: "<command> — commands: setup, enrich, evaluate, draft, status, next"
---

# /github-outreach

Competitive outreach pipeline. Scan a competitor's dependents, evaluate which repos would benefit from switching to your library, and draft personalized GitHub issues.

Works with any crate/package — not specific to any product.

## Scripts

Use these instead of reimplementing from scratch:

- `scripts/init_jsonl.py <repos.txt> <out.jsonl>` — convert repo list to JSONL
- `scripts/enrich.py <jsonl> [--batch 30]` — add stars/description via `gh api`, skip forks/archived
- `scripts/evaluate.py <jsonl> <owner/repo>` — deep-evaluate a repo (README + Cargo.toml + feature detection)
- `scripts/evaluate.py <jsonl> --next` — pick next highest-star enriched repo
- `scripts/status.py <jsonl> [--targets] [--csv]` — show pipeline status table

## Data Format

All data lives in `data/outreach/{competitor}/` in the project directory:

```
data/outreach/{competitor}/
  config.json          # Competitor, our product, feature matrix
  dependents.jsonl     # One JSON object per repo (append-only)
  progress.json        # Cursor: last evaluated index, stats
```

### dependents.jsonl schema

Each line is a JSON object:

```json
{
  "repo": "owner/name",
  "stars": 1234,
  "description": "...",
  "language": "Rust",
  "last_push": "2026-03-20T...",
  "archived": false,
  "phase": "raw|enriched|evaluated|drafted|posted|skipped",
  "score": 0,
  "features_used": ["streaming", "tools", "embeddings"],
  "our_advantages": ["websocket", "structured_outputs"],
  "verdict": "skip|maybe|target",
  "verdict_reason": "fork of AppFlowy, not original",
  "draft_title": "",
  "draft_body": "",
  "issue_url": "",
  "evaluated_at": "",
  "notes": ""
}
```

JSONL is append-friendly and `grep`/`jq` compatible. Render as table with `status` command.

## Routing

| User says | Action |
|-----------|--------|
| `/outreach setup` | Configure competitor + our product |
| `/outreach enrich` | Add stars/description via `gh api` |
| `/outreach next` | Evaluate next unevaluated repo |
| `/outreach evaluate [repo]` | Deep-evaluate a specific repo |
| `/outreach draft [repo]` | Generate issue text for a target |
| `/outreach status` | Show progress table |
| `/outreach batch [N]` | Evaluate next N repos (default 5) |

## Setup

First-time configuration.

1. Ask or read from `$ARGUMENTS`:
   - Competitor: crate name or `owner/repo` (e.g., `async-openai`)
   - Our product: crate name + repo URL
   - Feature matrix file path (or build interactively)

2. Create `data/outreach/{competitor}/config.json`:

```json
{
  "competitor": "async-openai",
  "competitor_repo": "64bit/async-openai",
  "our_product": "openai-oxide",
  "our_repo": "fortunto2/openai-oxide",
  "feature_matrix": {
    "persistent_websockets": {"us": true, "them": false, "impact": "high", "pitch": "..."},
    "structured_outputs": {"us": true, "them": false, "impact": "high", "pitch": "..."}
  }
}
```

3. Check if `dependents.jsonl` exists. If not, run scraper:
   ```bash
   scripts/scrape-dependents.sh {competitor_repo} 50 > /tmp/deps.txt
   ```
   Convert to JSONL with phase=raw.

## Enrich

Fast pass: add GitHub metadata to all `phase=raw` entries.

```bash
# For each raw entry, call gh api
gh api repos/{owner}/{repo} --jq '{
  stars: .stargazers_count,
  description: .description,
  language: .language,
  last_push: .pushed_at,
  archived: .archived,
  topics: .topics
}'
```

- Update phase to `enriched`
- Skip if `gh api` returns 404 (private/deleted) — set phase=skipped
- Rate limit: batch 30 per minute (authenticated), save after each batch
- Sort by stars descending for evaluation priority

## Evaluate (per repo)

Deep analysis of a single repo. This is where the agent thinks.

### Step 1: Quick filter (skip obvious non-targets)
- Archived? Skip
- Fork with <5 stars? Skip (not the original)
- Last push >1 year ago? Skip (abandoned)
- Stars <3 and no meaningful description? Skip

### Step 2: Read README
```bash
gh api repos/{owner}/{repo}/readme --jq '.content' | base64 -d
```

Understand: what does this project do? How do they use the competitor?

### Step 3: Read Cargo.toml (find usage pattern)
```bash
gh api repos/{owner}/{repo}/contents/Cargo.toml --jq '.content' | base64 -d
```

Which features do they use? What else is in their dependency tree?

### Step 3b: Check if they forked the competitor
If Cargo.toml references the competitor via `git = "..."` (not crates.io), they forked it — this is a HIGH SIGNAL:
```bash
# Find their fork
gh api repos/{fork_owner}/{competitor_name}/commits --jq '.[0:5] | .[] | "\(.sha[0:7]) \(.commit.message | split("\n")[0])"'
```
Compare their fork commits against upstream. If they added a feature we already have (e.g. schemars for structured outputs), that's our strongest pitch: "you can drop the fork and use us — we have that built-in." Record exactly what they added in `notes`.

### Step 4: Grep for usage patterns (optional, for top targets)
If stars >50, clone shallow and grep:
```bash
git clone --depth 1 {url} /tmp/outreach-eval
grep -rn "async.openai\|ChatCompletion\|stream\|tool_call\|embedding" /tmp/outreach-eval/src/
rm -rf /tmp/outreach-eval
```

Map findings to feature signals (streaming, tools, structured, websocket, etc.)

### Step 5: Score and verdict

Score based on:
- Stars (weight: 30%) — reach/impact
- Activity (weight: 20%) — will they actually migrate?
- Feature fit (weight: 30%) — do our advantages matter to them?
- Approachability (weight: 20%) — open to contributions? Has issues enabled?

Verdict:
- **target** (score >= 60) — worth creating an issue
- **maybe** (score 30-59) — revisit later
- **skip** (score < 30) — not worth effort

Update JSONL entry with phase=evaluated.

### Step 6: Cleanup
Always `rm -rf /tmp/outreach-eval` after analysis.

## Draft (per repo)

Generate a personalized GitHub issue for a `target` repo.

1. Load config (feature matrix, pitches)
2. Load evaluation data (features_used, our_advantages)
3. Draft issue using `references/issue-templates.md`
4. Key rules:
   - **Never generic** — reference their specific use case
   - **Lead with their problem** — not our solution
   - **Offer concrete benefit** — "your agent loop would be 40% faster with persistent WebSockets"
   - **No hard sell** — "you might find this useful" tone
   - **Include migration path** — show how imports change
5. Save draft to JSONL entry (phase=drafted)
6. Output draft for user review before posting

## Status

Show progress across all repos.

```
Outreach: async-openai → openai-oxide

Phase       Count
─────────────────
raw            12
enriched      340
evaluated     180
  → target      8
  → maybe      47
  → skip      125
drafted         3
posted          1
skipped        59
─────────────────
Total         591

Top targets (not yet drafted):
  1. fastrepl/char (8068★) — streaming + agent loop
  2. risingwavelabs/risingwave (7000★) — embeddings
  ...
```

Read from JSONL, aggregate by phase/verdict.

## Batch Mode

Evaluate next N repos efficiently.

1. Load JSONL, filter phase=enriched, sort by stars desc
2. For each (up to N):
   - Run Evaluate flow
   - Print one-line result
   - Continue to next (no pause)
3. Print batch summary

## Critical Rules

1. **Never post issues without user approval** — draft only, user reviews
2. **Never clone repos larger than 100MB** — check size via `gh api` first
3. **Always cleanup** — `rm -rf /tmp/outreach-eval` after every evaluation
4. **Rate limit gh api** — max 30 requests per batch, save progress
5. **Respect repos** — if issues are disabled, skip. If they said no, mark as skipped
6. **One issue per repo** — never spam
7. **Personalize everything** — generic "try our lib" issues get ignored and damage reputation
8. **JSONL is append-only** — update by rewriting the line (match by repo field)

## Gotchas

1. **Forks dominate dependents** — 50%+ of dependents are forks of big projects (AppFlowy, meilisearch). Filter by checking if the repo is a fork via `gh api` `.fork` field. Only evaluate originals.
2. **gh api rate limit** — 5000/h authenticated but large scans hit it. Use `--paginate` sparingly. Check `X-RateLimit-Remaining` header.
3. **README doesn't show actual usage** — a repo may list async-openai in Cargo.toml but barely use it. Always check Cargo.toml features and grep source.
4. **Stale dependents** — GitHub's dependency graph is delayed. Some repos may have already switched away. Check Cargo.lock if available.
5. **Issue tone matters enormously** — "I noticed you use X, have you tried Y?" works. "X is slow, switch to Y" does not. See `references/issue-templates.md`.
6. **Competitor forks are the strongest signal** — if a repo uses `git = "..."` instead of crates.io, they forked the competitor because it's missing something. Check the fork diff (usually 1-3 commits). If they added a feature we already have, that's our #1 pitch — "drop your fork, we have it built-in." Example: fastrepl/char forked async-openai to add schemars → our `structured` feature does exactly that.
