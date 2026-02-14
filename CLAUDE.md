# CLAUDE.md — solo-factory

Claude Code plugin for solopreneurs. Single source of truth for all skills, agents, hooks, and templates.

## Structure

```
.claude-plugin/plugin.json  # Manifest (name, version)
skills/                     # 22 skills (SKILL.md + references/)
agents/                     # 3 agents (researcher, code-analyst, idea-validator)
hooks/                      # SessionStart info + Stop pipeline hook
scripts/                    # Pipeline launchers (bighead, solo-dev.sh, solo-research.sh, solo-codex.sh)
templates/                  # Stack templates, dev principles, PRD templates
solo → .claude-plugin/      # Symlink for plugin cache compatibility
Makefile                    # plugin-link, plugin-publish
```

## Publishing Plugin

After editing skills, agents, hooks, or templates:

```bash
# 1. Bump version in .claude-plugin/plugin.json (e.g. 1.4.0 → 1.5.0)
# 2. Commit and publish:
git add -A && git commit -m "feat: description"
make plugin-publish    # git push + sync marketplace clone + claude plugin install
```

**Always bump version before publishing.** `claude plugin update` compares version strings — same version = no update.

### How it works

1. `git push` — pushes to GitHub (`fortunto2/solo-factory`)
2. Marketplace clone (`~/.claude/plugins/marketplaces/solo/`) is synced via `git fetch + reset`
3. `claude plugin install solo@solo --scope user` — copies from marketplace to cache
4. New Claude Code session picks up updated skills

### Dev mode (no push needed)

```bash
make plugin-link    # symlinks cache → solo-factory dir, changes are instant
```

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

## Don't

- Don't forget to bump version before `make plugin-publish`
- Don't use bare skill names without `solo-` prefix
- Don't hardcode absolute paths in skills
- Don't modify `solo` symlink (it maps `.claude-plugin/` for cache compatibility)
