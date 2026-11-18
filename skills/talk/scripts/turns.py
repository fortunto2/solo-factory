#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10,<3.14"
# dependencies = ["onnxruntime>=1.19", "numpy", "transformers>=4.40"]
# ///
"""
Ears for a voice conversation with an agent: follow supervox's live transcript, drop the agent's
own voice, ask smart-turn whether the speaker has finished, print one line per finished turn.

    uv run turns.py                          # follow ~/.supervox/live/current.jsonl
    uv run turns.py --check a.wav b.wav      # smart-turn verdict on files (known-answer check)

Output, one line each, flushed (meant for the Monitor tool in the main session):

    TURN p=0.91 wait=0.2s | Слушай, а что у нас сегодня по продажам?
    STATE recording stopped

How a turn ends. supervox cuts speech at its VAD pause (vad_pause_ms, 1200 by default) and writes
one transcript line per cut. For each line this script reads the last 8 s of the WAV supervox is
writing (~/.supervox/calls/recording-*.wav, flushed as it records), trims it to 0.2 s after the
last voiced frame, and asks smart-turn v3.2 (pipecat-ai, BSD-2, 8 MB int8 ONNX, Whisper-tiny
encoder, 23 languages) for the probability that the turn is complete. Complete: print now.
Incomplete: hold for the next line, extending while the WAV shows voice, and print after --hold
seconds of quiet anyway.

Echo. Lines that arrive while (or just after) speak_server.py was playing are compared with what
it played (~/.supervox/live/speaking.jsonl): if at least --echo of their words were in the
agent's own sentences, the line is the room hearing the agent and is dropped. With headphones
there is no echo; --barge-in then also stops the agent's speech when the person starts talking.
Decisions are logged to ~/.supervox/live/turns.log.
"""

import argparse
import json
import os
import re
import sys
import time
import urllib.request
import wave
from pathlib import Path

import numpy as np

LIVE = Path.home() / ".supervox" / "live"
CALLS = Path.home() / ".supervox" / "calls"
SPEAKING = LIVE / "speaking.jsonl"
MODEL_DIR = Path.home() / ".cache" / "solo-tts" / "smart-turn"
MODEL_URL = "https://huggingface.co/pipecat-ai/smart-turn-v3/resolve/main/smart-turn-v3.2-cpu.onnx"
LOG = LIVE / "turns.log"


def log(msg: str) -> None:
    LOG.parent.mkdir(parents=True, exist_ok=True)
    with open(LOG, "a", encoding="utf-8") as f:
        f.write(f"{time.strftime('%H:%M:%S')} {msg}\n")


def say(msg: str) -> None:
    print(msg, flush=True)
    log(msg)


# --- smart-turn ----------------------------------------------------------------------------
class SmartTurn:
    def __init__(self) -> None:
        os.environ.setdefault("TRANSFORMERS_VERBOSITY", "error")
        import onnxruntime as ort
        from transformers import WhisperFeatureExtractor

        path = MODEL_DIR / "smart-turn-v3.2-cpu.onnx"
        if not path.exists():
            MODEL_DIR.mkdir(parents=True, exist_ok=True)
            urllib.request.urlretrieve(MODEL_URL, path)
        so = ort.SessionOptions()
        so.inter_op_num_threads = 1
        so.intra_op_num_threads = 2
        self.sess = ort.InferenceSession(
            str(path), sess_options=so, providers=["CPUExecutionProvider"]
        )
        self.fe = WhisperFeatureExtractor(chunk_length=8)

    def __call__(self, x16: np.ndarray) -> float:
        """Probability that the speech in x16 (16 kHz mono, ends at the pause) is a finished turn."""
        x = x16[-8 * 16000 :]
        x = np.pad(
            x, (8 * 16000 - len(x), 0)
        )  # pad at the start, as pipecat's inference does
        feats = self.fe(
            x,
            sampling_rate=16000,
            return_tensors="np",
            padding="max_length",
            max_length=8 * 16000,
            truncation=True,
            do_normalize=True,
        ).input_features.astype(np.float32)
        return float(self.sess.run(None, {"input_features": feats})[0].reshape(-1)[0])


# --- audio ---------------------------------------------------------------------------------
def to16k(x: np.ndarray, sr: int) -> np.ndarray:
    if sr == 16000:
        return x
    n = np.arange(-32, 33)
    h = np.sinc(2 * 7600 / sr * n) * np.hamming(
        len(n)
    )  # low-pass at 7.6 kHz before decimating
    y = np.convolve(x, h / h.sum(), mode="same")
    t = np.arange(0, len(y) / sr, 1 / 16000)
    return np.interp(t, np.arange(len(y)) / sr, y).astype(np.float32)


