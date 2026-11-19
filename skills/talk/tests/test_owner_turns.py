"""JSON-RPC protocol test with a file as the mic: the owner's turn is labelled, a stranger's is not.

Needs the models and voices this Mac has (supervox voiceprint, ASR, TTS); skipped elsewhere.
Run: uv run --with pytest --with numpy --with scipy pytest skills/talk/tests -q
"""

import json
import subprocess
import time
import wave
from pathlib import Path

import numpy as np
import pytest

TALK = Path(__file__).resolve().parents[1] / "scripts"
OWNER = Path.home() / ".supervox/voices/Рустам.wav"
STRANGER = Path.home() / ".cache/solo-tts/voices/designed-6ea4da2023.wav"
MODEL = Path.home() / ".supervox/models/wespeaker_en_voxceleb_CAM++.onnx"

pytestmark = pytest.mark.skipif(
    not (OWNER.exists() and STRANGER.exists() and MODEL.exists()),
    reason="needs the supervox voiceprint, a stranger clip and the CAM++ model",
)


def _read(p: Path, secs: float) -> np.ndarray:
    with wave.open(str(p)) as w:
        sr = w.getframerate()
        x = np.frombuffer(w.readframes(int(secs * sr)), np.int16)
    if sr != 16000:
        from scipy.signal import resample_poly

        x = resample_poly(x.astype(np.float32), 16000, sr).astype(np.int16)
    return x


def _wav(path: Path, parts: list[np.ndarray]) -> None:
    gap = np.zeros(int(2.5 * 16000), np.int16)
    x = np.concatenate([np.concatenate([p, gap]) for p in parts])
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1), w.setsampwidth(2), w.setframerate(16000)
        w.writeframes(x.tobytes())


def test_turns_carry_owner_attrs(tmp_path: Path) -> None:
    mic = tmp_path / "mic.wav"
    _wav(mic, [_read(STRANGER, 6), _read(OWNER, 6)])
    p = subprocess.Popen(
        [
            "uv",
            "run",
            "--script",
            str(TALK / "voice_channel.py"),
            "--input",
            str(mic),
            "--sink",
            "none",
            "--ack",
            "",
        ],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        text=True,
    )
    reqs = [
        {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {}},
        {"jsonrpc": "2.0", "method": "notifications/initialized"},
    ]
    for r in reqs:
        p.stdin.write(json.dumps(r) + "\n")
    p.stdin.flush()
    turns, init, deadline = [], None, time.time() + 240
    while time.time() < deadline and not any(t["owner"] == "true" for t in turns):
        line = p.stdout.readline()
        if not line:
            break
        m = json.loads(line)
        if m.get("id") == 1:
            init = m["result"]
        if m.get("method") == "notifications/claude/channel":
            meta = m["params"]["meta"]
            if meta.get("kind") == "turn":
                turns.append(meta)
    p.kill()
    assert 'owner="true"' in init["instructions"]
    assert turns, "no turn arrived"
    # the stranger comes first and may be split in several turns: none of them is the owner
    assert (turns[0]["owner"], turns[0]["speaker"]) == ("false", "unknown"), turns
    assert (turns[-1]["owner"], turns[-1]["speaker"]) == ("true", "Рустам"), turns
    assert float(turns[-1]["sim"]) >= 0.55 > float(turns[0]["sim"]), turns
