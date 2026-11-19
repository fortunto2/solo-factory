#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = []
# ///
"""
supervox: a Claude Code channel that carries the live transcript of a room into the session.

    talk.sh --supervox                       # claude with this channel (and voice) loaded
    uv run supervox_channel.py --file t.jsonl --from-start < mcp-requests.jsonl   # protocol test

Follows ~/.supervox/live/current.jsonl like `tail -F`: the path is a symlink that supervox
replaces on every new recording, so the channel re-resolves it and reads a new target from its
first line. Each {"type":"transcript"} becomes
<channel source="supervox" kind="transcript" speaker=S1 t=23>text</channel>; the `start` and
`stop` events come through as kind="start" / kind="stop". Lines from speaker AGENT (the agent's
own speech), heartbeats and summaries are dropped. Notifications are held back until
`notifications/initialized`. stdout is the MCP wire; logs go to stderr. Stdlib only.
"""

import argparse
import json
import os
import sys
import threading
import time
from pathlib import Path

VERSION = "0.1.0"
DEFAULT = Path.home() / ".supervox" / "live" / "current.jsonl"
INSTRUCTIONS = """\
The local `supervox` channel streams the live transcript of the room the person is in (far-field
mic, transcribed on this Mac). Each line arrives as
<channel source="supervox" kind="transcript" speaker="S1" t="23">what was said</channel>
(t = seconds since the recording started); kind="start" / kind="stop" mark a recording beginning
or ending. The text is ASR: names are mangled and `S1` may be several people. This is not a
conversation with you, so do not answer each line. Keep one evolving summary of the room (see
the supervox skill), post a short delta every few lines, and say at once when kind="stop" comes."""

_lock, _open = threading.Lock(), threading.Event()


def send(obj: dict) -> None:
    with _lock:
        sys.stdout.write(json.dumps(obj, ensure_ascii=False) + "\n")
        sys.stdout.flush()


def notify(text: str, **meta) -> None:
    _open.wait()
    send(
        {
            "jsonrpc": "2.0",
            "method": "notifications/claude/channel",
            "params": {"content": text, "meta": {k: str(v) for k, v in meta.items()}},
        }
    )
    print(
        f"-> {meta.get('kind')} {meta.get('speaker', '')}: {text}",
        file=sys.stderr,
        flush=True,
    )


def handle(line: str) -> None:
    try:
        ev = json.loads(line)
    except ValueError:
        return
    kind = ev.get("type")
    if kind == "transcript":
        text = (ev.get("text") or "").strip()
        speaker = str(ev.get("speaker", "?"))
        if text and speaker.upper() != "AGENT":
            notify(text, kind="transcript", speaker=speaker, t=ev.get("t", ""))
    elif kind in ("start", "stop"):
        info = ", ".join(f"{k}={v}" for k, v in ev.items() if k not in ("type", "ts"))
        notify(
            f"recording {kind}" + (f" ({info})" if info else ""),
            kind=kind,
            ts=ev.get("ts", ""),
        )


def follow(path: Path, poll: float, from_start: bool) -> None:
    """tail -F: re-resolve the link each tick; a new target is read from its first line."""
    target, f, buf, first = None, None, b"", True
    while True:
        try:
            real = os.path.realpath(path)
            st = os.stat(real)
        except OSError:
            time.sleep(poll)
            continue
        key = (real, st.st_ino)
        if key != target:
            if f:
                f.close()
            f, buf, target = open(real, "rb"), b"", key  # noqa: SIM115
            if first and not from_start:
                f.seek(0, os.SEEK_END)  # attached mid-recording: no replay of the past
            first = False
            print(f"following {real}", file=sys.stderr, flush=True)
        chunk = f.read()
        if chunk:
            buf += chunk
            *lines, buf = buf.split(b"\n")
            for ln in lines:
                handle(ln.decode("utf-8", "replace"))
        elif st.st_size < f.tell():  # truncated in place
            f.seek(0)
        else:
            time.sleep(poll)


def serve(a: argparse.Namespace) -> None:
    threading.Thread(
        target=follow,
        args=(Path(a.file).expanduser(), a.poll, a.from_start),
        daemon=True,
    ).start()
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
                        "serverInfo": {"name": "supervox", "version": VERSION},
                        "instructions": INSTRUCTIONS,
                    },
                }
            )
        elif method == "notifications/initialized":
            _open.set()
        elif method == "tools/list":
            send({"jsonrpc": "2.0", "id": mid, "result": {"tools": []}})
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
    if a.linger:
        time.sleep(
            a.linger
        )  # test mode: give the follower time to flush after stdin closes
    os._exit(0)


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__.split("\n")[1])
    p.add_argument("--file", default=os.environ.get("SUPERVOX_LIVE", str(DEFAULT)))
    p.add_argument("--poll", type=float, default=0.3)
    p.add_argument(
        "--from-start", action="store_true", help="replay the current file too"
    )
    p.add_argument("--linger", type=float, default=0.0, help=argparse.SUPPRESS)
    serve(p.parse_args())


if __name__ == "__main__":
    main()
