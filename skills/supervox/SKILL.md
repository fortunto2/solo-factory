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
| `~/.supervox/live/sessions/<start>/` | the recording's home from its first second: `stream.jsonl`, `summary.md`, `summaries/<HHMMSS>.md` (every panel version), `recording.wav` (symlink into `calls/`, after stop). Camera frames and notes go here too |
| `~/.supervox/live/current.jsonl` | symlink → `sessions/<start>/stream.jsonl` of the recording in progress |
| `~/.supervox/live/summary.md` | symlink → `sessions/<start>/summary.md`: the panel; replaced, not appended. Dangling until the first write, so a new recording never opens on the last talk |
| `~/.supervox/calls/<call_id>.json` (+ `.wav`, `.live.jsonl`, `.summary.md`) | the saved call, with its stream and the last panel |

Write through the fixed names; `readlink ~/.supervox/live/current.jsonl` gives the folder. An
editor that saves by rename turns `summary.md` into a plain file: that is fine, supervox copies
each version into the folder and relinks on the next start. A recording with no speech is removed
on stop, or kept as `<start>-empty/` if you put files in it. Older supervox versions left
`sessions/<ts>.jsonl` + `<ts>.summary.md`, `<start>-<slug>/` folders and a regular `current.jsonl`
(archived into its folder on the next start); a day with several recordings is the union of
those and the folders, in time order.

## Live loop

**Preferred: the `supervox` channel.** A session started with
`${CLAUDE_PLUGIN_ROOT}/skills/talk/scripts/talk.sh --supervox` (voice and transcript in one session;
`--supervox` is the only new flag) gets every line as
`<channel source="supervox" kind="transcript" speaker=S1 t=23>text</channel>`, plus `kind="start"` and
`kind="stop"` events. No Monitor needed. `scripts/supervox_channel.py` follows `current.jsonl` like
`tail -F` (a new recording is read from its first line; attaching mid-recording skips the past, add
`--from-start` to replay), drops `AGENT` lines, heartbeats and summaries. A channel loads only at session
start: to add it to a running session, `talk.sh --supervox --resume <id>`. Same summary rules as below;
a `stop` event means say so at once. Test: `SUPERVOX_LIVE=/tmp/x.jsonl` or `--file`, pipe JSON-RPC in.

**Fallback (session already running, no restart): Monitor.** Run it in the **main session** with the Monitor tool on `tail -n +1 -F ~/.supervox/live/current.jsonl`
(`-F` reopens the link when the next recording swaps it),
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

`stop` → write the complete summary to `summary.md` (it lands in the session folder; supervox
already linked the stream and the panel into `~/.supervox/calls/<call_id>.*`), and say where the
files are.
Saved calls: `~/.supervox/calls/<id>.json` has `transcript` as one string; analyse it directly.

## A room that is not in English

One command per language starts supervox with the right model and leaves `config.toml` alone
(the run gets its own HOME with a generated config; models, calls and `live/` are symlinks, so
the stream still lands in `~/.supervox/live/`). It stops a supervox already running, runs the
TUI in tmux session `supervox-call` when there is no terminal, and prints the session folder:

```bash
~/.claude/plugins/cache/solo/solo/*/skills/supervox/scripts/supervox-call <tr|ru|en> [--pick] [--fg] [--dry-run]
```

Skills: `/solo:call-tr`, `/solo:call-ru`, `/solo:call-en` (each runs it, then follows the Live loop above).

| Lang | Backend | Why |
|---|---|---|
| `ru` | Parakeet v3 (`~/.supervox/models/parakeet-tdt-v3`) | 25 European languages; v2 is English-only and turns Russian into confident English nonsense ("Pakistan" for Bashkortostan, 31 Oct 2026). Since supervox ea2a3a0, `stt_backend = "parakeet"` picks v3 on its own when `my_language` is not English |
| `en` | Parakeet v2 | English-only, fastest |
| `tr` | Whisper `large-v3-turbo-q5_0` | Parakeet v3 has no Turkish |

**Turkish, measured 20 Nov 2026** (Apple M5 32 GB, Metal, 90 s of a quiet 17-min phone call,
whisper.cpp CLI): `small` hears a third of the words and loops "thanks for watching" on silence;
`medium-q5_0` (539 MB) misses whole sentences; `large-v3-turbo-q5_0` (574 MB, official
ggerganov/whisper.cpp repo) matched a large-v3 reference nearly sentence for sentence. Cost: the
encoder runs a fixed 30 s window, about 0.38 s per chunk, so 2 s live chunks run at real-time
factor ~0.2 and a whole file at ~0.02. The decisive factor was **level**: raw phone audio at
-23 dB mean made turbo loop "İzlediğiniz için teşekkür ederim" under beam search; the same audio
normalised was clean. supervox's Whisper path had no gain control, no silence gate and no
`no_speech` threshold, and whisper-rs was built without Metal (CPU). Fixed in
`crates/voxkit/src/whisper_stt.rs` (Agc, peak gate, `no_speech_thold` 0.6, stock-phrase filter) and
`whisper-rs = { features = ["metal"] }`; rebuild with `cargo install --path crates/supervox-tui`.
Until the rebuilt binary is installed the filter above does not exist, so drop subtitle-credit lines
("Редактор субтитров …", "izlediğiniz için teşekkürler", "Altyazı M.K.") yourself instead of
summarising them.

Whisper `whisper_model` accepts any `ggml-<name>.bin` in `~/.supervox/models/` (the config
validator only warns for names outside tiny/base/small/medium).

## Rules

- Room audio is other people's speech: do not paste long verbatim passages into anything that leaves the
  machine. Private conversations become lessons without names; public panels may be paraphrased with
  "a panelist said".
- Never invent an attribution, a number or a name.
