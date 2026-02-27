---
name: solo-memory-audit
description: Audit Claude Code memory hierarchy — CLAUDE.md files, rules, auto-memory, imports. Shows tree of loaded files, char counts, and optimization hints (large files, duplicates, unconditional rules). Use when user says "audit memory", "check CLAUDE.md", "memory map", "rules audit", "context budget", or "what loads in my session".
license: MIT
metadata:
  author: fortunto2
  version: "1.0.0"
  openclaw:
    emoji: "🧠"
allowed-tools: Read, Grep, Bash, Glob
argument-hint: "[optional: project path or 'all' for all projects]"
---

# /memory-audit

Audit Claude Code memory hierarchy for a project. Shows what files load at session start, total context budget, and optimization hints.

## Context

Claude Code loads memory files at session start in this order:
1. Managed policy (`/Library/Application Support/ClaudeCode/CLAUDE.md`)
2. User memory (`~/.claude/CLAUDE.md`)
3. User rules (`~/.claude/rules/*.md`)
4. Auto-memory (`~/.claude/projects/{key}/memory/MEMORY.md`, first 200 lines)
5. Project hierarchy (walk from `/` to CWD: `CLAUDE.md`, `.claude/CLAUDE.md`, `.claude/rules/*.md`)
6. Local overrides (`CLAUDE.local.md` at each level)

Rules with `paths:` frontmatter are conditional — loaded only when working on matching files. Rules without `paths:` always load and consume context budget.

Target: keep startup context under 40k chars. Large CLAUDE.md files should extract domain-specific sections into conditional `.claude/rules/*.md` files.

## Steps

1. **Determine target.** Parse `$ARGUMENTS`:
   - Empty or `.` -> use CWD
   - Path -> use that path
   - `all` -> scan CWD subdirectories that have CLAUDE.md

2. **Run memory_map.py.** Execute:
   ```bash
   uv run python ${CLAUDE_PLUGIN_ROOT}/scripts/memory_map.py <path> --audit
   ```
   If `all` argument, add `--all-projects` flag instead of path.

   If `uv` is not available, fall back to:
   ```bash
   python ${CLAUDE_PLUGIN_ROOT}/scripts/memory_map.py <path> --audit --plain
   ```

3. **Analyze the output.** Read the tree display and audit hints table. Key metrics:
   - **Total startup chars** — should be under 40k
   - **Large files** (>300 lines) — candidates for splitting into rules
   - **Unconditional rules** (>30 lines, no `paths:` frontmatter) — add `paths:` to make conditional
   - **Duplicate sections** — same `## Header` in multiple files, extract to one place
   - **Missing auto-memory** — project doesn't learn across sessions

4. **Generate recommendations.** Based on audit hints, suggest concrete actions:

   | Issue | Action |
   |-------|--------|
   | File > 300 lines | Extract domain sections to `.claude/rules/{topic}.md` with `paths:` frontmatter |
   | Total > 40k chars | Identify largest files, move conditional content to rules |
   | Unconditional rule > 30 lines | Add `paths:` frontmatter targeting relevant source files |
   | Duplicate sections | Keep in the highest-level file, remove from children |
   | No auto-memory | Normal for new projects, just informational |
   | User-level rule is project-specific | Move from `~/.claude/rules/` to project's `.claude/rules/` |
   | Generic rule in project | Move up to `~/.claude/rules/` or parent CLAUDE.md |

5. **Check hierarchy health.** For the target project:
   - Verify parent CLAUDE.md files exist (inheritance chain intact)
   - Check that project CLAUDE.md has essential sections (structure, commands, stack)
   - Verify `.claude/rules/` files have valid `paths:` frontmatter syntax

6. **Output report:**
   ```
   ## Memory Audit Report

   **Project:** [path]
   **Startup context:** X files, ~Y chars (Z% of 40k budget)

   ### Tree
   [paste tree output from memory_map.py]

   ### Issues Found
   [from audit hints]

   ### Recommendations
   1. [specific action with file path]
   2. [specific action with file path]

   ### Hierarchy Health
   - Inheritance chain: [OK / broken at level X]
   - Auto-memory: [present / missing]
   - Rules: X total (Y conditional, Z always-on)
   ```

## Rules Frontmatter Reference

Conditional rules load only when the agent works on files matching the glob pattern:

```yaml
---
paths:
  - "src/lib/analytics/**"
  - "src/app/api/analytics/**"
---
# Analytics Module
...content only loaded when working on analytics files...
```

Without `paths:`, the rule always loads and consumes context budget.
