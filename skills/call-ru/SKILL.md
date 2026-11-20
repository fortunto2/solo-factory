---
name: solo-call-ru
description: Start live transcription and a rolling agent summary for a phone call in Russian in seconds, without editing config. Use when user says "звонок по-русски, включи русский, слушай звонок", "call-ru", "russian call", or a call in Russian is about to start. Do NOT use for a room or conference in English (use /supervox) or for transcribing a finished recording (use /transcribe).
license: MIT
metadata:
  author: fortunto2
  version: "1.1.0"
  openclaw:
    emoji: "🇷🇺"
---

# call-ru — Russian call, live

Parakeet v3 (25 European languages, Russian included), local, no Whisper.

## Workflow

1. Start it (one command, no config edits, stops a supervox already running):
   `${CLAUDE_PLUGIN_ROOT}/skills/supervox/scripts/supervox-call ru`
   It prints the session folder; a TUI runs in tmux session `supervox-call`.
2. Push the call into this session as it happens: arm **Monitor** (`timeout_ms: 1800000`, re-arm when it expires) on
   `tail -n 0 -F ~/.supervox/live/current.jsonl | grep --line-buffered '"transcript"'`.
   Each event is one finished phrase (`speaker`, `text`, `t`). Answer every event in chat, short:
   Each line arrives as is (the user's own language): no translation. After every 2-4 lines give a one-line gist; when someone asks the user a question, suggest a short answer.
   Speaker labels: a name from `~/.supervox/voices` (the owner's voiceprint) is the user, `AGENT` is our own voice (skip it), `S<n>` are the others.
   Keep the rolling summary in `~/.supervox/live/summary.md` (the TUI panel) as in `/solo:supervox`.
3. On `stop`: write the full summary, give the session folder.

## Gotchas

- Needs `~/.supervox/models/parakeet-tdt-v3`; the launcher does not check it, supervox falls back to English v2 if it is missing and the text turns into English nonsense.
