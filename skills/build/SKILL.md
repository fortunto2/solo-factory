---
name: solo-build
description: Execute implementation plan tasks with TDD workflow, auto-commit, and phase gates. Use when user says "build it", "start building", "execute plan", "implement tasks", "ship it", or references a track ID. Do NOT use for planning (use /plan) or scaffolding (use /scaffold).
license: MIT
metadata:
  author: fortunto2
  version: "2.1.0"
allowed-tools: Read, Grep, Bash, Glob, Write, Edit, AskUserQuestion, mcp__solograph__session_search, mcp__solograph__project_code_search, mcp__solograph__codegraph_query
argument-hint: "[track-id] [--task X.Y] [--phase N]"
---

# /build

Execute tasks from an implementation plan. Finds `plan.md` (in `docs/plan/` for projects or `4-opportunities/` for KB), picks the next unchecked task, implements it with TDD workflow, commits, and updates progress.

## When to use

After `/plan` has created a track with `spec.md` + `plan.md`. This is the execution engine.

Pipeline: `/plan` → **`/build`**

## MCP Tools (use if available)

- `session_search(query)` — find how similar problems were solved before
- `project_code_search(query, project)` — find reusable code across projects
- `codegraph_query(query)` — check file dependencies, imports, callers

If MCP tools are not available, fall back to Glob + Grep + Read.

## Pre-flight Checks

1. **Detect context** — find where plan files live:
   - Check `docs/plan/*/plan.md` — project context
   - Check `4-opportunities/*/plan.md` — KB context
   - Use whichever exists. If both, prefer `docs/plan/`.

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

**Update plan.md:** `[~]` → `[x]` for completed task.

### 7. Phase Completion Check

After each task, check if all tasks in current phase are `[x]`.

If phase complete:

1. Run verification steps listed under `### Verification` for the phase.
2. Run full test suite.
3. Run linter.
4. Report results and **wait for user approval**:

```
Phase {N} complete!

  Tests:   {pass/fail}
  Linter:  {pass/fail}
  Verification:
    - [x] {check 1}
    - [x] {check 2}

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

### 2. Summary

```
Track complete: {title} ({trackId})

  Phases: {N}/{N}
  Tasks:  {M}/{M}
  Tests: All passing

Next:
  /build {next-track-id}  — continue with next track
  /plan "next feature"    — plan something new
```

## Critical Rules

1. **NEVER skip phase checkpoints** — always wait for user approval between phases.
2. **STOP on failure** — do not continue past test failures or errors.
3. **Keep plan.md updated** — task status must reflect actual progress at all times.
4. **Commit after each task** — atomic commits with conventional format.
5. **Research before coding** — 30 seconds of search saves 30 minutes of reimplementation.
6. **One task at a time** — finish current task before starting next.

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
