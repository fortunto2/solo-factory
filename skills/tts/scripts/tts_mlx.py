#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10,<3.14"
# dependencies = ["mlx-audio==0.6.6"]
# ///
"""
Text to speech on the Apple GPU (mlx-audio), cloning a voice from one short clip.

    uv run tts_mlx.py --ref me.wav --text "Hi, welcome back to the channel." -o hi.wav
    uv run tts_mlx.py --ref me.wav --file script.txt -o voiceover.mp3     # whole script, one file
    uv run tts_mlx.py --ref me.wav --samples en,ru,tr -o compare.mp3      # same voice, several languages
    uv run tts_mlx.py --model zonos3 --lang tr --ref me.wav --text "Merhaba!" -o tr.wav
    uv run tts_mlx.py --model shtorm-ru --ref me.wav --text "Он откр+ыл зам+ок." -o ru.wav
    uv run tts_mlx.py --describe "calm deep male voice" --text "No reference needed." -o v.wav

Models (Apache-2.0, weights download once to the Hugging Face cache):
  voxcpm2    mlx-community/VoxCPM2-4bit, 2.3 GB, 30 languages, 48 kHz. Default: cleanest clones.
  zonos3     mlx-community/ZONOS3-Mini, 1.4 GB, 43 languages, about 3x faster, output band-limited
             to ~8 kHz, copies the pauses of its reference (a halting clip gives halting speech).
  shtorm-ru  VoxCPM2 + merged LoRA that follows Russian stress marks (`+` before the stressed
             vowel). Built locally once by convert_shtorm_ru.py.
  Anything else is taken as a Hugging Face repo id or a local folder mlx-audio can load.

Output is cleaned unless --raw: a 13-15 kHz cosine low-pass (VoxCPM2 fills 16-20 kHz with hiss)
and DeepFilterNet 3 (hiss between words). Clips are joined in numpy and encoded once by ffmpeg
when the extension is not .wav. A watchdog exits the process if free memory falls below
--min-free percent (macOS memory_pressure); peak is ~5.5-5.9 GB for VoxCPM2, ~3.8 GB for ZONOS3.
"""

import argparse
import os
import re
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path

import numpy as np

MODELS = {
    "voxcpm2": "mlx-community/VoxCPM2-4bit",
    "zonos3": "mlx-community/ZONOS3-Mini",
    "shtorm-ru": str(Path.home() / ".cache" / "solo-tts" / "shtorm-ru-4bit"),
}
SAMPLES = {
    "en": "Hi everyone, welcome back to the channel. Today I will show you how I cut a short film in one "
    "evening, using nothing but my laptop and a few open source tools.",
    "ru": "Всем привет, с возвращением на канал. Сегодня покажу, как я монтирую короткий фильм за один вечер, "
    "только на ноутбуке и с парой открытых инструментов.",
    "tr": "Herkese merhaba, kanala tekrar hoş geldiniz. Bugün size tek bir akşamda, sadece dizüstü bilgisayarım "
    "ve birkaç açık kaynak araçla nasıl kısa bir film kurguladığımı göstereceğim.",
    "de": "Hallo zusammen und willkommen zurück auf dem Kanal. Heute zeige ich euch, wie ich an einem Abend "
    "einen kurzen Film schneide, nur mit meinem Laptop und ein paar Open-Source-Werkzeugen.",
    "es": "Hola a todos y bienvenidos de nuevo al canal. Hoy os enseño cómo monto un cortometraje en una sola "
    "tarde, solo con mi portátil y unas cuantas herramientas de código abierto.",
    "fr": "Bonjour à tous et bon retour sur la chaîne. Aujourd'hui, je vous montre comment je monte un court "
    "métrage en une soirée, avec mon ordinateur portable et quelques outils open source.",
}
_DFN = []


def memory_guard(min_free: int) -> None:
    """Exit the whole process when macOS reports less than min_free % memory free."""
    if sys.platform != "darwin" or min_free <= 0:
        return

    def watch() -> None:
        while True:
            out = subprocess.run(
                ["memory_pressure"], capture_output=True, text=True
            ).stdout
            m = re.search(r"free percentage:\s*(\d+)%", out)
            if m and int(m.group(1)) < min_free:
                print(
                    f"\nmemory guard: {m.group(1)}% free < {min_free}%, stopping",
                    file=sys.stderr,
                    flush=True,
                )
                os._exit(3)
            time.sleep(2)

    threading.Thread(target=watch, daemon=True).start()


def chunks(text: str, limit: int = 220) -> list[str]:
    """Sentences packed into chunks of at most ~limit chars; a blank line always starts a new chunk."""
    out = []
    for para in re.split(r"\n\s*\n", text.strip()):
        cur = ""
        for sent in re.split(r"(?<=[.!?…])\s+", " ".join(para.split())):
            if cur and len(cur) + len(sent) > limit:
                out.append(cur)
                cur = sent
            else:
                cur = f"{cur} {sent}".strip()
        if cur:
            out.append(cur)
    return out


def clean(audio, sr: int) -> tuple[np.ndarray, int]:
    """Low-pass 13-15 kHz (cosine taper), resample to 48 kHz, DeepFilterNet 3 (loaded once)."""
    from mlx_audio.resample import resample_audio_array
    from mlx_audio.sts.models.deepfilternet import DeepFilterNetModel

    x = np.asarray(audio, dtype=np.float32).reshape(-1)
    spec = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / sr)
    spec *= 0.5 * (
        1 - np.cos(np.pi * np.clip((15000 - f) / 2000, 0, 1))
    )  # 1 below 13 kHz, 0 above 15
    x = np.fft.irfft(spec, n=len(x)).astype(np.float32)
    if sr != 48000:
        x = np.asarray(resample_audio_array(x, sr, 48000), dtype=np.float32)
    if not _DFN:
        _DFN.append(DeepFilterNetModel.from_pretrained())
    return np.asarray(_DFN[0].enhance_array(x), dtype=np.float32)[: len(x)], 48000


