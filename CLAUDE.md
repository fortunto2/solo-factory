# CLAUDE.md — solo-factory

Claude Code plugin for solopreneurs. Single source of truth for all skills, agents, hooks, and templates.

## Structure

```
.claude-plugin/plugin.json  # Manifest (name, version)
skills/                     # 23 skills (SKILL.md + references/)
agents/                     # 3 agents (researcher, code-analyst, idea-validator)
hooks/                      # SessionStart info + Stop pipeline hook
scripts/                    # Pipeline launchers (bighead, solo-dev.sh, solo-research.sh, solo-codex.sh)
templates/                  # Stack templates, dev principles, PRD templates
Makefile                    # plugin-link, plugin-publish, evolve, evolve-apply, factory-critique
solo → .claude-plugin/      # Symlink for plugin cache compatibility
```

## Publishing (3 Registries)

Skills are dual-compatible: Claude Code plugin + OpenClaw ClawHub. Each SKILL.md has `metadata.openclaw` block.

### Registries

| Registry | Command | Audience |
|----------|---------|----------|
| **Claude Code plugin** | `make plugin-publish` | Claude Code users (plugin marketplace) |
| **ClawHub** | `make clawhub-publish S=name` | OpenClaw users (clawhub.com) |
| **npx skills** | automatic (from GitHub) | Any AI agent (Cursor, Copilot, Gemini CLI, Codex) |
| **All at once** | `make publish-all` | Push to all registries |

### Workflow

```bash
# 1. Edit skills
# 2. Bump version in .claude-plugin/plugin.json AND skill's SKILL.md metadata.version
# 3. Commit and publish:
git add -A && git commit -m "feat: description"

make plugin-publish          # Claude Code only
make clawhub-publish S=research MSG="Added Reddit fallback"  # One skill to ClawHub
make clawhub-publish-all     # All skills to ClawHub (slow, 3s delay per skill)
make publish-all             # All registries at once
```

**Always bump version before publishing.** Claude Code compares version strings. ClawHub rejects duplicate versions.

### How Claude Code plugin works

1. `git push` → GitHub (`fortunto2/solo-factory`)
2. Marketplace clone (`~/.claude/plugins/marketplaces/solo/`) synced via `git fetch + reset`
3. `claude plugin install solo@solo --scope user` → copies to cache
4. New session picks up updated skills

### How ClawHub works

1. `clawhub login` (one-time, GitHub OAuth)
2. `clawhub publish skills/<name> --slug solo-<name> --version <ver>` → published to clawhub.com
3. Users install via `clawhub install solo-<name>` or `clawhub sync`
4. Rate limit: ~10 publishes/batch, use 3s delay between skills

### How npx skills works

Automatic — `npx skills add fortunto2/solo-factory --all` pulls from GitHub directly. No extra publishing step.

### Dev mode (no push needed)

```bash
make plugin-link    # symlinks cache → solo-factory dir, changes are instant
```

### Adding OpenClaw metadata to new skills

Run `python3 scripts/add-openclaw-meta.py` — idempotently adds `openclaw:` block to all SKILL.md files. Edit `EMOJIS` dict in the script for new skill emoji.

## Skill Naming Convention

All skills MUST use `solo-` prefix in SKILL.md frontmatter:

```yaml
---
name: solo-review      # ✓ correct — matches /solo:review
name: review           # ✗ wrong — registers as /review, pipeline can't find it
---
```

The pipeline (`solo-dev.sh`) calls skills as `/solo:{name}`. Claude Code resolves skill names from the `name:` field in SKILL.md frontmatter with the plugin prefix.

## Key Rules

- **Skill names:** always `solo-{skillname}` in SKILL.md `name:` field
- **Version:** bump in `.claude-plugin/plugin.json` before every publish
- **MCP conditional:** skills must work with AND without MCP tools (use "IF available" pattern)
- **No hardcoded paths:** use `${CLAUDE_PLUGIN_ROOT}` or relative paths for references
- **Submodule:** this repo is included as git submodule in `solopreneur`
- **MCP in pipeline:** `solo-dev.sh` passes `--mcp-config ~/.mcp.json` so solograph tools work in `--print` sessions
- **Codex optional:** `solo-codex.sh` runs OpenAI Codex CLI for review/test/fix — reads `AGENTS.md` in project root
- **Factory Critic / Evolution Loop:** `/retro` Phase 10 runs factory critique (opus evaluates skills/scripts/pipeline), `solo-codex.sh --factory` adds independent Codex critique. Both append structured defects to `~/.solo/evolution.md`. Use `make evolve` to view, `make evolve-apply` to fix interactively, `make factory-critique P=project` to run Codex factory critique.
- **Signal priority:** `<solo:redo/>` takes priority over `<solo:done/>` when both present in same iteration output. `<solo:redo/>` removes ALL markers (build+deploy+review) and re-execs from build.
- **Circuit breaker:** fingerprint-based (md5 of last 5 lines), limit 3 identical failures

## Utilities

### `scripts/memory_map.py` — Claude Code Memory Map

Replicates Claude Code's memory loading algorithm. Shows exactly which CLAUDE.md files, rules, auto-memory, and `@`-imports are loaded for a given working directory.

```bash
python scripts/memory_map.py                    # from CWD
python scripts/memory_map.py /path/to/project   # for specific dir
python scripts/memory_map.py --all-projects     # scan CWD subdirs
python scripts/memory_map.py --json             # JSON output
```

**Algorithm:** walks from CWD up to `/` (not just git root), checks at each level: `CLAUDE.md`, `.claude/CLAUDE.md`, `.claude/rules/*.md`. Also loads: `~/.claude/CLAUDE.md` (user), `CLAUDE.local.md` (CWD only), auto-memory (`MEMORY.md`, first 200 lines). Deduplicates by resolved path. Detects `@`-imports (max depth 5). Child directory CLAUDE.md shown as on-demand.

**Markers:** `[~~]` user, `[am]` auto-memory, `[>>]` project hierarchy, `[pr]` rules, `[**]` local, `[..]` child (on-demand), `[@@]` import.

No dependencies — stdlib only (Python 3.10+).

## Don't

- Don't forget to bump version before `make plugin-publish`
- Don't use bare skill names without `solo-` prefix
- Don't hardcode absolute paths in skills
- Don't modify `solo` symlink (it maps `.claude-plugin/` for cache compatibility)
