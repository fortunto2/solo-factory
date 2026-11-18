#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10,<3.14"
# dependencies = ["mlx-audio==0.6.6"]
# ///
"""
Build the Russian stress-mark VoxCPM2 for MLX once: ArtShtorm/Shtorm-VoxCPM2-RU -> 4-bit.

    uv run convert_shtorm_ru.py                  # -> ~/.cache/solo-tts/shtorm-ru-4bit (2.3 GB)
    uv run convert_shtorm_ru.py --keep-src       # keep the 5 GB bf16 download for other builds

The fine-tune is openbmb/VoxCPM2 with a merged LoRA that follows `+` before the stressed vowel
(Apache-2.0). Only model.safetensors differs from the base: audiovae.pth, config.json and
tokenizer.json carry the same LFS sha256 as openbmb/VoxCPM2. Recipe = mlx-community/VoxCPM2-4bit:
only base_lm and residual_lm go to 4 bits (group 64); DiT, encoder and AudioVAE stay full precision.

Three traps this script handles, all met on the first build:
- `hf download` (xet) stalled at a few hundred KB; one plain connection through a VPN gave ~1 MB/s,
  eight ranged connections 6.5 MB/s. Files are fetched in 8 ranges, resumable, sha256-checked.
- audiovae.pth needs torch, which mlx-audio does not pull in: it is turned into safetensors in a
  throwaway `uv run --with torch`. Keys get an `audio_vae.` prefix because mlx-audio loads every
  *.safetensors in the folder as model weights, and prefixed raw keys are what its sanitize maps.
  convert copies that raw file into the output, where it would load twice, so it is deleted there.
- The repo's tokenizer_config sends AutoTokenizer to its own tokenization_voxcpm2.py (remote code).
  tokenizer.json is the base one, so it is loaded as LlamaTokenizer like mlx-community's build and
  none of the repo's code runs.
"""

import argparse
import hashlib
import json
import shutil
import ssl
import subprocess
import sys
import time
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

REPO = "ArtShtorm/Shtorm-VoxCPM2-RU"
FILES = [
    "config.json",
    "tokenizer.json",
    "tokenizer_config.json",
    "special_tokens_map.json",
    "audiovae.pth",
    "model.safetensors",
]
CACHE = Path.home() / ".cache" / "solo-tts"


def _ssl() -> ssl.SSLContext:
    """python.org builds on macOS ship without root certificates; certifi comes with mlx-audio's deps."""
    try:
        import certifi

        return ssl.create_default_context(cafile=certifi.where())
    except ImportError:
        return ssl.create_default_context()


CTX = _ssl()


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        while block := f.read(1 << 24):
            h.update(block)
    return h.hexdigest()


