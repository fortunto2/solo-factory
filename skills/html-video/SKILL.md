---
name: solo-html-video
description: Make standalone motion graphics from plain HTML and render them to MP4 with HyperFrames (headless Chrome, one seeked frame at a time, FFmpeg) — title cards, animated explainers and diagrams, app-store previews, promo and ad shots, kinetic captions. Use when user says "сделай анимацию", "моушн из html", "анимированный ролик", "видео из кода", "hyperframes", "animated explainer", "motion graphics from HTML", "title card", "animated diagram to mp4". Do NOT use for editing real footage (use /video-edit), planning a storyboard from a PRD (use /video-promo), scoring or shipping ad creatives (use /ad-video), or overlays that must stay editable on an editor timeline (they bake into pixels).
license: MIT
metadata:
  author: fortunto2
  version: "1.0.0"
  openclaw:
    emoji: "🎞️"
argument-hint: "<what to animate, size, length>"
---

# html-video — a clip written as a web page, rendered as video

The agent writes one HTML file, `data-start`/`data-duration` say when things are on screen, a
paused GSAP timeline says how they move. The renderer seeks the page to frame N, screenshots it,
and FFmpeg encodes. Output is a finished MP4 you drop into a cut. Upstream:
[heygen-com/hyperframes](https://github.com/heygen-com/hyperframes) (HeyGen, **Apache-2.0**; the
CLI, runtime and its own agent skills are theirs, this skill is a thin, measured wrapper).

**Niche.** Standalone shots: title cards, animated diagrams, app-store and promo clips,
explainer scenes. Not for an editor with a timeline of its own: the result is baked pixels, so a
caption you want to move later must be re-rendered, not dragged.

## Setup (checked: Node 22.22, macOS, Chrome not required)

```bash
node -v                                  # needs >= 22; ffmpeg + ffprobe on PATH
npx -y hyperframes@0.9.94 init promo --example blank --resolution portrait --non-interactive
```

Pin the version (the scaffold's `package.json` does it): same pin, same render weeks later.
No Chrome install: the first run downloads its own to `~/.cache/hyperframes` (about 230 MB, first
render ~1 min instead of ~25 s). Presets for `--resolution`: `portrait` 1080x1920, `landscape`,
`square`, `*-1440p`, `*-4k`. Set `HYPERFRAMES_SKIP_SKILLS=1` to stop `init` installing its skills.

## Workflow

1. **Write `index.html`** from `assets/title-card.html` (a 6 s 1080x1920 card: kicker, two-line
   reveal, rule, subtitle, glow). Rules the runtime enforces:
   - root: `data-composition-id`, `data-start`, `data-duration`, `data-width`, `data-height`;
   - every timed child: `class="clip"` plus `data-start`, `data-duration`, `data-track-index`;
   - one paused timeline in `window.__timelines["<composition-id>"]`, finished with `tl.seek(0)`;
   - no `Date.now()`, `Math.random()`, network fetches at render time; fonts and images local.
2. **Check, then look.**
   ```bash
   npx -y hyperframes@0.9.94 check                  # lint + runtime + layout + motion + contrast, ~18 s
   npx -y hyperframes@0.9.94 snapshot --at 0,1,3    # PNGs + contact-sheet.jpg under .hyperframes/artifacts/
   ```
   Read the frames. A green check does not say it looks right (look before you render).
3. **Render.**
   ```bash
   npx -y hyperframes@0.9.94 render promo -q standard -o out.mp4        # 1080x1920, 6 s, 30 fps
   ```
   `-q`: `draft`, `looks` (default, CRF 16), `standard`, `delivery`. `--format mov` keeps alpha
   (ProRes 4444), `webm` too, `gif` best at 15 fps, `png-sequence` for After Effects. `--fps 60`,
   `--start/--end` for a span, `--workers auto` (one Chrome, ~256 MB, per worker).
4. **Verify the file**: `ffprobe -v error -show_entries stream=codec_name,pix_fmt,width,height,r_frame_rate,nb_frames,duration -of default=nw=1 out.mp4`.
   Expect h264, yuv420p, size and `nb_frames == fps x duration` (180 for 6 s at 30).

## Measured here (v0.9.94, M-series Mac, one 6 s portrait card, no audio)

| What | Number |
|---|---|
| `check` | 18 s |
| `render -q standard`, warm | 21-26 s (capture ~10 s, encode ~2 s, Chrome compile ~6 s) |
| `render` default `looks` | 24.5 s, 1.0 MB; `standard` 0.8 MB |
| cold first run (Chrome download) | ~70 s |
| Two renders, same input | byte-identical MP4 (`cmp`), identical per-frame md5 |

Cost is per frame (180 frames here); only this one simple card was measured, so time a 10 s
scene before promising a batch. WebGL/Three.js scenes will be slower.

## Determinism: golden-test the frames

Frames are a pure function of the HTML, the pin and the machine's fonts/Chrome. So a composition
is testable like code:

```bash
ffmpeg -v error -i out.mp4 -f framemd5 - | grep -v '^#' | awk -F, '{print $6}' | md5   # one hash per film
```

Keep that hash (or a few `snapshot --at` PNG hashes) beside the composition and fail CI when it
moves. Identical bytes held on one machine; across machines expect font and Chrome differences
and use `render --docker` (their deterministic mode) if the golden must travel. Update the golden
only after looking at the new frames.

## Output into the rest of the toolbox

- **`/video-edit`**: render at the master's size and fps (`--fps` equal to the cut, usually 30 or
  25), then use the MP4 as a cutaway or title card. Same frame rate avoids drift at the seam; for
  a join without re-encode, match codec/pix_fmt (h264 yuv420p) and use ffmpeg concat copy.
  Give it silence only if the cut has its own sound; otherwise `-an` is already the default here.
