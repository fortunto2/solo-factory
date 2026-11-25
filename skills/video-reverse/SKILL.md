---
name: solo-video-reverse
description: Reverse-engineer a finished video shot by shot with the rea-video CLI, locally and without a video-model key — for each shot whether it was filmed, AI-generated, 3D or built in code, camera setups and moves, light, grade, captions, the sound track, and a remake plan; output is a VIDEO.md package plus report.html. Use when user says "разбери ролик по кадрам", "как это снято", "как переснять эту рекламу", "это AI или снято на камеру", "сделай такой же ролик", "reverse-engineer this video", "shot breakdown", "how was this ad made", "remake this video". Do NOT use for fact-checking or summarising what a video claims (use /claim-check), for editing your own footage (use /video-edit), or for making the ad itself (use /ad-video; this skill feeds it).
license: MIT
metadata:
  author: fortunto2
  version: "1.0.0"
  openclaw:
    emoji: "🔬"
argument-hint: "<video file>"
---

# video-reverse: how was this video made, shot by shot

A reference video goes in; a layered breakdown comes out: per shot the production method (filmed, AI,
3D, code, screen recording), camera, light, grade, captions, sound, and what it would take to remake.
The engine is **rea-video** by JuneYaooo (Apache-2.0, https://github.com/JuneYaooo/rea-video); this skill is
the way we run it: local only, the agent as the vision model, and the output wired into
`solo:ad-video` and `solo:video-edit`. Everything below was run on a 29 s 720p clip.

## 1. Install (once, ~70 s)

Needs ffmpeg and Python 3.10-3.14. Isolated tool, no global pip:

```bash
uv tool install --python 3.12 "rea-video[ocr] @ git+https://github.com/JuneYaooo/rea-video"
rea-video --help
```

Add speech recognition (`[ocr,asr]`, SenseVoice, ~160 MB) only when the clip has speech and no burned
subtitles. First `decompose` downloads ~216 MB of audio-separation models (UVR MDX-Net, BandIt v2); set
`REA_VIDEO_MODELS=<dir>` to choose where. It also writes `~/.rea-video/` (a sha256 -> source path map).

## 2. Break one video down

```bash
V=ref.mp4; O=_work/ref            # work files in the project's _work/, never /tmp
rea-video --lang en decompose "$V" -o "$O" --lang en     # no key: pixel statistics + audio, ~3 min, 150% CPU
rea-video summary "$O/breakdown.json"                    # the compact verdict; read the VLM: line
rea-video review "$O"                                    # writes review_tasks.json + review_answers.json
# look at the images it lists, fill review_answers.json, then:
rea-video apply-review "$O" --by agent --lang en
rea-video videomd "$O" --check                           # validates the package against the VIDEO.md spec
```

Say `--lang en` twice: the global flag sets CLI messages, the subcommand flag sets the report. Cyrillic
or other scripts burned into the picture: `--ocr-lang` supports zh/en/ja/ko only.

### The review step is not optional

Without a vision model the tools judge live / AI / 3D from pixel noise and palette. Measured here: a
filmed stage keynote, low-resolution and recompressed, came back **"3D render" 55-64% on all 6 shots**
(flat colour, small palette), with the verdict line reading `Mixed production: 3D render 100%`.
You are the vision model: open `storyboard.jpg` and each `shots/shot_NNN.jpg`, then fill
`review_answers.json` (per shot: `label_probs`, `image_source`, `evidence`, `description`). After
`apply-review` all six became live action 100%. The tool fuses your answer with its own, so overall
confidence stays near 0.5 even when you are sure; say so in the report rather than trusting the number.
Rules and the full answer schema: [references/review.md](references/review.md).

## 3. Read it in layers (do not open breakdown.json)

Output layout (`out/ref/`, 20 MB, 6 shots): `VIDEO.md`, `video/*.md`, `report.html`, `report.md`,
`breakdown.json`, `storyboard.jpg`, `audio.png`, `shots/`, `stems/`, `packaging/`.

| Read | Tokens | When |
|---|---|---|
| `VIDEO.md` | ~2k | first, always: card, verdict, open questions, map |
| `video/timeline.md` | ~0.5k per 6 shots | one line per shot; keys ending `~` are inferred |
| `video/look.md`, `sound.md`, `packaging.md`, `rhythm.md` | 0.2-0.5k | a specific question |
| `video/remake.md` | ~1.5k | remake plan, shoot schedule, real assets needed |
| `video/shots/NN.md` + `shots/shot_NNN.jpg` | ~0.5k | verifying one shot against its frames |
| `breakdown.json` | ~21k | never, unless writing code |

Seen on screen and measured are plain keys; inferred ones carry `~`. Where they disagree, trust the frames.
Details of every file: [references/output.md](references/output.md).

## 4. What it gives for live footage

Shot size, fixed vs moving camera, key-light direction and ratio, colour temperature, grade, cuts per
minute, jump cuts, which cuts land in speech pauses, a shooting plan with a gear list, subtitle timing
(exports `.ass`), the stems (`vocals.wav`, `music.wav`, `effects.wav`), BPM and sound-effect anchors.
Light and gear are estimates from a recompressed file: say "about", never "shot with".

## 5. Feed the other skills (what is ours)

**Remake a competitor ad for our product -> `solo:ad-video`.**

```bash
uv run --script ${CLAUDE_PLUGIN_ROOT}/skills/video-reverse/scripts/shotlist.py "$O" --beats-bpm 100
```

prints the breakdown as an ad-video shot-list table (`# | Beats | Seconds | Source | Direction | sees |
Caption`). Source is mapped: filmed -> `real`, 3D and code -> `render`, AI and avatar -> `generated`.
Direction and Caption are left empty on purpose: those are our decisions. Then, per
[references/to-ad-video.md](references/to-ad-video.md): keep the original's shot count, pacing and
transitions, swap the product for ours (only from its real footage or 3D model, never generated),
keep the caption beats, replace every real asset the breakdown lists, and run ad-video's quality gate.

**Own footage in the same style -> `solo:video-edit`.** Use `video/rhythm.md` (cuts per minute, shot
lengths, cut times in frames) and `video/look.md` as the target, not as a template to copy frame for
frame. [references/to-video-edit.md](references/to-video-edit.md).

**Remake plan, no generation.** `rea-video plan "$O"` rewrites `video/remake.md` for a named model (default
MiniMax H3; `--model <id>`, list with `rea-video models`). It only plans. The paid generation path is
`remake-run`, which needs capsule-cinema: out of scope here (see Don't).

## Gotchas

- **Filmed vs 3D is the weak call** on old, small or re-encoded sources. The README's own table says tools
  only are 88.6% on re-encoded files against 98-99% on originals. Always review (section 2).
- **Report language leaks**: `huazi` (the Chinese word for styled text) stays in English output, and
  capability tables and eval docs are Chinese. Translate when quoting.
- **Every shot gets the same description** if you fill the template lazily. Describe what changes per shot.
- **`remake/` holds one `intent.yaml`** after `plan`; edit `model`, `generate`, `swaps` there, rerun `plan`.
- **Shot count follows cuts the detector sees.** A hard-cut talk can come back as 6 shots with 3 jump cuts;
  check `video/rhythm.md` before planning one generation per shot.
- **It is slow because of the audio stems**, not the downloads: 180 s first run, 162 s with models cached, for a
  29 s clip (CPU only). Budget ~5-6x realtime. Numbers: [references/run-log.md](references/run-log.md).
- **Your review can be overruled.** With one reviewer the answer is limited to the tool's top-2 labels unless
  its top 3 are all under 0.4 (that is why live action was accepted here). A flip that does not stick: say so.

## Don't

- Don't upload the video anywhere by default. `--vlm` with `GEMINI_API_KEY` or `REA_VLM_*` sends shot clips
  (Gemini: the video itself) to a third party: only when the user chose it and the material may leave the
  machine. Never print or open the `.env` that holds the key.
- Don't call `remake-run` or any generation command without the user's yes: it is paid.
- Don't reuse the original's footage, music, characters or likeness. This is for learning structure,
  pacing and technique, then remaking with material we have rights to.
- Don't paste `breakdown.json` or `report.md` into the conversation; read `VIDEO.md` first.
- Don't use this to judge whether what a video says is true (use /claim-check).

## Credit

rea-video, Apache-2.0, https://github.com/JuneYaooo/rea-video. VIDEO.md is an open format by the same
ecosystem: https://videomd.github.io/videomd/. Sound separation inside it uses UVR MDX-Net and BandIt v2
(weights CC BY-SA 4.0), downloaded on first use. This skill adds the install recipe, the review discipline
and the ad-video and video-edit bridges; it does not vendor upstream code.
