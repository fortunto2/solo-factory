---
name: solo-call-en
description: Start live transcription and a rolling agent summary for a phone call in English in seconds, without editing config. Use when user says "звонок по-английски, включи английский", "call-en", "english call", or a call in English is about to start. Do NOT use for a room or conference in English (use /supervox) or for transcribing a finished recording (use /transcribe).
license: MIT
metadata:
  author: fortunto2
  version: "1.0.0"
  openclaw:
    emoji: "🇬🇧"
---

# call-en — English call, live

Parakeet, local: v3 when installed (it is, and supervox picks it for every language; English WER on par with v2), else v2.

## Workflow

1. Start it (one command, no config edits, stops a supervox already running):
   `${CLAUDE_PLUGIN_ROOT}/skills/supervox/scripts/supervox-call en`
   It prints the session folder; a TUI runs in tmux session `supervox-call`.
2. Follow the **Live loop** in `/solo:supervox`: Monitor on
   `tail -n +1 -F ~/.supervox/live/current.jsonl` in the main session, summary panel at
   `~/.supervox/live/summary.md`, delta to chat in 2-6 lines. Summary language: the user's.
3. On `stop`: write the full summary, give the session folder.

## Gotchas

- English only; for another language use `/solo:call-tr` or `/solo:call-ru`.
