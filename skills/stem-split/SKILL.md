---
name: solo-stem-split
description: Separate a song or a film's soundtrack into stems (vocals, drums, bass, other) with Demucs, locally, on the Apple GPU when there is one. Use when user says "раздели на стемы", "вытащи вокал", "сделай минусовку", "acapella", "instrumental", "split stems", "isolate the vocal", or needs a voice separated from music in footage, stems for a mashup or sample chops, or drums+bass to detect music. Do NOT use for turning a recording into notes (use audio-to-midi from SuperDuper DSP) or for transcribing speech (use /transcribe).
license: MIT
metadata:
  author: fortunto2
  version: "1.0.0"
  openclaw:
    emoji: "🎚️"
---

# stem-split — Demucs stems, local

Any track becomes `vocals.wav`, `drums.wav`, `bass.wav`, `other.wav` (44.1 kHz stereo) with Meta's
`htdemucs`. Nothing is uploaded; the model downloads once.

## The command

```bash
uv tool install demucs --with numpy        # once; --with numpy avoids torch's "Failed to initialize NumPy"
demucs -d mps -o out "song.mp3"            # Apple Silicon GPU
demucs -o out "song.mp3"                   # CUDA if present, else CPU
```

No install: `uvx --with numpy --from demucs demucs -d mps -o out "song.mp3"` (`--from demucs`
because `uvx demucs` alone resolves the wrong entry point).

Output: `out/htdemucs/<file name without extension>/{vocals,drums,bass,other}.wav`.

Measured on an M-series Mac, 60 s of a song, 4 stems including model load: **8.3 s with `-d mps`,
15.7 s on CPU**, stems equal to 0.1 dB between the two. Without `-d`, Demucs does not pick the
Apple GPU on its own.

## Variants

```bash
demucs -d mps --two-stems=vocals -o out "song.mp3"   # vocals + no_vocals, ~2x faster: acapella or instrumental
demucs -d mps -n htdemucs_ft -o out "song.mp3"        # fine-tuned model, better, ~4x slower
demucs -d mps --mp3 --mp3-bitrate 320 -o out "song.mp3"
demucs -d mps -j 4 -o out "song.mp3"                  # more parallel jobs, more RAM
```

## Uses

- **Music:** stems for a mashup, a vocal for sample chops (no backing bleed), `no_vocals` as a clean
  instrumental bed or a filter loop.
- **Video, other people's music in the frame:** drums + bass is the music detector (engine, wind and
  city noise land in `other`, so "no_vocals" is blind to radio), and the **vocals** stem keeps the
  speaker when the music is replaced. Details: `/video-edit`, `references/sound.md`.
- **Video, a voice drowned by a live band:** raise the speaker from the vocals stem under one
  continuous span of the live audio.
- **Before audio-to-MIDI:** separate first; a pitch tracker on a full mix follows whatever is loudest.

For a film, extract the soundtrack first: `ffmpeg -i film.mp4 -vn -ac 2 -ar 44100 film_audio.wav`.

## Gotchas

- **The output folder can exist but be empty** if a run was killed. Check that all four `.wav`s are
  there before using them.
- Quote paths: Cyrillic and spaces work.
- Long files take minutes even on the GPU (~4 min per 20 min of audio); run them in the background.
- A singer's voice from a radio ends up in the vocals stem with the speaker's, 5–10 dB under. It
  disappears under a new score; it does not disappear on its own.
