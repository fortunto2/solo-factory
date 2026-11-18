---
name: solo-talk
description: Talk with the agent by voice, fully local — one process hears (Silero VAD, smart-turn end-of-turn, GigaAM or Parakeet ASR) and speaks (VoxCPM2, cloned or designed voice) and plugs into Claude Code as a channel at start, or attaches to an already open session through Monitor, so the session is the brain and can use every tool mid-conversation. Use when user says "поговори со мной голосом", "давай голосом", "включи голос", "голосовой режим", "слушай меня и отвечай", "talk to me", "voice chat", "voice mode, local", or wants to work hands-free with the agent. Do NOT use for listening to a room and summarising it without replying (use /supervox) or for rendering a voice-over file (use /tts).
license: MIT
metadata:
  author: fortunto2
  version: "1.2.0"
  openclaw:
    emoji: "🗣"
---

# talk — a voice conversation where the Claude Code session is the brain

```
mic 16 kHz ─▶ Silero VAD ─▶ 0.25 s pause ─▶ smart-turn: finished? ─▶ GigaAM / Parakeet
                                                                          │
                       voice_channel.py (one MCP server, one process)     ▼
speaker ◀─ afplay ◀─ VoxCPM2 ◀─ say tool ◀── Claude Code session ◀─ notifications/claude/channel
```

## Start: one command

```bash
cd ~/where-the-work-is && ${CLAUDE_PLUGIN_ROOT}/skills/talk/scripts/talk.sh
talk.sh -- --asr parakeet --ref ~/me.wav --barge-in     # voice_channel.py options after `--`
```

`talk.sh` writes an MCP config for `voice_channel.py` and runs
`claude --mcp-config … --dangerously-load-development-channels server:voice`. Custom channels are
not on the research-preview allowlist, so Claude Code shows a confirmation screen on every start;
the flag is ignored with `-p`, so it must be an interactive session. The channel loads its models
in the background (8 s warm, ~50 s the first time while GigaAM and the voice download), then sends
a `kind="status"` message and the session greets the person.

A channel can only be loaded when the session starts. To give voice to a session that is
already open with its context: `/exit`, then `talk.sh -c` in the same directory (or
`talk.sh --resume <id>`): the same conversation comes back, now with the channel.

## Already in a session: attach without a restart

When the person asks for voice in a session that was started without the channel, run the same
process in attach mode and listen through Monitor. Nothing to restart, no confirmation screen:

1. Bash, `run_in_background: true`:
   `uv run --script ${CLAUDE_PLUGIN_ROOT}/skills/talk/scripts/voice_channel.py --http 7799` (add
   `--ref voice.wav`, `--asr parakeet` as needed).
2. Monitor, `timeout_ms: 1800000`, command `${CLAUDE_PLUGIN_ROOT}/skills/talk/scripts/next.sh 7799`.
   Lines arrive as `READY: … Rules: …` and `TURN why=end p=0.97 secs=2.7 lag=0.75 asr_ms=499: text`.
3. Answer each TURN with `curl -s --data-binary 'text' 127.0.0.1:7799/say` (`?interrupt` first
   drops what is still queued); `POST /stop`, `POST /listen?on=0`, `POST /quit` to end.
4. A Monitor lives at most 30 minutes: when it expires, arm it again. Turns wait in the voice
   process meanwhile, so none are lost. A `VOICE DOWN` line means the process died.

Same rules as the channel: one or two phrases aloud, the rest in the text reply. Measured with a
file as the mic: ready in 18 s on a loaded machine, both turns delivered, 0.75 s lag on the
finished one.

