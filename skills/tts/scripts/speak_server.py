#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10,<3.14"
# dependencies = ["mlx-audio==0.6.6"]
# ///
"""
A speaking daemon: the model loads once, text arrives over localhost, and each sentence plays as
soon as it is ready while the next one is generated.

    uv run speak_server.py --ref voice.wav                          # VoxCPM2 on 127.0.0.1:7788
    uv run speak_server.py --describe "calm, warm male voice"       # design a voice once, then keep it
    curl -s localhost:7788/say --data-binary "Привет. Я слушаю."    # queue text, returns at once
    curl -s -X POST localhost:7788/stop                             # drop the queue, cut playback
    curl -s localhost:7788/state                                    # {"speaking": …, "queued": …}

Every sentence is logged to ~/.supervox/live/speaking.jsonl as {"start", "end", "text"} the
moment it starts playing, so a listener on the same machine can recognise its own echo
(skills/talk/scripts/turns.py does). `--describe` without `--ref` synthesises one reference clip
from the description, caches it under ~/.cache/solo-tts/voices/ and clones from it from then on:
a described voice alone comes out different on every sentence.
"""

import argparse
import hashlib
import json
import queue
import re
import subprocess
import sys
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from tts_mlx import MODELS, clean, lowpass, memory_guard  # noqa: E402

SPEAKING_LOG = Path.home() / ".supervox" / "live" / "speaking.jsonl"
VOICES = Path.home() / ".cache" / "solo-tts" / "voices"
DESIGN_TEXT = {
    "ru": "Привет! Я на связи и готов помогать. Говори спокойно, я дослушаю до конца, "
    "а потом отвечу коротко и по делу. Если нужно что-то сделать, просто скажи.",
    "en": "Hi! I'm here and ready to help. Take your time, I'll listen until you finish, "
    "and then answer briefly and to the point. If something needs doing, just say so.",
}


def pieces(text: str, first_max: int = 60, max_len: int = 80) -> list[str]:
    """Sentences, long ones cut at a comma. Short pieces keep speech gapless: at RTF ~1 (a busy
    machine) piece N+1 is generated while piece N plays, so no piece should outlast the one before."""
    out: list[str] = []
    for sent in re.split(r"(?<=[.!?…])\s+", " ".join(text.split())):
        limit = first_max if not out else max_len
        while len(sent) > limit:
            cut = sent.rfind(", ", 20, limit)
            if cut < 0:
                cut = sent.rfind(" ", 20, limit)
            if cut < 0:
                break
            out.append(sent[: cut + 1].strip())
            sent = sent[cut + 1 :].strip()
            limit = max_len
        if sent:
            out.append(sent)
    return out


def cache_reference(model) -> None:
    """VoxCPM2 VAE-encodes its reference clip on every call (~1 s); the clip never changes here."""
    enc = getattr(model, "_encode_wav", None)
    if enc is None:
        return
    memo: dict = {}

    def cached(
        audio_input, padding_mode: str = "right", trim_silence_vad: bool = False
    ):
        if not isinstance(audio_input, str):
            return enc(
                audio_input,
                padding_mode=padding_mode,
                trim_silence_vad=trim_silence_vad,
            )
        key = (audio_input, padding_mode, trim_silence_vad)
        if key not in memo:
            memo[key] = enc(
                audio_input,
                padding_mode=padding_mode,
                trim_silence_vad=trim_silence_vad,
            )
        return memo[key]

    model._encode_wav = cached


