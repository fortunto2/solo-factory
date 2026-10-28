---
name: solo-build
description: Use when "build it", "start building", "execute plan", "implement tasks", "ship it", track ID referenced, or plan tasks need execution. Do NOT use for planning (/plan) or scaffolding (/scaffold).
license: MIT
metadata:
  author: fortunto2
  version: "2.5.0"
  openclaw:
    emoji: "🔨"
allowed-tools: Read, Grep, Bash, Glob, Write, Edit, AskUserQuestion, mcp__solograph__session_search, mcp__solograph__symbol_search, mcp__solograph__codegraph_shared, mcp__searxng__web_search, mcp__context7__resolve-library-id, mcp__context7__query-docs
argument-hint: "[track-id] [--task X.Y] [--phase N]"
---

# /build

This skill is self-contained — follow the task loop, test rules, and completion flow below instead of delegating to external build/execution skills (superpowers, etc.).

Execute tasks from an implementation plan. Finds `plan.md` (in `docs/plan/`), picks the next unchecked task, implements it with tests at agreed seams, commits, and updates progress.

## Live Context
- Branch: !`git branch --show-current 2>/dev/null`
- Status: !`git status --short 2>/dev/null | head -10`
- Last commit: !`git log --oneline -3 2>/dev/null`

## When to use

After `/plan` has created a track with `spec.md` + `plan.md`. This is the execution engine.

Pipeline: `/plan` → **`/build`** → `/deploy` → `/review`

## MCP Tools (use if available)

- `session_search(query)` — find how similar problems were solved before
- `symbol_search("<words>")` — find reusable code across projects (symbol names, every project; Grep inside one)
- Grep — file dependencies, imports, callers (a structural graph answered these no better: measured 27 Oct 2026)

If MCP tools are not available, fall back to Glob + Grep + Read.

## Pre-flight Checks

1. **Detect context** — find where plan files live:
   - Check `docs/plan/*/plan.md` — standard location
   - Use whichever exists.
   - **DO NOT** search for `conductor/` or any other directory — only `docs/plan/`.

2. Load workflow config from `docs/workflow.md` (if exists):
   - TDD strictness (strict / moderate / none)
   - Commit strategy (conventional commits format)
   - Verification checkpoint rules
   - **Integration Testing section** — if present, run the specified CLI commands after completing tasks that touch the listed paths
   If `docs/workflow.md` missing: use defaults (moderate TDD, conventional commits).

3. **Verify git hooks are installed:**

   Read the stack YAML (`templates/stacks/{stack}.yaml`) — the `pre_commit` field tells you which system and what it runs:
   - `husky + lint-staged` → JS/TS stacks (eslint + prettier + tsc)
   - `pre-commit` → Python stacks (ruff + ruff-format + ty)
   - `lefthook` → mobile stacks (swiftlint/detekt + formatter)

   Then verify the hook system is active:
   ```bash
   # husky
   [ -f .husky/pre-commit ] && git config core.hooksPath | grep -q husky && echo "OK" || echo "NOT ACTIVE"
   # pre-commit (Python)
   [ -f .pre-commit-config.yaml ] && [ -f .git/hooks/pre-commit ] && echo "OK" || echo "NOT ACTIVE"
   # lefthook
   [ -f lefthook.yml ] && lefthook version >/dev/null 2>&1 && echo "OK" || echo "NOT ACTIVE"
   ```

   **If not active — install before first commit:**
   - husky: `pnpm prepare` (or `npm run prepare`)
   - pre-commit: `uv run pre-commit install`
   - lefthook: `lefthook install`

   Don't use `--no-verify` on commits — if hooks fail, fix the issue and commit again.

## Track Selection

### If `$ARGUMENTS` contains a track ID:
- Validate: `{plan_root}/{argument}/plan.md` exists (check `docs/plan/`).
- If not found: search `docs/plan/*/plan.md` for partial matches, suggest corrections.

### If `$ARGUMENTS` contains `--task X.Y`:
- Jump directly to that task in the active track.

### If no argument:
1. Search for `plan.md` files in `docs/plan/`.
2. Read each `plan.md`, find tracks with uncompleted tasks.
3. If multiple, ask via AskUserQuestion.
4. If zero tracks: "No plans found. Run `/plan` first."

## Context Loading

