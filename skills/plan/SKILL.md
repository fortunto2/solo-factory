---
name: solo-plan
description: Explore codebase, write spec + battle plan — zero questions, pure code research
license: MIT
metadata:
  author: fortunto2
  version: "1.3.0"
allowed-tools: Read, Grep, Bash, Glob, Write, Edit, AskUserQuestion, mcp__solograph__session_search, mcp__solograph__project_code_search, mcp__solograph__codegraph_query, mcp__solograph__codegraph_explain, mcp__solograph__kb_search
argument-hint: "<task description>"
---

# /plan

Research the codebase and create a Conductor track with spec + phased plan. Replaces `/conductor:new-track` which asks 6 interactive questions — this skill explores the code instead.

## When to use

After `/setup` has created `conductor/` artifacts. Creates a track for any feature, bug fix, or refactor with a concrete, file-level implementation plan.

## MCP Tools (use if available)

- `session_search(query)` — find similar past work in Claude Code chat history
- `project_code_search(query, project)` — find reusable code across projects
- `codegraph_query(query)` — check dependencies of affected files
- `codegraph_explain(project)` — architecture overview: stack, languages, directory layers, key patterns, top dependencies, hub files
- `kb_search(query)` — search knowledge base for relevant methodology

If MCP tools are not available, fall back to Glob + Grep + Read.

## Steps

1. **Parse task description** from `$ARGUMENTS`.
   - If empty, ask via AskUserQuestion: "What feature, bug, or refactor do you want to plan?"
   - This is the ONE question maximum.

2. **Verify Conductor is initialized:**
   - Check `conductor/product.md` exists.
   - Check `conductor/workflow.md` exists.
   - Check `conductor/tracks.md` exists.
   - If missing, tell user to run `/setup` first.

3. **Load project context** (parallel reads):
   - `conductor/product.md` — what the product does
   - `conductor/tech-stack.md` — stack, versions, deps
   - `conductor/workflow.md` — TDD policy, commit strategy, verification
   - `conductor/tracks.md` — existing tracks (avoid overlap)
   - `CLAUDE.md` — architecture, constraints, Do/Don't

4. **Auto-classify track type** from keywords in task description:
   - Contains "fix", "bug", "broken", "error", "crash" → `bug`
   - Contains "refactor", "cleanup", "reorganize", "migrate" → `refactor`
   - Contains "update", "upgrade", "bump" → `chore`
   - Default → `feature`

5. **Research phase** — explore the codebase to understand what needs to change:

   a. **Get architecture overview** (if MCP available — do this FIRST):
      ```
      codegraph_explain(project="{project name from CLAUDE.md or directory name}")
      ```
      Gives you: stack, languages, directory layers, key patterns (base classes, mixins, CRUD schemas), top dependencies, and hub files. Use this to orient before any file search.

   b. **Find relevant files** — Glob + Grep for patterns related to the task:
      - Search for keywords from the task description
      - Look at directory structure to understand architecture
      - Identify files that will need modification

   c. **Search past sessions** (if MCP available):
      ```
      session_search(query="{task description keywords}")
      ```
      Look for: similar features, relevant decisions, patterns used.

   d. **Search code across projects** (if MCP available):
      ```
      project_code_search(query="{relevant pattern}")
      ```
      Look for: existing implementations to reuse or adapt.

   e. **Check dependencies** of affected files (if MCP available):
      ```
      codegraph_query(query="MATCH (f:File {path: '{file}'})-[:IMPORTS]->(dep) RETURN dep.path")
      ```

   f. **Read existing tests** in the affected area — understand testing patterns used.

   g. **Read CLAUDE.md** architecture constraints — understand boundaries and conventions.

6. **Generate track ID:**
   - Extract a short name (2-3 words, kebab-case) from task description.
   - Format: `{shortname}_{YYYYMMDD}` (e.g., `user-auth_20260209`).

7. **Create track directory:**
   ```bash
   mkdir -p conductor/tracks/{trackId}
   ```

8. **Generate `conductor/tracks/{trackId}/spec.md`:**
   Based on research findings, NOT generic questions.
   ```markdown
   # Specification: {Title}

   **Track ID:** {trackId}
   **Type:** {Feature|Bug|Refactor|Chore}
   **Created:** {YYYY-MM-DD}
   **Status:** Draft

   ## Summary
   {1-2 paragraph description based on research}

   ## User Stories
   - As a {user}, I want to {action} so that {benefit}
   {derive from product.md target users + task description}

   ## Acceptance Criteria
   - [ ] {concrete, testable criterion}
   - [ ] {concrete, testable criterion}
   {3-8 criteria based on research findings}

   ## Dependencies
   - {external deps, packages, other tracks}
   {from codegraph + package manifest research}

   ## Out of Scope
   - {what this track does NOT cover}

   ## Technical Notes
   - {architecture decisions from research}
   - {relevant patterns found in codebase}
   - {reusable code from other projects}
   ```

