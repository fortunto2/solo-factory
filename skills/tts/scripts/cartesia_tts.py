"""
Cartesia Sonic as a mouth for speak_server / the talk channel: the text goes to Cartesia's API,
audio comes back; no audio of anyone leaves the machine, only what the agent decided to say.

    speak_server.py --model cartesia --cartesia-voice <voice id>
    voice_channel.py --tts cartesia --cartesia-voice <voice id>

Key: CARTESIA_API_KEY, else the macOS Keychain item named by CARTESIA_KEYCHAIN_SERVICE
(default "cartesia-api-key"); it is read once and never printed. One HTTPS connection is kept
open, so a sentence costs one round trip instead of a TLS handshake each time.
"""

import http.client
import json
import os
import re
import ssl
import subprocess
from pathlib import Path

import numpy as np

HOST, PATH = "api.cartesia.ai", "/tts/bytes"
API_VERSION = "2026-08-14"
SR = 44100
_CAFILE = "/etc/ssl/cert.pem"  # python.org builds ship no CA bundle; macOS has one here


def api_key() -> str:
    key = os.environ.get("CARTESIA_API_KEY", "").strip()
    if key:
        return key
    service = os.environ.get("CARTESIA_KEYCHAIN_SERVICE", "cartesia-api-key")
    r = subprocess.run(
        ["security", "find-generic-password", "-s", service, "-w"],
        capture_output=True,
        text=True,
        check=False,
    )
    if r.returncode == 0 and r.stdout.strip():
        return r.stdout.strip()
    raise RuntimeError(
        f"no Cartesia key: set CARTESIA_API_KEY or add a Keychain item named {service!r}"
    )


def guess_lang(text: str) -> str:
    """Cartesia needs the language per request; a mixed conversation switches it per sentence."""
    if re.search(r"[А-Яа-яЁё]", text):
        return "ru"
    if re.search(r"[çğıöşüÇĞİÖŞÜ]", text):
        return "tr"
    return "en"


class Cartesia:
    def __init__(
        self,
        voice: str,
        model: str = "sonic-3.6",
        lang: str | None = None,
        speed: float | None = None,
    ) -> None:
        if not voice:
            raise RuntimeError(
                "--cartesia-voice <voice id> is required (play.cartesia.ai/voices)"
            )
        self.voice, self.model, self.lang, self.speed = voice, model, lang, speed
        self.key = api_key()
        cafile = _CAFILE if Path(_CAFILE).exists() else None
        self.ctx = ssl.create_default_context(cafile=cafile)
        self.conn: http.client.HTTPSConnection | None = None

    def _post(self, body: bytes) -> bytes:
        for attempt in (1, 2):  # a kept-alive connection the server closed: reopen once
            if self.conn is None:
                self.conn = http.client.HTTPSConnection(
                    HOST, timeout=30, context=self.ctx
                )
            try:
                self.conn.request(
                    "POST",
                    PATH,
                    body,
                    {
                        "X-API-Key": self.key,
                        "Cartesia-Version": API_VERSION,
                        "Content-Type": "application/json",
                        "User-Agent": "solo-tts/1",
                    },
                )
                r = self.conn.getresponse()
                data = r.read()
            except (OSError, http.client.HTTPException):
                self.conn.close()
                self.conn = None
                if attempt == 2:
                    raise
                continue
            if r.status != 200:
                raise RuntimeError(
                    f"Cartesia {r.status}: {data[:300].decode('utf-8', 'replace')}"
                )
            return data
        raise AssertionError("unreachable")

    def synth(self, text: str) -> tuple[np.ndarray, int]:
        body: dict = {
            "model_id": self.model,
            "transcript": text,
            "voice": {"id": self.voice},
            "language": self.lang or guess_lang(text),
            "output_format": {
                "container": "raw",
                "encoding": "pcm_f32le",
                "sample_rate": SR,
            },
        }
        if self.speed:
            body["generation_config"] = {"speed": self.speed}
        data = self._post(json.dumps(body, ensure_ascii=False).encode())
        return np.frombuffer(data, dtype="<f4").copy(), SR
