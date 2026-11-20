---
name: solo-call-en
description: Start live transcription and a rolling agent summary for a phone call in English in seconds, without editing config. Use when user says "звонок по-английски, включи английский", "call-en", "english call", or a call in English is about to start. Do NOT use for a room or conference in English (use /supervox) or for transcribing a finished recording (use /transcribe).
license: MIT
metadata:
  author: fortunto2
  version: "1.1.0"
  openclaw:
    emoji: "🇬🇧"
---

# call-en — English call, live

Parakeet, local: v3 when installed (it is, and supervox picks it for every language; English WER on par with v2), else v2.

## Workflow

1. Start it (one command, no config edits, stops a supervox already running):
   `${CLAUDE_PLUGIN_ROOT}/skills/supervox/scripts/supervox-call en`
   It prints the session folder; a TUI runs in tmux session `supervox-call`.
   Never block the start on questions: once it runs, ask the owner ONE optional line in chat (who is on the call, topic); if he answers, use it for gists and answers, and write names to `speakers.json` as clusters get confirmed.
2. Push the call into this session as it happens: arm **Monitor** (`timeout_ms: 1800000`, re-arm when it expires) on
   `tail -n 0 -F ~/.supervox/live/current.jsonl | grep --line-buffered '"transcript"'`.
   Each event is one finished phrase (`speaker`, `text`, `t`). Answer every event in chat, short:
   Every line: the Russian translation in one line (`EN → RU`), then, only when useful, a few words on what is going on (who wants what, a term, a number). When the other side asks a question or waits for an answer, suggest 1-2 short replies **in English** the user can say aloud, using what this chat and the repo already know.
   Speaker labels: a name from `~/.supervox/voices` (the owner's voiceprint) is the user, `AGENT` is our own voice (skip it), `S<n>` are the others.
   If context makes the speaker clear (the owner says his name, answers what was asked of him, continues his own thought) but the label is `S<n>`, merge `{"S<n>": "<name>"}` into the session's `speakers.json` (`~/.supervox/live/speakers.json`) at once and use the real name in chat and summary.
   Unsure who a cluster is: note it, do not ask mid-call unless he invites it.
   Keep the rolling summary in `~/.supervox/live/summary.md` (the TUI panel) as in `/solo:supervox`.
3. On `stop`: write the full summary, give the session folder, then one short numbered list he can answer in one line: (1) each leftover `S<n>` cluster with 1-2 sample lines, who is it (`supervox voices name <session> S<n> <name>` for each answer); (2) what to do with the outcome (tasks, follow-up message draft).
   Then write `report.md` into the session folder (who, topic, decisions, tasks with owner and dates, open questions, insights, follow-up draft; only sections with content) and route it by context as in `/solo:supervox` "Call report": public call -> the owner's wiki, project/client call -> the project's tasks and notes plus a brain `capture`, personal call -> private notes area only. Ask only if the type is unclear, inside the same list.

## Channel mode (from a terminal)

`${CLAUDE_PLUGIN_ROOT}/skills/supervox/scripts/supervox-chat en` starts supervox and opens Claude Code with the supervox channel and this skill already loaded: phrases arrive as `<channel source="supervox" kind="transcript">` events instead of through Monitor. Handle each one as step 2 says.

## Gotchas

- English only; for another language use `/solo:call-tr` or `/solo:call-ru`.