def read_wav_tail(path: Path, secs: float) -> tuple[np.ndarray, int]:
    """Last `secs` of a 16-bit mono WAV that may still be growing (header sizes not final yet)."""
    with open(path, "rb") as f:
        hdr = f.read(44)
        if hdr[:4] != b"RIFF" or hdr[8:12] != b"WAVE" or hdr[36:40] != b"data":
            raise ValueError(f"{path.name}: not a plain 16-bit PCM WAV")
        sr = int.from_bytes(hdr[24:28], "little")
        size = os.fstat(f.fileno()).st_size
        start = max(44, size - int(secs * sr) * 2)
        start -= (start - 44) % 2
        f.seek(start)
        raw = f.read(size - start)
    x = np.frombuffer(raw[: len(raw) // 2 * 2], "<i2").astype(np.float32) / 32768
    return x, sr


def frames_rms(x: np.ndarray, sr: int, ms: int = 20) -> np.ndarray:
    n = sr * ms // 1000
    k = len(x) // n
    return np.sqrt((x[: k * n].reshape(k, n) ** 2).mean(axis=1)) if k else np.zeros(0)


def voice_threshold(rms: np.ndarray) -> float:
    return max(0.006, float(np.percentile(rms, 10)) * 4) if len(rms) else 0.006


def trim_to_pause(x: np.ndarray, sr: int, keep: float = 0.2) -> np.ndarray:
    """Cut the trailing silence down to `keep` s: smart-turn is meant to run right at the pause."""
    rms = frames_rms(x, sr)
    voiced = np.nonzero(rms > voice_threshold(rms))[0]
    if not len(voiced):
        return x
    end = (voiced[-1] + 1) * sr // 50 + int(keep * sr)
    return x[: min(len(x), end)]


def live_wav(explicit: Path | None) -> Path | None:
    if explicit:
        return explicit
    cands = sorted(CALLS.glob("recording-*.wav"), key=lambda p: p.stat().st_mtime)
    if cands and time.time() - cands[-1].stat().st_mtime < 30:
        return cands[-1]
    return None


def voice_now(wav: Path | None, window: float = 0.4) -> bool:
    """Voice in the last `window` s of a WAV that is still being written (stalled = no voice)."""
    if not wav or not wav.exists() or time.time() - wav.stat().st_mtime > 1.0:
        return False
    try:
        x, sr = read_wav_tail(wav, 8)
    except (OSError, ValueError):
        return False
    rms = frames_rms(x, sr)
    tail = rms[-int(window * 50) :]
    return bool(len(tail) and (tail > voice_threshold(rms)).any())


# --- echo ----------------------------------------------------------------------------------
def words(s: str) -> list[str]:
    return [w for w in re.findall(r"\w+", s.lower().replace("ё", "е")) if len(w) > 1]


class Echo:
    """What the agent said and when, read incrementally from speak_server's log."""

    def __init__(self) -> None:
        self.pos = SPEAKING.stat().st_size if SPEAKING.exists() else 0
        self.spans: list[tuple[float, float, str]] = []

    def refresh(self) -> None:
        if not SPEAKING.exists():
            return
        with open(SPEAKING, encoding="utf-8") as f:
            f.seek(self.pos)
            for line in f:
                try:
                    d = json.loads(line)
                    self.spans.append((d["start"], d["end"], d["text"]))
                except (ValueError, KeyError):
                    pass
            self.pos = f.tell()
        self.spans = [s for s in self.spans if s[1] > time.time() - 120]

    def speaking(self, now: float, tail: float = 0.0) -> bool:
        self.refresh()
        return any(s <= now <= e + tail for s, e, _ in self.spans)

    def share(self, text: str, now: float, tail: float = 5.0) -> float:
        """Share of the line's word pairs that the agent itself said in its last sentences.

        Pairs, not words: a person answering reuses the agent's words ("what about sales" after
        "I'll check sales") but not its word order; the room hearing the agent repeats both.
        A one-word line falls back to the word itself."""
        self.refresh()
        spoken = [t for s, e, t in self.spans if s - 1 <= now <= e + tail]
        lw = [w[:5] for w in words(text)]
        if not spoken or not lw:
            return 0.0
        said = [[w[:5] for w in words(t)] for t in spoken]
        if len(lw) == 1:
            return float(any(lw[0] in t for t in said))
        pairs = {(a, b) for t in said for a, b in zip(t, t[1:], strict=False)}
        mine = list(zip(lw, lw[1:], strict=False))
        return sum(p in pairs for p in mine) / len(mine)


# --- following supervox ----------------------------------------------------------------------
class Follow:
    """tail -F on a symlink that supervox repoints at each new recording."""

    def __init__(self, path: Path) -> None:
        self.path, self.target, self.f, self.buf = path, None, None, ""
        self.reopen(from_start=False)

    def reopen(self, from_start: bool) -> None:
        try:
            target = os.path.realpath(self.path)
            f = open(target, encoding="utf-8")  # noqa: SIM115 (kept open while following)
        except OSError:
            self.target, self.f = None, None
            return
        if not from_start:
            f.seek(0, 2)
        if self.f:
            self.f.close()
        self.target, self.f, self.buf = target, f, ""

    def lines(self) -> list[dict]:
        if self.path.exists() and os.path.realpath(self.path) != self.target:
            self.reopen(from_start=True)  # a new recording: read it from its first line
        if not self.f:
            return []
        self.buf += self.f.read()
        *done, self.buf = self.buf.split("\n")
        out = []
        for line in done:
            try:
                out.append(json.loads(line))
            except ValueError:
                pass
        return out


def stop_speech(port: int) -> None:
    try:
        urllib.request.urlopen(
            urllib.request.Request(
                f"http://127.0.0.1:{port}/stop", data=b"", method="POST"
            ),
            timeout=1,
        )
    except OSError:
        pass


def main() -> None:
    ap = argparse.ArgumentParser(
        description=__doc__.split("\n\n")[1],
        formatter_class=argparse.RawTextHelpFormatter,
    )
    ap.add_argument(
        "--stream",
        type=Path,
        default=LIVE / "current.jsonl",
        help="supervox live stream",
    )
    ap.add_argument(
        "--wav",
        type=Path,
        help="audio being recorded (default: newest ~/.supervox/calls/recording-*.wav)",
    )
    ap.add_argument(
        "--threshold",
        type=float,
        default=0.5,
        help="smart-turn probability that ends a turn",
    )
    ap.add_argument(
        "--hold",
        type=float,
        default=2.0,
        help="seconds of quiet after an unfinished line before it is sent anyway",
    )
    ap.add_argument(
        "--echo",
        type=float,
        default=0.5,
        help="drop a line when this share of its words was the agent's own",
    )
    ap.add_argument(
        "--barge-in",
        action="store_true",
        help="with headphones: the person talking stops the agent's speech",
    )
    ap.add_argument(
        "--port", type=int, default=7788, help="speak_server port, for --barge-in"
    )
    ap.add_argument(
        "--check",
        nargs="+",
        type=Path,
        help="print smart-turn's verdict for these WAV files and exit",
    )
    a = ap.parse_args()

    st = SmartTurn()
    if a.check:
        for p in a.check:
            with wave.open(str(p)) as w:
                sr, raw = w.getframerate(), w.readframes(w.getnframes())
                x = np.frombuffer(raw, "<i2").astype(np.float32) / 32768
                if w.getnchannels() > 1:
                    x = x.reshape(-1, w.getnchannels()).mean(axis=1)
            t0 = time.perf_counter()
            prob = st(to16k(trim_to_pause(x, sr), sr))
            print(
                f"p={prob:.2f} {'complete' if prob >= a.threshold else 'unfinished'}  "
                f"({(time.perf_counter() - t0) * 1000:.0f} ms)  {p.name}"
            )
        return

    follow, echo = Follow(a.stream), Echo()
    pending: list[str] = []
    deadline = last_p = first_at = 0.0
    say(
        f"STATE listening: {a.stream} -> {follow.target or 'no recording yet, start `supervox live`'}"
    )

    def emit(why: str) -> None:
        nonlocal pending
        say(
            f"TURN p={last_p:.2f} wait={time.time() - last_line_at:.1f}s {why}| {' '.join(pending)}"
        )
        pending = []

    last_line_at = 0.0
    while True:
        for ev in follow.lines():
            kind = ev.get("type")
            if kind == "start":
                say("STATE recording started")
            elif kind == "stop":
                if pending:
                    emit("stop ")
                say("STATE recording stopped")
            elif kind == "transcript" and ev.get("text", "").strip():
                now, text = time.time(), ev["text"].strip()
                share = echo.share(text, now)
                if share >= a.echo:
                    log(f"echo {share:.2f} dropped: {text}")
                    continue
                if a.barge_in and echo.speaking(now):
                    stop_speech(a.port)
                    log("barge-in: speech stopped")
                wav = live_wav(a.wav)
                if wav:
                    try:
                        x, sr = read_wav_tail(wav, 10)
                        last_p = st(to16k(trim_to_pause(x, sr), sr))
                    except (OSError, ValueError) as e:
                        log(f"wav unreadable ({e}), punctuation fallback")
                        last_p = 0.9 if text[-1] in ".?!…" else 0.3
                else:
                    last_p = 0.9 if text[-1] in ".?!…" else 0.3
                if not pending:
                    first_at = now
                pending.append(text)
                last_line_at = now
                log(
                    f"line p={last_p:.2f} echo={share:.2f} wav={wav.name if wav else '-'}: {text}"
                )
                if last_p >= a.threshold:
                    emit("")
                else:
                    deadline = now + a.hold
        if pending and time.time() >= deadline:
            if voice_now(live_wav(a.wav)) and time.time() - first_at < 60:
                deadline = (
                    time.time() + 0.4
                )  # still talking: the next line is on its way
            else:
                emit("hold ")
        time.sleep(0.1)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(0)
