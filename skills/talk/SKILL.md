---
name: solo-talk
description: Talk with the agent by voice, fully local — supervox hears and transcribes, smart-turn decides when the person has finished, the agent (this session) answers, and a cloned or designed voice speaks the answer on the Apple GPU. Use when user says "поговори со мной голосом", "давай голосом", "голосовой режим", "слушай меня и отвечай", "talk to me", "voice chat", "voice mode, local", or wants to work hands-free with the agent. Do NOT use for listening to a room and summarising it without replying (use /supervox) or for rendering a voice-over file (use /tts).
license: MIT
metadata:
  author: fortunto2
  version: "1.0.0"
  openclaw:
    emoji: "🗣"
---

# talk — a voice conversation where this session is the brain

```
mic ─▶ supervox live ──transcript lines──▶ turns.py ──TURN lines──▶ Monitor ─▶ agent (you)
        (Parakeet, VAD,      + live WAV      (echo gate,                          │
         writes the WAV)                      smart-turn)                         ▼
speaker ◀── afplay ◀── speak_server.py (model loaded once, sentence by sentence) ◀ curl /say
                         └─ logs what it played ─▶ speaking.jsonl ─▶ turns.py drops the echo
```

Nothing leaves the machine except what the agent itself does with tools. The person talks; the
agent hears finished turns, can run any tool mid-conversation, and answers out loud.

## Start (three processes)

```bash
T=${CLAUDE_PLUGIN_ROOT}/skills/tts/scripts
S=${CLAUDE_PLUGIN_ROOT}/skills/talk/scripts
uv run $T/speak_server.py --describe "calm, warm, middle-aged male voice"   # or --ref voice.wav
curl -s localhost:7788/state                                                # wait for "ready": true
```

1. **Mouth**: start `speak_server.py` with `run_in_background`. First start designs the voice once
   (cached in `~/.cache/solo-tts/voices/`), loads VoxCPM2 (~5 s) and warms up.
2. **Ears**: the person runs `supervox live` in their own terminal (it needs the mic permission and a
   TTY). Headphones are better: no echo, and `--barge-in` works.
3. **Turns**: the Monitor tool, in the main session, on `uv run $S/turns.py` (`--barge-in` with
   headphones). It prints `STATE listening …` at once; then one `TURN` line per finished turn.

Say a short greeting through the mouth so the person knows it is live.

## Each turn

`TURN p=0.91 wait=0.1s | <what they said>` is a message from the person. Answer through the mouth:

```bash
curl -s localhost:7788/say --data-binary @- <<'EOF'
Понял. Сейчас посмотрю открытые задачи и расскажу.
EOF
```

- **First sentence 3-8 words**, the rest under ~12 words each: the first piece is the buffer the
  next one is generated behind.
- **Spoken text only**: no markdown, lists, code, links or emoji. Numbers, dates and units as
  words. Anything long (a table, code, a path) goes to the chat; say «вывел на экран».
- **Work requests**: say what you are about to do in one line, do it with tools, then speak the
  result in two or three sentences. Silence longer than ~10 s feels broken: say «ещё минуту».
- **Change your mind mid-answer**: `curl -s -X POST localhost:7788/say?interrupt --data-binary "…"`
  drops what is queued. `POST /stop` only stops.
- `hold` in a TURN line means smart-turn thought the thought was unfinished and the person then
  went quiet: answer, but it may be half a question.
- `STATE recording stopped`: supervox stopped; say so in the chat and wait.

**End** on «стоп», «хватит», «пока», «конец разговора», or when the person types in the terminal:
say a one-line goodbye, stop the Monitor (TaskStop) and the mouth (`pkill -f speak_server.py`).

## Measured (Apple M5, 32 GB, load average ~5 from other jobs)

| Step | Time |
|---|---|
| supervox VAD pause before a line exists | 1.2 s (`vad_pause_ms`) + Parakeet |
| smart-turn verdict | ~40 ms on CPU; complete turns sent 0.0-0.1 s after their line |
| first audio after `/say` | 1.0 s (VoxCPM2, 10 steps), 0.7 s (`--steps 6`) |
| VoxCPM2 under load | RTF 0.9-1.1 (0.56-0.75 on an idle machine) |

The brain is the slow part: the agent's own reply takes seconds. smart-turn v3.2 on labelled real
speech from pipecat's test set: 11 of 12 right (6/6 unfinished, 5/6 finished, English). Russian
was not measured against labels yet.

## Gotchas

- **Synthetic speech cut mid-sentence reads as finished.** Six clips cut from TTS output, three
  of them mid-phrase, all scored 0.77-0.99. smart-turn hears unfinished *intonation*, which cut
  synthesis does not have. Test it on real recordings (pipecat's test set has labels).
- **Echo by single words drops real questions.** «А что по продажам сегодня?» right after the agent
  said «посмотрю, что открыто по продажам» shared 75% of its words. turns.py compares word pairs
  (33% there, 100% for the actual echo).
- **A described voice changes on every sentence.** The server turns the description into one
  reference clip and clones from it.
- **VoxCPM2 re-encodes the reference on every call** (+1 s per sentence); the server memoizes it.
- **Gaps between sentences**: at RTF about 1 a sentence longer than the one before it leaves a
  pause while it is generated. Pieces are cut at commas to at most 80 chars.
- supervox's WAV header is not final while recording; turns.py reads it by file size, and a WAV
  that stopped growing counts as silence.

## Tuning

`vad_pause_ms` in `~/.supervox/config.toml` (lower is snappier; smart-turn then holds the unfinished
ones), `turns.py --hold` (quiet seconds before an unfinished line is sent anyway), `--threshold`,
`speak_server.py --steps 6`, `--model zonos3 --lang <code>` (faster, same-language reference only,
band-limited). Decisions: `~/.supervox/live/turns.log`; what was spoken:
`~/.supervox/live/speaking.jsonl`.