def fetch(url: str, dest: Path, size: int, parts: int = 8) -> None:
    """Ranged parallel download with resume; each part must come back as 206 Partial Content."""
    chunk = -(-size // parts)

    def part(i: int) -> None:
        start, end = i * chunk, min(size, (i + 1) * chunk) - 1
        p = dest.with_name(f"{dest.name}.part{i}")
        want = end - start + 1
        for _ in range(8):
            have = p.stat().st_size if p.exists() else 0
            if have >= want:
                return
            req = urllib.request.Request(
                url, headers={"Range": f"bytes={start + have}-{end}"}
            )
            try:
                with (
                    urllib.request.urlopen(req, timeout=60, context=CTX) as r,
                    open(p, "ab") as f,
                ):
                    if r.status != 206:
                        raise RuntimeError(
                            f"server ignored the range request (HTTP {r.status})"
                        )
                    shutil.copyfileobj(r, f, 1 << 20)
            except OSError as e:
                print(f"  part {i}: {e}, retrying", file=sys.stderr)
                time.sleep(3)
        raise RuntimeError(f"part {i} incomplete after 8 tries")

    with ThreadPoolExecutor(parts) as ex:
        list(ex.map(part, range(parts)))
    with open(dest, "wb") as out:
        for i in range(parts):
            p = dest.with_name(f"{dest.name}.part{i}")
            with open(p, "rb") as f:
                shutil.copyfileobj(f, out, 1 << 24)
            p.unlink()


def download(src: Path) -> None:
    src.mkdir(parents=True, exist_ok=True)
    with urllib.request.urlopen(
        f"https://huggingface.co/api/models/{REPO}/tree/main", timeout=30, context=CTX
    ) as r:
        tree = {x["path"]: x for x in json.load(r)}
    for name in FILES:
        meta, dest = tree[name], src / name
        url = f"https://huggingface.co/{REPO}/resolve/main/{name}"
        lfs = meta.get("lfs")
        if (
            dest.exists()
            and dest.stat().st_size == meta["size"]
            and (not lfs or sha256(dest) == lfs["oid"])
        ):
            continue
        t0 = time.perf_counter()
        if lfs:
            fetch(url, dest, meta["size"])
            if sha256(dest) != lfs["oid"]:
                raise RuntimeError(f"{name}: sha256 mismatch, delete it and run again")
        else:
            with (
                urllib.request.urlopen(url, timeout=60, context=CTX) as r,
                open(dest, "wb") as f,
            ):
                shutil.copyfileobj(r, f)
        print(
            f"{name}: {meta['size'] / 1e6:.0f} MB in {time.perf_counter() - t0:.0f} s",
            flush=True,
        )


def pth_to_safetensors(src: Path) -> None:
    """Runs inside `uv run --with torch`: audiovae.pth -> audio_vae_raw.safetensors, keys prefixed."""
    import torch
    from safetensors.numpy import save_file

    state = torch.load(src / "audiovae.pth", map_location="cpu", weights_only=True)
    state = state.get("state_dict", state)
    out = {
        "audio_vae." + k.removeprefix("module."): v.float().numpy()
        for k, v in state.items()
        if hasattr(v, "numpy")
    }
    save_file(out, str(src / "audio_vae_raw.safetensors"))
    print(f"audio_vae_raw.safetensors: {len(out)} tensors")


def to_mlx(src: Path, dst: Path) -> None:
    from mlx_audio.convert import convert
    from mlx_audio.tts.models.voxcpm2 import voxcpm2

    cfg = json.loads((src / "config.json").read_text())
    for key in ("device", "dtype"):
        cfg.pop(key, None)
    cfg["model_type"] = "voxcpm2"
    (src / "config.json").write_text(json.dumps(cfg, indent=2))
    voxcpm2.Model.model_quant_predicate = lambda self, path, module: path.startswith(
        ("base_lm", "residual_lm")
    )
    if (
        dst.exists()
    ):  # only an earlier build of this model is replaced, never an arbitrary folder
        if not (
            (dst / "config.json").exists() and (dst / "model.safetensors").exists()
        ):
            sys.exit(f"{dst} exists and is not a model build: pick another --out")
        shutil.rmtree(dst)
    convert(
        hf_path=str(src), mlx_path=str(dst), quantize=True, q_bits=4, q_group_size=64
    )
    (dst / "audio_vae_raw.safetensors").unlink(missing_ok=True)
    (dst / "tokenization_voxcpm2.py").unlink(missing_ok=True)
    tok = json.loads((dst / "tokenizer_config.json").read_text())
    tok["tokenizer_class"] = "LlamaTokenizer"
    tok.pop("auto_map", None)
    (dst / "tokenizer_config.json").write_text(
        json.dumps(tok, indent=2, ensure_ascii=False)
    )
    out = json.loads((dst / "config.json").read_text())
    out["quantization"]["targets"] = ["base_lm", "residual_lm"]
    (dst / "config.json").write_text(json.dumps(out, indent=2))


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--src", type=Path, default=CACHE / "shtorm-ru-src", help="bf16 download"
    )
    ap.add_argument("--out", type=Path, default=CACHE / "shtorm-ru-4bit")
    ap.add_argument(
        "--keep-src",
        action="store_true",
        help="keep the 5 GB bf16 weights after the build",
    )
    ap.add_argument(
        "--pth-only", action="store_true", help=argparse.SUPPRESS
    )  # the torch subprocess
    a = ap.parse_args()
    if a.pth_only:
        pth_to_safetensors(a.src)
        return
    download(a.src)
    if not (a.src / "audio_vae_raw.safetensors").exists():
        subprocess.run(
            [
                "uv",
                "run",
                "--no-project",
                "--python",
                "3.12",
                "--with",
                "torch",
                "--with",
                "safetensors",
                "--with",
                "numpy",
                "python",
                __file__,
                "--pth-only",
                "--src",
                str(a.src),
            ],
            check=True,
        )
    t0 = time.perf_counter()
    to_mlx(a.src, a.out)
    size = sum(f.stat().st_size for f in a.out.iterdir()) / 1e9
    print(f"{a.out}: {size:.2f} GB in {time.perf_counter() - t0:.0f} s")
    if not a.keep_src:
        for name in ("model.safetensors", "audiovae.pth", "audio_vae_raw.safetensors"):
            (a.src / name).unlink(missing_ok=True)
    print(
        'try: uv run tts_mlx.py --model shtorm-ru --ref voice.wav --text "Он откр+ыл зам+ок." -o ru.wav'
    )


if __name__ == "__main__":
    main()
