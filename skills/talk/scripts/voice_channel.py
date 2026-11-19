#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10,<3.14"
# dependencies = ["mlx-audio==0.6.6", "onnx-asr[cpu,hub]>=0.12", "sounddevice>=0.5", "transformers>=4.40"]
# ///
"""
voice: a Claude Code channel that hears and speaks. One process, everything on this Mac.

    talk.sh                                   # claude with this channel loaded (the usual way)
    uv run voice_channel.py --input a.wav --sink none < mcp-requests.jsonl   # protocol test

mic (16 kHz) -> Silero VAD -> pause of --pause s -> smart-turn v3.2 says "finished?" -> ASR
(GigaAM v3 for Russian, or Parakeet v3) -> notifications/claude/channel into the session.
The session answers with the `say` tool -> VoxCPM2 (tts/scripts/speak_server.Speaker) -> afplay.

While the agent speaks (and --echo-tail s after) the mic is ignored, so the agent never hears
itself; with headphones --barge-in instead stops the agent when the person starts talking.
stdout is the MCP wire: it is kept private, and everything else that prints goes to stderr.
"""

import argparse
import collections
import json
import os
import queue
import re
import sys
import threading
import time
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path[:0] = [str(HERE), str(HERE.parent.parent / "tts" / "scripts")]

WIRE = os.fdopen(os.dup(1), "w", buffering=1, encoding="utf-8")
os.dup2(2, 1)  # native libraries and print() now land on stderr, never on the wire
sys.stdout = sys.stderr

import numpy as np  # noqa: E402

VERSION = "0.1.0"
SR, FRAME = 16000, 512  # Silero's window: 32 ms
CACHE = Path.home() / ".cache" / "solo-tts"
SILERO_URL = "https://github.com/snakers4/silero-vad/raw/master/src/silero_vad/data/silero_vad.onnx"
ASR_MODELS = {"gigaam": "gigaam-v3-e2e-rnnt", "parakeet": "nemo-parakeet-tdt-0.6b-v3"}
INSTRUCTIONS = """\
The person is talking to you by voice through the local `voice` channel (microphone on this
Mac, transcribed on the device). Each finished spoken turn arrives as
<channel source="voice" kind="turn" ...>what they said</channel>; kind="status" is a notice
from the channel itself. They may not be looking at the screen: answer every turn out loud
with the `say` tool, in the language they spoke.
Voice and screen have different jobs. VOICE is the headline: one or two short phrases, about
fifteen words in all, the answer or the decision only; no preamble, no recap, no lists read
out; numbers and dates as words; no markdown, code, links or emoji. SCREEN is everything else:
put details, lists, numbers, code and paths in your normal text reply, as long as useful, and
end the spoken part with «подробности на экране» when there are any. `say` speaks whole
sentences up to a character cap and drops the rest, so a long text is cut, not read. For work:
say in a few words what you will do, do it with tools, then say the result in one phrase; if a
step takes longer than ten seconds, say «ещё минуту». The text is ASR output: read through misheard
names; ask by voice only when a risky action is ambiguous. why="hold" means they paused
mid-thought and went quiet, so the turn may be unfinished. Typed messages in the terminal
get normal text answers. When they say «стоп», «хватит», «пока» or «конец», say a short
goodbye and call `listen` with on=false."""
TOOLS = [
    {
        "name": "say",
        "description": "Speak one or two short phrases aloud; returns at once. Details go on screen.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "text": {
                    "type": "string",
                    "description": "plain spoken words, ~15 words; whole sentences past the cap are dropped",
                },
                "interrupt": {
                    "type": "boolean",
                    "description": "drop what is still queued first",
                },
            },
            "required": ["text"],
        },
    },
    {
        "name": "stop",
        "description": "Stop speaking now and drop the queue.",
        "inputSchema": {"type": "object", "properties": {}},
    },
    {
        "name": "listen",
        "description": "Turn the microphone on or off.",
        "inputSchema": {
            "type": "object",
            "properties": {"on": {"type": "boolean"}},
            "required": ["on"],
        },
    },
]

_wire_lock, _wire_open = threading.Lock(), threading.Event()


def send(obj: dict) -> None:
    with _wire_lock:
        WIRE.write(json.dumps(obj, ensure_ascii=False) + "\n")
        WIRE.flush()


