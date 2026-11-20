---
name: solo-call-report
description: Turn a finished supervox session folder (transcript, speakers, owner notes) into a typed report.md, route it to the right place and end with one follow-up list. Use when user says "сделай отчёт по звонку", "разбери запись", "call report", "meeting notes", "итоги разговора", or when a call-ru, call-en, call-tr or supervox session stops. Do NOT use for live listening during the call (use /supervox or /call-*) or for transcribing a file that did not come from supervox (use /transcribe).
license: MIT
metadata:
  author: fortunto2
  version: "1.0.0"
  openclaw:
    emoji: "📝"
---

# call-report — a session folder in, a typed report out

Router plus core rules. The section prompts for each type live in `references/`; read only the one you picked.

## Input

A supervox session folder (`~/.supervox/live/sessions/<start>/`, or the path the caller gives):

- `stream.jsonl`: `transcript` events with `t` (seconds), `speaker`, `text`
- `speakers.json`: names for `S<n>` clusters (may be partial)
- optional: `notes.md` (the owner's jottings), focus points, the answer to the start question, camera frames, `summary.md` (the live panel, a hint, not a source)

## 1. Classify

Signals, in this order: the answer to the start question; calendar title if a calendar is reachable; the first ~50 transcript lines; who is on the call.

| Type | Reference | Typical |
|---|---|---|
| `recap` | `references/recap.md` | default, anything unclear |
| `public-talk` | `references/public-talk.md` | panel, talk, meetup, demo day, hackathon, podcast |
| `client` | `references/client.md` | sales, partner, vendor, consulting call |
| `official` | `references/official.md` | government, immigration, grant, bank, tax, legal |
| `interview` | `references/interview.md` | customer or user interview |
| `personal` | `references/personal.md` | friends, family |
| `interpreter` | `references/interpreter.md` | a MODE on top of any type: the owner needed live translation |

Unclear or mixed: use `recap` and say so in the first line of the report ("type unclear, used recap"). Never guess `official` or `personal` from thin signals: they change routing.

## 2. Core rules (all types)

- **Grounded.** Every claim carries a short quote and a timestamp: `"quote" (12:40, Anna)`. No quote, no claim.
- **ASR is lossy.** Proper nouns, numbers, dates and amounts are the usual casualties. When a phrase looks mangled, write `[ASR gap?] heard "…"` and keep it; never repair a name or figure from memory. A name heard once is a guess: mark it.
- **Tasks.** One owner, one verb, a date only if it was spoken. "We should" with no owner goes to open questions, not tasks.
- **Skip empty sections.** A heading with nothing under it does not appear.
- **Notes steer.** If `notes.md` or focus points exist, expand what the owner jotted down, in his words, and compress the rest. Notes without transcript support are kept and marked `(from notes)`.
- **Language.** Report in the owner's language; quotes stay in the speaker's language, with a gloss when they differ.
- **Interpreter mode** stacks on any type: add the sections of `references/interpreter.md` when the owner used live translation.
- **Short beats complete.** A 10-minute call gets a page, not three.

## 3. Write `report.md`

Into the session folder. First line: type, date, duration, who (named, with `S<n>` for unnamed). Then the sections of the chosen reference, in its order.

## 4. Route

By type, without asking unless unclear:

| Type | Goes to |
|---|---|
| public-talk | a draft through the owner's wiki skill, published per that repo's rules |
| client, interview, project calls | the project's task registry and notes, plus a decision or finding `capture` into the brain inbox if the KB has one |
| official | the matter's own folder or registry entry; deadlines and reference numbers become tasks with dates |
| personal | the owner's private area only, as his CLAUDE.md defines it; never summarized into another project, a brain capture or a shared wiki |
| employer or work calls | only the channel the owner's CLAUDE.md names for work; nothing into personal tooling |

If the owner's CLAUDE.md has no rule for a destination, leave `report.md` where it is and say so.

Public repo note: this skill names no destination of its own. Paths and channels come from the owner's own instructions.

## 5. End with ONE numbered list

The last thing in chat, answerable in one line:

1. Each leftover `S<n>` with 1-2 sample lines: who is it? Each answer becomes `supervox voices name <session> S<n> <name>`.
2. Destination, only if the type or routing was unclear.
3. Follow-up draft (message or email to the other side): yes or no?

Omit a number that does not apply; do not renumber into a longer list.

## Gotchas

- `summary.md` from the live loop is often rewritten and drops detail. Build from `stream.jsonl`.
- Diarization is far-field: `S1` can be two people. Quote the line, not the label, when it matters.
- A recording with no speech has no folder; an `-empty` folder holds only files the owner put there.

## Don't

- Invent an attribution, number, date or name.
- Paste long verbatim passages into anything that leaves the machine; private calls become lessons without names.
- Route a personal or official report into a shared place "for context".
