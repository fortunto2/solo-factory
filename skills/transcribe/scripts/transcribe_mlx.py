#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10,<3.14"
# dependencies = ["mlx-whisper", "faster-whisper>=1.0"]
# ///
"""
Transcribe on the Apple GPU (MLX), with the language decided per stretch of speech.

Why this exists next to transcribe.py: faster-whisper runs on CTranslate2, which has no
Metal backend, so on a Mac it is CPU-only however fast the machine is. mlx-whisper runs
the same large-v3 weights on the Apple GPU, many times faster.

What mlx-whisper does not do is switch language mid-file — like openai-whisper it
detects once from the first 30 seconds and applies that to everything, so a call that
opens in English and moves to Russian comes out with the Russian half rendered as
fluent, confident English. So the audio is split on silences first (Silero VAD, the
one faster-whisper ships), each chunk is transcribed on its own and its language
detected on its own, and the chunks are stitched back on the original timeline.

    uv run transcribe_mlx.py call.m4a
    uv run transcribe_mlx.py call.m4a --languages en ru
    uv run transcribe_mlx.py clip.mp4 --words          # + word timings for editing
    uv run transcribe_mlx.py call.m4a --out-dir ./transcripts

Writes <name>.txt ([MM:SS] (lang) text) and <name>.srt next to the input; with --words
also <name>.words.json: [{"word", "start", "end", "p", "lang"}], seconds on the file's
timeline. faster-whisper is only used for its Silero VAD.
"""

import argparse
import sys
import time
from pathlib import Path

SAMPLE_RATE = 16_000
REPO = "mlx-community/whisper-large-v3-mlx"


def stamp(seconds: float) -> str:
    m, s = divmod(int(seconds), 60)
    return f"{m:02d}:{s:02d}"


def srt_time(seconds: float) -> str:
    ms = int(round(seconds * 1000))
    h, ms = divmod(ms, 3_600_000)
    m, ms = divmod(ms, 60_000)
    s, ms = divmod(ms, 1000)
    return f"{h:02d}:{m:02d}:{s:02d},{ms:03d}"


def chunks_on_silence(audio, max_seconds: float):
    """Speech regions from Silero VAD, merged into chunks no longer than max_seconds.

    A chunk boundary always falls in a silence, so a sentence is never cut in two and
    a language switch — which in a conversation happens at a turn — lands between
    chunks rather than inside one.
    """
    from faster_whisper.vad import VadOptions, get_speech_timestamps

    regions = get_speech_timestamps(audio, VadOptions(min_silence_duration_ms=500))
    limit = int(max_seconds * SAMPLE_RATE)
    chunks, start, end = [], None, None
    for r in regions:
        if start is None:
            start, end = r["start"], r["end"]
        elif r["end"] - start <= limit:
            end = r["end"]
        else:
            chunks.append((start, end))
            start, end = r["start"], r["end"]
    if start is not None:
        chunks.append((start, end))
    return chunks


def main() -> int:
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    ap.add_argument("input")
    ap.add_argument(
        "--languages",
        nargs="+",
        default=["en", "ru"],
        help="languages that can occur; a chunk detected as anything else "
        "is re-run in the first of these that is not English",
    )
    ap.add_argument(
        "--max-chunk",
        type=float,
        default=28.0,
        help="seconds; under Whisper's 30 s window so one chunk is one window",
    )
    ap.add_argument("--out-dir", default=None)
    ap.add_argument(
        "--words",
        action="store_true",
        help="also write <name>.words.json with per-word timings",
    )
    args = ap.parse_args()

    import mlx_whisper
    from mlx_whisper.audio import load_audio

    src = Path(args.input).expanduser().resolve()
    out_dir = Path(args.out_dir).expanduser().resolve() if args.out_dir else src.parent
    out_dir.mkdir(parents=True, exist_ok=True)

    t0 = time.time()
    audio = load_audio(str(src))
    duration = len(audio) / SAMPLE_RATE
    chunks = chunks_on_silence(audio, args.max_chunk)
    print(
        f"  engine: mlx-whisper large-v3 on the Apple GPU, {len(chunks)} chunks, "
        f"{duration / 60:.1f} min of audio",
        flush=True,
    )

    fallback = next((lg for lg in args.languages if lg != "en"), args.languages[0])
    lines, srt, counts, words = [], [], {}, []
    for i, (a, b) in enumerate(chunks, 1):
        piece = audio[a:b]
        offset = a / SAMPLE_RATE
        result = mlx_whisper.transcribe(
            piece,
            path_or_hf_repo=REPO,
            language=None,
            condition_on_previous_text=False,
            verbose=None,
            word_timestamps=args.words,
        )
        lang = result.get("language")
        if lang not in args.languages:
            # A short chunk can be misread — Russian as Ukrainian or Bulgarian, a laugh as
            # Welsh. Constrain it to the languages actually spoken rather than keep a guess.
            result = mlx_whisper.transcribe(
                piece,
                path_or_hf_repo=REPO,
                language=fallback,
                condition_on_previous_text=False,
                verbose=None,
                word_timestamps=args.words,
            )
            lang = fallback
        counts[lang] = counts.get(lang, 0) + 1
        for seg in result.get("segments", []):
            text = seg["text"].strip()
            if not text:
                continue
            start, end = offset + seg["start"], offset + seg["end"]
            lines.append(f"[{stamp(start)}] ({lang}) {text}")
            for w in seg.get("words", []):
                words.append(
                    {
                        "word": w["word"].strip(),
                        "start": round(offset + float(w["start"]), 3),
                        "end": round(offset + float(w["end"]), 3),
                        "p": round(float(w["probability"]), 3),
                        "lang": lang,
                    }
                )
            srt.append(
                f"{len(srt) + 1}\n{srt_time(start)} --> {srt_time(end)}\n{text}\n"
            )
        if i % 10 == 0 or i == len(chunks):
            print(f"  {i}/{len(chunks)} chunks", flush=True)

    txt_path = out_dir / f"{src.stem}.txt"
    srt_path = out_dir / f"{src.stem}.srt"
    txt_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    srt_path.write_text("\n".join(srt), encoding="utf-8")
    if args.words:
        import json

        (out_dir / f"{src.stem}.words.json").write_text(
            json.dumps(words, ensure_ascii=False, indent=0), encoding="utf-8"
        )
    took = time.time() - t0
    print(f"  languages by chunk: {counts}")
    print(
        f"✅ done in {took / 60:.1f} min ({duration / took:.0f}x realtime): {txt_path}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
