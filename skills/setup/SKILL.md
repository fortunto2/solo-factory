---
name: solo-setup
description: Wire up dev workflow from PRD + CLAUDE.md — zero questions asked
license: MIT
metadata:
  author: fortunto2
  version: "1.3.0"
allowed-tools: Read, Grep, Bash, Glob, Write, Edit, AskUserQuestion, mcp__solograph__project_info, mcp__solograph__codegraph_query, mcp__solograph__kb_search
argument-hint: "[project-name]"
---

# /setup

Auto-generate Conductor artifacts from existing PRD, CLAUDE.md, and stack template. Zero interactive questions — all answers are extracted from project data that already exists after `/scaffold`.

Replaces the old `/conductor:setup` (which asks 19 questions with answers already available).

## When to use

After `/scaffold` creates a project, before `/plan`. The generated artifacts make `/build` work.

## MCP Tools (use if available)

- `project_info(name)` — get project details, detected stack
- `kb_search(query)` — search for dev principles, manifest, stack templates
- `codegraph_query(query)` — check project dependencies in code graph

If MCP tools are not available, fall back to reading local files only.

## Steps

1. **Detect project root:**
   - If `$ARGUMENTS` is provided, use `~/startups/active/<name>` as project root.
   - Otherwise use current working directory.
   - Verify the directory exists and has `CLAUDE.md`.
   - If not found, ask via AskUserQuestion.

2. **Check if already initialized:**
   - If `conductor/setup_state.json` exists with `"status": "complete"`, warn and ask whether to regenerate.

3. **Read project data** (parallel — all reads at once):
   - `CLAUDE.md` — tech stack, architecture, commands, Do/Don't
   - `docs/prd.md` — problem, users, solution, features, metrics, pricing
   - `package.json` or `pyproject.toml` — exact dependency versions
   - `Makefile` — available commands
   - Linter configs (`.eslintrc*`, `eslint.config.*`, `.swiftlint.yml`, `ruff.toml`, `detekt.yml`)
   - Formatter configs (`.prettierrc*`)

4. **Read ecosystem sources** (optional — enhances quality):
   - Detect stack name from CLAUDE.md (look for "Stack:" or the stack name in tech section).
   - If MCP `kb_search` available: search for stack template and dev-principles.
   - Otherwise: look for `1-methodology/stacks/<stack>.yaml` and `1-methodology/dev-principles.md` relative to solopreneur root (if accessible).
   - If neither available: derive all info from CLAUDE.md + package manifest (sufficient).

5. **Detect languages** from package manifest:
   - `package.json` → TypeScript
   - `pyproject.toml` → Python
   - `*.xcodeproj` or `Package.swift` → Swift
   - `build.gradle.kts` → Kotlin
   - Multiple languages possible (e.g., TypeScript + Python monorepo).

6. **Create `conductor/` directory:**
   ```bash
   mkdir -p conductor/code_styleguides
   ```

7. **Generate `conductor/product.md`:**
   Extract from `docs/prd.md`:
   ```markdown
   # Product Definition — {ProjectName}

   ## Project Name
   {name}

   ## One-Liner
   {from PRD summary}

   ## Problem
   {from PRD problem section}

   ## Target Users
   {from PRD target users}

   ## Solution
   {from PRD solution/features}

   ## Key Differentiators
   {from PRD differentiators or competitive advantage}

   ## Success Metrics
   {from PRD metrics table}

   ## Pricing
   {from PRD pricing, if present}
   ```

8. **Generate `conductor/product-guidelines.md`:**
   Extract from CLAUDE.md Do/Don't sections:
   ```markdown
   # Product Guidelines — {ProjectName}

   ## Voice and Tone
   {infer from PRD/CLAUDE.md, default: "Friendly and approachable"}

   ## Design Principles
   1. **Privacy** — user data stays local where possible
   2. **Simplicity** — zero learning curve
   3. **Speed** — responsive UI, fast processing
   {add more from CLAUDE.md Do/Don't}

   ## UI Principles
   {from CLAUDE.md architecture/design sections}
   ```

9. **Generate `conductor/tech-stack.md`:**
   Extract from CLAUDE.md tech stack + `package.json`/`pyproject.toml` for exact versions:
   ```markdown
   # Tech Stack — {ProjectName}

   ## Languages
   | Language | Version | Role |
   |----------|---------|------|
   {detected languages with versions}

   ## Dependencies
   | Technology | Version | Purpose |
   |-----------|---------|---------|
   {from package manifest — key deps with versions}

   ## Dev Dependencies
   | Technology | Version | Purpose |
   |-----------|---------|---------|
   {dev deps}

   ## Infrastructure
   {from stack YAML or CLAUDE.md deploy/infra section}

   ## Package Manager
   {from CLAUDE.md or package manifest}
   ```

