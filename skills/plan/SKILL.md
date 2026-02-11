---
name: solo-plan
description: Explore codebase, write spec + battle plan — zero questions, pure code research
license: MIT
metadata:
  author: fortunto2
  version: "2.0.0"
allowed-tools: Read, Grep, Bash, Glob, Write, Edit, AskUserQuestion, mcp__solograph__session_search, mcp__solograph__project_code_search, mcp__solograph__codegraph_query, mcp__solograph__codegraph_explain, mcp__solograph__kb_search
argument-hint: "<task description>"
---

# /plan

Research the codebase and create a spec + phased implementation plan. Zero interactive questions — explores the code instead.

## When to use

Creates a track for any feature, bug fix, or refactor with a concrete, file-level implementation plan. Works with or without `/setup`.

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

2. **Detect context** — determine where plan files should be stored:

   **Project context** (normal project with code):
   - Detected by: `package.json`, `pyproject.toml`, `Cargo.toml`, `*.xcodeproj`, or `build.gradle.kts` exists in working directory
   - Plan path: `docs/plan/{trackId}/`

   **Knowledge base context** (solopreneur KB or similar):
   - Detected by: NO package manifest found, BUT directories like `0-principles/`, `1-methodology/`, `4-opportunities/` exist
   - Plan path: `4-opportunities/{shortname}/`
   - Note: the shortname is derived from the task (kebab-case, no date suffix for the directory)

   Set `$PLAN_ROOT` based on detected context. All subsequent file paths use `$PLAN_ROOT`.

3. **Load project context** (parallel reads):
   - `CLAUDE.md` — architecture, constraints, Do/Don't
   - `docs/prd.md` — what the product does (if exists)
   - `docs/workflow.md` — TDD policy, commit strategy (if exists)
   - `package.json` or `pyproject.toml` — stack, versions, deps

3. **Auto-classify track type** from keywords in task description:
   - Contains "fix", "bug", "broken", "error", "crash" → `bug`
   - Contains "refactor", "cleanup", "reorganize", "migrate" → `refactor`
   - Contains "update", "upgrade", "bump" → `chore`
   - Default → `feature`

4. **Research phase** — explore the codebase to understand what needs to change:

   a. **Get architecture overview** (if MCP available — do this FIRST):
      ```
      codegraph_explain(project="{project name from CLAUDE.md or directory name}")
      ```
      Gives you: stack, languages, directory layers, key patterns, top dependencies, hub files.

   b. **Find relevant files** — Glob + Grep for patterns related to the task:
      - Search for keywords from the task description
      - Look at directory structure to understand architecture
      - Identify files that will need modification

   c. **Search past sessions** (if MCP available):
      ```
      session_search(query="{task description keywords}")
      ```

   d. **Search code across projects** (if MCP available):
      ```
      project_code_search(query="{relevant pattern}")
      ```

   e. **Check dependencies** of affected files (if MCP available):
      ```
      codegraph_query(query="MATCH (f:File {path: '{file}'})-[:IMPORTS]->(dep) RETURN dep.path")
      ```

   f. **Read existing tests** in the affected area — understand testing patterns used.

   g. **Read CLAUDE.md** architecture constraints — understand boundaries and conventions.

5. **Generate track ID:**
   - Extract a short name (2-3 words, kebab-case) from task description.
   - Format: `{shortname}_{YYYYMMDD}` (e.g., `user-auth_20260209`).

6. **Create track directory:**
   ```bash
   mkdir -p $PLAN_ROOT
   ```
   - Project context: `docs/plan/{trackId}/`
   - KB context: `4-opportunities/{shortname}/`

7. **Generate `$PLAN_ROOT/spec.md`:**
   Based on research findings, NOT generic questions.
   ```markdown
   # Specification: {Title}

   **Track ID:** {trackId}
   **Type:** {Feature|Bug|Refactor|Chore}
   **Created:** {YYYY-MM-DD}
   **Status:** Draft

   ## Summary
   {1-2 paragraph description based on research}

   ## Acceptance Criteria
   - [ ] {concrete, testable criterion}
   - [ ] {concrete, testable criterion}
   {3-8 criteria based on research findings}

   ## Dependencies
   - {external deps, packages, other tracks}

   ## Out of Scope
   - {what this track does NOT cover}

   ## Technical Notes
   - {architecture decisions from research}
   - {relevant patterns found in codebase}
   - {reusable code from other projects}
   ```

8. **Generate `$PLAN_ROOT/plan.md`:**
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
   ### Tasks
   - [ ] Task {N}.1: Update CLAUDE.md with any new commands, architecture changes, or key files
   - [ ] Task {N}.2: Update README.md if public API or setup steps changed
   - [ ] Task {N}.3: Remove dead code — unused imports, orphaned files, stale exports

   ### Verification
   - [ ] CLAUDE.md reflects current project state
   - [ ] Linter clean, tests pass

   ## Final Verification
   - [ ] All acceptance criteria from spec met
   - [ ] Tests pass
   - [ ] Linter clean
   - [ ] Build succeeds
   - [ ] Documentation up to date

   ---
   _Generated by /plan. Tasks marked [~] in progress and [x] complete by /build._
   ```

   **Plan quality rules:**
   - Every task mentions specific file paths (from research).
   - Tasks are atomic — one commit each.
   - Phases are independently verifiable.
   - Total: 5-15 tasks (not 70).
   - **Last phase is always "Docs & Cleanup"**.

9. **Show plan for approval** via AskUserQuestion:
   Present the spec summary + plan overview. Options:
   - "Approve and start" — ready for `/build`
   - "Edit plan" — user wants to modify before implementing
   - "Cancel" — discard the track

   If "Edit plan": tell user to edit `$PLAN_ROOT/plan.md` manually, then run `/build`.

## Output

```
Track created: {trackId}

  Type:   {Feature|Bug|Refactor|Chore}
  Phases: {N}
  Tasks:  {N}
  Spec:   $PLAN_ROOT/spec.md
  Plan:   $PLAN_ROOT/plan.md

Research findings:
  - {key finding 1}
  - {key finding 2}
  - {reusable code found, if any}

Next: /build {trackId}
```

## Compatibility Notes

- Plan format must match what `/build` parses: `## Phase N:`, `- [ ] Task N.Y:`.
- `/build` reads `docs/workflow.md` for TDD policy and commit strategy (if exists).
- If `docs/workflow.md` missing, `/build` uses sensible defaults (moderate TDD, conventional commits).