### Step 1 — Architecture overview (if MCP available)
```
codegraph_explain(project="{project name}")
```
Returns: stack, languages, directory layers, key patterns, top dependencies, files with the most definitions.


### Step 2 — Essential docs (parallel reads)
1. `docs/plan/{trackId}/plan.md` — task list (REQUIRED). **Read the `## Context Handoff` section first** — it has a compact summary of intent, key files, decisions, and risks. This is your primary orientation.
2. `docs/plan/{trackId}/spec.md` — acceptance criteria (REQUIRED)
3. `docs/workflow.md` — TDD policy, commit strategy (if exists)
4. `CLAUDE.md` — architecture, Do/Don't
5. `.solo/pipelines/progress.md` — running docs from previous iterations (if exists, pipeline-specific). Contains what was done in prior pipeline sessions: stages completed, commit SHAs, last output lines. **Use this to avoid repeating completed work.**

**Do NOT read source code files at this stage.** Only docs. Source files are loaded per-task in the execution loop (step 3 below).

## Resumption

If a task is marked `[~]` in plan.md:

```
Resuming: {track title}
Last task: Task {X.Y}: {description} [in progress]

1. Continue from where we left off
2. Restart current task
3. Show progress summary first
```

Ask via AskUserQuestion, then proceed.

## Context Engineering Rules

Read `references/context-engineering.md` for full rules on observation masking, attention positioning, and plan recitation. Key points:
- **Observation masking:** large outputs (>50 lines) → write to `scratch/`, keep 5-10 line summary
- **Attention positioning:** errors at START, history in MIDDLE, next steps at END
- **Plan recitation:** re-read plan.md at START of each task to prevent drift

## Task Execution Loop

**Makefile convention:** If `Makefile` exists in project root, **always prefer `make` targets** over raw commands. Use `make test` instead of `pnpm test`, `make lint` instead of `pnpm lint`, `make build` instead of `pnpm build`, etc. Run `make help` (or read Makefile) to discover available targets. If a `make integration` or similar target exists, use it for integration testing after pipeline-related tasks.

**IMPORTANT — All-done check:** Before entering the loop, scan plan.md for ANY `- [ ]` or `- [~]` tasks. If ALL tasks are `[x]` — skip the loop entirely and jump to **Completion** section below to run final verification and output `<solo:done/>`.

For each incomplete task in plan.md (marked `[ ]`), in order:

### 1. Find Next Task

Parse plan.md for first line matching `- [ ] Task X.Y:` (or `- [~] Task X.Y:` if resuming).

### 2. Start Task

- Update plan.md: `[ ]` → `[~]` for current task.
- Announce: **"Starting Task X.Y: {description}"**

### 3. Research (smart, before coding)

**Do NOT grep the entire project or read all source files.** Load only what this specific task needs.

**If MCP available (preferred):**
1. Grep the project for the task keywords — exact names beat any index. If the name is uncertain: `symbol_search("<words>", project="{name}")`. Read only the top 2-3 files.
2. `session_search("{task keywords}")` — check if you solved this before.
3. Grep the imports of the files you'll modify, and Grep for their module name to find who depends on them.

**If MCP unavailable (fallback):**
1. Read ONLY the files explicitly mentioned in the task description (file paths).
2. Glob for the specific module directory the task targets (e.g., `src/auth/**/*.ts`), not the entire project.
3. If the task doesn't mention files, use Grep with a narrow pattern on `src/` or `app/` — never `**/*`.

**Never do:** `Grep "keyword" .` across the whole project. This dumps hundreds of lines into context for no reason. Be surgical.

### Platform-Specific Quality Tools

Read `references/quality-tools.md` for full commands per stack. Quick reference:

| Stack | Lint | Format | Type-check | Pre-commit |
|-------|------|--------|------------|------------|
| Python | `uv run ruff check --fix .` | `uv run ruff format .` | `uv run ty check .` | `uv run pre-commit run --all-files` |
| JS/TS | `pnpm lint --fix` | `pnpm format` | `pnpm tsc --noEmit` | husky + lint-staged |
| iOS | `swiftlint lint --strict` | `swift-format` | — | lefthook |
| Android | `./gradlew detekt` | `./gradlew ktlintCheck` | — | lefthook |

Run after each task implementation, before `git commit`. If any fail, fix before proceeding.

### 4. Tests (policy from workflow.md)

Who owns the expectation decides the workflow. A red test proves something only when someone checked *why* it went red; when you write the test, run it and watch it fail, all it proves is that you ran it.