OUTBOX: "queue.Queue[str] | None" = None  # --http mode: turns wait here for GET /next


def notify(text: str, **meta) -> None:
    if OUTBOX is not None:
        kind = str(meta.pop("kind", "turn")).upper()
        tags = " ".join(f"{k}={v}" for k, v in meta.items())
        OUTBOX.put(f"{kind} {tags}: {text}" if tags else f"{kind}: {text}")
        print(f"-> {kind}: {text}", file=sys.stderr, flush=True)
        return
    _wire_open.wait()
    send(
        {
            "jsonrpc": "2.0",
            "method": "notifications/claude/channel",
            "params": {"content": text, "meta": {k: str(v) for k, v in meta.items()}},
        }
    )
    print(f"-> {meta.get('kind')}: {text}", file=sys.stderr, flush=True)


class Silero:
    def __init__(self) -> None:
        import onnxruntime as ort

        path = CACHE / "silero" / "silero_vad.onnx"
        if not path.exists():
            path.parent.mkdir(parents=True, exist_ok=True)
            urllib.request.urlretrieve(SILERO_URL, path)
        self.sess = ort.InferenceSession(str(path), providers=["CPUExecutionProvider"])
        self.reset()

    def reset(self) -> None:
        self.state = np.zeros((2, 1, 128), np.float32)
        self.ctx = np.zeros(64, np.float32)

    def __call__(self, frame: np.ndarray) -> float:
        inp = np.concatenate([self.ctx, frame])[None].astype(np.float32)
        out, self.state = self.sess.run(
            None, {"input": inp, "state": self.state, "sr": np.array(SR, np.int64)}
        )
        self.ctx = frame[-64:]
        return float(out.reshape(-1)[0])


