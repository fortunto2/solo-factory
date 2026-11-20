---
name: solo-call-ru
description: Start live transcription and a rolling agent summary for a phone call in Russian in seconds, without editing config. Use when user says "звонок по-русски, включи русский, слушай звонок", "call-ru", "russian call", or a call in Russian is about to start. Do NOT use for a room or conference in English (use /supervox) or for transcribing a finished recording (use /transcribe).
license: MIT
metadata:
  author: fortunto2
  version: "1.0.0"
  openclaw:
    emoji: "🇷🇺"
---

# call-ru — Russian call, live

Parakeet v3 (25 European languages, Russian included), local, no Whisper.

## Workflow

1. Start it (one command, no config edits, stops a supervox already running):
   `${CLAUDE_PLUGIN_ROOT}/skills/supervox/scripts/supervox-call ru`
   It prints the session folder; a TUI runs in tmux session `supervox-call`.
2. Follow the **Live loop** in `/solo:supervox`: Monitor on
   `tail -n +1 -F ~/.supervox/live/current.jsonl` in the main session, summary panel at
   `~/.supervox/live/summary.md`, delta to chat in 2-6 lines. Summary language: the user's.
3. On `stop`: write the full summary, give the session folder.

## Gotchas

- Needs `~/.supervox/models/parakeet-tdt-v3`; the launcher does not check it, supervox falls back to English v2 if it is missing and the text turns into English nonsense.