How the session should behave is in the channel's MCP `instructions`, delivered automatically:
answer every turn aloud with `say`, «ещё минуту» during long work, `listen on=false` on «стоп».
Voice is the headline, the screen holds the rest: one or two phrases (~15 words) spoken, and the
details, lists and numbers in the normal text reply. The instructions alone did not hold this (the
first live session read whole paragraphs out), so `say` also enforces it: whole sentences up to
`--max-say` characters (120, about eight seconds) are spoken, the rest is dropped, and the tool
result tells the session how much was cut. Tools: `say(text, interrupt?)`, `stop()`,
`listen(on)`. A turn arrives as `<channel source="voice" kind="turn" why="end|hold|long" p=… secs=…
lag=… asr_ms=…>text</channel>`; `why="hold"` means the person paused mid-thought and went quiet.

## ASR: which model

| `--asr` | Languages | Why |
|---|---|---|
| `gigaam` (default), GigaAM v3 e2e RNN-T, int8 ONNX | Russian | Best Russian we have numbers for: 10.4% WER on Golos crowd against 18% for Whisper large-v3 (Sber's figures), beats Parakeet on every Russian set; writes punctuation and capitals. English words come out in Cyrillic, which the agent reads fine |
| `parakeet`, Parakeet TDT 0.6B v3 | 25 European languages, ru and en among them | Mixed-language speech |
| any onnx-asr name | | e.g. `whisper-base`; Turkish has no good option here yet (neither model knows it) |

Both through `onnx-asr`, CPU, ~250-290 ms per turn on an M5.

## Measured (Apple M5, 32 GB, other jobs running)

| | |
|---|---|
| end of speech → message in the session | **0.50-0.54 s** (0.25 s pause + 0.25-0.29 s ASR) |
| smart-turn on labelled real speech (pipecat test set, English) | 11/12 right, ~40 ms |
| GigaAM on an 18 s Russian line | verbatim, with punctuation |
| `say` → first audio | 1.0-1.6 s (VoxCPM2, 10 steps; `--steps 6` ~0.3 s less) |
| channel start | 0.2 s to `initialize`, 8 s to ready (warm) |

The slow part is the session itself: its reply takes seconds. The pre-rendered «Угу.» (`--ack`)
plays the instant a turn ends, so the silence does not feel dead.

## Echo and interruptions

The process knows when it is speaking, so the mic is ignored while it speaks and for
`--echo-tail` (0.35 s) after: the agent never hears itself, on laptop speakers too. The price is
half duplex: the person cannot interrupt. With headphones, `--barge-in` keeps the mic open and
stops the agent's speech the moment the person talks.

## Gotchas

- **The ack swallowed the start of the next turn.** After a mid-thought pause the person went on
  at once, the mic was deaf for the «угу», and «Он открыл» was lost. The ack now plays only after
  smart-turn says the turn is finished (`why="end"`).
- **stdout is the MCP wire.** Anything that prints (mlx-audio, transformers, CoreAudio) corrupts
  the protocol; the script duplicates fd 1 for the wire and points fd 1 at stderr before importing
  anything. Its logs are in Claude Code's MCP log (`claude --debug`).
- **Synthetic speech cut mid-sentence reads as finished**, and a TTS line that ends normally can
  read as unfinished (p 0.07 on one). smart-turn hears intonation; test it on real recordings.
- Notifications before `notifications/initialized` are held back; Claude Code drops channel
  events silently when the session did not load the server as a channel.

## Test without a microphone

`voice_channel.py --input speech.wav --sink none` plays the file in real time as the mic and times
playback without sound; drive it with JSON-RPC lines on stdin (initialize, notifications/initialized,
tools/call). `uv run scripts/turns.py --check a.wav` prints smart-turn's verdict for files.

## With supervox already recording a room

`scripts/turns.py` follows supervox's `~/.supervox/live/current.jsonl` and its live WAV, drops
echo by word pairs against `~/.supervox/live/speaking.jsonl`, and prints `TURN` lines for the
Monitor tool; the mouth is then `tts/scripts/speak_server.py` on `127.0.0.1:7788`. Slower (supervox
waits `vad_pause_ms`, 1.2 s), and a Monitor expires every 30 minutes: use it only when supervox
must keep its own recording and diarization.
