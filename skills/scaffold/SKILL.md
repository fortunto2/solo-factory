---
name: solo-scaffold
description: PRD to running project in 2 minutes — structure, deps, git, GitHub
license: MIT
metadata:
  author: fortunto2
  version: "1.4.0"
allowed-tools: Read, Grep, Bash, Glob, Write, Edit, AskUserQuestion, mcp__context7__resolve-library-id, mcp__context7__query-docs, mcp__solograph__kb_search, mcp__solograph__project_info, mcp__solograph__project_code_search, mcp__solograph__codegraph_query, mcp__solograph__codegraph_explain, mcp__solograph__project_code_reindex
argument-hint: "[project-name] [stack-name]"
---

# /scaffold

Scaffold a complete project from PRD + stack template. Creates directory structure, configs, CLAUDE.md, git repo, and pushes to GitHub. Studies existing projects via SoloGraph for consistent patterns, uses Context7 for latest library versions.

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

2. **Load org defaults** from `~/.solo-factory/defaults.yaml`:
   - Read `org_domain` (e.g. `co.superduperai`), `apple_dev_team`, `github_org`, `projects_dir`
   - If file doesn't exist, ask via AskUserQuestion:
     - "What is your reverse-domain prefix for bundle IDs?" (e.g. `com.mycompany`)
     - "Apple Developer Team ID?" (optional, leave empty if no iOS)
   - Create `~/.solo-factory/defaults.yaml` with answers for future runs
   - Replace `<org_domain>`, `<apple_dev_team>`, `<github_org>` placeholders in all generated files

3. **Load stack + PRD + principles:**

   - Look for stack YAML: search for `stacks/<stack>.yaml` in solopreneur KB (via `kb_search` or Glob).
   - If stack YAML not found, use built-in knowledge of the stack (packages, structure, deploy).
   - Check if PRD exists: `4-opportunities/<project>/prd.md` or `docs/prd.md`
     - If not: generate a basic PRD template
   - Look for dev principles: search for `dev-principles.md` or use built-in SOLID/DRY/KISS/TDD principles.

4. **Study existing projects via SoloGraph** (learn from your own codebase — critically):

   Before generating code, study active projects with the same stack. **Don't blindly copy** — existing projects may have legacy patterns or mistakes. Evaluate what's actually useful.

   a. **Find sibling projects** — use `project_info()` to list active projects, filter by matching stack.
      Example: for `ios-swift`, find FaceAlarm, KubizBeat, etc.

   b. **Architecture overview** — `codegraph_explain(project="<sibling>")` for each sibling.
      Gives: directory layers, key patterns (base classes, protocols, CRUD), top dependencies, hub files.

   c. **Search for reusable patterns** — `project_code_search(query="<pattern>", project="<sibling>")`:
      - Search for stack-specific patterns: "MVVM ViewModel", "SwiftData model", "AVFoundation recording"
      - Search for shared infrastructure: "Makefile", "project.yml", ".swiftlint.yml"
      - Search for services: "Service protocol", "actor service"

   d. **Check shared packages** — `codegraph_query("MATCH (p:Project)-[:DEPENDS_ON]->(pkg:Package) WHERE p.name = '<sibling>' RETURN pkg.name")`.
      Collect package versions for reference (but verify with Context7 for latest).

   e. **Critically evaluate** what to adopt vs skip:
      - **Adopt:** consistent directory structure, Makefile targets, config patterns (.swiftlint.yml, project.yml)
      - **Adopt:** proven infrastructure patterns (actor services, protocol-based DIP)
      - **Skip if outdated:** old API patterns (ObservableObject → @Observable), deprecated deps
      - **Skip if overcomplicated:** unnecessary abstractions, patterns that don't fit the new project's needs
      - **Always prefer:** Context7 latest best practices over old project patterns when they conflict

   **Goal:** Generated code should feel consistent with your portfolio but use the **best available** patterns, not just the same old ones.
   Limit to 2-3 sibling projects to keep research focused.