10. **Generate `conductor/workflow.md`:**
    Based on dev-principles (from MCP/KB or built-in defaults):
    ```markdown
    # Workflow — {ProjectName}

    ## TDD Policy
    **Moderate** — Tests encouraged but not blocking. Write tests for:
    - Business logic and validation
    - API route handlers
    - Complex algorithms
    Tests optional for: UI components, one-off scripts, prototypes.

    ## Test Framework
    {from package manifest devDeps: vitest/jest/pytest/xctest}

    ## Commit Strategy
    **Conventional Commits**
    Format: `<type>(<scope>): <description>`
    Types: feat, fix, refactor, test, docs, chore, perf, style

    ## Code Review
    **Optional / self-review OK.**

    ## Verification Checkpoints
    **After each phase completion:**
    1. Run tests — all pass
    2. Run linter — no errors
    3. Run build — successful (if applicable)
    4. Manual smoke test
    5. Mark phase as verified

    ## Task Lifecycle
    pending → in_progress → completed

    ## Branch Strategy
    - `main` — production-ready
    - `feat/<track-id>-<short-name>` — feature branches
    - `fix/<description>` — hotfixes
    ```

11. **Generate `conductor/tracks.md`:**
    ```markdown
    # Tracks Registry

    | Status | Track ID | Title | Created | Updated |
    | ------ | -------- | ----- | ------- | ------- |

    <!-- Tracks registered by /plan -->
    ```

12. **Generate `conductor/code_styleguides/<lang>.md`** for each detected language:
    Read linter configs from the project and generate style guide. Include:
    - Formatting rules (from prettier/ruff/swiftlint config)
    - Naming conventions (from stack conventions)
    - Import ordering
    - Key patterns (from CLAUDE.md architecture section)

13. **Generate `conductor/index.md`:**
    ```markdown
    # Conductor — {ProjectName}

    Navigation hub for project context.

    ## Core
    - [Product Definition](./product.md)
    - [Product Guidelines](./product-guidelines.md)
    - [Tech Stack](./tech-stack.md)
    - [Workflow](./workflow.md)

    ## Planning
    - [Tracks](./tracks.md)

    ## Code Style Guides
    {list detected language guides}
    ```

14. **Generate `conductor/setup_state.json`:**
    ```json
    {
      "status": "complete",
      "project_type": "brownfield",
      "current_section": "done",
      "current_question": 0,
      "completed_sections": ["product", "guidelines", "tech_stack", "workflow", "styleguides", "generation"],
      "answers": {
        "project_name": "{name}",
        "description": "{one-liner from PRD}",
        "problem": "{problem from PRD}",
        "target_users": "{users from PRD}",
        "key_goals": ["{goals from PRD}"],
        "voice_tone": "Friendly and approachable",
        "design_principles": ["Privacy", "Simplicity", "Speed"],
        "tech_stack_confirmed": true,
        "tdd_strictness": "moderate",
        "commit_strategy": "conventional",
        "code_review": "optional",
        "verification": "phase",
        "style_guides": ["{detected languages}"]
      },
      "files_created": ["{list of created files}"],
      "started_at": "{ISO timestamp}",
      "last_updated": "{ISO timestamp}"
    }
    ```

15. **Show summary and suggest next step:**
    ```
    Conductor initialized for {ProjectName}!

    Created:
      conductor/product.md          — from docs/prd.md
      conductor/product-guidelines.md — from CLAUDE.md
      conductor/tech-stack.md       — from CLAUDE.md + package manifest
      conductor/workflow.md         — TDD moderate, conventional commits
      conductor/tracks.md           — empty registry
      conductor/code_styleguides/   — {languages}
      conductor/index.md            — navigation hub
      conductor/setup_state.json    — complete

    Next: /plan "Your first feature"
    ```

## Compatibility Notes

- `setup_state.json` must have `"status": "complete"` — `/build` checks this.
- All file formats match what `/build` reads (product.md, tech-stack.md, workflow.md, tracks.md).
- Track format uses `## Phase N:` and `- [ ] Task N.Y:` markers that implement.md parses.
- `conductor/tracks/{id}/` directories are created by `/plan`, not here.