class Speaker:
    """Owns the model: MLX arrays stay on the one thread that created them."""

    def __init__(self, a: argparse.Namespace) -> None:
        self.a = a
        self.epoch = 0
        self.gen_q: queue.Queue = queue.Queue()
        self.play_q: queue.Queue = queue.Queue()
        self.ready = threading.Event()
        self.generating = False
        self.proc: subprocess.Popen | None = None
        self.tmp = Path(tempfile.mkdtemp(prefix="speak-"))
        self.n = 0
        self.playing = False
        self.last_end = 0.0  # when the last piece stopped playing: a listener's echo tail starts here
        self.ack_wav: Path | None = None

    # --- generation thread -------------------------------------------------------------
    def synth(self, model, text: str, ref: str | None, instruct: str | None = None):
        import mlx.core as mx

        mx.random.seed(self.a.seed)
        zonos = "zonos" in self.repo.lower()
        kw = (
            {"lang_code": self.a.lang or "en"}
            if zonos
            else {"inference_timesteps": self.a.steps}
        )
        if ref:
            kw["ref_audio"] = ref
        if instruct and not zonos:
            kw["instruct"] = instruct
        r = next(model.generate(text=text, **kw))
        if self.a.clean == "dfn":
            return clean(r.audio, r.sample_rate)
        x = np.asarray(r.audio, np.float32).reshape(-1)
        return (
            lowpass(x, r.sample_rate) if self.a.clean == "lowpass" else x
        ), r.sample_rate

    def design_ref(self, model) -> str:
        from mlx_audio.audio_io import write

        key = hashlib.sha1(
            f"{self.repo}|{self.a.describe}|{self.a.seed}".encode()
        ).hexdigest()[:10]
        path = VOICES / f"designed-{key}.wav"
        if not path.exists():
            VOICES.mkdir(parents=True, exist_ok=True)
            text = DESIGN_TEXT.get(self.a.design_lang, DESIGN_TEXT["en"])
            audio, sr = self.synth(model, text, None, self.a.describe)
            write(str(path), audio, sr)
            print(f"designed voice saved: {path}", flush=True)
        return str(path)

    def gen_loop(self) -> None:
        from mlx_audio.audio_io import write
        from mlx_audio.tts import load

        self.repo = MODELS.get(self.a.model, self.a.model)
        t0 = time.perf_counter()
        model = load(self.repo)
        cache_reference(model)
        self.ref = (
            str(self.a.ref)
            if self.a.ref
            else (self.design_ref(model) if self.a.describe else None)
        )
        self.synth(
            model, "Проверка." if self.a.design_lang == "ru" else "Check.", self.ref
        )  # warm-up
        ack = getattr(self.a, "ack", None)
        if ack:  # pre-rendered, so it plays the instant a turn ends
            audio, sr = self.synth(model, ack, self.ref)
            self.ack_wav = self.tmp / "keep-ack.wav"
            write(str(self.ack_wav), audio, sr)
            self.ack_dur = len(audio) / sr
        print(
            f"ready: {self.a.model} in {time.perf_counter() - t0:.1f} s, voice {self.ref or 'model default'}, "
            f"http://127.0.0.1:{self.a.port}",
            flush=True,
        )
        self.ready.set()
        while True:
            epoch, text, t_req, first = self.gen_q.get()
            if epoch != self.epoch:
                continue
            self.generating = True
            t1 = time.perf_counter()
            audio, sr = self.synth(model, text, self.ref)
            took = time.perf_counter() - t1
            self.generating = False
            if epoch != self.epoch:
                continue
            self.n += 1
            wav = self.tmp / f"{self.n:05d}.wav"
            write(str(wav), audio, sr)
            dur = len(audio) / sr
            print(
                f"  gen {len(text):3d} chars -> {dur:4.1f} s in {took:4.1f} s",
                flush=True,
            )
            self.play_q.put((epoch, wav, dur, text, t_req, first))

    # --- playback thread ---------------------------------------------------------------
    def play_loop(self) -> None:
        while True:
            epoch, wav, dur, text, t_req, first = self.play_q.get()
            if epoch == self.epoch:
                start = time.time()
                if first:
                    print(
                        f"  first audio {start - t_req:.2f} s after the request",
                        flush=True,
                    )
                SPEAKING_LOG.parent.mkdir(parents=True, exist_ok=True)
                with open(SPEAKING_LOG, "a", encoding="utf-8") as f:
                    f.write(
                        json.dumps(
                            {"start": start, "end": start + dur, "text": text},
                            ensure_ascii=False,
                        )
                        + "\n"
                    )
                self.playing = True
                if self.a.sink == "afplay":
                    self.proc = subprocess.Popen(["afplay", str(wav)])
                    self.proc.wait()
                    self.proc = None
                else:  # "none": timing only, nothing is played
                    time.sleep(dur)
                self.playing = False
                self.last_end = time.time()
            if not wav.name.startswith("keep-"):
                wav.unlink(missing_ok=True)

    # --- API -----------------------------------------------------------------------------
    def say(self, text: str) -> int:
        parts = pieces(text)
        now = time.time()
        for i, p in enumerate(parts):
            self.gen_q.put((self.epoch, p, now, i == 0))
        return len(parts)

    def ack(self) -> None:
        """Play the pre-rendered acknowledgement (no-op without --ack)."""
        if self.ack_wav:
            self.play_q.put(
                (self.epoch, self.ack_wav, self.ack_dur, self.a.ack, time.time(), False)
            )

    def busy(self, tail: float = 0.0) -> bool:
        """Speaking, about to speak, or stopped less than `tail` seconds ago."""
        return self.state()["speaking"] or time.time() - self.last_end < tail

    def stop(self) -> None:
        self.epoch += 1
        for q in (self.gen_q, self.play_q):
            while not q.empty():
                try:
                    q.get_nowait()
                except queue.Empty:
                    break
        if self.proc:
            self.proc.terminate()

    def state(self) -> dict:
        busy = (
            self.generating
            or self.playing
            or not self.gen_q.empty()
            or not self.play_q.empty()
        )
        return {
            "ready": self.ready.is_set(),
            "speaking": busy,
            "queued": self.gen_q.qsize() + self.play_q.qsize(),
        }


