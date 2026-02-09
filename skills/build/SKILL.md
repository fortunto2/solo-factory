---
name: solo-build
description: Ship it — execute plan tasks with TDD, auto-commit, phase gates
license: MIT
metadata:
  author: fortunto2
  version: "1.3.0"
allowed-tools: Read, Grep, Bash, Glob, Write, Edit, AskUserQuestion, mcp__codegraph__session_search, mcp__codegraph__project_code_search, mcp__codegraph__codegraph_query
argument-hint: "[track-id] [--task X.Y] [--phase N]"
---

# /build

Execute tasks from a track's implementation plan. Reads `conductor/tracks/{id}/plan.md`, picks the next unchecked task, implements it with TDD workflow, commits, and updates progress.

## When to use

After `/plan` has created a track with `spec.md` + `plan.md`. This is the execution engine.

Pipeline: `/setup` → `/plan` → **`/build`**

## MCP Tools (use if available)

- `session_search(query)` — find how similar problems were solved before
- `project_code_search(query, project)` — find reusable code across projects
- `codegraph_query(query)` — check file dependencies, imports, callers

If MCP tools are not available, fall back to Glob + Grep + Read.

## Pre-flight Checks

1. Verify conductor is initialized:
   - Check `conductor/product.md`, `conductor/workflow.md`, `conductor/tracks.md` exist.
   - If missing: "Run `/setup` first."

2. Load workflow config from `conductor/workflow.md`:
   - TDD strictness (strict / moderate / none)
   - Commit strategy (conventional commits format)
   - Verification checkpoint rules

## Track Selection

### If `$ARGUMENTS` contains a track ID:
- Validate: `conductor/tracks/{argument}/plan.md` exists.
- If not found: search for partial matches, suggest corrections.

### If `$ARGUMENTS` contains `--task X.Y`:
- Jump directly to that task in the active track.

### If no argument:
1. Read `conductor/tracks.md`.
2. Find tracks marked `[~]` (in progress) — resume first.
3. If none in progress, find tracks marked `[ ]` (pending).
4. If multiple, ask via AskUserQuestion.
5. If zero tracks: "No tracks found. Run `/plan` first."

## Context Loading

Load in parallel:
1. `conductor/tracks/{trackId}/spec.md` — requirements, acceptance criteria
2. `conductor/tracks/{trackId}/plan.md` — task list with checkboxes
3. `conductor/tracks/{trackId}/metadata.json` — progress state
4. `conductor/tech-stack.md` — technical constraints
5. `conductor/workflow.md` — TDD policy, commit strategy
6. `conductor/code_styleguides/{lang}.md` — if exists
7. `CLAUDE.md` — architecture, Do/Don't

## Resumption

If `metadata.json` shows `status: "in_progress"` and a task is marked `[~]` in plan.md:

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
- Update metadata.json: `current_task`, `current_phase`, `updated`.
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
- If tests pass unexpectedly: investigate before proceeding.

**Green — implement:**
- Write minimum code to make the test pass.
- Run tests to confirm pass.
- If tests fail: debug and fix.

**Refactor:**
- Clean up while tests stay green.
- Run tests one final time.

### 5. Non-TDD Workflow (if TDD is "none" or "moderate" and task is simple)

- Implement the task directly.
- Run existing tests to check nothing broke.
- For "moderate": write tests for business logic and API routes, skip for UI/config.

### 6. Complete Task

**Commit** (following commit strategy from workflow.md):
```bash
git add {specific files changed}
git commit -m "<type>(<scope>): <description> ({trackId})"
```

Types: `feat`, `fix`, `refactor`, `test`, `docs`, `chore`, `perf`, `style`

**Update plan.md:** `[~]` → `[x]` for completed task.

**Update metadata.json:**
- Increment `tasks.completed`
- Record commit hash in `commits` array
- Update `updated` timestamp

**Commit plan update:**
```bash
git add conductor/tracks/{trackId}/plan.md conductor/tracks/{trackId}/metadata.json
git commit -m "chore: mark task {X.Y} complete ({trackId})"
```

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

If issues found: fix them before asking to proceed.

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

### Git Conflict
```
Git error: {message}

1. Show git status
2. Attempt to resolve
3. Pause for manual intervention
```

## Track Completion

When all phases and tasks are `[x]`:

### 1. Final Verification
- Run full test suite.
- Run linter.
- Check acceptance criteria from spec.md.

### 2. Update Status

In `conductor/tracks.md`: `[~]` → `[x]` for this track.

In `metadata.json`:
```json
{
  "status": "complete",
  "tasks": { "completed": N, "total": N },
  "phases": { "completed": N, "total": N }
}
```

### 3. Summary

```
Track complete: {title} ({trackId})

  Phases: {N}/{N}
  Tasks:  {M}/{M}
  Commits: {count}
  Tests: All passing

Next:
  /build {next-track-id}  — continue with next track
  /plan "next feature"  — plan something new
```

## Critical Rules

1. **NEVER skip phase checkpoints** — always wait for user approval between phases.
2. **STOP on failure** — do not continue past test failures or errors.
3. **Follow workflow.md** — TDD policy, commit strategy, verification rules are mandatory.
4. **Keep plan.md updated** — task status must reflect actual progress at all times.
5. **Commit after each task** — atomic commits with conventional format.
6. **Research before coding** — 30 seconds of search saves 30 minutes of reimplementation.
7. **Track all commits** — record hashes in metadata.json for potential revert.
8. **One task at a time** — finish current task before starting next.