5. **Context7 research** (latest library versions and best practices):
   - For each key package from the stack:
     - `mcp__context7__resolve-library-id` — find the Context7 library ID
     - `mcp__context7__query-docs` — query "latest version, project setup, recommended file structure, best practices"
   - Collect: current versions, recommended directory structure, configuration patterns, setup commands
   - Limit to the 3-4 most important packages to keep research focused

6. **Show plan + get confirmation** via AskUserQuestion:
   - Project path: `~/startups/active/<name>`
   - Stack name and key packages with versions from Context7
   - Proposed directory structure
   - Confirm or adjust before creating files

7. **Create project directory:**
   ```bash
   mkdir -p ~/startups/active/<name>
   ```

8. **Create file structure** based on the stack. **SGR-first: always start with domain schemas/models before any logic or views.** Every project gets these common files:
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
   - `project.yml` (XcodeGen) — **MUST include** App Store requirements:
     - `info.properties`: `UISupportedInterfaceOrientations` (all 4), `UILaunchScreen`, `UIApplicationSceneManifest`
     - `settings.base`: `PRODUCT_BUNDLE_IDENTIFIER: <org_domain>.<name>`, `MARKETING_VERSION: "1.0.0"`, `CURRENT_PROJECT_VERSION: "1"`, `DEVELOPMENT_TEAM: <apple_dev_team>`, `CODE_SIGN_STYLE: Automatic`
   - `<Name>/` with MVVM: `Models/`, `Views/`, `ViewModels/`, `Services/`
   - `<Name>Tests/`, `Package.swift`, `.swiftlint.yml`
   - Makefile must include `archive` target: `xcodegen generate && xcodebuild archive -scheme <Name> ...`

   **kotlin-android:**
   - `build.gradle.kts` — **MUST include** Play Store requirements:
     - `applicationId = "<org_domain>.<name>"`, `namespace = "<org_domain>.<name>"`
     - `compileSdk = 35`, `targetSdk = 35`, `minSdk = 26`
     - `versionCode = 1`, `versionName = "1.0.0"`
     - `signingConfigs` block loading from `keystore.properties` (gitignored)
   - `gradle/libs.versions.toml`
   - `app/src/main/kotlin/<org_domain_path>/<name>/` with `ui/`, `data/`, `domain/`
   - `detekt.yml`, `keystore.properties.example`
   - Makefile must include `release` target: `./gradlew bundleRelease`

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

9. **Generate Makefile** — stack-adapted with: `help`, `dev`, `test`, `lint`, `format`, `build`, `clean` targets.
   - **ios-swift** must also include: `generate` (xcodegen), `archive` (xcodebuild archive), `open` (open .xcarchive for Distribute)

10. **Generate CLAUDE.md** for the new project:
   - Project overview (problem/solution from PRD)
   - Tech stack (packages + versions from Context7)
   - Directory structure
   - Common commands (reference `make help`)
   - SGR / Domain-First section
   - Architecture principles (from dev-principles)
   - Do/Don't sections
   - **Solopreneur Integration section** (if MCP tools available):
     Lists available MCP tools: `project_code_search`, `kb_search`, `session_search`, `codegraph_query`, `project_info`, `web_search`

11. **Generate README.md** — project name, description, prerequisites, setup, run/test/deploy.

12. **Generate .gitignore** — stack-specific patterns.

13. **Copy PRD to docs/:** Copy from solopreneur KB or generate in place.

14. **Git init + first commit:**
    ```bash
    cd ~/startups/active/<name>
    git init && git add . && git commit -m "Initial project scaffold

    Stack: <stack-name>
    Generated by /scaffold"
    ```

15. **Create GitHub private repo + push:**
    ```bash
    cd ~/startups/active/<name>
    gh repo create <name> --private --source=. --push
    ```

16. **Register project + index code** (if in solopreneur ecosystem):
    - Append project to `~/.solo/registry.yaml`:
      ```bash
      cat >> ~/.solo/registry.yaml << 'EOF'

      - name: <name>
        path: ~/startups/active/<name>
        active: true
      EOF
      ```
    - Index the new project for code search:
      ```
      mcp__solograph__project_code_reindex(project="<name>")
      ```

17. **Output summary:**
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
