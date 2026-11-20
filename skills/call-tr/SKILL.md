---
name: solo-call-tr
description: Start live transcription and a rolling agent summary for a phone call in Turkish in seconds, without editing config. Use when user says "звонок по-турецки, включи турецкий, слушай звонок", "call-tr", "turkish call, listen to this call in Turkish", or a call in Turkish is about to start. Do NOT use for a room or conference in English (use /supervox) or for transcribing a finished recording (use /transcribe).
license: MIT
metadata:
  author: fortunto2
  version: "1.0.0"
  openclaw:
    emoji: "🇹🇷"
---

# call-tr — Turkish call, live

Whisper large-v3-turbo (q5_0, Metal) via a per-run config; Parakeet v3 has no Turkish. Measured real-time factor about 0.2 per 2 s chunk on an M5.

## Workflow

1. Start it (one command, no config edits, stops a supervox already running):
   `${CLAUDE_PLUGIN_ROOT}/skills/supervox/scripts/supervox-call tr`
   It prints the session folder; a TUI runs in tmux session `supervox-call`.
2. Follow the **Live loop** in `/solo:supervox`: Monitor on
   `tail -n +1 -F ~/.supervox/live/current.jsonl` in the main session, summary panel at
   `~/.supervox/live/summary.md`, delta to chat in 2-6 lines. Summary language: the user's.
   Drop lines that are a stock subtitle phrase ("izlediğiniz için teşekkürler", "Altyazı M.K.") instead of summarising them. Numbers (amounts, dates, tax terms) are quoted with `t=`: Turkish phone ASR garbles digits first.
3. On `stop`: write the full summary, give the session folder.

## Gotchas

- Model file `~/.supervox/models/ggml-large-v3-turbo-q5_0.bin` (574 MB) must exist; the launcher prints the download command if not.
- Quiet phone audio is the failure mode: supervox must be built with the gain control + silence gate in `whisper_stt.rs`, else Whisper loops "thank you for watching".