def serve(sp: Speaker, port: int) -> None:
    class H(BaseHTTPRequestHandler):
        def reply(self, obj: dict, code: int = 200) -> None:
            body = json.dumps(obj, ensure_ascii=False).encode()
            self.send_response(code)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self) -> None:
            self.reply(
                sp.state()
                if self.path.startswith("/state")
                else {"error": "GET /state"},
                200,
            )

        def do_POST(self) -> None:
            n = int(self.headers.get("Content-Length") or 0)
            text = self.rfile.read(n).decode("utf-8", "replace").strip()
            if self.path.startswith("/stop"):
                sp.stop()
                self.reply({"stopped": True})
            elif self.path.startswith("/say") and text:
                if self.path.startswith("/say?interrupt"):
                    sp.stop()
                self.reply({"queued": sp.say(text)})
            else:
                self.reply({"error": "POST /say with a text body, or POST /stop"}, 400)

        def log_message(self, *args) -> None:
            pass

    ThreadingHTTPServer(("127.0.0.1", port), H).serve_forever()


def main() -> None:
    ap = argparse.ArgumentParser(
        description=__doc__.split("\n\n")[1],
        formatter_class=argparse.RawTextHelpFormatter,
    )
    ap.add_argument(
        "--model",
        default="voxcpm2",
        help=f"{', '.join(MODELS)}, or a repo id / local path",
    )
    ap.add_argument(
        "--ref", type=Path, help="voice to clone: 10-60 s of one clean speaker"
    )
    ap.add_argument(
        "--describe", help="voxcpm2: design a voice once from this description (cached)"
    )
    ap.add_argument(
        "--design-lang",
        default="ru",
        help="language of the designed reference clip: ru or en",
    )
    ap.add_argument("--lang", help="zonos3 only: language code (default en)")
    ap.add_argument(
        "--clean",
        choices=["lowpass", "dfn", "none"],
        default="lowpass",
        help="lowpass: hiss band only, ~free (default); dfn: + DeepFilterNet, slower",
    )
    ap.add_argument("--steps", type=int, default=10, help="voxcpm2 diffusion steps")
    ap.add_argument("--seed", type=int, default=0)
    ap.add_argument(
        "--ack", help="a short word pre-rendered at start (e.g. «Угу.»), for listeners"
    )
    ap.add_argument("--port", type=int, default=7788)
    ap.add_argument(
        "--sink",
        choices=["afplay", "none"],
        default="afplay",
        help="none: time it, play nothing",
    )
    ap.add_argument(
        "--min-free",
        type=int,
        default=15,
        help="exit below this %% of free memory (0 = off)",
    )
    a = ap.parse_args()
    if a.ref and not a.ref.exists():
        sys.exit(f"reference not found: {a.ref}")
    memory_guard(a.min_free)
    sp = Speaker(a)
    threading.Thread(target=sp.gen_loop, daemon=True).start()
    threading.Thread(target=sp.play_loop, daemon=True).start()
    serve(sp, a.port)


if __name__ == "__main__":
    main()
