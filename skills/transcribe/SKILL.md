---
name: solo-transcribe
description: Transcribe audio or video to text locally — on the Apple GPU with mlx-whisper large-v3, or faster-whisper on CPU/CUDA — with the language decided per stretch of speech, .srt subtitles, word timings for editing, and optional speaker labels. Nothing is uploaded. Use when user says "расшифруй", "транскрибируй", "transcribe this", "make a transcript", "субтитры из видео", "что там говорят в записи", or hands a recording, a call, a voice memo or a folder of clips that needs its speech as text. Do NOT use for listening to a live room (use /supervox) or for cutting the footage itself (use /video-edit).
license: MIT
metadata:
  author: fortunto2
  version: "1.0.0"
  openclaw:
    emoji: "🎙️"
---

# transcribe — local speech to text, GPU first

Any ffmpeg-decodable file becomes `<name>.txt` (`[MM:SS] (lang) text`), `<name>.srt`, and on request
`<name>.words.json` with per-word timings, the input a video edit needs. Audio never leaves the
machine; the only network step is a one-time model download.

## Pick the engine

| Machine | Script | Why |
|---|---|---|
| Apple Silicon | `scripts/transcribe_mlx.py` | large-v3 on the GPU. Measured: 2 min of a noisy prize announcement in 16 s, where `medium` on CPU returned fragments; a 38-min talk in 8.7 min (4x realtime) |
| NVIDIA / Linux, or speaker labels needed | `scripts/transcribe.py` | faster-whisper (CTranslate2): CUDA yes, **Metal no**, so on a Mac it is CPU-only however fast the Mac |

```bash
uv run scripts/transcribe_mlx.py rec.m4a                      # → rec.txt, rec.srt
uv run scripts/transcribe_mlx.py clip.mp4 --words             # + rec.words.json for editing
uv run scripts/transcribe_mlx.py call.m4a --languages en ru   # languages that can occur
uv run scripts/transcribe.py rec.m4a --model large-v3         # CPU/CUDA path
uv run scripts/transcribe.py call.m4a --multilingual          # per-segment language on that path
uv run --with pyannote.audio scripts/transcribe.py talk.wav --diarize --speakers Alice Bob
```

Both scripts declare their dependencies in a PEP 723 header, so `uv run` needs no venv. Diarization
needs `HUGGINGFACE_TOKEN` with the pyannote model terms accepted; without it the transcript comes back
unlabelled, and the script says so.

Long files (10+ min): run in the background and wait for `✅ done`.

## Gotchas

- **Whisper picks one language from the first 30 s and applies it to the whole file.** A call that
  opens in English and moves to Russian comes out as fluent, confident English, or the second
  language simply vanishes (measured: a Russian+English file detected as `ru` returned only the
  Russian words). `transcribe_mlx.py` splits on silences (Silero VAD) and detects per chunk; on the
  CPU path pass `--multilingual`.
- **A chunk detected as a language not in `--languages`** (Russian read as Ukrainian, a laugh as
  Welsh) is re-run in the first non-English listed language instead of keeping the guess.
- **Crowd noise hallucinates.** 25 minutes of a bar came back as `lang=fr` with 454 invented
  sentences. Treat such a file as no speech; if one voice in it matters, re-run with the language
  forced.
- **Unknown names become celebrities.** Keep a glossary per project (people, places, products) and
  fix the transcript once, before anything quotes it.
- **Screen recordings on macOS often have no audio track.** `ffprobe` first.
- **Parakeet and other English-only models** are fast but drop every non-English clip; check the
  language mix before choosing them for a folder.

## Finding recordings on a Mac

- Zoom: `~/Documents/Zoom/<date time …>/audioNNN.m4a` (folder name = start, file mtime ≈ end).
- Voice Memos: names and files are in
  `~/Library/Group Containers/group.com.apple.VoiceMemos.shared/Recordings/CloudRecordings.db`
  (`ZCLOUDRECORDING`: `ZCUSTOMLABEL`, `ZPATH`, `ZDATE` + 978307200 = unix start, `ZDURATION`).
- Long video on a slow card: pull only the audio, `ffmpeg -i in.mp4 -vn -c:a copy out.m4a`.

## Privacy

Write transcripts where the task lives, never into an unrelated repo. Personal recordings belong in
the user's own private store, not next to project code.
