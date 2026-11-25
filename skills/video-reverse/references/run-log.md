# Run log: one real breakdown, no key

Machine: Apple Silicon laptop, Python 3.12 via uv, ffmpeg 9, CPU only. Clip: a 29.2 s 1280x720 24.9 fps
filmed talk (stage, one speaker, low-resolution source), burned-in lower graphics.

| Step | Command | Wall |
|---|---|---|
| install | `uv tool install --python 3.12 "rea-video[ocr] @ git+https://github.com/JuneYaooo/rea-video"` | 70 s (rea-video 0.1.0, videomd 1.2.0, rapidocr-onnxruntime) |
| decompose, cold | `rea-video --lang en decompose ref.mp4 -o out/ref --lang en` | 180 s incl. 216 MB model download |
| decompose, warm | same, new output dir | 162 s (150-200% CPU) |
| review | `rea-video review out/ref` | 0.1 s |
| apply-review | after filling 6 shots | 1.5 s |
| plan | `rea-video --lang en plan out/ref` | 0.7 s |
| check | `rea-video videomd out/ref --check` | passes |

Timeline of a cold run: shot detection in 1 s, per-shot analysis and OCR done by ~45 s, the rest is
vocal/music stem separation (UVR MDX-Net) and effects separation (BandIt v2) in the background.

## Results

- Tool verdict, before review: "3D render 100%", 55-64% per shot, confidence 0.588, 5 of 6 shots flagged
  low confidence. Wrong: it is filmed.
- After my review of all 6 shots (live action 0.93 each): "live action 100%", confidence 0.516, every shot
  still flagged low confidence (the fusion keeps the tool's 3D prior in the number).
- Right without help: 6 shots found, medium close-ups, fixed then moving camera, 2 set-ups, 10.3 cuts per
  minute, 3 jump cuts, voice present on 64% of the duration, human voice (73%), key light frame-left, warm.
- Wrong or doubtful: "moving camera (gimbal / handheld)" 71% on cuts between zooms; the "ceiling light"
  key source; "graphic" overlays on shots that carry only a lower-third.
- Output language: `--lang en` gave English prose, but `huazi` appears untranslated.

## Side effects on the machine

`~/.rea-video/sources.json` (sha256 -> source path) and
`$REA_VIDEO_MODELS` (default `~/.cache/rea-video/models`). Nothing else outside the output directory.
Before sharing a package run `rea-video clean-paths <out>` (report only) and then `--apply`: it strips local
paths (none were found here because the run used relative paths; absolute inputs may leave some).
