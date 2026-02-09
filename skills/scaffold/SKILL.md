---
name: solo-scaffold
description: PRD to running project in 2 minutes — structure, deps, git, GitHub
license: MIT
metadata:
  author: fortunto2
  version: "1.3.0"
allowed-tools: Read, Grep, Bash, Glob, Write, Edit, AskUserQuestion, mcp__context7__resolve-library-id, mcp__context7__query-docs, mcp__codegraph__kb_search, mcp__codegraph__project_info
argument-hint: "[project-name] [stack-name]"
---

# /scaffold

Scaffold a complete project from PRD + stack template. Creates directory structure, configs, CLAUDE.md, git repo, and pushes to GitHub. Uses Context7 to research latest library versions and best practices.

## Steps

1. **Parse arguments** from `$ARGUMENTS` — extract `<project-name>` and `<stack-name>`.
   - If not provided or incomplete, use AskUserQuestion to ask for missing values.
   - Show available stacks (if MCP `project_info` available, show detected stacks from active projects):

   Common stacks:
   - `ios-swift` — SwiftUI, CoreML, StoreKit 2, async/await
   - `nextjs-supabase` — Next.js 16, React 19, Tailwind 4, shadcn-ui, Supabase, Drizzle ORM
   - `cloudflare-workers` — Hono, D1, R2, Durable Objects, edge-first
   - `kotlin-android` — Jetpack Compose, Room, Koin, CameraX
   - `astro-static` — Astro 5, Cloudflare Pages, content collections
   - `nextjs-ai-agents` — extends nextjs-supabase + Vercel AI SDK, @ai-sdk/react, ToolLoopAgent
   - `python-api` — uv, FastAPI, Pydantic, PostgreSQL, SQLAlchemy, Alembic
   - `python-ml` — uv, Pydantic, ChromaDB, MLX, CLI-first

   Project name should be kebab-case.

2. **Load stack + PRD + principles:**
   - Look for stack YAML: search for `stacks/<stack>.yaml` in solopreneur KB (via `kb_search` or Glob).
   - If stack YAML not found, use built-in knowledge of the stack (packages, structure, deploy).
   - Check if PRD exists: `3-opportunities/<project>/prd.md` or `docs/prd.md`
     - If not: generate a basic PRD template
   - Look for dev principles: search for `dev-principles.md` or use built-in SOLID/DRY/KISS/TDD principles.

3. **Context7 research** (key step — determines exact versions and patterns):
   - For each key package from the stack:
     - `mcp__context7__resolve-library-id` — find the Context7 library ID
     - `mcp__context7__query-docs` — query "latest version, project setup, recommended file structure, best practices"
   - Collect: current versions, recommended directory structure, configuration patterns, setup commands
   - Limit to the 3-4 most important packages to keep research focused

4. **Show plan + get confirmation** via AskUserQuestion:
   - Project path: `~/startups/active/<name>`
   - Stack name and key packages with versions from Context7
   - Proposed directory structure
   - Confirm or adjust before creating files

5. **Create project directory:**
   ```bash
   mkdir -p ~/startups/active/<name>
   ```

6. **Create file structure** based on the stack. **SGR-first: always start with domain schemas/models before any logic or views.** Every project gets these common files:
   ```
   ~/startups/active/<name>/
   ├── CLAUDE.md          # AI-friendly project docs
   ├── Makefile           # Common commands (run, test, build, lint, deploy)
   ├── README.md          # Human-friendly project docs
   ├── docs/
   │   └── prd.md         # Copy of PRD
   └── .gitignore         # Stack-specific ignores
   ```

   Then stack-specific files. Key patterns per stack:

   **nextjs-supabase / nextjs-ai-agents:**
   - `package.json`, `tsconfig.json`, `next.config.ts`, `tailwind.config.ts`
   - `eslint.config.mjs` (flat config v9), `.prettierrc`, `components.json` (shadcn)
   - `drizzle.config.ts`, `db/schema.ts`
   - `vitest.config.ts`, `.env.local.example`
   - `app/layout.tsx`, `app/page.tsx`, `app/globals.css`
   - `lib/supabase/client.ts`, `lib/supabase/server.ts`, `lib/utils.ts`

   **ios-swift:**
   - `<Name>/` with MVVM: `Models/`, `Views/`, `ViewModels/`, `Services/`
   - `<Name>Tests/`, `Package.swift`, `.swiftlint.yml`

   **kotlin-android:**
   - `build.gradle.kts`, `gradle/libs.versions.toml`
   - `app/src/main/kotlin/<package>/` with `ui/`, `data/`, `domain/`
   - `detekt.yml`

   **cloudflare-workers:**
   - `package.json`, `wrangler.toml`, `tsconfig.json`
   - `src/index.ts`, `test/index.test.ts`

   **astro-static:**
   - `package.json`, `astro.config.mjs`
   - `src/pages/index.astro`, `src/layouts/Layout.astro`, `src/content/config.ts`

   **python-api:**
   - `pyproject.toml`, `src/<name>/main.py`, `src/<name>/schemas/`, `src/<name>/models/`
   - `alembic/`, `docker-compose.yml`, `tests/test_main.py`

   **python-ml:**
   - `pyproject.toml`, `src/<name>/main.py`, `src/<name>/models.py`
   - `tests/test_main.py`

7. **Generate Makefile** — stack-adapted with: `help`, `dev`, `test`, `lint`, `format`, `build`, `clean` targets.

8. **Generate CLAUDE.md** for the new project:
   - Project overview (problem/solution from PRD)
   - Tech stack (packages + versions from Context7)
   - Directory structure
   - Common commands (reference `make help`)
   - SGR / Domain-First section
   - Architecture principles (from dev-principles)
   - Do/Don't sections
   - **Solopreneur Integration section** (if MCP tools available):
     Lists available MCP tools: `project_code_search`, `kb_search`, `session_search`, `codegraph_query`, `project_info`, `web_search`

9. **Generate README.md** — project name, description, prerequisites, setup, run/test/deploy.

10. **Generate .gitignore** — stack-specific patterns.

11. **Copy PRD to docs/:** Copy from solopreneur KB or generate in place.

12. **Git init + first commit:**
    ```bash
    cd ~/startups/active/<name>
    git init && git add . && git commit -m "Initial project scaffold

    Stack: <stack-name>
    Generated by /scaffold"
    ```

13. **Create GitHub private repo + push:**
    ```bash
    cd ~/startups/active/<name>
    gh repo create <name> --private --source=. --push
    ```

14. **Update KB registry + index code** (if in solopreneur ecosystem):
    - If `make scan` available: run it to update project registry
    - If MCP `project_code_reindex` available: index the new project

15. **Output summary:**
    ```
    Project scaffolded!

      Path:   ~/startups/active/<name>
      GitHub: https://github.com/<user>/<name>
      Stack:  <stack-name>
      PRD:    docs/prd.md
      CLAUDE: configured

    Next steps:
      cd ~/startups/active/<name>
      <install command>    # pnpm install / uv sync / etc.
      <run command>        # pnpm dev / uv run ... / etc.

    Then: /setup → /plan "First feature" → /build
    ```
