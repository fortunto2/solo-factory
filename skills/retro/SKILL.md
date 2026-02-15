---
name: solo-retro
description: Post-pipeline retrospective — parse logs, score process quality, find waste patterns, suggest skill/script patches. Use after pipeline completes or when user says "retro", "evaluate pipeline", "what went wrong", "pipeline review", "check pipeline logs".
license: MIT
metadata:
  author: fortunto2
  version: "1.0.0"
allowed-tools: Read, Grep, Bash, Glob, Write, Edit, AskUserQuestion, mcp__solograph__session_search, mcp__solograph__codegraph_explain, mcp__solograph__codegraph_query
argument-hint: "[project-name]"
---

# /retro

<CRITICAL>
This skill is SELF-CONTAINED. You MUST follow ONLY the instructions in this file.
Do NOT invoke, delegate to, or spawn any other skill (no /review, /audit, /build).
Do NOT spawn Task subagents. Run all analysis yourself, directly.
</CRITICAL>

Post-pipeline retrospective. Parses Big Head pipeline logs, counts productive vs wasted iterations, identifies recurring failure patterns, scores the pipeline run, and suggests concrete patches to skills/scripts to prevent the same failures next time.

## When to use

After a Big Head pipeline completes (or gets cancelled). This is the process quality check — `/review` checks **code quality**, `/retro` checks **pipeline process quality**.

Can also be used standalone on any project that has pipeline logs.

## MCP Tools (use if available)

- `session_search(query)` — find past pipeline runs and known issues
- `codegraph_explain(project)` — understand project architecture context
- `codegraph_query(query)` — query code graph for project metadata

If MCP tools are not available, fall back to Glob + Grep + Read.

## Phase 1: Locate Artifacts

1. **Detect project** from `$ARGUMENTS` or CWD:
   - If argument provided: use it as project name
   - Otherwise: extract from CWD basename (e.g., `~/startups/active/life2film` → `life2film`)

2. **Find pipeline state file:** `~/.solo/pipelines/solo-pipeline-{project}.local.md`
   - If it exists: pipeline is still running or wasn't cleaned up — read YAML frontmatter for `project_root:`
   - If not: pipeline completed — use `~/startups/active/{project}` as project root

3. **Verify artifacts exist (parallel reads):**
   - Pipeline log: `{project_root}/.solo/pipelines/pipeline.log` (REQUIRED — abort if missing)
   - Iter logs: `{project_root}/.solo/pipelines/iter-*.log`
   - Progress file: `{project_root}/.solo/pipelines/progress.md`
   - Plan-done directory: `{project_root}/docs/plan-done/`
   - Active plan: `{project_root}/docs/plan/`

4. **Count iter logs:** `ls {project_root}/.solo/pipelines/iter-*.log | wc -l`
   - Report: "Found {N} iteration logs"

## Phase 2: Parse Pipeline Log (quantitative)

Read `pipeline.log` in full. Parse line-by-line, extracting structured data from log tags:

**Log format:** `[HH:MM:SS] TAG | message`

**Extract by tag:**

| Tag | What to extract |
|-----|----------------|
| `START` | Pipeline run boundary — count restarts (multiple START lines = restarts) |
| `STAGE` | `iter N/M \| stage S/T: {stage_id}` — iteration count per stage |
| `SIGNAL` | `<solo:done/>` or `<solo:redo/>` — which stages got completion signals |
| `INVOKE` | Skill invoked — extract skill name, check for wrong names |
| `ITER` | `commit: {sha} \| result: {stage complete\|continuing}` — per-iteration outcome |
| `CHECK` | `{stage} \| {path} -> FOUND\|NOT FOUND` — marker file checks |
| `FINISH` | `Duration: {N}m` — total duration per run |
| `MAXITER` | `Reached max iterations ({N})` — hit iteration ceiling |
| `QUEUE` | Plan cycling events (activating, archiving) |
| `CIRCUIT` | Circuit breaker triggered (if present) |
| `CWD` | Working directory changes |
| `CTRL` | Control signals (pause/stop/skip) |

**Compute metrics:**

```
total_runs = count of START lines
total_iterations = count of ITER lines
productive_iters = count of ITER lines with "stage complete"
wasted_iters = total_iterations - productive_iters
waste_pct = wasted_iters / total_iterations * 100
maxiter_hits = count of MAXITER lines
plan_cycles = count of QUEUE lines with "Cycling"

per_stage = {
  stage_id: {
    attempts: count of STAGE lines for this stage,
    successes: count of ITER lines with "stage complete" for this stage,
    waste_ratio: (attempts - successes) / attempts * 100,
  }
}
```

