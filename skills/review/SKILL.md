---
name: review
description: Final code review and quality gate — run tests, check coverage, audit security, verify acceptance criteria from spec, and generate ship-ready report. Use when user says "review code", "quality check", "is it ready to ship", "final review", or after /deploy completes. Do NOT use for planning (use /plan) or building (use /build).
license: MIT
metadata:
  author: fortunto2
  version: "1.0.0"
argument-hint: "[focus-area]"
---

# /review

Final quality gate before shipping. Runs tests, checks security, verifies acceptance criteria from spec.md, audits code quality, and generates a ship-ready report with go/no-go verdict.

## When to use

After `/deploy` (or `/build` if deploying manually). This is the quality gate.

Pipeline: `/deploy` → **`/review`**

Can also be used standalone: `/review` on any project to audit code quality.

## MCP Tools (use if available)

- `session_search(query)` — find past review patterns and common issues
- `project_code_search(query, project)` — find similar code patterns across projects
- `codegraph_query(query)` — check dependencies, imports, unused code

If MCP tools are not available, fall back to Glob + Grep + Read.

## Pre-flight Checks

### 1. Architecture overview (if MCP available)
```
codegraph_explain(project="{project name}")
```
Returns: stack, languages, directory layers, key patterns, top dependencies, hub files. Use this to detect stack and understand project structure.

### 2. Essential docs (parallel reads)
- `CLAUDE.md` — architecture, Do/Don't rules
- `docs/plan/*/spec.md` — acceptance criteria to verify (REQUIRED)
- `docs/plan/*/plan.md` — task completion status (REQUIRED)
- `docs/workflow.md` — TDD policy, quality standards (if exists)

**Do NOT read source code at this stage.** Only docs.

### 3. Detect stack
Use stack from `codegraph_explain` response (or `CLAUDE.md` if no MCP) to choose tools:
- Next.js → `npm run build`, `npm test`, `npx next lint`
- Python → `uv run pytest`, `uv run ruff check`
- Swift → `swift test`, `swiftlint`
- Kotlin → `./gradlew test`, `./gradlew lint`

### 4. Smart source code loading (for code quality spot check)

**Do NOT read random source files.** Use the graph to find the most important code:

```
codegraph_query("MATCH (f:File {project: '{name}'})-[e]-() RETURN f.path, COUNT(e) AS edges ORDER BY edges DESC LIMIT 5")
```

Read only the top 3-5 hub files (most connected = most impactful). For security checks, use Grep with narrow patterns (`sk_live`, `password\s*=`) — not full file reads.

## Review Dimensions

Run all dimensions in sequence. Report findings per dimension.

### 1. Test Suite

Run the full test suite:
```bash
# Next.js / Node
npm test -- --coverage 2>&1 || true

# Python
uv run pytest --tb=short -q 2>&1 || true

# Swift
swift test 2>&1 || true
```

Report:
- Total tests: pass / fail / skip
- Coverage percentage (if available)
- Any failing tests with file:line references

### 2. Linter & Type Check

```bash
# Next.js
npx next lint 2>&1 || true
npx tsc --noEmit 2>&1 || true

# Python
uv run ruff check . 2>&1 || true
uv run mypy . 2>&1 || true

# General
# Check for any linter config (.eslintrc, ruff.toml, .swiftlint.yml)
```

Report: warnings count, errors count, top issues.

### 3. Build Verification

```bash
# Next.js
npm run build 2>&1 || true

# Python
uv run python -m py_compile src/**/*.py 2>&1 || true

# Astro
npm run build 2>&1 || true
```

Report: build success/failure, any warnings.

### 4. Security Audit

**Dependency vulnerabilities:**
```bash
# Node
npm audit --audit-level=moderate 2>&1 || true

# Python
uv run pip-audit 2>&1 || true
```

**Code-level checks** (Grep for common issues):
- Hardcoded secrets: `grep -rn "sk_live\|sk_test\|password\s*=\s*['\"]" src/ app/ lib/`
- SQL injection: look for string concatenation in queries
- XSS: look for `dangerouslySetInnerHTML` without sanitization
- Exposed env vars: check `.gitignore` includes `.env*`

Report: vulnerabilities found, severity levels.

### 5. Acceptance Criteria Verification

Read `docs/plan/*/spec.md` and check each acceptance criterion:

For each `- [ ]` criterion in spec.md:
1. Search codebase for evidence it was implemented.
2. Check if related tests exist.
3. Mark as verified or flag as missing.

```
Acceptance Criteria:
  - [x] User can sign up with email — found in app/auth/signup/page.tsx + test
  - [x] Dashboard shows project list — found in app/dashboard/page.tsx
  - [ ] Stripe checkout works — route exists but no test coverage
```

### 6. Code Quality Spot Check

Read 3-5 key files (entry points, API routes, main components):
- Check for TODO/FIXME/HACK comments that should be resolved
- Check for console.log/print statements left in production code
- Check for proper error handling (try/catch, error boundaries)
- Check for proper loading/error states in UI components

Report specific file:line references for any issues found.

### 7. Plan Completion Check

Read `docs/plan/*/plan.md`:
- Count completed tasks `[x]` vs total tasks
- Flag any `[ ]` or `[~]` tasks still remaining
- Verify all phase checkpoints have SHAs

## Review Report

Generate the final report:

