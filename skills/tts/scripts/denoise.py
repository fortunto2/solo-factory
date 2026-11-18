#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10,<3.14"
# dependencies = ["mlx-audio==0.6.6"]
# ///
"""
Speech denoise with DeepFilterNet 3 on the Apple GPU (MLX, ~2M params, ~0.4 GB RSS).

    uv run denoise.py ref.m4a                 # -> ref-dfn.wav, 48 kHz mono
    uv run denoise.py --mix 0.1 a.wav b.wav   # keep 10% of the original under the filter

Run it on a voice reference before cloning: every clone copies its reference's room. Measured on a
25 s phone-quality clip: noise floor -52 dB before, -77 dB after, and the clones' floor dropped
from -50 to -58...-63 dB. tts_mlx.py already runs the same filter on its own output.
"""

import argparse
from pathlib import Path

import numpy as np


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("files", nargs="+", type=Path)
    ap.add_argument(
        "--mix",
        type=float,
        default=0.0,
        help="share of the unfiltered signal mixed back",
    )
    a = ap.parse_args()

    from mlx_audio.audio_io import read, write
    from mlx_audio.sts.models.deepfilternet import DeepFilterNetModel

    model = DeepFilterNetModel.from_pretrained()
    for path in a.files:
        noisy, _ = read(str(path), dtype="float32", sample_rate=48000, nchannels=1)
        noisy = np.asarray(noisy, dtype=np.float32).reshape(-1)
        clean = np.asarray(model.enhance_array(noisy), dtype=np.float32)[: len(noisy)]
        out = (1 - a.mix) * clean + a.mix * noisy[: len(clean)]
        dest = path.with_name(f"{path.stem}-dfn.wav")
        write(str(dest), out, 48000)
        print(f"{path.name} -> {dest}")


if __name__ == "__main__":
    main()
