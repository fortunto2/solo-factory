# Changelog

What changed for the people who install this plugin. Docs describe the current state;
history lives here. One entry per version, newest first; `scripts/check-version`
refuses a `plugin.json` version with no entry.

## 1.82.1 — 2026-10-26

- `video-edit`: "Copy first, encode only what changed" in `references/delivery.md`. A full recording, a trim, a muted line, loudness and an outro need no picture re-encode: copy the video stream, process only the audio, concat the outro. Measured on the same SD card: stream copy 4.4x realtime against 1.2x for an HEVC 1440p re-encode. Upload each file as soon as it is ready.

## 1.82.0 — 2026-10-25

- `secret_guard` hook (new): credentials stay out of the conversation. PostToolUse on every tool masks keys in the output as `[REDACTED:<rule> len=N id=<sha8>]` before the model sees them (Read, Bash, Grep, MCP alike; the output keeps its structure). PreToolUse refuses a Write/Edit that would write a marker over the real secret. UserPromptSubmit blocks a prompt with a pasted key and moves the value to `~/.claude/secrets/<project>.env` (0600). `audit` lists secrets already in transcripts without values; `scrub` rewrites old transcripts, needed because Claude Code echoes a blocked prompt into the transcript as "Original prompt". Verified end to end with `claude -p`: the key was in neither the answer nor the transcript. 20 ms per tool call, 90 ms on 1 MB. Off: `SECRET_GUARD=off`.
- Stop gate: a session that changed nothing is not blocked on a tree that was already dirty or red (`sensor-baseline.sh` at SessionStart).

## 1.81.1 — 2026-10-25

- `transcribe`: both scripts pin `av<19`. PyAV 19 removed `metadata_errors`, which faster-whisper 1.2.1 still passes, so a clean `uv run` failed on the first real file while `--help` worked. Checked from an empty uv cache on both paths.

## 1.81.0 — 2026-10-25

- New `video-edit`: footage to a film with the agent as editor. Editorial rules (cutaways that match
  the words, never over moving lips, hand-picked hook, scenes not best phrases), an eyes-before-render
  pass, and `references/sound.md` + `references/delivery.md` with ffmpeg recipes each re-run on a
  test clip. Found while checking them: Homebrew's default `ffmpeg` has neither `ass` nor `drawtext`;
  a concat-copy outro with a 48 vs 44.1 kHz card came out 8.71 s instead of 8.0 with no error.
- New `transcribe` (was a personal skill): mlx-whisper large-v3 on the Apple GPU as the default on a
  Mac (38-min talk in 8.7 min), language per silence-split chunk, `--words` writes word timings for
  editing. PEP 723 headers, so `uv run` needs no venv; Python pinned `<3.14`.
- New `stem-split` (was a personal skill): Demucs with `-d mps`. Measured 60 s of music in 8.3 s vs
  15.7 s on CPU, stems equal to 0.1 dB. The old text said the Mac was CPU-only.

## 1.80.0 — 2026-10-24

- Stop gate: whole-suite sensors (`pytest`, `cargo test`, `clippy`, `tsc`) run only
  when the change has a file or manifest of their language; otherwise they are
  not-applicable with that reason. Measured on a repo with Cargo.toml and
  pyproject.toml: a `.jpg`/`.yml` change ran cargo test (138 s) and pytest (96 s)
  every turn against the 120 s gate, 325 timeouts in three weeks, no verdict. Now
  0.36 s. Published promises in `rules/harness-sensors.md` changed accordingly.

## 1.79.2 — 2026-10-24

- `swiftui-design-system/references/apple-xcode-skills.md`: install Apple's skills
  and Xcode's MCP server as the plugin Xcode 27.1 exports
  (`xcrun agent plugin path --plugin-format claude`), scoped per project.

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
