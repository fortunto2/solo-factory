# Output layout (measured on a 29 s clip, 6 shots, 20 MB)

```
out/ref/
  VIDEO.md            card (front matter: made_mix, confidence, readers, source sha256) + verdict + map
  video/              timeline.md content.md cast.md sound.md rhythm.md look.md packaging.md remake.md moments.md
  video/shots/NN.md   per shot: inferred label, probability, runner-up, who decided, beats, frames
  report.html         for a person; report.md is the same text
  breakdown.json      everything, ~21k tokens for 6 shots; for code, not for reading
  storyboard.jpg      one frame per shot with its label; audio.png = waveform and beats
  shots/              shot_NNN.jpg contact sheet, _first/_last, _strip, _el_/_ly_/_st_ detail crops
  stems/              original.wav vocals.wav music.wav effects.wav
  packaging/          overlays.ass (subtitles and styled text), timeline.json
  review_tasks.json, review_answers.json   after `rea-video review`
  remake/intent.yaml  after `rea-video plan`
```

Topic files with nothing to say are not written (`voice_S1.wav` per speaker needs the `asr` extra).

## What VIDEO.md looks like

```
---
videomd: 1
name: ref
made_mix: {live_action: 1.0}
confidence: 0.516
readers: [tools, agent]
---
# ref.mp4
**Verdict** (inferred): Mixed production: live action 100%; overlays: ...
## Open questions   ## Map  (path | ~tokens | what is in it)
```

A timeline line, one per shot:

```
#02 8.5-12.3 | camera smooth move | transition jump cut | overlay graphic | made~ 3D render 62% · runner-up code / template render 22% | material~ ... | remake AI generation / 3D render · G2
```

`~` after a key = inferred. `rea-video videomd "$O" --check` validates against the spec (pip package `videomd`).

## Plan and remake commands (upstream, not run here beyond `plan`)

`plan` (free, 0.7 s) writes the second half of the report. `remake`, `remake-run`, `assemble` need
capsule-cinema and paid models; `code-remake` and `drive` are for code-rendered and dance shots.
`pdf` needs a local Chrome. `moments` finds reveals, twists and goofs; it asks the agent to look too.
