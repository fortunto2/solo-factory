---
name: solo-music-reels-cut
description: Cut a vertical reels/shorts/TikTok music video from a source video plus a new audio track. Real beat detection (no guessed BPM), section-aware cut density (verse = mirror/water, chorus = kaleidoscope/RGB shift, peak = fastest cuts with a flash on every downbeat), 14-effect ffmpeg palette. Use when user says "cut a reel for this song", "music video from this footage", "beat-synced clip", "shorts from this track", "сделай ролик на трек", "клип на мою музыку", or hands over an audio file and a video expecting a montage. Do NOT use for cutting speech or interviews (use /video-edit) or for splitting a song into stems (use /stem-split).
license: MIT
metadata:
  author: fortunto2
  version: "1.1.0"
  openclaw:
    emoji: "🎬"
---

# music-reels-cut

Beat-synced vertical 1080x1920 mp4 from source footage and a music track. Cut density follows the
song's real beats and phrases, not a guessed BPM.

## Tools

- `scripts/beats.mjs`: beat, downbeat and section detection with the public `life2film-engine` package (WASM, runs offline). Needs Node 20+, ffmpeg, `npm i life2film-engine` in the working folder.
- `scripts/render_template.py`: the orchestrator. Copy it, edit the `# EDIT:` lines, run it with `uv run --script`.
- ffmpeg with `-filter_complex_script` (the chain is too long for an inline argument).

## Workflow

1. **Inputs.** Audio file, source video (any aspect), density preset: `chill` (1 s verse / 0.5 s chorus), `medium` (0.5 / 0.25, default), `wild` (0.25 / 0.125, near subliminal). Target length defaults to `min(audio length, 60 s)`. Ask once, in one message.
2. **Beats.**
   ```bash
   npm i life2film-engine
   node scripts/beats.mjs song.mp3 > beats.json
   jq '{bpm, confidence, pulse_strength, sections}' beats.json
   ```
   If `pulse_strength` is under 0.2 the BPM is a guess; say so. A BPM that looks halved is half-time: treat 0.5 s cuts as on-beat, 0.25 s as half-beat. `sections` come from loudness per four-bar phrase (loud = chorus, quiet = verse); check them against the song and edit `beats.json` by hand if a phrase is mislabelled.
3. **Frame pools.** Extract a preview frame every ~15 s with `ffmpeg -ss T -i src -vframes 1 -vf scale=320:-1`, look at each, sort timestamps into `INTIMATE` (close-ups, dark, faces), `WIDE` (landscape, crowds, walking) and `TEXTURE` (sky, water, abstract). Mix pools in the chorus; do not stay in one pool for more than four cuts.
4. **Render script.** Copy `scripts/render_template.py` next to `beats.json`, set `SRC_VIDEO`, `SRC_AUDIO`, the three pools and `DENSITY`, run it.
5. **Verify.** Pull ~7 frames at section boundaries (intro, mid-verse, chorus, peak, outro) and look at them: aspect not stretched (see lesson 2), effect changes visible between adjacent cuts, flashes landing on downbeats.

## Effect palette (14)

INTRO_FADE, OUTRO_FADE, INTIMATE_DARK (dark grade), FLASH_WHITE (downbeat snap), MIRROR_H, DBL_MIRROR, DBL_MIRROR_HUE, WATER and WATER_HUE (reflection), KALEIDO and KALEIDO_RGB (4-way quadrants), TILE3X3, CHROMA (RGB shift), INVERT, PIXEL_CHROMA (pixelise plus frame echo). Add one in `chain(idx, ss, dur, fx)` by copying an existing branch: `trim`, composite, `eq=...`, `setsar=1,format=yuv420p[c{idx}]`.

## Lessons

1. **Real beats only.** Detection takes seconds and removes the guesswork. Energy drives density: loud chorus 0.25 s, quiet verse 0.5 s.
2. **Aspect trap in stacked effects.** For a 9:16 source `scale=1080:960` stretches. Use `scale=1080:1920,crop=1080:960:0:480`. Same for any vstack/hstack of two halves where target ratio differs from the source.
3. **`setsar=1` at the end of every chain.** overlay/hstack/vstack change SAR silently and `concat` then fails with `Input link parameters do not match`.
4. **`-filter_complex_script`, not inline,** past ~60 cuts.
5. **FLASH_WHITE on downbeats** lets the eye lock on at 0.25 s cuts; without it eighth-note chaos feels arrhythmic. Match with `near_downbeat(t, eps=0.12)`.
6. **0.25 s is the visual floor.** 0.125 s works as an occasional accent, not a sustained section.
7. **Variety.** Stride-shuffle the pool (`pool[(idx * 7) % len]`): a non-repeating order without a random seed.
8. **Size.** CRF 21 + preset medium gives ~75 MB for 40 s of 1080p vertical. For TikTok under 50 MB use CRF 24 + preset slow.
9. **Trust the detector over your ear for sections.** A passage guessed as a breakdown can be the loudest chorus; rewrite the cuts to match.
10. **Landscape source into vertical.** Do not `scale=1080:1920` (stretches faces). Zoom-crop `scale=-1:1920,crop=1080:1920` loses the sides; `scale=1080:-1,pad=1080:1920:0:(1920-ih)/2:black` letterboxes. Ask which.

## Don't

- Guess the BPM or section boundaries from the file name or a hunch.
- Ship without looking at output frames.