```
Code Review: {project-name}
Date: {YYYY-MM-DD}

## Verdict: {SHIP / FIX FIRST / BLOCK}

### Summary
{1-2 sentence overall assessment}

### Tests
- Total: {N} | Pass: {N} | Fail: {N} | Skip: {N}
- Coverage: {N}%
- Status: {PASS / FAIL}

### Linter
- Errors: {N} | Warnings: {N}
- Status: {PASS / WARN / FAIL}

### Build
- Status: {PASS / FAIL}
- Warnings: {N}

### Security
- Vulnerabilities: {N} (critical: {N}, high: {N}, moderate: {N})
- Hardcoded secrets: {NONE / FOUND}
- Status: {PASS / WARN / FAIL}

### Acceptance Criteria
- Verified: {N}/{M}
- Missing: {list}
- Status: {PASS / PARTIAL / FAIL}

### Plan Progress
- Tasks: {N}/{M} complete
- Phases: {N}/{M} complete
- Status: {COMPLETE / IN PROGRESS}

### Issues Found
1. [{severity}] {description} — {file:line}
2. [{severity}] {description} — {file:line}

### Recommendations
- {actionable recommendation}
- {actionable recommendation}
```

**Verdict logic:**
- **SHIP**: All tests pass, no security issues, acceptance criteria met, build succeeds
- **FIX FIRST**: Minor issues (warnings, partial criteria, low-severity vulns) — list what to fix
- **BLOCK**: Failing tests, security vulnerabilities, missing critical features — do not ship

## Completion

### Verdict: SHIP

If verdict is **SHIP** — create completion marker:

```bash
cat > .review-complete << EOF
Verdict: SHIP
Tests: {pass}/{total}
Coverage: {N}%
Security: {PASS|WARN|FAIL}
Criteria: {verified}/{total}
Completed: $(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF
```

This file signals to the pipeline that the review stage is finished.
Add it to `.gitignore` if not already there.

### Verdict: FIX FIRST or BLOCK

If verdict is **FIX FIRST** or **BLOCK** — do NOT create `.review-complete`. Instead:

1. **Remove BUILD_COMPLETE** to send pipeline back to build stage:
```bash
rm -f docs/plan/*/BUILD_COMPLETE
```

2. **Add fix tasks to plan.md** — append a new phase at the bottom with tasks for each issue found:
```markdown
## Phase N+1: Review Fixes

### Tasks
- [ ] Task N.1: {Fix issue description} — {file:line}
- [ ] Task N.2: {Fix issue description} — {file:line}
```

3. **Update plan.md header** — change `**Status:** [x] Complete` back to `**Status:** [~] In Progress`

4. **Commit** the updated plan.md:
```bash
git add docs/plan/*/plan.md && git commit -m "fix: add review fix tasks (verdict: {FIX FIRST|BLOCK})"
```

This way the pipeline loops: `/review` (FIX FIRST) → removes BUILD_COMPLETE → `/build` picks up new tasks → `/build` creates BUILD_COMPLETE → `/deploy` → `/review` again.

## Error Handling

### Tests won't run
**Cause:** Missing dependencies or test config.
**Fix:** Run `npm install` / `uv sync`, check test config exists (jest.config, pytest.ini).

### Linter not configured
**Cause:** No linter config file found.
**Fix:** Note as a recommendation in the report, not a blocker.

### Build fails
**Cause:** Type errors, import issues, missing env vars.
**Fix:** Report specific errors. This is a BLOCK verdict — must fix before shipping.

## Two-Stage Review Pattern

When reviewing significant work, use two stages (inspired by `superpowers:requesting-code-review`):

**Stage 1 — Spec Compliance:**
- Does the implementation match spec.md requirements?
- Are all acceptance criteria actually met (not just claimed)?
- Any deviations from the plan? If so, are they justified improvements or problems?

**Stage 2 — Code Quality:**
- Architecture patterns, error handling, type safety
- Test coverage and test quality
- Security and performance
- Code organization and maintainability

If `superpowers:requesting-code-review` is available, use it to dispatch a dedicated code-reviewer agent for Stage 2. This gives an independent second opinion.

## Verification Gate

**Iron rule: NO VERDICT WITHOUT FRESH EVIDENCE.**

Before writing any verdict (SHIP/FIX/BLOCK):
1. **Run** the actual test/build/lint commands (not cached results).
2. **Read** full output — exit codes, pass/fail counts, error messages.
3. **Confirm** the output matches your claim.
4. **Only then** write the verdict with evidence.

If `superpowers:verification-before-completion` is available, invoke it before final verdict.

Never write "tests should pass" — run them and show the output.

## Rationalizations Catalog

| Thought | Reality |
|---------|---------|
| "Tests were passing earlier" | Run them NOW. Code changed since then. |
| "It's just a warning" | Warnings become bugs. Report them. |
| "The build worked locally" | Check the platform too. Environment differences matter. |
| "Security scan is overkill" | One missed secret = data breach. Always scan. |
| "Good enough to ship" | Quantify "good enough". Show the numbers. |
| "I already checked this" | Fresh evidence only. Stale checks are worthless. |

## Critical Rules

1. **Run all checks** — do not skip dimensions even if project seems simple.
2. **Be specific** — always include file:line references for issues.
3. **Verdict must be justified** — every SHIP/FIX/BLOCK needs evidence from actual commands.
4. **Don't auto-fix code** — report issues and add fix tasks to plan.md. Let `/build` fix them. Review only modifies plan.md and BUILD_COMPLETE, never source code.
5. **Check acceptance criteria** — spec.md is the source of truth for "done".
6. **Security is non-negotiable** — any hardcoded secret = BLOCK.
7. **Fresh evidence only** — run commands before making claims. Never rely on memory.
