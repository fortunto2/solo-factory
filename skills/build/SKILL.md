---
name: solo-build
description: Execute implementation plan tasks with TDD workflow, auto-commit, and phase gates. Use when user says "build it", "start building", "execute plan", "implement tasks", "ship it", or references a track ID. Do NOT use for planning (use /plan) or scaffolding (use /scaffold).
license: MIT
metadata:
  author: fortunto2
  version: "2.2.0"
allowed-tools: Read, Grep, Bash, Glob, Write, Edit, AskUserQuestion, mcp__solograph__session_search, mcp__solograph__project_code_search, mcp__solograph__codegraph_query
argument-hint: "[track-id] [--task X.Y] [--phase N]"
---

# /build

Execute tasks from an implementation plan. Finds `plan.md` (in `docs/plan/` for projects or `4-opportunities/` for KB), picks the next unchecked task, implements it with TDD workflow, commits, and updates progress.

## When to use

After `/plan` has created a track with `spec.md` + `plan.md`. This is the execution engine.

Pipeline: `/plan` → **`/build`** → `/deploy` → `/review`

## MCP Tools (use if available)

- `session_search(query)` — find how similar problems were solved before
- `project_code_search(query, project)` — find reusable code across projects
- `codegraph_query(query)` — check file dependencies, imports, callers

If MCP tools are not available, fall back to Glob + Grep + Read.

## Pre-flight Checks

1. **Detect context** — find where plan files live:
   - Check `docs/plan/*/plan.md` — project context (standard location)
   - Check `4-opportunities/*/plan.md` — KB context (solopreneur only)
   - Use whichever exists. If both, prefer `docs/plan/`.
   - **DO NOT** search for `conductor/` or any other directory — only `docs/plan/` and `4-opportunities/`.

2. Load workflow config from `docs/workflow.md` (if exists):
   - TDD strictness (strict / moderate / none)
   - Commit strategy (conventional commits format)
   - Verification checkpoint rules
   If `docs/workflow.md` missing: use defaults (moderate TDD, conventional commits).

## Track Selection

### If `$ARGUMENTS` contains a track ID:
- Validate: `{plan_root}/{argument}/plan.md` exists (check both `docs/plan/` and `4-opportunities/`).
- If not found: search `docs/plan/*/plan.md` and `4-opportunities/*/plan.md` for partial matches, suggest corrections.

### If `$ARGUMENTS` contains `--task X.Y`:
- Jump directly to that task in the active track.

### If no argument:
1. Search for `plan.md` files in `docs/plan/` and `4-opportunities/`.
2. Read each `plan.md`, find tracks with uncompleted tasks.
3. If multiple, ask via AskUserQuestion.
4. If zero tracks: "No plans found. Run `/plan` first."

## Context Loading

Load in parallel:
1. `docs/plan/{trackId}/spec.md` — requirements, acceptance criteria
2. `docs/plan/{trackId}/plan.md` — task list with checkboxes
3. `docs/workflow.md` — TDD policy, commit strategy (if exists)
4. `CLAUDE.md` — architecture, Do/Don't

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

## Task Execution Loop

For each incomplete task in plan.md (marked `[ ]`), in order:

### 1. Find Next Task

Parse plan.md for first line matching `- [ ] Task X.Y:` (or `- [~] Task X.Y:` if resuming).

### 2. Start Task

- Update plan.md: `[ ]` → `[~]` for current task.
- Announce: **"Starting Task X.Y: {description}"**

### 3. Research (quick, before coding)

Before implementing, do a quick search:
- Grep project for relevant keywords from the task description.
- If MCP available: `session_search("{task keywords}")` — check if you solved this before.
- If MCP available: `project_code_search("{pattern}")` — find reusable code.
- Read files that the task mentions (file paths in task description).

This takes 10-30 seconds and prevents reinventing the wheel.

### 4. TDD Workflow (if TDD enabled in workflow.md)

**Red — write failing test:**
- Create/update test file for the task functionality.
- Run tests to confirm they fail.

**Green — implement:**
- Write minimum code to make the test pass.
- Run tests to confirm pass.

**Refactor:**
- Clean up while tests stay green.
- Run tests one final time.

### 5. Non-TDD Workflow (if TDD is "none" or "moderate" and task is simple)

- Implement the task directly.
- Run existing tests to check nothing broke.
- For "moderate": write tests for business logic and API routes, skip for UI/config.

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

**Update plan.md** — mark task done and append SHA:
- `[~]` → `[x]` for completed task
- Append commit SHA inline: `- [x] Task X.Y: description <!-- sha:abc1234 -->`

This enables reverting individual tasks later via `git revert <sha>`.

If task required multiple commits, record the last one (it covers the full change).

### 7. Phase Completion Check

After each task, check if all tasks in current phase are `[x]`.

If phase complete:

1. Run verification steps listed under `### Verification` for the phase.
2. Run full test suite.
3. Run linter.
4. Mark verification checkboxes in plan.md: `- [ ]` → `- [x]`.
5. Commit plan.md progress: `git commit -m "chore(plan): complete phase {N}"`.
6. Capture checkpoint SHA and append to phase heading in plan.md:
   `## Phase N: Title <!-- checkpoint:abc1234 -->`.
7. Report results and **wait for user approval**:

```
Phase {N} complete! <!-- checkpoint:abc1234 -->

  Tasks:  {M}/{M}
  Tests:  {pass/fail}
  Linter: {pass/fail}
  Verification:
    - [x] {check 1}
    - [x] {check 2}

  Revert this phase: git revert abc1234..HEAD

Continue to Phase {N+1}?
```

**CRITICAL: Always wait for user approval before proceeding to next phase.**

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
- Run full test suite.
- Run linter.
- Check acceptance criteria from spec.md.

### 2. Update plan.md header

Change `**Status:** [ ] Not Started` → `**Status:** [x] Complete` at the top of plan.md.

### 3. Create completion marker

Write a `BUILD_COMPLETE` file in the track directory:
```bash
echo "Track: {trackId}" > {plan_root}/{trackId}/BUILD_COMPLETE
echo "Completed: $(date -u +%Y-%m-%dT%H:%M:%SZ)" >> {plan_root}/{trackId}/BUILD_COMPLETE
```
This file signals to the pipeline that the build stage is finished.

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

## Critical Rules

1. **NEVER skip phase checkpoints** — always wait for user approval between phases.
2. **STOP on failure** — do not continue past test failures or errors.
3. **Keep plan.md updated** — task status must reflect actual progress at all times.
4. **Commit after each task** — atomic commits with conventional format.
5. **Research before coding** — 30 seconds of search saves 30 minutes of reimplementation.
6. **One task at a time** — finish current task before starting next.
7. **Keep test output concise** — when running tests, pipe through `head -50` or use `--reporter=dot` / `-q` flag. Thousands of test lines pollute context. Only show failures in detail.

## Common Issues

### "No plans found"
**Cause:** No `plan.md` exists in `docs/plan/` or `4-opportunities/`.
**Fix:** Run `/plan "your feature"` first to create a track.

### Tests failing after task
**Cause:** Implementation broke existing functionality.
**Fix:** Use the error handling flow — attempt fix, rollback if needed, pause for user input. Never skip failing tests.

### Phase checkpoint skipped
**Cause:** Model proceeded without user approval.
**Fix:** Phase gates are mandatory. If skipped, re-run verification for that phase before continuing.
