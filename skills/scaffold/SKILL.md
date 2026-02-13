---
name: solo-scaffold
description: Generate complete project from PRD + stack template — directory structure, configs, CLAUDE.md, git repo, and GitHub push. Use when user says "scaffold project", "create new project", "start new app", "bootstrap project", or "set up from PRD". Uses SoloGraph for patterns and Context7 for latest versions. Do NOT use for planning features (use /plan) or PRD generation (use /validate).
license: MIT
metadata:
  author: fortunto2
  version: "1.5.0"
allowed-tools: Read, Grep, Bash, Glob, Write, Edit, AskUserQuestion, mcp__context7__resolve-library-id, mcp__context7__query-docs, mcp__solograph__kb_search, mcp__solograph__project_info, mcp__solograph__project_code_search, mcp__solograph__codegraph_query, mcp__solograph__codegraph_explain, mcp__solograph__project_code_reindex
argument-hint: "[project-name] [stack-name]"
---

# /scaffold

Scaffold a complete project from PRD + stack template. Creates directory structure, configs, CLAUDE.md, git repo, and pushes to GitHub. Studies existing projects via SoloGraph for consistent patterns, uses Context7 for latest library versions.

## Steps

1. **Parse arguments** from `$ARGUMENTS` — extract `<project-name>` and `<stack-name>`.
   - If not provided or incomplete, use AskUserQuestion to ask for missing values.
   - Show available stacks from `templates/stacks/*.yaml` (source of truth).
     If MCP `project_info` available, also show detected stacks from active projects.
     List stack names with one-line descriptions from each YAML's `description` field.
   - Project name should be kebab-case.

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
   ├── .claude/
   │   └── skills/        # Product-specific workflow skills
   │       └── dev/
   │           └── SKILL.md  # Dev workflow skill (run, test, deploy)
   └── .gitignore         # Stack-specific ignores
   ```

   ### `.claude/skills/dev/SKILL.md` — product dev workflow skill

   Generate a skill that teaches Claude how to work with THIS specific project. Structure:

   ```yaml
   ---
   name: <name>-dev
   description: Dev workflow for <Name> — run, test, build, deploy. Use when working on <Name> features, fixing bugs, or deploying changes. Do NOT use for other projects.
   license: MIT
   metadata:
     author: <github_org>
     version: "1.0.0"
   allowed-tools: Read, Grep, Glob, Bash, Write, Edit
   ---
   ```

   Body should include:
   - **Stack:** key packages, versions, where configs live
   - **Commands:** `make dev`, `make test`, `make build`, `make deploy` (from Makefile)
   - **Architecture:** directory structure, naming conventions, key patterns
   - **Testing:** how to run tests, where test files live, testing conventions
   - **Common tasks:** add a new page/screen, add an API endpoint, add a model

   This makes every scaffolded project immediately Claude-friendly — new sessions get project context via the skill.

   **MCP server** (optional): If PRD indicates a data/AI/developer product, also generate MCP server stub.
   See `templates/mcp-skills-bundle.md` for the full "MCP + Skills bundle" pattern and rules for when to generate MCP.

   Then add stack-specific files. See `references/stack-structures.md` for per-stack file listings (8 stacks: nextjs, ios, kotlin, cloudflare, astro-static, astro-hybrid, python-api, python-ml).

9. **Generate Makefile** — stack-adapted with: `help`, `dev`, `test`, `lint`, `format`, `build`, `clean` targets.
   - **ios-swift** must also include: `generate` (xcodegen), `archive` (xcodebuild archive), `open` (open .xcarchive for Distribute)

10. **Generate CLAUDE.md** for the new project:
   - Project overview (problem/solution from PRD)
   - Tech stack (packages + versions from Context7)
   - **Skills section:** list available `.claude/skills/` with descriptions
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
      Skills: .claude/skills/dev/ (project workflow)

    Next steps:
      cd ~/startups/active/<name>
      <install command>    # pnpm install / uv sync / etc.
      <run command>        # pnpm dev / uv run ... / etc.

    Then: /setup → /plan "First feature" → /build
    ```

## Common Issues

### Stack YAML not found
**Cause:** Stack template missing from `templates/stacks/` or not symlinked.
**Fix:** Skill uses built-in knowledge if template not found. To fix: ensure `solo-factory/templates/stacks/<stack>.yaml` exists.

### GitHub repo creation fails
**Cause:** `gh` CLI not authenticated or repo name already taken.
**Fix:** Run `gh auth login` first. If name taken, choose a different project name.

### Context7 queries fail
**Cause:** MCP server not running or Context7 rate limited.
**Fix:** Skill proceeds with stack YAML versions as fallback. Context7 enhances but is not required.

### org defaults missing
**Cause:** `~/.solo-factory/defaults.yaml` not created.
**Fix:** Run `/init` first for one-time setup, or skill will ask for bundle ID and team ID interactively.