**Agree the seam first:** name the public interface this task's tests will observe, and confirm it with the user before writing a test. No test at an unconfirmed seam.

**Design before code.** Write down the data model, edge cases and contracts for the task before any code or test. In Böckeler's eval ([TDD inside the agent loop](https://martinfowler.com/articles/exploring-gen-ai/tdd-in-the-agent-loop.html), martinfowler.com, Aug 2026) this up-front design is what moved quality; a test-by-test loop let the first test fix the shape, and behaviour nobody wrote a test for was never built.

**Strict — the user owns the test.** Write the failing test at the agreed seam, show it to the user, and implement only after they confirm it tests the wanted behaviour. Then green, then refactor while tests stay green. Use this when the user asked for it in `docs/workflow.md`, or when the expectation comes from acceptance examples or a contract written before the code.

**Moderate (default) — you own the test.** No red-green ritual: implement and test together at the agreed seams, one behaviour at a time. The same eval found agent-run TDD cost 2.96x to 8.5x the tokens with no better mutation scores or design, and agents skipped or faked the red step. Test business logic and API routes; skip UI layout and config. Check the suite instead of the ritual: at the end of a phase, run the stack's mutation tool on the changed business logic if it is installed (mutmut, Stryker, cargo-mutants) and kill the surviving mutants that matter. With no mutation tool, break one line of the new logic by hand and confirm a test goes red, then restore it.

One behaviour → code + test → next (**vertical slices**). Writing all tests first then all implementation verifies imagined behaviour, not real.

Read `references/tdd-seams.md` before the first test of a feature — it covers where seams go, vertical vs horizontal slicing, and the four ways a test lies (implementation-coupled, side-channel, tautological, insensitive).

### 5. No new tests (policy "none", or a trivial task)

- Implement the task directly.
- Run existing tests to check nothing broke.

### 5.5. Integration Testing (CLI-First)

If the task touches core business logic (pipeline, algorithms, agent tools), run `make integration` (or the integration command from `docs/workflow.md`). The CLI exercises the same code paths as the UI without requiring a browser. If `make integration` fails, fix before committing.

### 5.6. Visual Verification (if browser/simulator/emulator available)

After implementation, run a quick visual smoke test if tools are available:

**Web projects (Playwright MCP or browser tools):**
If you have Playwright MCP tools or browser tools available:
1. Start the dev server if not already running (check stack YAML for `dev_server.command`)
2. Navigate to the page affected by the current task
3. Check the browser console for errors (hydration mismatches, uncaught exceptions, 404s)
4. Take a screenshot to verify the visual output matches expectations
5. If the task affects responsive layout, resize to mobile viewport (375px) and check

**iOS projects (simulator):**
If instructed to use iOS Simulator in the pipeline prompt:
1. Build for simulator: `xcodebuild -scheme {Name} -sdk iphonesimulator build`
2. Install on booted simulator: `xcrun simctl install booted {app-path}`
3. Launch and take screenshot: `xcrun simctl io booted screenshot /tmp/sim-screenshot.png`
4. Check simulator logs: `xcrun simctl spawn booted log stream --style compact --timeout 10`

**Android projects (emulator):**
If instructed to use Android Emulator in the pipeline prompt:
1. Build debug APK: `./gradlew assembleDebug`
2. Install: `adb install -r app/build/outputs/apk/debug/app-debug.apk`
3. Take screenshot: `adb exec-out screencap -p > /tmp/emu-screenshot.png`
4. Check logcat: `adb logcat '*:E' --format=time -d 2>&1 | tail -20`

**Graceful degradation:** If browser/simulator/emulator tools are not available or fail — skip visual checks entirely. Visual testing is a bonus, never a blocker. Log that it was skipped and continue with the task.

### 6. Complete Task

**Commit** (following commit strategy):
```bash
git add {specific files changed}
git commit -m "<type>(<scope>): <description>"
```

Types: `feat`, `fix`, `refactor`, `test`, `docs`, `chore`, `perf`, `style`

**Capture SHA** after commit:
```bash
git rev-parse --short HEAD
```

**SHA annotation in plan.md.** After every task commit:
1. Mark task done: `[~]` → `[x]`
2. Append commit SHA inline: `- [x] Task X.Y: description <!-- sha:abc1234 -->`

