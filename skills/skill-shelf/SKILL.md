---
name: solo-skill-shelf
description: Keep rarely used skills off the session's skill list and bring them back on demand — usage stats from transcripts, shelve, list, restore, plugin and claude.ai sync switches. Use when user says "skill usage", "which skills do I use", "archive skills", "too many skills", "bring back the X skill", "is there an archived skill for", "статистика скилов", "убери скилы", "достань скил", or a task needs a capability no loaded skill covers. Do NOT use for scoring one skill's quality (use /skill-audit) or creating a skill (make new-skill).
license: MIT
metadata:
  author: fortunto2
  version: "1.0.0"
  openclaw:
    emoji: "🗄️"
allowed-tools: Bash, Read
argument-hint: "stats | list [query] | shelve <name> | restore <name>"
---

# /skill-shelf

Every visible skill costs its description in every session, and tool choice gets
worse as the list grows (Anthropic reports selection degrading past 30–50
definitions). The shelf is a directory no skill loader reads. A skill on it costs
nothing, and `restore` makes it visible again from the next session.

```bash
SHELF="${CLAUDE_PLUGIN_ROOT}/skills/skill-shelf/scripts/shelf.py"
python3 "$SHELF" stats [--days 56]       # who was invoked, how often, last date; unused in ~/.claude/skills
python3 "$SHELF" list [query]            # what is on the shelf, with description and why it went there
python3 "$SHELF" shelve a b --reason "0 uses in 8 weeks"   # [--from <project>/.claude/skills]
python3 "$SHELF" restore a               # back where it came from; [--to <project>/.claude/skills]
```

Shelf: `$SKILL_SHELF_DIR`, default `~/.claude/skills-archive/`, with `.shelf.json`
recording origin, date and reason per skill.

## When a task needs a skill you do not have

Before writing the procedure from scratch, run `shelf list <keyword>`. If one
fits, `restore` it, tell the user it is back, and read its SKILL.md by path for
this session (a restored skill is listed only from the next session).

## Pruning pass

1. `stats`. Zero is a candidate, not a verdict: a skill read by path instead of
   invoked is not counted, and transcripts older than `cleanupPeriodDays` are gone.
2. Shelve third-party skills with zero uses. Own skills with zero uses: ask, or
   move them into the one project that needs them (`restore --to`).
3. **Scope by folder** where use is local: `<project>/.claude/skills/`. Claude Code
   does NOT read `.claude/skills` from parent directories (measured: a skill in
   `~/projects/.claude/skills` is invisible to a session in `~/projects/app`), so
   the scope is one project, not a tree.
4. Verify with a headless count, never by assumption:
   `claude -p 'How many skills are available via the Skill tool? total=N'`.

## Skills that are not files

| Source | Switch (in `~/.claude/settings.json`) |
|---|---|
| Plugin | `"enabledPlugins": {"name@marketplace": false}` (per project in `.claude/settings.json`) |
| Plugins synced from claude.ai (Cowork: `marketing:`, `design:` …) | `"syncClaudeAiPlugins": false`. `enabledPlugins` does not reach them |
| Skills synced from claude.ai (`anthropic-skills:*`) | `"syncClaudeAiSkills": false` |

## Don't

- Don't shelve a plugin's skill by moving files inside the plugin cache; the next
  update restores it. Disable the plugin, or split it.
- Don't `rm` a skill to prune it. The shelf is the undo.
- Don't call a skill unused from a run that read zero transcripts: `stats` exits 2
  with UNKNOWN in that case, on purpose.
