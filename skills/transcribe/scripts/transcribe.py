#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10,<3.14"
# dependencies = ["faster-whisper>=1.0", "av<19"]  # av 19 dropped metadata_errors, faster-whisper 1.2.1 still passes it
# ///
"""General local audio/video transcription — fully offline, nothing leaves the machine.

Works on any ffmpeg-decodable input (m4a/mp3/wav/ogg/mp4/mov/...). Auto-detects
language by default. Optional 2+-speaker diarization (pyannote, needs HF token).

Engine: faster-whisper (with VAD). The only network step is a one-time model-weights
download; audio itself is never uploaded.

Run (uv reads the dependencies from the header above; no venv to manage):
    uv run transcribe.py path/to/file.mp4
    uv run transcribe.py file.m4a --language en --model large-v3
    uv run transcribe.py call.mov --out-dir ./transcripts
    uv run --with pyannote.audio transcribe.py talk.wav --diarize --speakers Alice Bob  # needs HUGGINGFACE_TOKEN

Outputs, next to the input (or in --out-dir):
    <name>.txt   clean, [MM:SS]-prefixed lines
    <name>.srt   subtitle timecodes
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

AUDIO_EXTS = {".wav", ".mp3", ".m4a", ".aac", ".ogg", ".opus", ".flac"}


def die(msg: str, code: int = 1) -> None:
    print(f"\n✋ {msg}", file=sys.stderr)
    sys.exit(code)


def need(pkg: str, pip_name: str | None = None):
    try:
        return __import__(pkg)
    except ImportError:
        die(
            f"missing package «{pkg}». Run with uv (reads the script header): "
            f"uv run {Path(__file__).name} …  or: pip install {pip_name or pkg}"
        )


def srt_ts(sec: float) -> str:
    h = int(sec // 3600)
    m = int((sec % 3600) // 60)
    s = sec % 60
    return f"{h:02d}:{m:02d}:{s:06.3f}".replace(".", ",")


def to_wav(src: Path) -> tuple[Path, bool]:
    """Return a 16 kHz mono WAV path. If src is already a plain WAV, use it as-is.
    Otherwise extract via ffmpeg into a temp file (caller cleans up when temp=True)."""
    if src.suffix.lower() == ".wav":
        return src, False
    if not shutil.which("ffmpeg"):
        die("ffmpeg not found — install it (brew install ffmpeg).")
    tmp = Path(tempfile.mkstemp(suffix=".wav", prefix="transcribe_")[1])
    # -vn drops any video track; fails loudly if the input has no audio stream.
    proc = subprocess.run(
        ["ffmpeg", "-y", "-i", str(src), "-vn", "-ac", "1", "-ar", "16000", str(tmp)],
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0 or not tmp.exists() or tmp.stat().st_size == 0:
        tail = "\n".join(proc.stderr.strip().splitlines()[-3:])
        tmp.unlink(missing_ok=True)
        die(
            f"ffmpeg could not extract audio from {src.name} "
            f"(no audio stream?).\n{tail}"
        )
    return tmp, True


def transcribe(
    wav: Path, model_size: str, language: str | None, multilingual: bool = False
):
    WhisperModel = need("faster_whisper", "faster-whisper").WhisperModel
    model = WhisperModel(model_size, device="cpu", compute_type="int8")
    # multilingual: detect the language on EVERY segment instead of once from the first
    # 30 seconds. Without it a call that opens in English and switches to Russian gets
    # the Russian half "transcribed" as English - fluent, confident and wrong.
    segments, info = model.transcribe(
        str(wav),
        language=language,
        vad_filter=True,
        beam_size=5,
        multilingual=multilingual,
    )
    print(
        f"  engine: faster-whisper {model_size} (CPU int8), "
        f"language={info.language} ({info.language_probability:.2f}), "
        f"duration={info.duration:.0f}s",
        flush=True,
    )
    return list(segments), info


def diarize_and_label(segs, wav: Path, num_speakers: int, speaker_names: list[str]):
    """Attach a speaker label to each segment using pyannote. Best-effort:
    if pyannote / HF token is missing, we return segments unlabelled."""
    try:
        from pyannote.audio import Pipeline  # type: ignore
    except ImportError:
        print("  (pyannote not installed — skipping diarization)", flush=True)
        return segs, False
    import os

    token = os.environ.get("HUGGINGFACE_TOKEN") or os.environ.get("HF_TOKEN")
    if not token:
        print("  (no HUGGINGFACE_TOKEN — skipping diarization)", flush=True)
        return segs, False
    pipe = Pipeline.from_pretrained(
        "pyannote/speaker-diarization-3.1",
        use_auth_token=token,
    )
    diar = pipe(str(wav), num_speakers=num_speakers or None)
    turns = [(t.start, t.end, spk) for t, _, spk in diar.itertracks(yield_label=True)]
    labels = sorted({spk for _, _, spk in turns})
    name_of = {
        lbl: (speaker_names[i] if i < len(speaker_names) else lbl)
        for i, lbl in enumerate(labels)
    }

    def who(mid: float) -> str:
        for s, e, spk in turns:
            if s <= mid <= e:
                return name_of[spk]
        return "?"

    for seg in segs:
        seg._speaker = who((seg.start + seg.end) / 2)  # type: ignore[attr-defined]
    return segs, True


def main() -> None:
    ap = argparse.ArgumentParser(
        description="Local offline transcription (any audio/video)."
    )
    ap.add_argument("input", help="path to audio or video (m4a/mp3/wav/mp4/mov/...)")
    ap.add_argument(
        "--language", default=None, help="ISO code (en, ru, ...). Default: auto-detect."
    )
    ap.add_argument(
        "--multilingual",
        action="store_true",
        help="detect language per segment - for calls that switch languages",
    )
    ap.add_argument(
        "--model",
        default="medium",
        help="whisper model: tiny/base/small/medium/large-v3 (default: medium)",
    )
    ap.add_argument(
        "--out-dir",
        default=None,
        help="where to write .txt/.srt (default: next to the input)",
    )
    ap.add_argument(
        "--diarize",
        action="store_true",
        help="label speakers (needs pyannote + HUGGINGFACE_TOKEN)",
    )
    ap.add_argument(
        "--speakers",
        nargs="+",
        default=[],
        help="speaker names in first-appearance order (with --diarize)",
    )
    ap.add_argument(
        "--num-speakers",
        type=int,
        default=0,
        help="hint the expected speaker count (0 = auto)",
    )
    args = ap.parse_args()

    src = Path(args.input).expanduser()
    if not src.exists():
        die(f"file not found: {src}")

    out_dir = Path(args.out_dir).expanduser() if args.out_dir else src.parent
    out_dir.mkdir(parents=True, exist_ok=True)
    out_txt = out_dir / f"{src.stem}.txt"
    out_srt = out_dir / f"{src.stem}.srt"

    t0 = time.time()
    wav, is_tmp = to_wav(src)
    try:
        segs, info = transcribe(wav, args.model, args.language, args.multilingual)
        labelled = False
        if args.diarize:
            segs, labelled = diarize_and_label(
                segs, wav, args.num_speakers, args.speakers
            )

        with open(out_txt, "w") as ftxt, open(out_srt, "w") as fsrt:
            for i, seg in enumerate(segs, 1):
                text = seg.text.strip()
                spk = getattr(seg, "_speaker", None)
                prefix = f"[{int(seg.start // 60):02d}:{int(seg.start % 60):02d}]"
                who = f" {spk}:" if labelled and spk else ""
                ftxt.write(f"{prefix}{who} {text}\n")
                fsrt.write(
                    f"{i}\n{srt_ts(seg.start)} --> {srt_ts(seg.end)}\n"
                    f"{(spk + ': ') if labelled and spk else ''}{text}\n\n"
                )
    finally:
        if is_tmp:
            wav.unlink(missing_ok=True)

    print(
        f"\n✅ done in {time.time() - t0:.0f}s\n   {out_txt}\n   {out_srt}", flush=True
    )


if __name__ == "__main__":
    main()
