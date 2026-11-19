"""
Owner check for the voice channel: is this turn in the owner's voice?

WeSpeaker CAM++ (ONNX, 512-d), the same model and features supervox uses
(crates/voxkit/src/speaker.rs): 80-bin Kaldi fbank, no dither, mean-normalised per clip.
A label, not authentication: a cloned or replayed voice passes it.
"""

import wave
from pathlib import Path

import numpy as np

SR = 16000
MODEL = Path.home() / ".supervox" / "models" / "wespeaker_en_voxceleb_CAM++.onnx"
OWNER_WAV = Path.home() / ".supervox" / "voices" / "Рустам.wav"
# Measured on 17 s of enrolment audio, 3 clips of other voices and 201 windows of a
# 19 min call: owner clips 0.60-0.89, everyone else <= 0.48 (see SKILL.md).
THRESHOLD = 0.55
MIN_SECS = 0.5  # shorter than this the embedding is noise


def read_wav(path: Path) -> np.ndarray:
    with wave.open(str(path)) as w:
        sr, ch = w.getframerate(), w.getnchannels()
        x = (
            np.frombuffer(w.readframes(w.getnframes()), np.int16).astype(np.float32)
            / 32768
        )
    if ch > 1:
        x = x.reshape(-1, ch).mean(1)
    if sr != SR:
        from math import gcd

        from scipy.signal import resample_poly

        g = gcd(sr, SR)
        x = resample_poly(x, SR // g, sr // g).astype(np.float32)
    return x


class OwnerGate:
    def __init__(
        self,
        wav: Path = OWNER_WAV,
        name: str = "Рустам",
        threshold: float = THRESHOLD,
        model: Path = MODEL,
    ) -> None:
        import onnxruntime as ort

        self.name, self.threshold = name, threshold
        self.sess = ort.InferenceSession(str(model), providers=["CPUExecutionProvider"])
        self.voiceprint = self.embed(read_wav(wav))

    def embed(self, x: np.ndarray) -> np.ndarray:
        import kaldi_native_fbank as knf

        o = knf.FbankOptions()
        o.frame_opts.dither = 0.0
        o.frame_opts.snip_edges = True
        o.frame_opts.samp_freq = SR
        o.mel_opts.num_bins = 80
        f = knf.OnlineFbank(o)
        f.accept_waveform(SR, x.astype(np.float32).tolist())
        f.input_finished()
        feats = np.stack([f.get_frame(i) for i in range(f.num_frames_ready)])
        feats = (feats - feats.mean(0)).astype(np.float32)[None]
        e = self.sess.run(None, {self.sess.get_inputs()[0].name: feats})[0][0]
        return e / np.linalg.norm(e)

    def check(self, x: np.ndarray) -> dict:
        """Attributes for the channel event; never raises."""
        try:
            if len(x) < MIN_SECS * SR:
                return {"speaker": "unknown", "owner": "false", "sim": "-"}
            sim = float(self.embed(x) @ self.voiceprint)
        except Exception:
            return {"speaker": "unknown", "owner": "false", "sim": "-"}
        mine = sim >= self.threshold
        return {
            "speaker": self.name if mine else "unknown",
            "owner": "true" if mine else "false",
            "sim": f"{sim:.2f}",
        }