- **`/ad-video`**: a still or a 6-15 s motion shot (end card, price card, feature callout) to feed
  its quality gate. Render 4:5 (set `data-width/height` to 1080x1350; not tested here) and 9:16
  separately; do not crop one into the other. Keep text inside the platform safe zone (check warns).
- **`/video-promo`**: it writes the storyboard; each text-and-motion shot becomes one composition.
- Transparent overlay for a real editor: `--format mov` (alpha ProRes) or `webm`, not mp4.

## What upstream bundles (point at it, don't copy it)

Install on request with `npx skills add heygen-com/hyperframes` or `npx hyperframes skills update`.

| Their skill | Use it for |
|---|---|
| `hyperframes` | The contract and the craft references (motion, type, review). Read first when a film is more than a card |
| `hyperframes-registry` | About 450 ready blocks (transitions, charts, kinetic type, 3D, captions). Search before hand-building |
| `hyperframes-cli` | CLI by job; read when a command fails |
| `media-use` | Music, voiceover, images, transcripts, cutouts; many paths use HeyGen's paid services, so prefer our `/tts`, `/transcribe` |
| `figma`, `remotion-to-hyperframes` | Only when the source is a Figma file or an existing Remotion project |
| `slideshow` | A live-presented deck, not an MP4 |
| `reverse-any-video`, `style-sampling` | Marked HyperFrames Pro: skip |

## Gotchas (each hit in the test render)

- **First frame must not be empty.** Check warns `first_frame_empty`: frame 0 is the social
  thumbnail. Start motion from a visible state, not from `opacity: 0`.
- **`.clip` gives every element a full-frame box.** A bar with `width: 0` is drawn full width at
  t=0 (we saw it). Give small elements a real size and animate `scaleX`/`scale`.
- **Do not animate `letterSpacing`, `width`, `top` and other layout properties**: lint error
  `gsap_non_transform_motion`, the glyphs snap to pixels under seek-by-frame. Animate `x`, `y`,
  `scale`, `opacity`.
- **Text clipped by a reveal mask**: `overflow:hidden` lines need `padding-bottom` or a taller
  line-height (layout check: `text_box_overflow`).
- **Safe zones**: keep text about 140 px from the left/right edges and out of the bottom ~25 %
  for TikTok/Reels/Shorts (`outside_safe_zone`).
- **GSAP is loaded from a CDN** in the scaffold. Render needs the network for it; vendor
  `gsap.min.js` into the project for an offline or golden-tested build.
- **`preview` blocks the terminal**; an agent uses `preview --background` then `--stop`.
- `init` writes `AGENTS.md`/`CLAUDE.md` into the project; fine, they are theirs.

## Don't

- Don't use it for real footage edits or long films: it is a motion-graphics renderer (a 10-minute
  explainer is many scenes, each a sub-composition via `data-composition-src`).
- Don't skip `check` and `snapshot`, and don't call a render done without ffprobe.
- Don't float versions (`@latest`) in a project you golden-test.
- Don't paste upstream skill files into this repo; link them.

## Credit

HyperFrames, (c) HeyGen, Apache-2.0: <https://github.com/heygen-com/hyperframes>. The template
in `assets/` is original to this skill and was rendered with their CLI.