class Voice:
    """Ears and mouth. start() loads everything, then the ears loop runs on its own thread."""

    def __init__(self, a: argparse.Namespace) -> None:
        self.a = a
        self.listening = True
        self.last_pt = -1.0
        self.ready = threading.Event()
        self.frames: queue.Queue = queue.Queue()

    # --- loading -------------------------------------------------------------------------
    def start(self) -> None:
        try:
            self._load()
        except Exception as e:  # the session must hear why, not see a silent channel
            notify(
                f"voice channel failed to start: {type(e).__name__}: {e}", kind="status"
            )
            raise
        threading.Thread(target=self.ears, daemon=True).start()

    def _load(self) -> None:
        import onnx_asr
        from speak_server import Speaker
        from tts_mlx import memory_guard
        from turns import SmartTurn

        memory_guard(self.a.min_free)
        t0 = time.perf_counter()
        sp_args = argparse.Namespace(
            model=self.a.tts,
            ref=self.a.ref,
            describe=None if self.a.ref else self.a.describe,
            design_lang=self.a.design_lang,
            lang=None,
            clean="lowpass",
            steps=self.a.steps,
            seed=0,
            sink=self.a.sink,
            ack=self.a.ack or None,
            port=0,
            cartesia_voice=self.a.cartesia_voice,
            cartesia_model=self.a.cartesia_model,
        )
        self.mouth = Speaker(sp_args)
        threading.Thread(target=self.mouth.gen_loop, daemon=True).start()
        threading.Thread(target=self.mouth.play_loop, daemon=True).start()
        self.vad, self.turn = Silero(), SmartTurn()
        name = ASR_MODELS.get(self.a.asr, self.a.asr)
        try:
            self.asr = onnx_asr.load_model(name, quantization=self.a.quant or None)
        except Exception as e:  # not every model publishes every quantization
            print(
                f"{name} {self.a.quant}: {e}; loading full precision", file=sys.stderr
            )
            self.asr = onnx_asr.load_model(name)
        self.asr.recognize(np.zeros(SR, np.float32), sample_rate=SR)  # warm-up
        self.mouth.ready.wait()
        self.ready.set()
        notify(
            f"voice ready in {time.perf_counter() - t0:.0f} s: listening ({self.a.asr}), "
            f"voice {self.mouth.ref}. Greet the person briefly with say."
            + (f" Rules: {INSTRUCTIONS}" if OUTBOX is not None else ""),
            kind="ready" if OUTBOX is not None else "status",
        )

    # --- audio in -------------------------------------------------------------------------
    def _mic(self) -> None:
        import sounddevice as sd

        def cb(indata, frames, t, status) -> None:
            self.frames.put(indata[:, 0].copy())

        self.stream = sd.InputStream(
            samplerate=SR, channels=1, dtype="float32", blocksize=FRAME, callback=cb
        )
        self.stream.start()

    def _file(self, path: Path) -> None:
        """Test input: the file in real time, then silence forever."""
        from mlx_audio.audio_io import read

        x, _ = read(str(path), dtype="float32", sample_rate=SR, nchannels=1)
        x = np.asarray(x, np.float32).reshape(-1)

        def feed() -> None:
            for i in range(0, len(x) - FRAME, FRAME):
                self.frames.put(x[i : i + FRAME])
                time.sleep(FRAME / SR)
            while True:
                self.frames.put(np.zeros(FRAME, np.float32))
                time.sleep(FRAME / SR)

        threading.Thread(target=feed, daemon=True).start()

    # --- turns ----------------------------------------------------------------------------
    def ears(self) -> None:
        self._file(self.a.input) if self.a.input else self._mic()
        pre = collections.deque(maxlen=10)  # 320 ms kept before speech starts
        speech: list[np.ndarray] = []
        voiced = quiet = 0
        checked = in_turn = False
        while True:
            frame = self.frames.get()
            if not self.listening or (
                self.mouth.busy(self.a.echo_tail) and not self.a.barge_in
            ):
                if in_turn or pre:
                    self.vad.reset()
                    pre.clear()
                    speech, in_turn = [], False
                continue
            p = self.vad(frame)
            if self.a.barge_in and p > 0.7 and self.mouth.busy():
                self.mouth.stop()
            if not in_turn:
                pre.append(frame)
                if p >= 0.5:
                    speech, in_turn, voiced, quiet, checked = (
                        list(pre),
                        True,
                        1,
                        0,
                        False,
                    )
                continue
            speech.append(frame)
            if p >= 0.35:
                voiced, quiet, checked = voiced + 1, 0, False
                if len(speech) * FRAME / SR < self.a.max_turn:
                    continue
            else:
                quiet += 1
            silent = quiet * FRAME / SR
            x = np.concatenate(speech)
            if silent >= self.a.pause and not checked:
                checked = True
                cut = x[
                    : len(x) - max(0, quiet * FRAME - int(0.2 * SR))
                ]  # 0.2 s after the voice
                pt = self.last_pt = self.turn(cut)
                if pt >= self.a.threshold:
                    self._finish(cut, voiced, pt, "end", silent)
                    in_turn = False
            elif silent >= self.a.hold or len(x) / SR >= self.a.max_turn:
                self._finish(
                    x,
                    voiced,
                    self.last_pt,
                    "hold" if silent >= self.a.hold else "long",
                    silent,
                )
                in_turn = False
            if not in_turn:
                self.vad.reset()
                pre.clear()

    def _finish(
        self, x: np.ndarray, voiced: int, pt: float, why: str, silent: float
    ) -> None:
        if voiced * FRAME / SR < 0.25:  # a click or a cough, not a turn
            return
        if (
            self.a.ack and why == "end"
        ):  # after a pause mid-thought the person may go on at once
            self.mouth.ack()
        t0 = time.perf_counter()
        text = self.asr.recognize(x, sample_rate=SR).strip()
        ms = (time.perf_counter() - t0) * 1000
        if not text:
            return
        notify(
            text,
            kind="turn",
            why=why,
            p=f"{pt:.2f}" if pt >= 0 else "-",
            secs=f"{len(x) / SR:.1f}",
            lag=f"{silent + ms / 1000:.2f}",
            asr_ms=f"{ms:.0f}",
        )

    # --- tools ----------------------------------------------------------------------------
    def headline(self, text: str) -> tuple[str, int]:
        """Whole sentences up to --max-say characters, and how many characters were dropped."""
        text = " ".join(text.split())
        cap = self.a.max_say
        if cap <= 0 or len(text) <= cap:
            return text, 0
        out = ""
        for sent in re.split(r"(?<=[.!?…])\s+", text):
            if out and len(out) + 1 + len(sent) > cap:
                break
            out = f"{out} {sent}".strip()
        if (
            len(out) > cap
        ):  # one long first sentence: cut at the last comma, else a space
            cut = out.rfind(", ", 0, cap)
            cut = cut if cut > cap // 3 else out.rfind(" ", 0, cap)
            out = out[: cut if cut > 0 else cap].rstrip(" ,;:—-") + "."
        return out, len(text) - len(out)

    def call(self, name: str, args: dict) -> str:
        if not self.ready.is_set():
            return "voice is still loading; try again in a few seconds"
        if name == "say":
            if args.get("interrupt"):
                self.mouth.stop()
            spoken, dropped = self.headline(str(args.get("text", "")))
            n = self.mouth.say(spoken)
            if dropped:
                return (
                    f"spoke {len(spoken)} chars in {n} pieces; {dropped} chars were NOT spoken. "
                    "Say one or two short phrases and put the rest in your text reply on screen."
                )
            return f"speaking ({n} pieces)"
        if name == "stop":
            self.mouth.stop()
            return "stopped"
        if name == "listen":
            self.listening = bool(args.get("on", True))
            return f"microphone {'on' if self.listening else 'off'}"
        raise ValueError(f"unknown tool {name}")