9. **Generate `conductor/tracks/{trackId}/plan.md`:**
   Concrete, file-level plan from research. Keep it tight: 2-4 phases, 5-15 tasks total.

   **Critical format rules** (parsed by `/build`):
   - Phase headers: `## Phase N: Name`
   - Tasks: `- [ ] Task N.Y: Description` (with period or detailed text)
   - Subtasks: indented `  - [ ] Subtask description`
   - All tasks use `[ ]` (unchecked), `[~]` (in progress), `[x]` (done)

   ```markdown
   # Implementation Plan: {Title}

   **Track ID:** {trackId}
   **Spec:** [spec.md](./spec.md)
   **Created:** {YYYY-MM-DD}
   **Status:** [ ] Not Started

   ## Overview
   {1-2 sentences on approach}

   ## Phase 1: {Name}
   {brief description of phase goal}

   ### Tasks
   - [ ] Task 1.1: {description with concrete file paths}
   - [ ] Task 1.2: {description}

   ### Verification
   - [ ] {what to check after this phase}

   ## Phase 2: {Name}
   ### Tasks
   - [ ] Task 2.1: {description}
   - [ ] Task 2.2: {description}

   ### Verification
   - [ ] {verification steps}

   {2-4 phases total}

   ## Phase {N}: Docs & Cleanup
   Documentation updates and tech debt resolution. Always the last phase.

   ### Tasks
   - [ ] Task {N}.1: Update CLAUDE.md with any new commands, architecture changes, or key files added
   - [ ] Task {N}.2: Update README.md if public API or setup steps changed
   - [ ] Task {N}.3: Grep for AICODE-TODO in modified files — resolve completed, leave valid
   - [ ] Task {N}.4: Add AICODE-NOTE comments on complex/non-obvious logic written
   - [ ] Task {N}.5: Remove dead code — unused imports, orphaned files, stale exports

   ### Verification
   - [ ] CLAUDE.md reflects current project state
   - [ ] No stale AICODE-TODO in modified files
   - [ ] Linter clean, tests pass

   ## Final Verification
   - [ ] All acceptance criteria from spec met
   - [ ] Tests pass
   - [ ] Linter clean
   - [ ] Build succeeds
   - [ ] Documentation up to date (CLAUDE.md, README.md, tech-stack.md)

   ---
   _Generated by /plan. Tasks marked [~] in progress and [x] complete by /build._
   ```

   **Plan quality rules:**
   - Every task mentions specific file paths (from research).
   - Tasks are atomic — one commit each.
   - Phases are independently verifiable.
   - Total: 5-15 tasks (not 70 like Conductor sometimes generates).
   - Subtasks are optional, only when a task has distinct sub-steps.
   - **Last phase is always "Docs & Cleanup"** — documentation updates are part of "done".

10. **Generate `conductor/tracks/{trackId}/metadata.json`:**
    ```json
    {
      "id": "{trackId}",
      "title": "{Title}",
      "type": "{feature|bug|refactor|chore}",
      "status": "pending",
      "created": "{ISO timestamp}",
      "updated": "{ISO timestamp}",
      "current_phase": 1,
      "current_task": "1.1",
      "phases": {
        "total": {N},
        "completed": 0
      },
      "tasks": {
        "total": {N},
        "completed": 0
      },
      "commits": []
    }
    ```

11. **Register in `conductor/tracks.md`:**
    Add a row to the tracks table:
    ```
    | [ ] | {trackId} | {Title} | {YYYY-MM-DD} | {YYYY-MM-DD} |
    ```

12. **Show plan for approval** via AskUserQuestion:
    Present the spec summary + plan overview. Options:
    - "Approve and start" — ready for `/build`
    - "Edit plan" — user wants to modify before implementing
    - "Cancel" — discard the track

    If "Edit plan": tell user to edit `conductor/tracks/{trackId}/plan.md` manually, then run `/build`.

## Output

```
Track created: {trackId}

  Type:   {Feature|Bug|Refactor|Chore}
  Phases: {N}
  Tasks:  {N}
  Spec:   conductor/tracks/{trackId}/spec.md
  Plan:   conductor/tracks/{trackId}/plan.md

Research findings:
  - {key finding 1}
  - {key finding 2}
  - {reusable code found, if any}

Next: /build {trackId}
```

## Compatibility Notes

- Plan format must match what `/build` parses: `## Phase N:`, `- [ ] Task N.Y:`.
- `metadata.json` fields match Conductor's expected schema (id, title, type, status, phases, tasks, commits).
- Track registered in `tracks.md` with `[ ]` status marker.
- `/build` reads `conductor/workflow.md` for TDD policy and commit strategy.