Without a SHA, there's no traceability and no revert capability. If a task required multiple commits, record the last one.

### 7. Phase Completion Check

After each task, check if all tasks in current phase are `[x]`.

If phase complete:

1. **SHA audit** — scan all `[x]` tasks in this phase. If any are missing `<!-- sha:... -->`, capture their SHA now from git log and add it. Every `[x]` task MUST have a SHA.
2. Run verification steps listed under `### Verification` for the phase.
3. Run full test suite.
4. Run linter.
5. Mark verification checkboxes in plan.md: `- [ ]` → `- [x]`.
6. Commit plan.md progress: `git commit -m "chore(plan): complete phase {N}"`.
7. Capture checkpoint SHA and append to phase heading in plan.md:
   `## Phase N: Title <!-- checkpoint:abc1234 -->`.
8. Report results and continue:

```
Phase {N} complete! <!-- checkpoint:abc1234 -->

  Tasks:  {M}/{M}
  Tests:  {pass/fail}
  Linter: {pass/fail}
  Verification:
    - [x] {check 1}
    - [x] {check 2}

  Revert this phase: git revert abc1234..HEAD
```

Proceed to the next phase automatically. No approval needed.

## Error Handling

### Test Failure
```
Tests failing after Task X.Y:
  {failure details}

1. Attempt to fix
2. Rollback task changes (git checkout)
3. Pause for manual intervention
```
Ask via AskUserQuestion. Do NOT automatically continue past failures.

## Track Completion

When all phases and tasks are `[x]`:

### 1. Final Verification
- **Run local build** — must pass before deploy:
  - Next.js: `pnpm build`
  - Python: `uv build` or `uv run python -m py_compile src/**/*.py`
  - Astro: `pnpm build`
  - Cloudflare: `pnpm build`
  - iOS: `xcodebuild -scheme {Name} -sdk iphonesimulator build`
  - Android: `./gradlew assembleDebug`
- Run full test suite.
- Run linter + type-checker.
- **Visual smoke test** (if tools available):
  - Web: start dev server, navigate to main page, check console for errors, take screenshot
  - iOS: build + install on simulator, launch, take screenshot, check logs
  - Android: build APK + install on emulator, launch, take screenshot, check logcat
  - Skip if tools unavailable — not a blocker for completion
- Check acceptance criteria from spec.md:
  - For EACH `- [ ]` criterion: verify it's met (search code, run command if specified).
  - **If criterion contains a runnable command** (`make task`, `cargo test`, benchmark, `passes N/N`) → **RUN IT.** Do NOT skip as "unverifiable".
  - Update spec.md checkboxes: `- [ ]` → `- [x]` for verified criteria.
  - If any criterion FAILS → do NOT mark plan complete. Fix or note the failure.
  - Commit spec updates: `git add docs/plan/*/spec.md && git commit -m "docs: update spec checkboxes (verified by build)"`
- **Map every criterion to the test that proves it.** Print one table in the summary,
  `criterion → test (file::name) → last result`. A criterion with no test is a red
  check, listed by name under **UNPROVEN**, even if the code looks right; a test that
  never ran in this session counts as no test. Criteria a test cannot reach (a store
  listing, a human sign-off) are listed as `manual: <who checks it>`, never silently
  ticked. Why: a checkbox ticked by reading code is the agent grading its own claim.

### Build failure escalation

If the same build/test error occurs **3+ times in a row**, STOP retrying. Instead:
1. Output the error message clearly.
2. Suggest a fix (e.g., `cargo clean`, `rm -rf node_modules`, disk space check).
3. Output `<solo:redo/>` to let review handle it.
Do NOT burn iterations on identical failures.

### 2. Update plan.md header

Change `**Status:** [ ] Not Started` → `**Status:** [x] Complete` at the top of plan.md.

### 3. Signal completion

Output pipeline signal ONLY if pipeline state directory (`.solo/states/`) exists:
```
<solo:done/>
```
**Do NOT repeat the signal tag elsewhere in the response.** One occurrence only.

### 4. Summary

```
Track complete: {title} ({trackId})

  Phases: {N}/{N}
  Tasks:  {M}/{M}
  Tests:  All passing

  Phase checkpoints:
    Phase 1: abc1234
    Phase 2: def5678
    Phase 3: ghi9012

  Revert entire track: git revert abc1234..HEAD

Next:
  /build {next-track-id}  — continue with next track
  /plan "next feature"    — plan something new
```

