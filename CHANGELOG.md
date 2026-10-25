# Changelog

What changed for the people who install this plugin. Docs describe the current state;
history lives here. One entry per version, newest first; `scripts/check-version`
refuses a `plugin.json` version with no entry.

## 1.79.1 — 2026-10-24

- `swiftui-design-system` hands SwiftUI correctness to Apple's `swiftui-specialist`
  (bundled with Xcode 27, supersedes training) instead of a third-party skill.

## 1.79.0 — 2026-10-24

- New skill `skill-shelf`: usage per skill from session transcripts, shelve the
  unused to `~/.claude/skills-archive/` with origin and reason, `list` and `restore`
  on demand. Documents the switches for skills that are not files:
  `enabledPlugins`, `syncClaudeAiPlugins`, `syncClaudeAiSkills`. Measured on one
  machine: 198 visible skills → 92 after a pruning pass.
- `make plugin-publish` works again: it expanded `${CLAUDE_CONFIG_DIR:-…}` in make
  instead of the shell, and its `install` was a no-op on an installed plugin.

## 1.78.0 — 2026-10-24

- `idea-validator` agent removed: it preloaded two skills that do not exist
  (`validate-idea`, `apply-stream`) and duplicated `/validate`. Use `/solo:validate`.
- `researcher` agent now preloads `solo:solo-research` (was the missing
  `deep-research`, so it started with no procedure at all).
- Ships 1.77.0's changes, which were pushed without a version bump.

## 1.77.0 — 2026-10-22

- One version number: `plugin.json` is the source, `marketplace.json` and
  `pyproject.toml` follow it, `scripts/check-version` (run by `make doctor`) refuses
  drift. Before this the repo carried 1.77.0 / 1.25.0 / 1.20.0 / 1.22.0 at once.
- `rules/routing.md` no longer carries the Signal → Route table. Prompt-shape routing
  is done by the profile's `UserPromptSubmit` hook (harness-core); the rule keeps the
  directory markers and the pipeline order.
- `rules/skills.md` keeps only the current rules; the incident history moved to
  `docs/harness-case-log.md`.
- The SessionStart echo no longer claims a version or a hand-picked skill list.
- New skills since 1.71: `creator-growth`, `paper`, `open-dataset`, `youtube-channel`.
- Stop gate: an UNKNOWN on unchanged files blocks once, not every turn.
- `ios-release`: face data triggers an App Review 2.1 information request.
