# Where Skills Live (edit here, not there)

`~/.claude/skills/` is the **runtime** — Claude Code reads skills from it, but most of what appears
there is not the source. Editing a skill in the place you happened to load it from is the mistake this
rule exists to prevent.

## Source of truth

| What | Where | In git? |
|------|-------|---------|
| Startup/dev skills (`solo:*`) | `~/startups/solopreneur/solo-factory/skills/<name>/SKILL.md` | yes — solo-factory (submodule of solopreneur) |
| Personal skills (music, home, one-offs) | `~/.claude/skills/<name>/SKILL.md` | no |
| Third-party skills | `~/.claude/plugins/cache/<marketplace>/…` or `~/.agents/skills/` | not ours — don't edit |
| User rules | `solo-factory/rules/*.md` → symlinked into `~/.claude/rules/` | yes — solo-factory (public) |
| User `CLAUDE.md` | `solopreneur/claude-user/CLAUDE.md` → symlinked to `~/.claude/CLAUDE.md` | yes — solopreneur (**private**) |

solo-factory is **public**: personal preferences, private paths and anything from `~/personal/` go in
the private repo, never here.

solo-factory is installed as the `solo` plugin, and its cache dir is a **symlink to the repo**
(`make plugin-link`). So a skill edited in solo-factory is live in the next session — no copying, no
reinstall. Its invocation name is `solo:<name>`.

## Rules

- **Never copy a `SKILL.md` between locations.** A copy silently forks: the runtime one gets the edits,
  the git one rots, and the next agent finds two different truths. Symlink or git — nothing else.
- **Before creating or editing a skill, find its source**: `ls ~/startups/solopreneur/solo-factory/skills/`.
  If the name is there, that file is the one to edit — regardless of which path the loaded skill came from.
- **New startup/dev skill** → `make new-skill S=<name>` in solo-factory. Don't hand-create the directory.
- **New personal skill** (not startup work) → `~/.claude/skills/<name>/SKILL.md` is fine, and it stays
  outside git; say so when you create it.
- **After changing skill layout** (new skill, moved skill, fresh machine) → `make doctor` in solo-factory.
  It checks the plugin symlink, duplicate skills, and linked rules.

## Why this bit us

The `solo` plugin was installed as a *copy* of solo-factory, so new skills didn't reach sessions and got
copied into `~/.claude/skills/` as a workaround. Two copies then drifted, and an agent updated the runtime
copy while the git one stayed old. Fixed by symlinking the plugin cache to the repo — see
[[harness-engineering]]: agent mistake → fix the harness, not the agent.