## Reverting Work

SHA comments in plan.md enable surgical reverts:

**Revert a single task:**
```bash
# Find SHA from plan.md: - [x] Task 2.3: ... <!-- sha:abc1234 -->
git revert abc1234
```
Then update plan.md: `[x]` → `[ ]` for that task.

**Revert an entire phase:**
```bash
# Find checkpoint from phase heading: ## Phase 2: ... <!-- checkpoint:def5678 -->
# Find previous checkpoint: ## Phase 1: ... <!-- checkpoint:abc1234 -->
git revert abc1234..def5678
```
Then update plan.md: all tasks in that phase `[x]` → `[ ]`.

**Never use `git reset --hard`** — always `git revert` to preserve history.

## Progress Tracking (TodoWrite)

At the start of a build session, create a task list from plan.md so progress is visible:

1. **On session start:** Read plan.md, find all incomplete tasks (`[ ]` and `[~]`).
2. **Create TaskCreate** for each phase with its tasks as description.
3. **TaskUpdate** as you work: `in_progress` when starting a task, `completed` when done.
4. This gives the user (and pipeline) real-time visibility into progress.

## Rationalizations Catalog

These thoughts mean STOP — you're about to cut corners:

| Thought | Reality |
|---------|---------|
| "This is too simple to test" | Simple code breaks too. Write the test. |
| "I'll add tests later" | Tests written after pass immediately — they prove nothing. |
| "I already tested it manually" | Manual tests don't persist. Automated tests do. |
| "The test framework isn't set up" | Set it up. That's part of the task. |
| "This is just a config change" | Config changes break builds. Verify. |
| "I'm confident this works" | Confidence without evidence is guessing. Run the command. |
| "Let me just try changing X" | Stop. Investigate root cause first. |
| "Tests are passing, ship it" | Tests passing ≠ acceptance criteria met. Check spec.md. |
| "I'll fix the lint later" | Fix it now. Tech debt compounds. |
| "It works on my machine" | Run the build. Verify in the actual environment. |

## Red Flags — STOP immediately if you catch yourself thinking:

- "I'll skip the test for this one" — No. Write it.
- "Let me keep the old code as reference" — Delete means delete. You'll adapt it instead of writing fresh. No exceptions.
- "I'm following the spirit, not the letter" — Violating the letter of the rules IS violating the spirit.
- "This is different because..." — It's not. Follow the process.
- "Just one more quick change before committing" — Commit what you have. Scope creep kills tracks.
- "The plan says X but Y would be better" — Follow the plan. If it's truly wrong, update plan.md FIRST, then implement.

**Foundational principle:** If you wouldn't mass-delete production data without checking, don't skip a test without evidence it's unnecessary.

## Critical Rules

1. **Run phase checkpoints** — verify tests + linter pass before moving to next phase.
2. **STOP on failure** — do not continue past test failures or errors.
3. **Keep plan.md updated** — task status must reflect actual progress at all times.
4. **Commit after each task** — atomic commits with conventional format.
5. **Research before coding** — 30 seconds of search saves 30 minutes of reimplementation.
6. **One task at a time** — finish current task before starting next.
7. **Keep test output concise** — when running tests, pipe through `head -50` or use `--reporter=dot` / `-q` flag. Thousands of test lines pollute context. Only show failures in detail. If output is large, use observation masking (write to `scratch/`, keep summary).
8. **Verify before claiming done** — run the actual command, read the full output, confirm success BEFORE marking a task complete. Never say "should work now".
9. **Recite the plan** — re-read plan.md at the start of each task. Don't rely on memory of what comes next.
10. **Three rounds, then a human** — when a reviewer (agent, `/review`, `/code-review`) and the author keep answering the same finding, stop after the third round on it: write the finding, both positions and what would settle it, and hand the decision to the human. A fourth round costs a context and decides nothing.

## Common Issues

### "No plans found"
**Cause:** No `plan.md` exists in `docs/plan/`.
**Fix:** Run `/plan "your feature"` first to create a track.

### Tests failing after task
**Cause:** Implementation broke existing functionality.
**Fix:** Use the error handling flow — attempt fix, rollback if needed, pause for user input. Never skip failing tests.

### Phase checkpoint failed
**Cause:** Tests or linter failed at phase boundary.
**Fix:** Fix failures before proceeding. Re-run verification for that phase.
