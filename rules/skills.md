# Where Skills Live (edit here, not there)

`~/.claude/skills/` is the **runtime** — Claude Code reads skills from it, but most of what appears
there is not the source. Editing a skill in the place you happened to load it from is the mistake this
rule exists to prevent.

## Source of truth

Find the solo-factory checkout on this machine — don't guess the path:

```bash
readlink ~/.claude/plugins/cache/solo/solo/*   # → the repo skills are served from
```

| What | Where | In git? |
|------|-------|---------|
| Startup/dev skills (`solo:*`) | `<solo-factory>/skills/<name>/SKILL.md` | yes — solo-factory |
| Personal skills (music, home, one-offs) | `~/.claude/skills/<name>/SKILL.md` | no, unless you version it yourself |
| Third-party skills | `~/.claude/plugins/cache/<marketplace>/…`, `~/.agents/skills/<theirs>` | not yours — don't edit |
| **`solo-*` in `~/.agents/skills/`** | the shared store codex/cursor/opencode read — must be a **symlink** to `<solo-factory>/skills/<name>` | the repo, via the link |
| **Apple's, bundled in Xcode 27+** | `/Applications/Xcode*.app/Contents/PlugIns/IDEIntelligenceChat.framework/…/Resources/*.idechatprompttemplate` (+ `IDEXCStringsSupport…/Skills` for localization) | not yours — read only |
| User rules | `<solo-factory>/rules/*.md` → symlinked into `~/.claude/rules/` | yes — solo-factory |
| User `CLAUDE.md` | keep it in a repo **you own** and symlink to `~/.claude/CLAUDE.md` | your call |

Apple's are in our own format (`SKILL.md` frontmatter + `references/`, just with a `.packaged`
extension) and their header says they supersede anything the model learned elsewhere — so on SwiftUI,
App Intents, UIKit modernization or String Catalogs, read Apple's before writing our own rule.
Xcode 27 also eats the same plugin repos the CLI does (`.claude-plugin`, a marketplace URL, skill
import/export), and pins the agent CLIs it downloads in `AgentVersions.plist`. Details and the
condensed rules: `<solo-factory>/skills/swiftui-design-system/references/apple-xcode-skills.md`.

solo-factory is installed as the `solo` plugin, and its cache dir is a **symlink to the repo**
(`make plugin-link`). So a skill edited in solo-factory is live in the next session — no copying, no
reinstall. Its invocation name is `solo:<name>`.

**solo-factory is a public repo.** Personal preferences, client names, account/app IDs, private paths
and anything from `~/personal/` belong in a private repo — never in a skill here. Skills are written
for whoever installs them, so keep examples generic (`com.example.app`, `user@example.com`).

## Rules

- **A solo skill must be reachable by exactly one route.** The plugin serves all of them as
  `solo:<name>`; a second entry under `~/.claude/skills/` is a duplicate even when it is a symlink,
  because the session then loads two descriptions of one skill. `npx skills add fortunto2/solo-factory`
  installs a *snapshot* into `~/.agents/skills/solo-<name>` — fine for other agents, wrong for this
  one. Point those at the repo and delete the `~/.claude/skills/` entries.
- **Never copy a `SKILL.md` between locations.** A copy silently forks: the runtime one gets the edits,
  the git one rots, and the next agent finds two different truths. Symlink or git — nothing else.
- **Before creating or editing a skill, find its source**: `ls <solo-factory>/skills/`. If the name is
  there, that file is the one to edit — regardless of which path the loaded skill came from.
- **New startup/dev skill** → `make new-skill S=<name>` in solo-factory. Don't hand-create the directory.
- **New personal skill** (not startup work) → `~/.claude/skills/<name>/SKILL.md` is fine, and it stays
  outside git; say so when you create it.
- **After changing skill layout** (new skill, moved skill, fresh machine) → `make doctor` in solo-factory.
  It checks the plugin symlink, duplicate skills, and linked rules.

## History

Two incidents shaped these rules (a `npx skills add` snapshot that drifted on 28 skills,
and a plugin installed as a copy). Both are in `docs/harness-case-log.md` under
"Where skills live".