def serve(a: argparse.Namespace) -> None:
    voice = Voice(a)
    for raw in sys.stdin.buffer:
        try:
            msg = json.loads(raw)
        except ValueError:
            continue
        mid, method = msg.get("id"), msg.get("method")
        if method == "initialize":
            ver = (msg.get("params") or {}).get("protocolVersion", "2025-06-18")
            send(
                {
                    "jsonrpc": "2.0",
                    "id": mid,
                    "result": {
                        "protocolVersion": ver,
                        "capabilities": {
                            "experimental": {"claude/channel": {}},
                            "tools": {},
                        },
                        "serverInfo": {"name": "voice", "version": VERSION},
                        "instructions": INSTRUCTIONS,
                    },
                }
            )
            threading.Thread(target=voice.start, daemon=True).start()
        elif method == "notifications/initialized":
            _wire_open.set()
        elif method == "tools/list":
            send({"jsonrpc": "2.0", "id": mid, "result": {"tools": TOOLS}})
        elif method == "tools/call":
            p = msg.get("params") or {}
            try:
                out, err = (
                    voice.call(p.get("name", ""), p.get("arguments") or {}),
                    False,
                )
            except Exception as e:
                out, err = f"{type(e).__name__}: {e}", True
            send(
                {
                    "jsonrpc": "2.0",
                    "id": mid,
                    "result": {
                        "content": [{"type": "text", "text": out}],
                        "isError": err,
                    },
                }
            )
        elif method == "ping":
            send({"jsonrpc": "2.0", "id": mid, "result": {}})
        elif mid is not None:
            send(
                {
                    "jsonrpc": "2.0",
                    "id": mid,
                    "error": {"code": -32601, "message": f"unknown method {method}"},
                }
            )
    os._exit(0)  # Claude Code closed the pipe: take the audio threads down with us


ATTACH_RULES = (
    "answer each TURN aloud: curl -s --data-binary 'text' 127.0.0.1:{port}/say ; "
    "one or two short phrases, details on screen; re-arm the Monitor when it expires; "
    "on «стоп» say goodbye, then curl -s -X POST 127.0.0.1:{port}/quit"
)


