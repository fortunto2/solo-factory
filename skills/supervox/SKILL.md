---
name: solo-supervox
description: Listen to a live room with supervox (local transcription) and keep one evolving summary on its panel; coach a pitch's Q&A; analyse a saved recording afterwards. Use when user says "слушай конфу", "включи супервокс", "что там говорят", "саммари по ходу", "режим критика", "подсказывай на питче", "разбери запись", or when ~/.supervox/live/current.jsonl is being written. Do NOT use for transcribing an audio file that did not come from supervox (use the transcribe skill).
license: MIT
metadata:
  author: fortunto2
  version: "1.0.0"
  openclaw:
    emoji: "🎧"
---

# supervox — I listen with you

[supervox](https://github.com/fortunto2/supervox) transcribes the room on the device (Parakeet,
far-field diarization S1..S3) and appends one JSON object per line to
`~/.supervox/live/current.jsonl`. With `summary = "external"` in `~/.supervox/config.toml` it shows
whatever the agent writes to `~/.supervox/live/summary.md` in its right panel within 2 s. supervox
records and saves; the agent does every bit of analysis.

```json
{"type":"start","ts":"…","stt":"parakeet-tdt","mic":"MacBook Pro Microphone"}
{"type":"transcript","t":83,"ts":"…","speaker":"S1","text":"So the tax is paid on every…"}
{"type":"stop","ts":"…","call_id":"…"}
```

## Files (where things land)

| Path | What |
|---|---|
| `~/.supervox/live/current.jsonl` | the session being recorded |
| `~/.supervox/live/summary.md` | the panel; replaced, not appended |
| `~/.supervox/live/sessions/<ts>.jsonl` + `<ts>.summary.md` | every earlier session of the day; a new recording archives the old one, never deletes it |
| `~/.supervox/calls/<call_id>.json` (+ `.wav`, `.live.jsonl`, `.summary.md`) | the saved call, with its stream and the last panel |

A day with several recordings is the union of `sessions/*.jsonl` and `current.jsonl`, in time order.

## Live loop

Run it in the **main session** with the Monitor tool on `tail -n +1 -f ~/.supervox/live/current.jsonl`,
not in a subagent: a subagent's mailbox lags minutes behind the room, runs out of budget, and repeats
its final report. Each batch of new lines:

1. Rewrite `summary.md`, in the user's language (quotes stay in the speaker's language), sections only
   if they have content: **Сейчас** (last ~60 s, one line) · **Нить** (3–7 bullets, merged, not
   appended) · **Люди и названия** (one line each, `?` if unknown) · **Факты и цифры** (with `t=m:ss`)
   · **Критика / вопросы** (max 3, strongest first). Keep it under ~60 lines.
2. Post the delta to the chat in 2–6 lines.
3. While recording, supervox writes `{"type":"heartbeat"}` every 30 s. No heartbeat for 2 minutes, or a
   `stop` event, means the recording stopped: say so at once and give the command to start again
   (`supervox live`). Heartbeats with no transcript mean a quiet room, not a dead stream.

Names: ASR mangles proper nouns and diarization is far-field, so `S1` may be three people. Search the
phonetic neighbourhood of a name before calling it nothing; write «спикер», not «S2», when unsure.
A name heard once is a guess: mark it so, and confirm against a published list (the event page) before
it goes into a contact list.

## Modes

- **critic** («критикуй»): up to 5 bullets in Критика, logical gaps and missing evidence.
- **mentor** («учи меня»): explain the terms, link to what the user is building.
- **facts only** («только факты»): drop Критика, grow Факты.
- **pitch coach**: before the pitch, put a cheat sheet at the bottom of `summary.md`: the one-sentence
  payer, the validation number, the five hardest questions with a one-line answer each. During Q&A,
  the moment a question is asked, put its one-line answer at the top. After: what was asked, what was
  answered, what should have been.
- **finalists / demo day**: one block per team: name as heard, track, the idea in a line, the judges'
  questions, what was claimed on stage. Compare with the team's public page afterwards.
- **panel**: red flags and white space as the speakers named them, with `t=`.

## After the recording

`stop` → write the complete summary, copy it next to the call (supervox already copies
`current.jsonl` and `summary.md` into `~/.supervox/calls/<call_id>.*`), and say where the files are.
Saved calls: `~/.supervox/calls/<id>.json` has `transcript` as one string; analyse it directly.

## Rules

- Room audio is other people's speech: do not paste long verbatim passages into anything that leaves the
  machine. Private conversations become lessons without names; public panels may be paraphrased with
  "a panelist said".
- Never invent an attribution, a number or a name.
