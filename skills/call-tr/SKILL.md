---
name: solo-call-tr
description: Start live transcription and a rolling agent summary for a phone call in Turkish in seconds, without editing config. Use when user says "звонок по-турецки, включи турецкий, слушай звонок", "call-tr", "turkish call, listen to this call in Turkish", or a call in Turkish is about to start. Do NOT use for a room or conference in English (use /supervox) or for transcribing a finished recording (use /transcribe).
license: MIT
metadata:
  author: fortunto2
  version: "1.1.0"
  openclaw:
    emoji: "🇹🇷"
---

# call-tr — Turkish call, live

Whisper large-v3-turbo (q5_0, Metal) via a per-run config; Parakeet v3 has no Turkish. Measured real-time factor about 0.2 per 2 s chunk on an M5.

## Workflow

1. Start it (one command, no config edits, stops a supervox already running):
   `${CLAUDE_PLUGIN_ROOT}/skills/supervox/scripts/supervox-call tr`
   It prints the session folder; a TUI runs in tmux session `supervox-call`.
2. Push the call into this session as it happens: arm **Monitor** (`timeout_ms: 1800000`, re-arm when it expires) on
   `tail -n 0 -F ~/.supervox/live/current.jsonl | grep --line-buffered '"transcript"'`.
   Each event is one finished phrase (`speaker`, `text`, `t`). Answer every event in chat, short:
   Every line: the Russian translation in one line (`TR → RU`), then, only when useful, a few words on what is going on (who wants what, a term, an amount, a date). When the other side asks a question or waits for an answer, suggest 1-2 short replies **in Turkish** with a Russian gloss, simple enough to say aloud, using what this chat already knows.
   Speaker labels: a name from `~/.supervox/voices` (the owner's voiceprint) is the user, `AGENT` is our own voice (skip it), `S<n>` are the others.
   Keep the rolling summary in `~/.supervox/live/summary.md` (the TUI panel) as in `/solo:supervox`.
3. On `stop`: write the full summary, give the session folder.

## Channel mode (from a terminal)

`${CLAUDE_PLUGIN_ROOT}/skills/supervox/scripts/supervox-chat tr` starts supervox and opens Claude Code with the supervox channel and this skill already loaded: phrases arrive as `<channel source="supervox" kind="transcript">` events instead of through Monitor. Handle each one as step 2 says.

## Gotchas

- Model file `~/.supervox/models/ggml-large-v3-turbo-q5_0.bin` (574 MB) must exist; the launcher prints the download command if not.
- Quiet phone audio is the failure mode: supervox must be built with the gain control + silence gate in `whisper_stt.rs`, else Whisper loops "thank you for watching".