def serve_http(a: argparse.Namespace) -> None:
    """Attach to a session that is already open: no MCP, no start flag. Turns queue up for
    GET /next (a Monitor long-polls it, so nothing is lost when it is re-armed); the session
    answers with POST /say (raw text body), /stop, /listen?on=0|1, /quit."""
    global OUTBOX, INSTRUCTIONS
    from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
    from urllib.parse import parse_qs, urlparse

    OUTBOX = queue.Queue()
    voice = Voice(a)

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *_args) -> None:
            pass

        def reply(self, code: int, text: str = "") -> None:
            body = (text + "\n").encode() if text else b""
            self.send_response(code)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self) -> None:
            u = urlparse(self.path)
            if u.path == "/next":
                wait = min(float(parse_qs(u.query).get("timeout", ["25"])[0]), 55.0)
                lines = []
                try:
                    lines.append(OUTBOX.get(timeout=wait))
                    while True:
                        lines.append(OUTBOX.get_nowait())
                except queue.Empty:
                    pass
                return self.reply(200, "\n".join(lines)) if lines else self.reply(204)
            if u.path == "/state":
                return self.reply(
                    200,
                    json.dumps(
                        {"ready": voice.ready.is_set(), "listening": voice.listening}
                    ),
                )
            self.reply(404, "GET /next | /state")

        def do_POST(self) -> None:
            u = urlparse(self.path)
            q = parse_qs(u.query, keep_blank_values=True)
            body = self.rfile.read(int(self.headers.get("Content-Length") or 0)).decode(
                "utf-8", "replace"
            )
            name = u.path.strip("/")
            if name == "quit":
                self.reply(200, "bye")
                voice.mouth.stop() if voice.ready.is_set() else None
                os._exit(0)
            args = {
                "say": {"text": body, "interrupt": "interrupt" in q},
                "listen": {"on": q.get("on", ["1"])[0] not in ("0", "off", "false")},
                "stop": {},
            }.get(name)
            if args is None:
                return self.reply(404, "POST /say /stop /listen?on=0|1 /quit")
            try:
                self.reply(200, voice.call(name, args))
            except Exception as e:  # noqa: BLE001  the caller reads the reason
                self.reply(500, f"{type(e).__name__}: {e}")

    server = ThreadingHTTPServer(("127.0.0.1", a.http), Handler)
    INSTRUCTIONS = ATTACH_RULES.format(port=a.http)  # the ready line carries the rules
    print(
        f"voice: http://127.0.0.1:{a.http} (attach mode)", file=sys.stderr, flush=True
    )
    threading.Thread(target=voice.start, daemon=True).start()
    server.serve_forever()


def main() -> None:
    ap = argparse.ArgumentParser(
        description=__doc__.split("\n\n")[1],
        formatter_class=argparse.RawTextHelpFormatter,
    )
    ap.add_argument(
        "--asr",
        default="gigaam",
        help="gigaam (Russian, best measured), parakeet (25 European languages), or an onnx-asr model name",
    )
    ap.add_argument(
        "--quant", default="int8", help="ASR weights: int8 or '' for full precision"
    )
    ap.add_argument(
        "--tts",
        default="voxcpm2",
        help="voxcpm2, shtorm-ru, zonos3, a repo id, or cartesia (API: only the agent's text leaves the Mac)",
    )
    ap.add_argument("--cartesia-voice", help="--tts cartesia: voice id")
    ap.add_argument("--cartesia-model", default="sonic-3.6")
    ap.add_argument("--ref", type=Path, help="voice to clone, 10-60 s of one speaker")
    ap.add_argument(
        "--describe",
        default="A calm, warm, middle-aged male voice, clear studio recording",
    )
    ap.add_argument("--design-lang", default="ru")
    ap.add_argument(
        "--steps", type=int, default=10, help="VoxCPM2 diffusion steps (6: faster)"
    )
    ap.add_argument(
        "--ack",
        default="Угу.|Ага.|Так.|Хм.|Ясно.|Слышу.",
        help="said the moment a turn ends, one of these '|'-separated at random, never twice in a row; '' for none",
    )
    ap.add_argument(
        "--max-say",
        type=int,
        default=120,
        help="characters spoken per say call, whole sentences; the rest is dropped (0: no cap)",
    )
    ap.add_argument(
        "--pause", type=float, default=0.25, help="silence before smart-turn is asked"
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
        help="silence that ends an unfinished turn anyway",
    )
    ap.add_argument("--max-turn", type=float, default=60.0)
    ap.add_argument(
        "--echo-tail",
        type=float,
        default=0.35,
        help="mic stays deaf this long after speech",
    )
    ap.add_argument(
        "--barge-in", action="store_true", help="headphones: talking stops the agent"
    )
    ap.add_argument("--input", type=Path, help="a WAV instead of the mic (tests)")
    ap.add_argument("--sink", choices=["afplay", "none"], default="afplay")
    ap.add_argument("--min-free", type=int, default=15)
    ap.add_argument(
        "--http",
        type=int,
        metavar="PORT",
        help="attach to an open session instead of MCP: GET /next for a Monitor, POST /say",
    )
    a = ap.parse_args()
    serve_http(a) if a.http else serve(a)


if __name__ == "__main__":
    main()
