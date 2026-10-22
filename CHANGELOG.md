# Changelog

What changed for the people who install this plugin. Docs describe the current state;
history lives here. One entry per version, newest first; `scripts/check-version`
refuses a `plugin.json` version with no entry.

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