def save(audio: np.ndarray, sr: int, out: Path) -> None:
    """Write .wav directly; anything else is one ffmpeg encode of a float wav (no concat filter)."""
    from mlx_audio.audio_io import write as audio_write

    out.parent.mkdir(parents=True, exist_ok=True)
    if out.suffix.lower() == ".wav":
        audio_write(str(out), audio, sr)
        return
    codec = {
        ".mp3": ["-c:a", "libmp3lame", "-q:a", "1"],
        ".m4a": ["-c:a", "aac", "-b:a", "192k"],
        ".ogg": ["-c:a", "libopus", "-b:a", "96k"],
        ".opus": ["-c:a", "libopus", "-b:a", "96k"],
    }
    with tempfile.TemporaryDirectory() as tmp:
        wav = Path(tmp) / "out.wav"
        audio_write(str(wav), audio, sr)
        subprocess.run(
            [
                "ffmpeg",
                "-v",
                "error",
                "-y",
                "-i",
                str(wav),
                *codec.get(out.suffix.lower(), []),
                str(out),
            ],
            check=True,
        )


def main() -> None:
    ap = argparse.ArgumentParser(
        description=__doc__.split("\n\n")[1],
        formatter_class=argparse.RawTextHelpFormatter,
    )
    what = ap.add_mutually_exclusive_group(required=True)
    what.add_argument("--text", help="one line or paragraph to speak")
    what.add_argument(
        "--file",
        type=Path,
        help="script file: chunked by sentence, joined into one output",
    )
    what.add_argument(
        "--samples",
        help="comma list of built-in sample languages: " + ",".join(SAMPLES),
    )
    ap.add_argument(
        "--ref", type=Path, help="clean speech of one speaker, 10-60 s, no long pauses"
    )
    ap.add_argument(
        "--describe",
        help="voxcpm2 only: design a voice from a description instead of --ref",
    )
    ap.add_argument(
        "--model",
        default="voxcpm2",
        help=f"{', '.join(MODELS)}, or a repo id / local path",
    )
    ap.add_argument(
        "--lang",
        help="zonos3 only (text normalisation, default en); voxcpm2 reads it from the text",
    )
    ap.add_argument(
        "-o", "--out", type=Path, required=True, help=".wav, .mp3, .m4a, .ogg"
    )
    ap.add_argument(
        "--raw", action="store_true", help="skip the low-pass + DeepFilterNet clean-up"
    )
    ap.add_argument("--steps", type=int, default=10, help="voxcpm2 diffusion steps")
    ap.add_argument(
        "--seed", type=int, default=0, help="same seed, same voice across chunks"
    )
    ap.add_argument(
        "--gap",
        type=float,
        default=0.3,
        help="seconds of silence between chunks (samples: 1.0)",
    )
    ap.add_argument(
        "--min-free",
        type=int,
        default=15,
        help="stop below this %% of free memory (0 = off)",
    )
    a = ap.parse_args()

    repo = MODELS.get(a.model, a.model)
    if a.model == "shtorm-ru" and not Path(repo).exists():
        sys.exit(f"{repo} is missing: build it once with `uv run convert_shtorm_ru.py`")
    if a.ref and not a.ref.exists():
        sys.exit(f"reference not found: {a.ref}")
    memory_guard(a.min_free)

    import mlx.core as mx
    from mlx_audio.tts import load

    zonos = "zonos" in repo.lower()
    if a.samples:
        jobs = [(lang, SAMPLES[lang]) for lang in a.samples.split(",")]
        gap = 1.0 if a.gap == 0.3 else a.gap
    else:
        text = a.text if a.text else a.file.read_text(encoding="utf-8")
        jobs, gap = [(a.lang, piece) for piece in chunks(text)], a.gap

    t0 = time.perf_counter()
    model = load(repo)
    print(f"{a.model}: load {time.perf_counter() - t0:.1f} s", flush=True)
    parts, sr, spoken, busy = [], 48000, 0.0, 0.0
    for lang, piece in jobs:
        mx.random.seed(a.seed)
        kw = {"lang_code": lang or "en"} if zonos else {"inference_timesteps": a.steps}
        if a.ref:
            kw["ref_audio"] = str(a.ref)
        if a.describe and not zonos:
            kw["instruct"] = a.describe
        t1 = time.perf_counter()
        r = next(model.generate(text=piece, **kw))
        took = time.perf_counter() - t1
        audio, sr = (
            (np.asarray(r.audio, np.float32).reshape(-1), r.sample_rate)
            if a.raw
            else clean(r.audio, r.sample_rate)
        )
        secs = len(audio) / sr
        spoken, busy = spoken + secs, busy + took
        parts += [audio, np.zeros(int(gap * sr), np.float32)]
        print(
            f"  {lang or '':2s} {len(piece):3d} chars -> {secs:4.1f} s in {took:4.1f} s (RTF {took / secs:.2f}), "
            f"peak {mx.get_peak_memory() / 1e9:.1f} GB",
            flush=True,
        )
    save(np.concatenate(parts[:-1]), sr, a.out)
    print(f"{spoken:.1f} s of speech, RTF {busy / spoken:.2f} -> {a.out}")


if __name__ == "__main__":
    main()