## Phase 3: Parse Progress.md (qualitative)

Read `progress.md` and scan for error patterns:

1. **Unknown skill errors:** grep for `Unknown skill:` — extract which skill name was wrong
2. **Empty iterations:** iterations where "Last 5 lines" show only errors or session header (no actual work done)
3. **Repeated errors:** same error appearing in consecutive iterations → spin-loop indicator
4. **Doubled signals:** `<solo:done/><solo:done/>` in same iteration → minor noise (note but don't penalize)
5. **Redo loops:** count how many times build→review→redo→build cycles occurred

For each error pattern found, record:
- Pattern name
- First occurrence (iteration number)
- Total occurrences
- Consecutive streak (max)

## Phase 4: Analyze Iter Logs (sample-based)

Do NOT read all iter logs — could be 60+. Use smart sampling:

1. **First failed iter per pattern:** For each failure pattern found in Phase 3, read the first iter log that shows it
   - Strip ANSI codes when reading: `sed 's/\x1b\[[0-9;]*m//g' < iter-NNN-stage.log | head -100`

2. **First successful iter per stage:** For each stage that eventually succeeded, read the first successful iter log
   - Look for `<solo:done/>` in the output

3. **Final review iter:** Read the last `iter-*-review.log` (the verdict)

4. **Extract from each sampled log:**
   - Tools called (count of tool_use blocks)
   - Errors encountered (grep for `Error`, `error`, `Unknown`, `failed`)
   - Signal output (`<solo:done/>` or `<solo:redo/>` present?)
   - First 5 and last 10 meaningful lines (skip blank lines)

## Phase 5: Plan Fidelity Check

For each track directory in `docs/plan-done/` and `docs/plan/`:

1. **Read spec.md** (if exists):
   - Count acceptance criteria: total `- [ ]` and `- [x]` checkboxes
   - Calculate: `criteria_met = checked / total * 100`

2. **Read plan.md** (if exists):
   - Count tasks: total `- [ ]` and `- [x]` checkboxes
   - Count phases (## headers)
   - Check for SHA annotations (`<!-- sha:... -->`)
   - Calculate: `tasks_done = checked / total * 100`

3. **Compile per-track summary:**
   - Track ID, criteria met %, tasks done %, has SHAs

## Phase 6: Git & Code Quality (lightweight)

Quick checks only — NOT a full /review:

1. **Commit count and format:**
   ```bash
   git -C {project_root} log --oneline | wc -l
   git -C {project_root} log --oneline | head -30
   ```
   - Count commits with conventional format (`feat:`, `fix:`, `chore:`, `test:`, `docs:`, `refactor:`, `build:`, `ci:`, `perf:`)
   - Calculate: `conventional_pct = conventional / total * 100`

2. **Committer breakdown:**
   ```bash
   git -C {project_root} shortlog -sn --no-merges | head -10
   ```

3. **Test status** (if test command exists in CLAUDE.md or package.json):
   - Run test suite, capture pass/fail count
   - If no test command found, skip and note "no tests configured"

4. **Build status** (if build command exists):
   - Run build, capture success/fail
   - If no build command found, skip and note "no build configured"

## Phase 7: Score & Report

Load scoring rubric from `${CLAUDE_PLUGIN_ROOT}/skills/retro/references/eval-dimensions.md`.
If plugin root not available, use the embedded weights:

**Scoring weights:**
- Efficiency (waste %): 25%
- Stability (restarts): 20%
- Fidelity (criteria met): 20%
- Quality (test pass rate): 15%
- Commits (conventional %): 5%
- Docs (plan staleness): 5%
- Signals (clean signals): 5%
- Speed (total duration): 5%

**Generate report** at `{project_root}/docs/retro/{date}-retro.md`:

```markdown
# Pipeline Retro: {project} ({date})

## Overall Score: {N}/10

## Pipeline Efficiency

| Metric | Value | Rating |
|--------|-------|--------|
| Total iterations | {N} | |
| Productive iterations | {N} ({pct}%) | {emoji} |
| Wasted iterations | {N} ({pct}%) | {emoji} |
| Pipeline restarts | {N} | {emoji} |
| Max-iter hits | {N} | {emoji} |
| Total duration | {time} | {emoji} |

## Per-Stage Breakdown

| Stage | Attempts | Successes | Waste % | Notes |
|-------|----------|-----------|---------|-------|
| scaffold | | | | |
| setup | | | | |
| plan | | | | |
| build | | | | |
| deploy | | | | |
| review | | | | |

## Failure Patterns

### Pattern 1: {name}
- **Occurrences:** {N} iterations
- **Root cause:** {analysis}
- **Wasted:** {N} iterations
- **Fix:** {concrete suggestion with file reference}

### Pattern 2: ...

## Plan Fidelity

| Track | Criteria Met | Tasks Done | SHAs | Rating |
|-------|-------------|------------|------|--------|
| {track-id} | {N}% | {N}% | {yes/no} | {emoji} |

## Code Quality (Quick)

- **Tests:** {N} pass, {N} fail (or "not configured")
- **Build:** PASS / FAIL (or "not configured")
- **Commits:** {N} total, {pct}% conventional format

## Recommendations

1. **[CRITICAL]** {patch suggestion with file:line reference}
2. **[HIGH]** {improvement}
3. **[MEDIUM]** {optimization}
4. **[LOW]** {nice-to-have}

## Suggested Patches

### Patch 1: {file} — {description}

**What:** {one-line description}
**Why:** {root cause reference from Failure Patterns}

\```diff
- old line
+ new line
\```
```

**Rating guide (use these emojis):**
- GREEN = excellent
- YELLOW = acceptable
- RED = needs attention

## Phase 8: Interactive Patching

After generating the report:

1. **Show summary** to user: overall score, top 3 failure patterns, top 3 recommendations

2. **For each suggested patch** (if any), use `AskUserQuestion`:
   - Question: "Apply patch to {file}? {one-line description}"
   - Options: "Apply" / "Skip" / "Show diff first"

3. **If "Show diff first":** display the full diff, then ask again (Apply / Skip)

4. **If "Apply":** use Edit tool to apply the change directly

5. **After all patches processed:**
   - If any patches were applied: suggest committing with `fix(retro): {description}`
   - Do NOT auto-commit — just suggest the command

## Phase 9: CLAUDE.md Revision

After patching, revise the project's CLAUDE.md to keep it lean and useful for future agents.

### Steps:

1. **Read CLAUDE.md** and check size: `wc -c CLAUDE.md`
2. **Add learnings from this retro:**
   - Pipeline failure patterns worth remembering (avoid next time)
   - New workflow rules or process improvements
   - Updated commands or tooling changes
   - Architecture decisions that emerged during the pipeline run
3. **If over 40,000 characters — trim ruthlessly:**
   - Collapse completed phase/milestone histories into one line each
   - Remove verbose explanations — keep terse, actionable notes
   - Remove duplicate info (same thing explained in multiple sections)
   - Remove historical migration notes, old debugging context
   - Remove examples that are obvious from code or covered by skill/doc files
   - Remove outdated troubleshooting for resolved issues
4. **Verify result ≤ 40,000 characters** — if still over, cut least actionable content
5. **Write updated CLAUDE.md**, update "Last updated" date

### Priority (keep → cut):
1. **ALWAYS KEEP:** Tech stack, directory structure, Do/Don't rules, common commands, architecture decisions
2. **KEEP:** Workflow instructions, troubleshooting for active issues, key file references
3. **CONDENSE:** Phase histories (one line each), detailed examples, tool/MCP listings
4. **CUT FIRST:** Historical notes, verbose explanations, duplicated content, resolved issues

### Rules:
- Never remove Do/Don't sections — critical guardrails
- Preserve overall section structure and ordering
- Every line must earn its place: "would a future agent need this to do their job?"
- Commit the update: `git add CLAUDE.md && git commit -m "docs: revise CLAUDE.md (post-retro)"`

## Signal Output

**Output signal:** `<solo:done/>`

**Important:** `/retro` always outputs `<solo:done/>` — it never needs redo. Even if pipeline was terrible, the retro itself always completes.

## Edge Cases

- **No pipeline.log:** abort with clear message — "No pipeline log found at {path}. Run a pipeline first."
- **Empty pipeline.log:** report "Pipeline log is empty — was the pipeline cancelled before any iteration?"
- **No iter logs:** skip Phase 4 sampling, note in report
- **No plan-done:** skip Phase 5, note "No completed plans found"
- **No test/build commands:** skip those checks in Phase 6, note in report
- **Pipeline still running:** warn user — "State file exists, pipeline may still be running. Retro on partial data."

## Reference Files

- `${CLAUDE_PLUGIN_ROOT}/skills/retro/references/eval-dimensions.md` — scoring rubric (8 axes, weights)
- `${CLAUDE_PLUGIN_ROOT}/skills/retro/references/failure-catalog.md` — known failure patterns and fixes
